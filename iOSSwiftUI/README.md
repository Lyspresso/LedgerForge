# Ledger Pocket for iPhone and iPad

Ledger Pocket is a local-first SwiftUI study app for iOS and iPadOS 17 or
later. Version 1.0.0 (build 1) uses the bundle identifier
`com.accountingquestionsuite.ledgerpocket`, supports iPhone and iPad in their
standard portrait and landscape orientations, and registers as an alternate
viewer for `.md` and `.markdown` documents.

The app includes every specialized response editor in the shared Accounting
Question Kit. It starts a new library with the 35-question All Formats Sample,
can directly load the bundled Spreadsheet Practice pack, imports structured or
legacy Markdown from Files, and saves the parsed packs, attempts, and in-progress
answers only in the app's local container.

## Open the self-contained Xcode source

The `Ledger-Pocket-iOS-Xcode.zip` deliverable expands to this buildable layout:

```text
Ledger-Pocket-iOS-Xcode/
├── iOSSwiftUI/
├── Shared/AccountingQuestionKit/
├── Samples/
└── Docs/
```

Keep those directories together: the Xcode project resolves the local package
at `../Shared/AccountingQuestionKit` and bundles the two sample files from
`../Samples`.

1. Install XcodeGen if it is not already available: `brew install xcodegen`.
2. In Terminal, change to `Ledger-Pocket-iOS-Xcode/iOSSwiftUI`.
3. Run `xcodegen generate` whenever `project.yml` changes.
4. Open `AccountingQuestionSuite.xcodeproj` in Xcode.
5. Select the **AccountingQuestionSuite** scheme, choose an iPhone or iPad
   simulator, and press Run.

The committed `.xcodeproj` is already regenerated, so XcodeGen is not required
unless the project specification is edited.

## Command-line build and tests

From `iOSSwiftUI/`, create one generic simulator test build with signing
disabled and DerivedData outside the project:

```sh
xcodegen generate
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LedgerPocket-iOS-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build-for-testing
```

Run that built suite on both required device classes:

```sh
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -derivedDataPath /tmp/LedgerPocket-iOS-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  test-without-building

xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=latest' \
  -derivedDataPath /tmp/LedgerPocket-iOS-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  test-without-building
```

If a future Xcode renames a simulator model, run
`xcodebuild -project AccountingQuestionSuite.xcodeproj -scheme AccountingQuestionSuite -showdestinations`
and substitute the displayed name.

## Install the prebuilt simulator app

`Ledger-Pocket-iOS-Simulator.zip` contains an unsigned, universal Release app
for Apple silicon and Intel iOS Simulators. It cannot run on a physical device.

```sh
unzip Ledger-Pocket-iOS-Simulator.zip
open -a Simulator
xcrun simctl bootstatus booted -b
xcrun simctl install booted 'Ledger Pocket (Simulator).app'
xcrun simctl launch booted com.accountingquestionsuite.ledgerpocket
```

In Simulator, choose **File > Open Simulator** and select an iOS 17-or-later
iPhone or iPad before running `bootstatus`. Using `booted` avoids ambiguity when
Xcode has the same model installed under more than one simulator runtime.

## Run on a physical iPhone or iPad

The source is device-ready, but Apple requires a signing identity and
provisioning profile that cannot be bundled generically:

1. Open the project and select the **AccountingQuestionSuite** app target.
2. In **Signing & Capabilities**, enable automatic signing and select your Apple
   development team.
3. If Xcode reports that the bundle identifier is unavailable, replace
   `com.accountingquestionsuite.ledgerpocket` with an identifier owned by your
   team.
4. Choose the connected iPhone or iPad and press Run.

To make an IPA, choose **Product > Archive** and export through Organizer using
your Development, Ad Hoc, or App Store distribution credentials. A usable
physical-device IPA requires the user's own Apple signing team and provisioning
profile; the supplied simulator app and zip are intentionally not an IPA.

## Import question packs and built-in samples

- Tap **+ Add Questions > All Formats Sample** to restore or update the bundled
  35-format pack.
- Tap **+ Add Questions > Spreadsheet Practice** to load the bundled formula and
  worksheet exercises directly.
- Tap **+ Add Questions > Import from Files** to choose a UTF-8 `.md` or
  `.markdown` file from iCloud Drive, On My iPhone/iPad, or another Files
  provider.
- In Files, a Markdown document can also be shared or opened with Ledger Pocket;
  the registered document type delivers it to the same importer.

Importing reads the selected document but does not edit it. Structured Markdown
gets specialized editors and deterministic grading. Legacy Markdown remains
usable and displays any heuristic-import warnings. Reimporting the same filename
updates that pack while stable question and part identifiers preserve attempts.
See `../Docs/MARKDOWN_FORMAT.md` for the authoring contract.

## Spreadsheet practice

Load **Spreadsheet Practice**, open one of its two questions, then tap a grid
cell or the formula bar. Begin a formula with `=` and use A1 references such as
`=B1+C1-D1` or `=SUM(B1:B4)`. The Previous/Next controls and keyboard Next button
move through cells. Raw formulas stay in the saved answer while their evaluated
values are shown separately and used for grading.

The local engine supports arithmetic, comparisons, ranges, percentages, and
`SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`, `IF`, `PV`, `FV`, `PMT`, and
`NPV`. It reports safe spreadsheet errors such as `#REF!`, `#DIV/0!`, and
`#CYCLE!`. It does not require Excel, Numbers, a network connection, or an
account. See `../Docs/SPREADSHEET.md` for the exact grammar and function rules.

## Local data

Ledger Pocket autosaves to:

```text
Library/Application Support/AccountingQuestionSuite/library-state.json
```

That path is inside the app's sandbox. For the currently booted simulator:

```sh
LEDGER_POCKET_DATA=$(xcrun simctl get_app_container booted \
  com.accountingquestionsuite.ledgerpocket data)
open "$LEDGER_POCKET_DATA/Library/Application Support/AccountingQuestionSuite"
```

On a physical device, use Xcode's **Window > Devices and Simulators**, select the
installed app, and download its container; the JSON file is under the same
`AppData/Library/Application Support/AccountingQuestionSuite/` path. Deleting
the app deletes this local state unless the device or container was backed up.
No account, analytics service, sync service, or remote database is used.
