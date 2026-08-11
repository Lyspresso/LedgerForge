# Changelog

All notable changes to the Accounting Question Suite are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and suite releases use semantic versions.

## [Unreleased]

### Added

- GitHub Actions validation and public contribution, security, issue, and pull-request guidance.

## [1.0.0] - 2026-08-10

### Added

- LedgerForge for macOS 11 and later, implemented in Rust with `eframe`/`egui`.
- Statement Studio for macOS 14 and later, implemented in SwiftUI.
- Ledger Pocket for iOS and iPadOS 17 and later, implemented in SwiftUI.
- Structured Accounting Question Markdown v1 and heuristic legacy ACCOUNT343-style import.
- Seven question shells, eight variation styles, all 35 catalogued response formats, and 12
  specialized response editors.
- Deterministic grading for objective responses and explicit rubric self-review for professional
  writing and judgment.
- Spreadsheet-style tables and formula responses with A1 references, ranges, arithmetic,
  comparisons, percentages, safe errors, and `SUM`, `AVERAGE`, `MIN`, `MAX`, `ROUND`, `ABS`, `IF`,
  `PV`, `FV`, `PMT`, and `NPV`.
- Local autosave, reimport-safe identifiers, library search and filters, progress tracking, answer
  reveal, and import warnings.
- Original all-formats, spreadsheet, lifecycle, and authoring-template sample packs.
- Shared Rust and Swift validation coverage, including optional read-only checks for private banks
  supplied by an authorized user.

### Changed

- Aligned LedgerForge's visual language with the native Statement Studio experience: system accent
  colors, compact three-column navigation, stacked response cards, and grouped review information.

### Security

- No account, API key, analytics service, remote database, or network connection is required.
- Imported files are read locally and user progress remains in each application's local container.

[Unreleased]: https://github.com/Lyspresso/LedgerForge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Lyspresso/LedgerForge/releases/tag/v1.0.0
