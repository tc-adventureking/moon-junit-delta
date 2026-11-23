"""Run both implementations on the compatibility cases documented in docs/JUNIT.md."""
from importlib.metadata import version
from pathlib import Path
from subprocess import run
import sys
from tempfile import TemporaryDirectory
from xml.etree.ElementTree import canonicalize

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
    for i, (actual, expected) in enumerate(zip(reports, reference_reports(), strict=True)):
        assert canonicalize(actual) == canonicalize(expected.tostring()), f"XML differs in case {i + 1}"
    with TemporaryDirectory() as temporary:
        check_cli(Path(temporary))
    print("Matched junitparser 5.0.3 on 4 library scenarios, CLI merge and verify.")


if __name__ == "__main__":
    main()
