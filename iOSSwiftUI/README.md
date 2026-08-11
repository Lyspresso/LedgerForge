# Ledger Pocket for iPhone and iPad

Ledger Pocket is a local-first SwiftUI study app for iOS and iPadOS 17 or later. It supports iPhone and iPad in standard portrait and landscape orientations and registers as an alternate viewer for `.md` and `.markdown` documents.

The app includes every specialized response editor in the shared [AccountingQuestionKit](../Shared/AccountingQuestionKit/). A new library starts with the 35-question All Formats Sample; the app can also load Spreadsheet Practice or import structured and legacy Markdown from Files. Parsed packs, attempts, and in-progress answers stay in the app's local container.

[Suite overview](../README.md) · [Documentation](../Docs/README.md) · [Markdown authoring](../Docs/MARKDOWN_FORMAT.md) · [Spreadsheet reference](../Docs/SPREADSHEET.md)

## Quick start from the repository

You need Xcode with Swift 6.1 and an iOS 17-or-later Simulator runtime. The generated Xcode project is committed, so XcodeGen is not required for normal builds.

```sh
cd iOSSwiftUI
open AccountingQuestionSuite.xcodeproj
```

In Xcode, select the **AccountingQuestionSuite** scheme, choose any available iPhone or iPad Simulator running iOS 17 or later, and press Command-R.

Keep `iOSSwiftUI`, `Shared/AccountingQuestionKit`, and `Samples` in their repository-relative locations. The Xcode project resolves the local package at `../Shared/AccountingQuestionKit` and bundles two sample files from `../Samples`.

The installed app runs fully offline. The repository has no remote Swift package dependencies. Installing Xcode, cloning the repository, or installing optional tooling may still require a network connection.

## XcodeGen policy

[`project.yml`](project.yml) is the project specification, and `AccountingQuestionSuite.xcodeproj` is its committed generated output. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you edit `project.yml`:

```sh
brew install xcodegen
cd iOSSwiftUI
xcodegen generate
```

Commit the regenerated `.xcodeproj` alongside the `project.yml` change. Do not require app users or ordinary source builders to install XcodeGen.

## Command-line build and tests

Create one generic Simulator test build with signing disabled and DerivedData outside the repository:

```sh
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LedgerPocket-iOS-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build-for-testing
```

List the destinations installed with your copy of Xcode:

```sh
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -showdestinations
```

Choose an available iOS 17-or-later Simulator UUID from that output and replace `SIMULATOR_UDID` below. Test one iPhone and one iPad when validating both layouts.

```sh
xcodebuild -project AccountingQuestionSuite.xcodeproj \
  -scheme AccountingQuestionSuite -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath /tmp/LedgerPocket-iOS-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  test-without-building
```

Using a UUID avoids documentation going stale when Apple renames Simulator models and avoids ambiguity when several runtimes contain the same model.

## Release downloads

When published, the Ledger Pocket artifacts are available from [GitHub Releases](https://github.com/Lyspresso/LedgerForge/releases):

- `Ledger-Pocket-iOS-Simulator.zip` contains an unsigned Simulator-only Release app with `arm64` and `x86_64` Simulator slices. It cannot run on a physical device.
- `Ledger-Pocket-iOS-Xcode.zip` contains a self-contained source layout with `iOSSwiftUI`, `Shared/AccountingQuestionKit`, `Samples`, and `Docs`. The repository clone has the same required relative layout.

### Install the prebuilt Simulator app

Extract the Simulator archive, then open Simulator and choose **File → Open Simulator** to start any iOS 17-or-later iPhone or iPad. After the device finishes booting:

```sh
xcrun simctl bootstatus booted -b
xcrun simctl install booted 'Ledger Pocket (Simulator).app'
xcrun simctl launch booted com.accountingquestionsuite.ledgerpocket
```

Using `booted` targets the device you opened and avoids assumptions about which Simulator models or runtime versions are installed.

## Run on a physical iPhone or iPad

The source is device-ready, but Apple requires a development signing identity and provisioning profile that cannot be bundled generically:

1. Open the project and select the **AccountingQuestionSuite** app target.
2. In **Signing & Capabilities**, enable automatic signing and select your Apple development team.
3. If Xcode reports that the bundle identifier is unavailable, replace `com.accountingquestionsuite.ledgerpocket` with an identifier owned by your team.
4. Choose the connected iPhone or iPad and press Run.

To create an IPA, choose **Product → Archive** and export through Organizer using your Development, Ad Hoc, or App Store credentials. The supplied Simulator build is unsigned and is intentionally not an IPA.

## Import question packs and built-in samples

- Tap **+ Add Questions → All Formats Sample** to restore or update the bundled [35-format pack](../Samples/ALL_FORMATS_SAMPLE.md).
- Tap **+ Add Questions → Spreadsheet Practice** to load the bundled [formula and worksheet exercises](../Samples/SPREADSHEET_PRACTICE.md).
- Tap **+ Add Questions → Import from Files** to choose a UTF-8 `.md` or `.markdown` file from iCloud Drive, On My iPhone/iPad, or another Files provider.
- In Files, a Markdown document can also be shared or opened with Ledger Pocket; the registered document type delivers it to the same importer.

Importing reads the selected document but does not edit it. Structured Markdown gets specialized editors and deterministic grading. Legacy Markdown remains usable and displays any heuristic-import warnings. Reimporting the same filename updates that pack while stable question and part identifiers preserve attempts. See the [Markdown authoring reference](../Docs/MARKDOWN_FORMAT.md) for the import contract.

## Spreadsheet practice

Load **Spreadsheet Practice**, open one of its two questions, then tap a grid cell or the formula bar. Begin a formula with `=` and use A1 references such as `=B1+C1-D1` or `=SUM(B1:B4)`. The Previous/Next controls and keyboard Next button move through cells. Raw formulas stay in the saved answer while evaluated values are shown separately and used for grading.

The local engine supports arithmetic, comparisons, ranges, percentages, and `SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`, `IF`, `PV`, `FV`, `PMT`, and `NPV`. It reports safe spreadsheet errors such as `#REF!`, `#DIV/0!`, and `#CYCLE!`. It does not require Excel, Numbers, a network connection, or an account. See the [spreadsheet reference](../Docs/SPREADSHEET.md) for the exact grammar and function rules.

## Local data

Ledger Pocket autosaves to this path inside its app sandbox:

```text
Library/Application Support/AccountingQuestionSuite/library-state.json
```

To inspect the currently booted Simulator's container:

```sh
LEDGER_POCKET_DATA=$(xcrun simctl get_app_container booted \
  com.accountingquestionsuite.ledgerpocket data)
open "$LEDGER_POCKET_DATA/Library/Application Support/AccountingQuestionSuite"
```

On a physical device, use Xcode's **Window → Devices and Simulators**, select the installed app, and download its container. The JSON file is under the same `AppData/Library/Application Support/AccountingQuestionSuite/` path. Deleting the app deletes this local state unless the device or container was backed up. No account, analytics service, sync service, or remote database is used.
