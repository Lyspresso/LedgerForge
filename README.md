# LedgerForge — Accounting Question Suite

Three local-first study applications share one Markdown question format and support the full intermediate-accounting response catalog. LedgerForge is the macOS Rust app and gives this repository its name; Statement Studio and Ledger Pocket are native SwiftUI companions.

![LedgerForge showing checked accounting-question feedback](Docs/Visual%20QA/LedgerForge-final-checked-feedback.png)

Once installed, every app works without a server, account, API key, analytics service, or network connection. A first source build may still need internet access to clone the repository, install development tools, and download uncached Rust dependencies. Imported questions and study progress remain on the device.

## Choose an application

| Application | Platform and stack | Source and instructions |
|---|---|---|
| LedgerForge | macOS 11+, Rust 2024, `eframe`/`egui` | [MacRust](MacRust/) |
| Statement Studio | macOS 14+, Swift 6, SwiftUI | [MacSwiftUI](MacSwiftUI/) |
| Ledger Pocket | iOS/iPadOS 17+, Swift 6, SwiftUI | [iOSSwiftUI](iOSSwiftUI/) |

The Apple apps use [AccountingQuestionKit](Shared/AccountingQuestionKit/), a tested local Swift package containing the models, structured and legacy Markdown importers, deterministic grader, self-review policy, format catalog, validator, and spreadsheet engine. LedgerForge implements the same interchange contract independently in Rust.

## Quick start

### Download a packaged build

Check [GitHub Releases](https://github.com/Lyspresso/LedgerForge/releases) for packaged downloads. If the Releases page has no published build, use the source instructions below. Compiled apps and ZIP archives are intentionally not committed to the repository.

| Release asset | Runs on | Distribution status |
|---|---|---|
| `LedgerForge-macOS.zip` | Apple-silicon Mac, macOS 11+ | `arm64`; ad-hoc signed; not notarized |
| `Statement-Studio-macOS.zip` | Intel or Apple-silicon Mac, macOS 14+ | Universal `x86_64` + `arm64`; ad-hoc signed; not notarized |
| `Ledger-Pocket-iOS-Simulator.zip` | iOS 17+ Simulator on an Intel or Apple-silicon Mac | Simulator-only `x86_64` + `arm64`; unsigned |
| `Ledger-Pocket-iOS-Xcode.zip` | Xcode source for Simulator or a user-signed device build | Physical devices require the user's Apple development team |

After extracting a Mac ZIP, move the app to Applications if desired. If Gatekeeper blocks its first launch, Control-click the app, choose **Open**, and confirm; do not disable Gatekeeper. See the [Ledger Pocket guide](iOSSwiftUI/README.md) for Simulator and physical-device instructions.

The [delivery manifest](Builds/DELIVERY_MANIFEST.md) is the release checklist and evidence record. Once its placeholders are populated for a published tag, use its checksums to verify assets from that same release; checksums change whenever an archive is rebuilt.

### Run from source

Clone the repository, then follow the application-specific README linked above. The short paths are:

```sh
git clone https://github.com/Lyspresso/LedgerForge.git
cd LedgerForge
```

For LedgerForge, fetch the locked Rust dependencies once and run it:

```sh
cd MacRust
cargo fetch --locked
cargo run --locked
```

After that fetch has populated Cargo's cache, `cargo run --locked --offline` works without network access. Dependencies are not vendored, so `--offline` is not guaranteed on a fresh machine.

For either SwiftUI app, open its committed Xcode project directly:

```sh
open MacSwiftUI/AccountingQuestionStudio.xcodeproj
# or
open iOSSwiftUI/AccountingQuestionSuite.xcodeproj
```

Choose **My Mac** for Statement Studio or an available iPhone/iPad Simulator for Ledger Pocket, then press Command-R. XcodeGen is needed only when changing a `project.yml`; normal users do not need to regenerate the committed projects.

## Development prerequisites

| Work | Required tooling |
|---|---|
| Build LedgerForge | Rust 1.92 or newer, Cargo, and the Xcode Command Line Tools |
| Build either SwiftUI app | Xcode with Swift 6.1 support and the matching Apple platform SDK |
| Regenerate an Xcode project | [XcodeGen](https://github.com/yonaskolb/XcodeGen), only after editing `MacSwiftUI/project.yml` or `iOSSwiftUI/project.yml` |
| Validate a question pack | Swift 6.1 through Xcode or a compatible Swift toolchain |

The application runtime is offline. Tool installation, cloning, and an initial dependency fetch are development-time operations and may require a network connection.

## Try every format

Import [ALL_FORMATS_SAMPLE.md](Samples/ALL_FORMATS_SAMPLE.md). It contains 35 original working questions: the 34 constructed-response formats plus single-best-answer multiple choice. [SPREADSHEET_PRACTICE.md](Samples/SPREADSHEET_PRACTICE.md) demonstrates A1 formulas, ranges, `SUM`, `IF`, `PV`, and `NPV`. Copy [QUESTION_TEMPLATE.md](Samples/QUESTION_TEMPLATE.md) to start authoring a question.

Read the [documentation index](Docs/README.md), [Markdown authoring reference](Docs/MARKDOWN_FORMAT.md), [spreadsheet reference](Docs/SPREADSHEET.md), and [product design specification](Docs/PRODUCT_DESIGN.md). [Import validation](Docs/IMPORT_VALIDATION.md) reports how the importer performed against two private question banks; those course files are not included, and their read-only tests run only when configured with your own paths.

## Import existing questions

The apps accept two Markdown modes:

- **Structured Markdown v1** uses `:::question` and `:::part` directives. It activates the intended editor, answer key, tolerance, automatic grading, and rubric for each part.
- **Legacy Markdown** recognizes ACCOUNT343-style `## Item` or backtick headings and `**Question:**`, `**Required:**`, `**Answer:**`, or `**Answer key:**` sections. Standard A–D multiple choice is detected automatically; other legacy items remain usable as written-response and self-review questions.

Imported questions and attempts remain in each app's local Application Support storage. Stable question and part IDs preserve attempts across re-imports.

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
cargo test --locked
cargo run --locked
```

Use `--offline` only after `cargo fetch --locked` has cached all locked dependencies. See the [LedgerForge guide](MacRust/README.md) for the complete quality gate and package command.

### Native SwiftUI apps

The generated `.xcodeproj` files are committed. Build them in Xcode or use the tested commands in the [Statement Studio guide](MacSwiftUI/README.md) and [Ledger Pocket guide](iOSSwiftUI/README.md). If you change a `project.yml`, run `xcodegen generate` in that application's directory and commit the resulting project changes with the specification change.

## Design constraints

- Seven question shells and eight variation styles compose all 35 response formats from 12 working editors.
- Objective formats are machine-checked; professional writing is self-reviewed against a visible model answer and rubric.
- Numerical answers can specify tolerances, and tables can allow arbitrary row order.
- Grid answers accept A1 formulas, ranges, common aggregate and logic functions, and accounting time-value functions; raw formulas are saved while evaluated values are graded.
- All interfaces support light and dark appearance and scalable text; iOS adds semantic surfaces, reduced-motion-aware feedback, and optional haptics.

## License

MIT — see [LICENSE](LICENSE).

The [sample question packs](Samples/) are original practice material written for this project. No publisher or textbook content is included in this repository.
