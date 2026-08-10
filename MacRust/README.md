# LedgerForge for macOS (Rust)

LedgerForge is a keyboard-friendly intermediate-accounting study workspace built with Rust and
`eframe`/`egui`. It implements the shared Accounting Question Markdown contract: seven question
shells, eight variation styles, 35 pedagogical formats, and 12 working response editors.

On a clean first launch, `../Samples/ALL_FORMATS_SAMPLE.md` is compiled into the app and installed
as a ready-to-use 35-question practice library. Answers, imported packs, preferences, and progress
are saved locally and atomically.

## Install the packaged app

1. Extract `../Builds/LedgerForge-macOS.zip`.
2. Move `LedgerForge.app` to `/Applications` if you want a conventional installation, or run it
   from the extracted folder.
3. Because this local build is ad-hoc signed and not notarized, macOS may block the first launch.
   Control-click the app, choose **Open**, then confirm **Open**. Do not disable Gatekeeper.
4. The complete 35-format sampler appears automatically on the first launch.

The delivered release requires macOS 11.0 or later and contains a native Apple-silicon (`arm64`)
executable. Intel Macs need a source build on Intel or a separately produced universal build.

## Run from source

The lockfile and cached dependencies support a fully offline build:

```sh
cargo run --offline
```

The release executable produced by Cargo is `target/release/accounting-question-studio`. The
packaged app uses the friendlier executable name `LedgerForge` at
`LedgerForge.app/Contents/MacOS/LedgerForge`.

## Import and open practice packs

LedgerForge accepts UTF-8 `.md` and `.markdown` files. The app bundle registers Markdown as an
alternate Viewer document type, while the reliable in-app import routes are:

- Click **Import Markdown…** and choose one or more files.
- Press `Command-O` and choose one or more files.
- Drag Markdown files onto the LedgerForge window.

Import reads the source without changing it, stores a local pack, selects its first question, and
reports any compatibility warnings. Re-importing the same canonical path replaces that pack while
keeping unrelated packs separate. Structured Accounting Question Markdown receives specialized
editors and deterministic grading. Legacy textbook-style Markdown receives a complete written-
response and rubric-based self-review workflow.

The release ZIP includes
`LedgerForge Practice Packs/SPREADSHEET_PRACTICE.md`. Import it, then select either
**Spreadsheet Practice — Warranty Rollforward** or
**Spreadsheet Practice — Time Value and Sensitivity**. It exercises A1 references, ranges,
aggregates, `IF`, `PV`, and `NPV` in live table cells. A copy also lives inside the app bundle at
`Contents/Resources/Practice Packs/SPREADSHEET_PRACTICE.md` for archival completeness.

## Spreadsheet formulas

Start a formula with `=`. Grid cells support case-insensitive A1 references, rectangular ranges,
`+`, `-`, `*`, `/`, `^`, parentheses, percentage literals, quoted text, and the comparisons `=`,
`<>`, `!=`, `<`, `<=`, `>`, and `>=`. Supported functions are:

| Function | Accepted form |
|---|---|
| `SUM`, `AVERAGE`, `MIN`, `MAX` | One or more values and/or ranges, such as `=SUM(B1:B4)` |
| `ROUND` | `ROUND(value)` or `ROUND(value, digits)` |
| `ABS` | `ABS(value)` |
| `IF` | `IF(condition, value_if_true)` or `IF(condition, value_if_true, value_if_false)` |
| `PV`, `FV`, `PMT` | Three to five numeric arguments using spreadsheet sign conventions |
| `NPV` | A rate followed by one or more values/ranges |

Formulas stay visible and saved exactly as authored. The evaluated value or spreadsheet-style
error is shown below the cell. Visible errors include `#VALUE!`, `#REF!`, `#DIV/0!`, and
`#CYCLE!`. Automatic table grading compares evaluated values, so a correct formula can satisfy a
numeric expected cell.

The standalone Formula editor evaluates self-contained formulas such as
`=-PV(8%,3,0,10000)` as a live preview. A1 references are intentionally limited to journal and
table grids. Structured Markdown may list exact formula or short-text alternatives under
`### Accepted`, one bullet per alternative; the older comma-separated `accepted:` setting also
remains supported.

## Study workspace

- Resizable question library with compact, collapsible pack, shell, and all-35-format filters.
- Readable central question canvas with scenario, stacked multipart response cards, and progress.
- SwiftUI-aligned inspector plus in-card deterministic feedback, model answers, rubrics, and
  honest self-review for judgment work.
- Editors for single choice, select-all, number, formula, short text, long text, journal entries,
  schedules/tables, matching, ordering, true/false corrections, and entry/no-entry rationales.
- System light/dark appearance, AccessKit semantics, visible control labels, and local autosave.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Command-O` | Import one or more Markdown packs |
| `Command-F` | Focus library search |
| `Command-S` | Save progress now |
| `Command-Return` | Check the active part |
| `Command-Shift-R` | Reveal or hide the model answer |
| `Command-I` | Show or hide answer review |
| `Command-[` / `Command-]` | Previous / next visible question |

## Local state and recovery

The primary state is:

```text
~/Library/Application Support/com.openai.ledgerforge/state.json
```

The atomic recovery copy is stored beside it as `.state.json.backup`. The files contain imported
pack content, source paths, attempts, preferences, and the last selection. LedgerForge does not use
a cloud service. To reset the workspace, quit LedgerForge and move the entire
`com.openai.ledgerforge` folder somewhere safe before relaunching; keeping that folder is the way
to preserve or migrate progress.

## Verify the source release

Run the complete offline gate from this directory:

```sh
cargo fmt --check
cargo test --offline --all-targets
cargo clippy --offline --all-targets -- -D warnings
MACOSX_DEPLOYMENT_TARGET=11.0 cargo build --release --offline
```

The current audited suite contains 55 tests: 33 library tests, 6 desktop tests, 14 import/grading
integration tests, and 2 complete supplied-bank QA tests.

## Reproduce the macOS package

From `MacRust`, run:

```sh
./scripts/package-macos.sh --clean
```

The script repeats all four quality gates, builds the release with a macOS 11.0 deployment target,
generates a complete multi-resolution `.icns` from
`../Shared/Brand/mac-rust-icon.png`, creates the native bundle, copies the quick-start and
spreadsheet practice pack, ad-hoc signs and verifies the bundle, and creates:

```text
../Builds/LedgerForge.app
../Builds/LedgerForge-macOS.zip
../Builds/LedgerForge Quick Start.md
../Builds/LedgerForge Practice Packs/SPREADSHEET_PRACTICE.md
```

`--clean` runs `cargo clean` only after the signed app and ZIP have been preserved. Omit the flag to
keep Cargo build products. The script validates the plist, executable architecture, deployment
target, icon, signature, and ZIP integrity. It does not publish, Developer ID sign, or notarize.

## Engine modules

- `domain`: question packs, parts, expected answers, student answers, and attempts.
- `markdown`: structured Accounting Question Markdown v1 plus heuristic legacy Markdown import.
- `grading`: deterministic automatic grading and explicit rubric-based self-review.
- `spreadsheet`: bounded, dependency-free formula parsing and evaluated grid values.
- `persistence`: schema-versioned JSON saved atomically in macOS Application Support.

Markdown is the interchange contract between the Rust, macOS SwiftUI, and iOS apps. Rust-only app
state uses camel-case, versioned JSON; ordered maps keep saved output and grading repeatable.
