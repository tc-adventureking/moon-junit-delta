"""Run both implementations on the compatibility cases documented in docs/JUNIT.md."""
from collections import Counter
from importlib.metadata import version
from pathlib import Path
from random import Random
from subprocess import run
import sys
from tempfile import TemporaryDirectory
from xml.etree.ElementTree import canonicalize
import xml.etree.ElementTree as ET

from junitparser import Failure, JUnitXml, TestCase, TestSuite, xunit2


ROOT = Path(__file__).resolve().parents[1]


def reference_reports():
    suite = TestSuite("service")
    case = TestCase("login", "api", 0.12)
    suite.add_testcase(case)
    suite.add_property("build", "12")
    report = JUnitXml()
    report.add_testsuite(suite)
    case.result = [Failure("assertion")]
    report.update_statistics()
    yield report

    report = JUnitXml.fromstring(
        "<testsuite name='s'><properties><property name='old' value='1'/></properties>"
        "<testcase name='keep' time='0.1'><system-out>log</system-out>"
        "<extra xmlns='urn:x'>payload</extra></testcase><testcase name='remove'/></testsuite>"
    )
    suite = next(iter(report))
    suite.remove_testcase(list(suite)[1])
    suite.add_property("new", "2")
    next(iter(suite)).classname = "renamed"
    report.update_statistics()
    yield report

    left = JUnitXml.fromstring("<testsuite name='s'><testcase name='one' time='0.1'/></testsuite>")
    right = JUnitXml.fromstring(
        "<testsuite name='s'><testcase name='two' time='0.2'><failure/><failure/></testcase></testsuite>"
    )
    yield left + right

    report = xunit2.JUnitXml.fromstring(
        "<testsuite name='retry'><testcase name='a' group='g'><rerunFailure message='retry'>"
        "<stackTrace>trace</stackTrace></rerunFailure></testcase></testsuite>"
    )
    next(iter(next(iter(report)))).add_property("attempt", "2")
    report.update_statistics()
    yield report


def nested_reference_reports():
    inputs = [
        "<testsuites><testsuite name='s'><testcase name='a'/></testsuite></testsuites>",
        "<testsuites><testsuite name='s'><testsuite name='inner'><testcase name='b'/></testsuite><testcase name='c'/></testsuite></testsuites>",
    ]
    left, right = (xunit2.JUnitXml.fromstring(xml) for xml in inputs)
    yield left + right
    yield left + left
    left += right
    yield left
    yield right
    left, right = (next(iter(xunit2.JUnitXml.fromstring(xml))) for xml in inputs)
    yield left + right
    left += right
    yield left
    yield right


def check_nested_shards(directory):
    rng = Random(501)
    paths = []
    expected = Counter()

    def populate(parent, path, depth):
        for _ in range(5):
            if depth < 3 and rng.randrange(2):
                name = rng.choice(["web", "api"])
                populate(ET.SubElement(parent, "testsuite", name=name, tests="99"), (*path, name), depth + 1)
            else:
                name = rng.choice(["login", "read", "write"])
                case = ET.SubElement(parent, "testcase", name=name)
                kind = rng.choice(["failure", "skipped", "error", "passed"])
                if kind != "passed":
                    ET.SubElement(case, kind)
                expected[(path, name, kind)] += 1

    for i in range(5):
        root = ET.Element("testsuites")
        populate(root, (), 0)
        path = directory / f"nested-{i}.xml"
        ET.ElementTree(root).write(path, encoding="utf-8")
        paths.append(path)

    def check(parent, path, actual):
        children = parent.findall("testsuite")
        names = [suite.attrib["name"] for suite in children]
        assert len(set(names)) == len(names), (path, names)
        counts = Counter()
        for case in parent.findall("testcase"):
            kind = case[0].tag if len(case) else "passed"
            counts[kind] += 1
            actual[(path, case.attrib["name"], kind)] += 1
        for child in children:
            counts.update(check(child, (*path, child.attrib["name"]), actual))
        assert int(parent.attrib["tests"]) == counts.total()
        for attr, kind in [("failures", "failure"), ("errors", "error"), ("skipped", "skipped")]:
            assert int(parent.attrib[attr]) == counts[kind], (path, attr, counts)
        return counts

    for order in [paths, list(reversed(paths))]:
        command = ["node", str(ROOT / "bin/junit-delta.mjs"), "merge", *order, "-"]
        result = run(command, check=True, capture_output=True)
        actual = Counter()
        check(ET.fromstring(result.stdout), (), actual)
        assert actual == expected


def check_cli(directory):
    passing = directory / "pass.xml"
    failing = directory / "fail.xml"
    passing.write_text("<testsuite name='s'><testcase name='a'/></testsuite>", encoding="utf-8")
    failing.write_text("<testsuite name='s'><testcase name='b'><failure/></testcase></testsuite>", encoding="utf-8")
    outputs = []
    for index, command in enumerate((
        [sys.executable, "-m", "junitparser"],
        ["node", str(ROOT / "bin/junit-delta.mjs")],
    )):
        output = directory / f"merged-{index}.xml"
        run([*command, "merge", passing, failing, output], cwd=ROOT, check=True)
        outputs.append(canonicalize(from_file=output))
        for xml, expected in [(passing, 0), (failing, 1), (output, 1)]:
            result = run([*command, "verify", xml], cwd=ROOT, capture_output=True)
            assert result.returncode == expected, (command, xml.name, result.returncode, result.stderr)
    assert outputs[0] == outputs[1], "CLI merge XML differs"


def main():
    assert version("junitparser") == "5.0.3" and version("lxml") == "6.1.1"
    result = run(["moon", "run", "tests/parity", "--target", "js", "--deny-warn"],
                 cwd=ROOT, check=True, capture_output=True, encoding="utf-8")
    reports = result.stdout.splitlines()
    expected_reports = [*reference_reports(), *nested_reference_reports()]
    for i, (actual, expected) in enumerate(zip(reports, expected_reports, strict=True)):
        assert canonicalize(actual) == canonicalize(expected.tostring()), f"XML differs in case {i + 1}"
    with TemporaryDirectory() as temporary:
        check_cli(Path(temporary))
        check_nested_shards(Path(temporary))
    print(f"Matched {len(reports)} upstream XML outputs and flat CLI merge/verify; nested shard invariants passed.")


if __name__ == "__main__":
    main()
