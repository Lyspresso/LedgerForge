# Contributing to LedgerForge

Thanks for helping improve the Accounting Question Suite. Changes should preserve the shared
Markdown contract, local-first privacy model, and equivalent question behavior across all three
applications.

## Repository map

| Path | Purpose |
|---|---|
| `MacRust/` | LedgerForge for macOS, implemented in Rust with `eframe`/`egui` |
| `MacSwiftUI/` | Statement Studio for macOS, implemented in SwiftUI |
| `iOSSwiftUI/` | Ledger Pocket for iPhone and iPad |
| `Shared/AccountingQuestionKit/` | Shared Swift models, importer, grader, validator, and spreadsheet engine |
| `Samples/` | Original public question packs used for examples and regression coverage |
| `Docs/` | Markdown authoring, spreadsheet, import, product, and visual specifications |

## Prerequisites

- A Mac capable of running a current Xcode release with Swift 6.1 support. Xcode 16.3 or later is
  required by `Shared/AccountingQuestionKit/Package.swift`.
- Rust 1.92 or later with `rustfmt` and `clippy`. The Rust crate uses edition 2024 and declares
  Rust 1.92 as its minimum supported toolchain.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when changing either Apple app's project
  specification. The checked-in projects were last generated successfully with XcodeGen 2.45.4.
- Git and the Xcode command-line tools.

Fetch Rust dependencies once before attempting an offline build:

```sh
cd MacRust
cargo fetch --locked
```

After that succeeds, Cargo commands may use `--offline` while the cache remains available.

## XcodeGen and checked-in projects

`MacSwiftUI/project.yml` and `iOSSwiftUI/project.yml` are the sources of truth for project
structure. Their generated `.xcodeproj` directories are intentionally committed so a fresh clone
can be built without first installing XcodeGen, and CI deliberately tests those committed
projects.

Whenever a `project.yml` change affects a target, build setting, package, source, test, or resource:

```sh
(cd MacSwiftUI && xcodegen generate)
(cd iOSSwiftUI && xcodegen generate)
```

Commit the relevant `project.yml` and generated `project.pbxproj` together. Avoid editing a
generated project by hand. If a necessary setting cannot be expressed in XcodeGen, explain the
exception in the pull request and verify that a later generation will not erase it.

## Compatibility obligations

- Preserve stable question and part IDs so reimports do not detach saved attempts.
- Keep Structured Markdown v1 portable across Rust and Swift. Parser or model changes require
  equivalent behavior in both implementations, updated samples, and documentation.
- Keep objective grading deterministic. Writing and professional-judgment formats must continue
  to use explicit model-answer/rubric self-review rather than pretend automatic grading.
- Preserve raw spreadsheet formulas while grading evaluated values. New formula behavior must be
  documented and covered in both engines.
- Do not add accounts, analytics, remote storage, API keys, or network requirements without an
  explicit product-level decision and corresponding privacy documentation.
- Maintain the published platform floors: macOS 11 for LedgerForge, macOS 14 for Statement Studio,
  and iOS/iPadOS 17 for Ledger Pocket.
- Never commit private course banks, answer keys, student responses, or local Application Support
  data. Use original minimal fixtures in tests.

## Quality gates

Run the gates relevant to your change; parser, grader, spreadsheet, or Markdown-contract changes
should run all of them.

### Rust

```sh
cd MacRust
cargo fmt --check
cargo test --locked --all-targets
cargo clippy --locked --all-targets -- -D warnings
MACOSX_DEPLOYMENT_TARGET=11.0 cargo build --release --locked
```

The public repository has 53 standard Rust tests. Two additional tests in
`tests/supplied_bank_qa.rs` are ignored read-only private-bank validations. Run them only when
`LEDGERFORGE_QA_COMPLETE` and `LEDGERFORGE_QA_NEEDS_HUMAN` point to files you are authorized to
use:

```sh
LEDGERFORGE_QA_COMPLETE=/absolute/path/to/ACCOUNT343_COMPLETE.md \
LEDGERFORGE_QA_NEEDS_HUMAN=/absolute/path/to/ACCOUNT343_NEEDS_HUMAN.md \
cargo test --locked --test supplied_bank_qa -- --ignored
```

The ordinary public gate reports 53 passed and 2 ignored.

### Shared Swift package

```sh
swift test --package-path Shared/AccountingQuestionKit
swift run --package-path Shared/AccountingQuestionKit aqvalidate Samples/ALL_FORMATS_SAMPLE.md
```

### Statement Studio

```sh
xcodebuild -project MacSwiftUI/AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/StatementStudioTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean test
```

The macOS suite includes one optional external-bank test. It is skipped unless the documented
`ACCOUNT343_*` fixture variables point to authorized local files.

### Ledger Pocket

Choose an available iPhone simulator from `xcodebuild -showdestinations`, then run:

```sh
xcodebuild -project iOSSwiftUI/AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite \
  -destination 'platform=iOS Simulator,name=<available iPhone>,OS=latest' \
  -derivedDataPath /tmp/LedgerPocketTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean test
```

GitHub Actions repeats the repository-contained gates on a pinned macOS runner and selects an
available simulator dynamically.

## Pull requests

Keep pull requests focused and describe user-visible behavior. Before requesting review:

- [ ] Format, test, lint, and build the affected components.
- [ ] Add or update original public fixtures for changed import/grading behavior.
- [ ] Update authoring or formula documentation when the interchange contract changes.
- [ ] Regenerate and commit affected Xcode projects after `project.yml` changes.
- [ ] Check behavior in light and dark appearance for UI changes, including keyboard navigation,
      VoiceOver labels, Dynamic Type or scalable text, and reduced motion where applicable.
- [ ] Add screenshots for material UI changes.
- [ ] Confirm no private course material, credentials, generated binaries, or local paths are in
      the diff.
- [ ] Add a changelog entry for a user-visible or compatibility-affecting change.
