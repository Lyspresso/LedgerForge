# Accounting Question Suite — v1.0.0 Delivery Manifest

Release tag: `v1.0.0`

Release commit: `{{RELEASE_COMMIT_SHA}}`

Packaged: `{{PACKAGED_AT_UTC}}`

This manifest is a release checklist and evidence record. Before publishing, replace every
`{{PLACEHOLDER}}` with a value measured from artifacts produced from the release commit. The tag
must resolve to the recorded commit; documentation-only changes after packaging require a new
package or an explicit release note.

## Products

| Product | Platform | Release asset | Source project |
|---|---|---|---|
| LedgerForge | macOS 11+, Apple silicon | `LedgerForge-macOS.zip` | `../MacRust` |
| Statement Studio | macOS 14+, Intel and Apple silicon | `Statement-Studio-macOS.zip` | `../MacSwiftUI` |
| Ledger Pocket | iOS/iPadOS 17+ | `Ledger-Pocket-iOS-Simulator.zip`; `Ledger-Pocket-iOS-Xcode.zip` | `../iOSSwiftUI` |

The GitHub-generated source archives for the `v1.0.0` tag are the canonical suite source archives.
Do not upload a separately staged source ZIP unless it is rebuilt from this exact commit and its
contents are independently verified.

## Functional coverage

- Seven question shells and eight variation styles.
- All 35 catalogued accounting response formats, composed from 12 working editors.
- Structured Markdown v1 plus heuristic ACCOUNT343-style legacy import.
- Deterministic objective grading and explicit rubric self-review for professional writing and
  judgment.
- Local persistence, resume, search/filtering, progress, reveal, and import warnings.
- Spreadsheet-enabled grids with raw-formula preservation and evaluated-value grading.
- A1 references, ranges, arithmetic, comparisons, percentages, `SUM`, `AVERAGE`, `MIN`, `MAX`,
  `ROUND`, `ABS`, `IF`, `PV`, `FV`, `PMT`, and `NPV`.
- No server, account, API key, analytics service, cloud database, or runtime network dependency.

## v1.0.0 validation gates

Record the final workflow run URL: `{{CI_WORKFLOW_RUN_URL}}`

| Layer | Required evidence |
|---|---|
| Shared Swift parser/grader/spreadsheet package | 16 repository-contained tests; `ALL_FORMATS_SAMPLE.md` passes `aqvalidate` |
| LedgerForge Rust | 53 repository-contained tests; format check; Clippy with `-D warnings`; locked Release build for macOS 11 |
| Optional Rust private-bank QA | 2 read-only test functions, run only with authorized `LEDGERFORGE_QA_*` files |
| Statement Studio macOS | 11 repository-contained tests plus one optional external-bank test; unsigned generic Release build |
| Ledger Pocket iOS | 16 repository-contained simulator tests; unsigned generic simulator Release build |

The two optional Rust bank validators are compiled but marked ignored. The ordinary public gate
therefore reports 53 passed and 2 ignored; an authorized maintainer can run the ignored test target
with both `LEDGERFORGE_QA_*` paths set. The optional Statement Studio external-bank test is skipped
when its fixtures are absent.

Private-bank validation previously established the following structural counts. Those source files
are not release assets and must not be committed or attached to issues:

| Authorized local source | Questions | Answerable parts | Choice parts | Long-text parts | Import warnings | Authoring issues |
|---|---:|---:|---:|---:|---:|---:|
| `ACCOUNT343_COMPLETE.md` | 3,088 | 3,228 | 754 | 2,474 | 1 | 0 |
| `ACCOUNT343_NEEDS_HUMAN.md` | 78 | 80 | 9 | 71 | 1 | 2 |

The one import warning on each bank records legacy-layout inference. The two needs-human authoring
issues are `core_047_q3/response` and `core_233_q3/response`, both lacking a model answer or rubric.
Structural validation does not establish that any answer key is accounting-correct; needs-human
keys still require human review.

## Release assets and checksums

Generate hashes only after the final packages are immutable:

```sh
shasum -a 256 \
  LedgerForge-macOS.zip \
  Statement-Studio-macOS.zip \
  Ledger-Pocket-iOS-Simulator.zip \
  Ledger-Pocket-iOS-Xcode.zip
```

| Archive | Size in bytes | SHA-256 |
|---|---:|---|
| `LedgerForge-macOS.zip` | `{{LEDGERFORGE_ZIP_SIZE_BYTES}}` | `{{LEDGERFORGE_ZIP_SHA256}}` |
| `Statement-Studio-macOS.zip` | `{{STATEMENT_STUDIO_ZIP_SIZE_BYTES}}` | `{{STATEMENT_STUDIO_ZIP_SHA256}}` |
| `Ledger-Pocket-iOS-Simulator.zip` | `{{LEDGER_POCKET_SIMULATOR_ZIP_SIZE_BYTES}}` | `{{LEDGER_POCKET_SIMULATOR_ZIP_SHA256}}` |
| `Ledger-Pocket-iOS-Xcode.zip` | `{{LEDGER_POCKET_XCODE_ZIP_SIZE_BYTES}}` | `{{LEDGER_POCKET_XCODE_ZIP_SHA256}}` |

Also attach a `SHA256SUMS.txt` generated from those four assets. Confirm every archive with
`unzip -t`, extract it to a temporary directory, and repeat the relevant signature/build check on
the extracted content.

## Signing and distribution

- LedgerForge is an Apple-silicon app with an ad-hoc signature. It is not Developer ID signed or
  notarized.
- Statement Studio is universal (`x86_64` and `arm64`), sandboxed, hardened-runtime enabled, and
  ad-hoc signed. It is not Developer ID signed or notarized.
- Ledger Pocket's prebuilt Simulator app is **unsigned** and cannot run on a physical device. The
  Xcode source archive is also not a signed application.
- Running Ledger Pocket on physical hardware or producing an IPA requires the user's own Apple
  development team, signing identity, bundle identifier entitlement, and provisioning profile.
- Public distribution of either Mac app without a Gatekeeper warning requires Developer ID signing
  and Apple notarization.

## Publication checklist

- [ ] `v1.0.0` is an annotated tag and resolves to `{{RELEASE_COMMIT_SHA}}`.
- [ ] CI is green for the tagged commit and its run URL is recorded above.
- [ ] All placeholders in this manifest are replaced with measured values.
- [ ] Four release archives and `SHA256SUMS.txt` are attached to the GitHub release.
- [ ] Archive integrity, extracted app signatures, architectures, deployment targets, and clean
      source builds have been independently checked.
- [ ] Release notes repeat the ad-hoc/unsigned and physical-device signing caveats.
- [ ] No private bank, answer key, student data, local state, credentials, or absolute build path is
      present in the assets.

See the project-specific READMEs and `../Docs` for build, import, spreadsheet, persistence, and
authoring details.
