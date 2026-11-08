# JUnit Delta

Gate: **FAIL**. Baseline: 5; candidate: 5; history runs: 1.

Triggered: added_failing, new_failure, removed.

| Change | Test ID | Notes | Message |
| --- | --- | --- | --- |
| added_failing | &#91;"class","app","new test"&#93; |  | fixture unavailable |
| fixed | &#91;"class","app","render output"&#93; |  |  |
| new_failure | &#91;"class","app","parse configuration"&#93; |  | expected a default value |
| removed | &#91;"class","app","legacy scenario"&#93; |  |  |
| unchanged | &#91;"class","app","load report"&#93; | duration increase |  |
| unchanged | &#91;"class","app","retry request"&#93; | flaky attempts | first attempt timed out |

Shown 6 details (limit 50); complete entries are available in JSON.
