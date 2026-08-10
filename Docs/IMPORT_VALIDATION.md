# Import Validation Report

Validation date: 2026-08-10

The shared Markdown parser and validator were exercised against the bundled samples and both supplied ACCOUNT343 banks.

The ACCOUNT343 banks are private course material and are **not** included in this repository. Only their import statistics are reported here. The test harnesses that read them (`MacRust/tests/supplied_bank_qa.rs`, `MacSwiftUI/Tests/AppStoreTests.swift`) skip themselves unless you set the corresponding environment variable to a bank file of your own.

| Source | Question items | Answerable parts | Import warnings | Authoring issues |
|---|---:|---:|---:|---:|
| `Samples/ALL_FORMATS_SAMPLE.md` | 35 | 36 | 0 | 0 |
| `Samples/COMPREHENSIVE_LIFECYCLE.md` | 1 | 7 | 0 | 0 |
| `Samples/SPREADSHEET_PRACTICE.md` | 2 | 5 | 0 | 0 |
| `ACCOUNT343_COMPLETE.md` | 3,088 | 3,228 | 1 | 0 |
| `ACCOUNT343_NEEDS_HUMAN.md` | 78 | 80 | 1 | 2 |

The one warning on each ACCOUNT343 bank is expected: those files use the legacy layout, so the importer must infer question boundaries and editor types. Standard A–D multiple-choice questions are detected and graded automatically. Other legacy prompts remain answerable with a long-form editor and model-answer review.

Several CORE items contain two complete multiple-choice subquestions under one item heading. The importer preserves those as separate answerable parts rather than discarding everything after the first answer key. The complete bank contains 754 detected single-choice parts and 2,474 long-form parts; the needs-human bank contains 9 single-choice parts and 71 long-form parts.

The two issues in `ACCOUNT343_NEEDS_HUMAN.md` are `core_047_q3/response` and `core_233_q3/response`. Both are written-response items without a model answer or rubric. They still import, but the apps must present them as unverified rather than automatically graded.

The validator does not certify the correctness of an answer key. In particular, `ACCOUNT343_NEEDS_HUMAN.md` is useful for question structures but its keys should remain flagged for human review.

## Reproduce the check

From `Shared/AccountingQuestionKit`:

```sh
swift run aqvalidate ../../Samples/ALL_FORMATS_SAMPLE.md
swift run aqvalidate ../../Samples/COMPREHENSIVE_LIFECYCLE.md
swift run aqvalidate /path/to/ACCOUNT343_COMPLETE.md
swift run aqvalidate /path/to/ACCOUNT343_NEEDS_HUMAN.md
```
