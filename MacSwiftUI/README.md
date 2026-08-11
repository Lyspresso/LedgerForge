# Statement Studio for macOS

Statement Studio is the suite's native SwiftUI workspace for importing, browsing, answering, checking, and reviewing intermediate-accounting question packs. It requires macOS 14 or later and uses the repository's local [AccountingQuestionKit](../Shared/AccountingQuestionKit/) Swift package.

The app provides dedicated editors for all 12 response primitives: single choice, multiple choice, number, formula, short response, long response, journal entry, accounting table, matching, ordering, true/false with correction, and entry/no-entry with rationale. Attempts autosave locally. Deterministic answers use the shared grader, while judgment-heavy responses use model-answer and rubric self-review.

[Suite overview](../README.md) · [Documentation](../Docs/README.md) · [Markdown authoring](../Docs/MARKDOWN_FORMAT.md) · [Spreadsheet reference](../Docs/SPREADSHEET.md)

## Quick start from the repository

You need Xcode with Swift 6.1 support. The generated Xcode project is committed, so XcodeGen is not required for normal builds.

```sh
cd MacSwiftUI
open AccountingQuestionStudio.xcodeproj
```

In Xcode, select the **AccountingQuestionStudio** scheme and **My Mac**, then press Command-R. In the empty workspace, choose **Load Complete Sample** or import [ALL_FORMATS_SAMPLE.md](../Samples/ALL_FORMATS_SAMPLE.md).

The installed application runs fully offline. This project has no remote Swift package dependencies: AccountingQuestionKit and both bundled sample packs are local to the repository. Installing Xcode, cloning the repository, or installing optional tooling may require a network connection.

## XcodeGen policy

[`project.yml`](project.yml) is the project specification, and `AccountingQuestionStudio.xcodeproj` is its committed generated output. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you edit `project.yml`:

```sh
brew install xcodegen
cd MacSwiftUI
xcodegen generate
```

Commit the regenerated `.xcodeproj` alongside the `project.yml` change. Do not require app users or ordinary source builders to install XcodeGen.

## Build and test

This command performs a clean, unsigned universal Release build with derived data outside the repository:

```sh
xcodebuild -project AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/StatementStudioDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean build
```

The result is `/tmp/StatementStudioDerivedData/Build/Products/Release/Statement Studio.app`.

Run the Mac test suite with the scheme's Debug test action, then use the separate Release command above for a shipping binary:

```sh
xcodebuild -project AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/StatementStudioTestDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean test
```

The optional full-bank tests discover `ACCOUNT343_COMPLETE.md` and `ACCOUNT343_NEEDS_HUMAN.md` in `~/Downloads`, or accept `ACCOUNT343_FIXTURE_DIR`, `ACCOUNT343_COMPLETE_PATH`, and `ACCOUNT343_NEEDS_HUMAN_PATH` in the test-process environment. Those private course banks are not included in this repository.

## Packaged release

When published, `Statement-Studio-macOS.zip` is available from [GitHub Releases](https://github.com/Lyspresso/LedgerForge/releases). It contains a universal `x86_64` + `arm64` app for macOS 14 or later. The packaged build is ad-hoc signed for local use; it is not Developer ID signed or Apple-notarized. A quarantined copy may therefore be blocked by Gatekeeper. If that happens, Control-click **Statement Studio.app**, choose **Open**, and confirm. Do not disable Gatekeeper.

The unsigned command-line build above is intended for local development. Public distribution requires an appropriate Developer ID identity, hardened-runtime signing, and notarization.

## Import Markdown and samples

- Choose **File → Import Markdown…** (Shift-Command-I) or use the toolbar import button to select one or more UTF-8 `.md` or `.markdown` files.
- Choose **File → Load Complete Format Sample** (Shift-Command-L) to import the bundled [ALL_FORMATS_SAMPLE.md](../Samples/ALL_FORMATS_SAMPLE.md) with every supported response format.
- Choose **File → Load Spreadsheet Practice Sample** (Option-Command-L) to import [SPREADSHEET_PRACTICE.md](../Samples/SPREADSHEET_PRACTICE.md).
- Because the app registers as an alternate Markdown viewer, a Markdown file can also be sent from Finder with **Open With → Statement Studio**.

Imported library IDs are scoped deterministically to each source file, so different banks can reuse author-facing question IDs without sharing attempts. Reimporting the same source updates it in place. See the [Markdown authoring reference](../Docs/MARKDOWN_FORMAT.md) for structured and legacy formats.

## Spreadsheet practice

Open the bundled spreadsheet sample, select a table or formula question, and enter formulas beginning with `=`. Grid editors show A1 addresses and formula results or errors, support Return/Tab navigation, and accept a tab- or line-separated range with Shift-Command-V. Raw formulas remain in the saved response while grading compares evaluated values.

Supported functions include `SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`, `IF`, `PV`, `FV`, `PMT`, and `NPV`; formulas may reference cells and ranges. Ordinary Command-V remains available inside a single text field. The exact formula grammar is in [Docs/SPREADSHEET.md](../Docs/SPREADSHEET.md).

## Local data

The sandboxed app stores its only mutable library file here:

```text
~/Library/Containers/com.accountingquestionsuite.mac/Data/Library/Application Support/Statement Studio/library.json
```

An explicitly unsigned command-line build runs without the App Sandbox and uses this fallback location instead:

```text
~/Library/Application Support/Statement Studio/library.json
```

No account, server, sync service, or API key is used. Deleting `library.json` resets imported questions and attempts for that build context; move it somewhere safe first if you may want to restore that progress.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Command-Return | Check the current part |
| Shift-Command-R | Reveal or hide its model answer |
| Command-[ / Command-] | Move between visible questions |
| Option-Command-I | Toggle the inspector |
| Shift-Command-V | Paste a range at the selected spreadsheet cell |
