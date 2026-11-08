# Fixture provenance

Fixtures here are project-authored examples, except `node.xml`, which is output generated from our own test program (hostname and absolute source path replaced with portable values). No third-party test code is copied.

| File | Origin | Validation claim |
|---|---|---|
| node.xml | Node v24.22.1, `node --test --test-reporter=junit fixtures/generate/node-case.mjs` | Real local reporter output; timing fields are a recorded sample, not deterministic regeneration targets. |
| surefire.xml | Authored from the [Surefire rerun documentation](https://maven.apache.org/surefire/maven-surefire-plugin/examples/rerun-failing-tests.html) | Checks the documented flaky versus rerun layout; Maven was not executed. |
| pytest.xml | Authored from the [pytest JUnit documentation](https://docs.pytest.org/en/stable/how-to/output.html#creating-junitxml-format-files) | Representative attributes and outcomes; pytest was not installed or executed. |
| gitlab.xml | Authored from [GitLab's supported fields](https://docs.gitlab.com/ci/testing/unit_test_reports/) | Checks failure text and ignored attachments; no GitLab pipeline was run. |

JUnit XML has no single universal specification. These fixtures demonstrate the supported profile, not complete compatibility with every producer. Tests additionally cover malformed documents, exact IDs, retries and limits.
