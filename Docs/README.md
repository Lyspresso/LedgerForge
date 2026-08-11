# LedgerForge documentation

Start with the [suite overview](../README.md), then use the reference that matches your task.

## Use the applications

| Application | Guide |
|---|---|
| LedgerForge for macOS (Rust) | [MacRust/README.md](../MacRust/README.md) |
| Statement Studio for macOS | [MacSwiftUI/README.md](../MacSwiftUI/README.md) |
| Ledger Pocket for iPhone and iPad | [iOSSwiftUI/README.md](../iOSSwiftUI/README.md) |

## Author and validate questions

- [MARKDOWN_FORMAT.md](MARKDOWN_FORMAT.md) defines structured Markdown v1, legacy import behavior, editor kinds, and all pedagogical format IDs.
- [SPREADSHEET.md](SPREADSHEET.md) defines A1 references, formulas, supported functions, and spreadsheet error behavior.
- [IMPORT_VALIDATION.md](IMPORT_VALIDATION.md) describes importer validation against large private banks and clearly separates structural validation from answer-key review.
- [ADAPTIVE_TITLES.md](ADAPTIVE_TITLES.md) explains readable title derivation, collapsed source metadata, existing-library compatibility, and the optional Apple Intelligence boundary.
- [QUESTION_TEMPLATE.md](../Samples/QUESTION_TEMPLATE.md) is the fastest authoring starting point.
- [ALL_FORMATS_SAMPLE.md](../Samples/ALL_FORMATS_SAMPLE.md) demonstrates every supported response format.
- [SPREADSHEET_PRACTICE.md](../Samples/SPREADSHEET_PRACTICE.md) demonstrates formula-enabled questions.
- [COMPREHENSIVE_LIFECYCLE.md](../Samples/COMPREHENSIVE_LIFECYCLE.md) demonstrates an integrated multipart lifecycle problem.

Validate a pack with the shared command-line tool:

```sh
cd Shared/AccountingQuestionKit
swift run aqvalidate ../../path/to/questions.md
```

Validation confirms structure and importer compatibility, not the accounting correctness of an answer key.

## Product and interface references

- [PRODUCT_DESIGN.md](PRODUCT_DESIGN.md) maps the accounting question catalog to application behavior.
- [VISUAL_LANGUAGE.md](VISUAL_LANGUAGE.md) defines the shared appearance across the Rust, macOS SwiftUI, and iOS apps.
- [Visual QA](Visual%20QA/) contains reference screenshots used for interface review.

All three applications operate offline after installation. Building from source may require development tools and an initial dependency fetch; see the root [prerequisites and quick start](../README.md#development-prerequisites).
