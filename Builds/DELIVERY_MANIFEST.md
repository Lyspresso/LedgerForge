# Accounting Question Suite — Delivery Manifest

Finalized: 2026-08-10

## Delivered products

| Product | Platform | Ready artifact | Source project |
|---|---|---|---|
| LedgerForge | macOS 11+, Apple silicon | `LedgerForge.app` / `LedgerForge-macOS.zip` | `../MacRust` |
| Statement Studio | macOS 14+, Intel and Apple silicon | `Statement Studio.app` / `Statement-Studio-macOS.zip` | `../MacSwiftUI` |
| Ledger Pocket | iOS/iPadOS 17+ | Simulator app/zip; user-signable Xcode zip | `../iOSSwiftUI` |

Each product received four separate specialist passes: architecture/import, complete editor UI, independent QA/accessibility, and release packaging.

## Functional coverage

- Seven question shells and eight variation styles.
- All 35 catalogued accounting response formats, composed from 12 working editors.
- Structured Markdown v1 plus heuristic ACCOUNT343 legacy import.
- Paired legacy multiple-choice blocks remain separate answerable parts.
- Deterministic objective grading and explicit rubric self-review for professional judgment/writing.
- Local persistence, resume, search/filtering, progress, reveal, and import warnings.
- Spreadsheet-enabled grids with raw formula preservation and evaluated-value grading.
- A1 references, ranges, arithmetic, comparisons, percentages, `SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`, `IF`, `PV`, `FV`, `PMT`, and `NPV`.
- Safe visible errors including reference, value, divide-by-zero, cycle, name, number, and parse failures.
- No server, account, API key, analytics service, or network dependency.

## Validation results

| Layer | Result |
|---|---|
| Shared Swift parser/grader/spreadsheet package | 16/16 tests passed |
| LedgerForge Rust | 49/49 tests; formatting, Clippy `-D warnings`, offline Release build passed |
| Statement Studio macOS | 12/12 tests; clean Debug tests and universal Release build passed |
| Ledger Pocket iOS | 16/16 on iPhone 17 Pro and 16/16 on iPad Pro 11-inch; generic and Release builds passed |

Read-only supplied-bank validation:

| Source | Question items | Answerable parts | Choice parts | Long-text parts | Issues |
|---|---:|---:|---:|---:|---:|
| `ACCOUNT343_COMPLETE.md` | 3,088 | 3,228 | 754 | 2,474 | 0 |
| `ACCOUNT343_NEEDS_HUMAN.md` | 78 | 80 | 9 | 71 | 2 warnings |

The two needs-human warnings are `core_047_q3/response` and `core_233_q3/response`, both lacking a model answer/rubric. They import but remain unverified. The validator confirms structure, not the correctness of an answer key; the needs-human keys should still receive human review.

## Archives and checksums

| Archive | Size | SHA-256 |
|---|---:|---|
| `LedgerForge-macOS.zip` | 5,112,153 bytes | `94a5ed594cefc1b8f0e45f059e0ea24a572f74665a7725a103af31d96cfd5173` |
| `Statement-Studio-macOS.zip` | 2,001,369 bytes | `aaaca20a320b39c611ade1c4f22a2004c64cddb055c81dca20c98d47bb8400c0` |
| `Ledger-Pocket-iOS-Simulator.zip` | 2,580,744 bytes | `c7623f70748c27585e2fd7fdaf9667e5be03a53d92998963380a28b2494a3249` |
| `Ledger-Pocket-iOS-Xcode.zip` | 486,446 bytes | `1509b9130b3d39b7e888a07eaf863bf7ed346c52dc1e32b8f34c03ab0197764d` |
| `Accounting-Question-Suite-Source.zip` | 3,318,873 bytes | `a6d3237a8cdc15961e3adbf3b5b13f5758ffae2c218b8039a0dea4fbff86240b` |

All archives passed integrity checks. The two Mac zips were extracted and their app signatures reverified; the iOS Xcode zip was independently built from its staged self-contained layout.

## Signing and distribution caveats

- LedgerForge is an arm64 app with an ad-hoc signature. On first launch, use Control-click → Open if Gatekeeper blocks it.
- Statement Studio is universal (`x86_64` + `arm64`), sandboxed, hardened-runtime, and ad-hoc signed. It is not Developer ID signed or notarized.
- Ledger Pocket’s prebuilt app is for iOS Simulator only. Running on a physical iPhone/iPad or producing an IPA requires the user's Apple development team, signing identity, and provisioning profile in Xcode.
- Public distribution of either Mac app requires Developer ID signing and Apple notarization.

See the project-specific READMEs and `../Docs` for exact build, import, spreadsheet, persistence, and authoring instructions.
