# Sources and third-party notices

junit-delta uses [MIT](../LICENSE) for its original implementation. The adapted report model, typed fields and I/O layer (`junit/model.mbt`, `junit/fields.mbt`, `junit/io.mbt`) are marked Apache-2.0.

- [Milky2018/xml 0.6.1](https://github.com/moonbit-community/xml-mbt): XML reader, namespace validation and writer dependency, Apache-2.0. Its compiled implementation is included when building the CLI. See [xml-LICENSE](xml-LICENSE).
- [MoonBit core](https://github.com/moonbitlang/core): standard library, Apache-2.0. Compiled standard-library code is included when building the CLI. See [moonbit-core-LICENSE](moonbit-core-LICENSE) and [moonbit-core-NOTICE](moonbit-core-NOTICE).
- [junitparser 5.0.3](https://github.com/weiwei/junitparser): the new typed report model and writer behavior are adapted to MoonBit from this Apache-2.0 project. Copyright 2025 Weiwei Wang. See the upstream [copyright notice](junitparser-LICENSE) and [Apache-2.0 terms](Apache-2.0.txt). Changes include MoonBit types, shared arena storage, callback I/O, bounded operations and the documented language adaptations. No Python runtime or Python source is bundled. The [comparison table](../docs/JUNIT.md) states the API mapping and differences.

No endorsement by these projects is implied. Input compatibility and project-specific comparison behavior are described in the [usage guide](../docs/USAGE.md).
