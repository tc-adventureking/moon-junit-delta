# Third-party notices

junit-delta project code is MIT licensed. The following components retain their original licenses:

- Milky2018/xml 0.6.1, moonbit-community/xml-mbt, Apache-2.0. Used as a dependency; its compiled implementation is included in the portable CLI. See [xml-LICENSE](xml-LICENSE).
- MoonBit core library, moonbitlang/core, Apache-2.0. Compiled standard-library code is included in the portable CLI. See [moonbit-core-LICENSE](moonbit-core-LICENSE) and [moonbit-core-NOTICE](moonbit-core-NOTICE).
- junitparser 5.0.3, Weiwei Cui and contributors, Apache-2.0. Reference implementation used to produce compatibility vectors; no Python runtime or implementation is bundled. See [junitparser-LICENSE](junitparser-LICENSE).
- publish-unit-test-result-action, EnricoMi and contributors, Apache-2.0. `fixtures/upstream-pytest.xml` is an unchanged text copy of `python/test/files/junit-xml/pytest/junit.fail.xml` at tree `da5b7be67623cd59bbbd1a0ce4f022050a55605f`; the contract vectors also contain this fixture. See [publish-unit-test-result-action-LICENSE](publish-unit-test-result-action-LICENSE).

No endorsement by these projects is implied. Reference files and tests do not extend compatibility beyond the documented input profile.

`fixtures/upstream-surefire.xml` is an unchanged-text fixture from Apache Maven Surefire, `surefire-report-parser/src/test/resources/fixture/testsuitexmlparser/TEST-org.acme.FlakyTest.xml`, tree `c0d85abd7496ea2f0be9a6bf3915b11196596793`. Apache Maven Surefire is licensed under Apache-2.0; see [surefire-LICENSE](surefire-LICENSE). The Apache Software Foundation and its contributors retain their rights. The project-authored `surefire-schema.xml` follows the root-attribute layout emitted by Surefire's `StatelessXmlReporter`; no Java implementation was copied.
