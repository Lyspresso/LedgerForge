# LedgerForge — Accounting Question Suite

Three local-first study applications share one Markdown question format and support the full intermediate-accounting response catalog. LedgerForge is the macOS Rust app and gives this repository its name; Statement Studio and Ledger Pocket ship alongside it.

Everything runs offline. No server, account, API key, or analytics service is involved, and no question content is bundled beyond the original sample packs in `Samples/`.

## Included applications

| Project | Platform and stack | Project location |
|---|---|---|
| LedgerForge | macOS 11+, Rust 2024, `eframe/egui` | `MacRust/` |
| Statement Studio | macOS 14+, Swift 6, SwiftUI, Xcode | `MacSwiftUI/` |
| Ledger Pocket | iOS/iPadOS 17+, Swift 6, SwiftUI, Xcode | `iOSSwiftUI/` |

The Apple apps use `Shared/AccountingQuestionKit`, a tested Swift package containing the models, structured/legacy Markdown importer, deterministic grader, self-review policy, format catalog, and validator. The Rust app implements the same interchange contract independently.

## Builds

Compiled apps are not committed to this repository — build them from source with the commands below, or download them from a [release](../../releases). The Rust binaries embed absolute build-time paths, which is why they stay out of the tree.

`Builds/DELIVERY_MANIFEST.md` records the test results, platform requirements, and signing caveats for the original 2026-08-10 build.

All three apps are ad-hoc signed rather than Developer ID signed and notarized. On first launch of a Mac app, use Control-click → Open if Gatekeeper blocks it. Running Ledger Pocket on a physical iPhone or iPad requires your own Apple development team and signing identity in Xcode.

## Try every format

Import `Samples/ALL_FORMATS_SAMPLE.md`. It contains 35 original working questions: the 34 constructed-response formats plus single-best-answer multiple choice. `Samples/SPREADSHEET_PRACTICE.md` demonstrates A1 formulas, ranges, `SUM`, `IF`, `PV`, and `NPV`. `Samples/QUESTION_TEMPLATE.md` is the fastest starting point for authoring a new question.

Read `Docs/MARKDOWN_FORMAT.md` for the complete authoring grammar, `Docs/SPREADSHEET.md` for formulas and supported functions, and `Docs/PRODUCT_DESIGN.md` for the experience and editor mapping.

`Docs/IMPORT_VALIDATION.md` reports how the importer performed against two large private question banks. Those banks are course material and are not part of this repository; the tests that read them are skipped unless you point an environment variable at your own file.

## Import existing questions

The apps accept two Markdown modes:

- **Structured Markdown v1** uses `:::question` and `:::part` directives. It activates the correct editor, answer key, tolerance, automatic grading, and rubric for each part.
- **Legacy Markdown** recognizes ACCOUNT343-style `## Item` / backtick headings and `**Question:**`, `**Required:**`, `**Answer:**`, or `**Answer key:**` sections. Standard A–D multiple choice is detected automatically; other legacy items remain fully usable as written-response/self-review questions.

No server, account, or API key is required. Imported questions and attempts remain in each app’s local Application Support storage.

## Development commands

### Shared Swift package

```sh
cd Shared/AccountingQuestionKit
swift test
swift run aqvalidate ../../Samples/ALL_FORMATS_SAMPLE.md
```

### Rust macOS app

```sh
cd MacRust
cargo test --offline
cargo run --offline
```

### Native macOS SwiftUI app

```sh
cd MacSwiftUI
xcodegen generate
xcodebuild -project AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio -destination 'platform=macOS' build
```

### iOS app

```sh
cd iOSSwiftUI
xcodegen generate
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Design constraints

- Stable question/part IDs preserve attempts across launches and re-imports.
- Objective formats are machine-checked; professional writing is self-reviewed against a visible model answer and rubric.
- Numerical answers can specify tolerances and tables can allow arbitrary row order.
- Grid answers accept A1 formulas, ranges, common aggregate/logic functions, and accounting time-value functions; raw formulas are saved while evaluated values are graded.
- All interfaces support light/dark appearance and scalable text; iOS adds semantic surfaces, reduced-motion-aware feedback, and optional haptics.

## License

MIT — see [LICENSE](LICENSE).

The sample question packs in `Samples/` are original practice material written for this project. No publisher or textbook content is included in this repository.
