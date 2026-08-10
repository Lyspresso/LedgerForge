# Statement Studio for macOS

Statement Studio is the suite's native SwiftUI workspace for importing,
browsing, answering, checking, and reviewing intermediate-accounting question
packs. It requires macOS 14 or later and links the local
`../Shared/AccountingQuestionKit` Swift package.

The app provides dedicated editors for all twelve response primitives: single
choice, multiple choice, number, formula, short response, long response,
journal entry, accounting table, matching, ordering, true/false with
correction, and entry/no-entry with rationale. Attempts autosave locally;
deterministic answers use the shared grader, while judgment-heavy responses use
model-answer and rubric self-review.

## Generate, build, and run

Install XcodeGen, then generate the checked-in Xcode project whenever
`project.yml` changes:

```sh
cd MacSwiftUI
xcodegen generate
```

For normal development, open `AccountingQuestionStudio.xcodeproj`, select the
**AccountingQuestionStudio** scheme and **My Mac**, then run with Command-R:

```sh
open -a Xcode AccountingQuestionStudio.xcodeproj
```

This command performs a clean, unsigned universal Release build with all build
state outside the project:

```sh
xcodebuild -project AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/StatementStudioDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean build
```

The result is
`/tmp/StatementStudioDerivedData/Build/Products/Release/Statement Studio.app`.
The ready-to-run, ad-hoc-signed deliverable is also available at
`../Builds/Statement Studio.app` and in
`../Builds/Statement-Studio-macOS.zip`; launch it with:

```sh
open '../Builds/Statement Studio.app'
```

The packaged build is ad-hoc signed for local use, not Developer ID signed or
notarized for public distribution. A quarantined copy moved to another Mac may
therefore be blocked by Gatekeeper.

## Test

Run the Mac test suite with the scheme's Debug test action, then use the
separate Release command above for the shipping binary:

```sh
xcodebuild -project AccountingQuestionStudio.xcodeproj \
  -scheme AccountingQuestionStudio \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/StatementStudioTestDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO clean test
```

The read-only full-bank test discovers `ACCOUNT343_COMPLETE.md` and
`ACCOUNT343_NEEDS_HUMAN.md` in `~/Downloads`, or accepts
`ACCOUNT343_FIXTURE_DIR`, `ACCOUNT343_COMPLETE_PATH`, and
`ACCOUNT343_NEEDS_HUMAN_PATH` in its test-process environment.

## Import Markdown and samples

- Choose **File → Import Markdown…** (Shift-Command-I) or use the toolbar
  import button to select one or more UTF-8 `.md` or `.markdown` files.
- Choose **File → Load Complete Format Sample** (Shift-Command-L) to import the
  bundled `ALL_FORMATS_SAMPLE.md` with every supported response format.
- Choose **File → Load Spreadsheet Practice Sample** (Option-Command-L) to
  import the bundled `SPREADSHEET_PRACTICE.md` exercises.
- Because the app registers as an alternate Markdown viewer, a `.md` file can
  also be sent from Finder with **Open With → Statement Studio**.

Imported library IDs are scoped deterministically to each source file, so
different banks can reuse author-facing question IDs without sharing attempts.
Reimporting the same source updates it in place.

## Spreadsheet practice

Open the bundled spreadsheet sample, select a table or formula question, and
enter formulas beginning with `=`. Grid editors show A1 addresses and formula
results or errors, support Return/Tab navigation, and accept a tab- or
line-separated range with Shift-Command-V. Raw formulas remain in the saved
response while grading compares evaluated values.

Supported functions include `SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`,
`IF`, `PV`, `FV`, `PMT`, and `NPV`; formulas may reference cells and ranges.
Ordinary Command-V remains available inside a single text field.

## Local data

The sandboxed app stores its only mutable library file here:

```text
~/Library/Containers/com.accountingquestionsuite.mac/Data/Library/Application Support/Statement Studio/library.json
```

An explicitly unsigned command-line build runs without the App Sandbox and
uses this fallback location instead:

```text
~/Library/Application Support/Statement Studio/library.json
```

No account, server, or API key is used. Deleting `library.json` resets imported
questions and attempts for that build context.

## Keyboard shortcuts

- Command-Return checks the current part.
- Shift-Command-R reveals or hides its model answer.
- Command-[ and Command-] move between visible questions.
- Option-Command-I toggles the inspector.
- Shift-Command-V pastes a range at the selected spreadsheet cell.
