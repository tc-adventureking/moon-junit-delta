# Changelog

## 0.2.0 — 2026-11-09

- Shared identity indexes remove repeated expansion of long suite paths; public collections are deeply read-only.
- Direct merge limits and original-order nested retries are checked consistently; Node flat JUnit reports are supported.
- JSON, Markdown and text have measured output budgets; JSONL aggregate output and terminal error fields are bounded.
- Failure attributes and bodies are separated; clipping has an explicit diagnostic. Historical notes remain visible in summaries.
- XML attribute preflight prevents quadratic work in the pinned reader and rejects DTD before parsing.
- Real pytest, Surefire/JUnit and Node integration; independent comparison oracle, malformed XML, 100,000-case and resource-boundary checks.
- Versioned portable downloads, centralized release checks and migration guidance. See [migration](docs/MIGRATION.md) for API changes.

## 0.1.0 — 2026-11-09

- JUnit XML read API with a pinned junitparser 5.0.3 compatibility contract.
- Exact test identities, explicit duplicate policies and Surefire retry semantics.
- Baseline/current comparison, historical annotations, duration heuristics and configurable CI gates.
- Node CLI with JSON, Markdown, text and JSONL interfaces; portable compiled distribution.
- Strict JSON request fields, Surefire schema metadata, Unicode-safe rendering and comparison JSON Schema.
- Three complete CI scenarios and deterministic source/module/CLI archives verified on Ubuntu and Windows.
- Four-target library tests, independent consumer, saved mature-library oracle and CLI end-to-end checks.

The Mooncakes package contains the library, tests, API, essential documentation, schema and license notices. The complete source, CLI and development tools are available on GitHub.
