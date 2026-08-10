# Accounting Question Markdown v1

The three apps import ordinary `.md` files. Structured files receive specialized editors and automatic grading; existing textbook-style Markdown is also accepted through a legacy importer.

## Minimal structured question

```markdown
:::question id=equation-001 shell=multipart variation=core formats=single_number,initial_journal_entry tags=chapter-2,equation
# Accounting Equation and Entry
## Scenario
A company receives **$10,000 cash** from its owner in exchange for common shares.

:::part id=a kind=number format=single_number points=1
### Prompt
By how much does total equity increase?
### Answer
10000
### Settings
tolerance: 0
:::endpart

:::part id=b kind=journal format=initial_journal_entry points=2
### Prompt
Prepare the journal entry.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Cash | 10000 | |
| Common Stock | | 10000 |
### Settings
row_order: any
:::endpart
:::endquestion
```

## Question directive

`:::question` accepts space-separated `key=value` attributes. Values must not contain spaces.

| Attribute | Required | Values |
|---|---|---|
| `id` | yes | Stable unique identifier |
| `shell` | no | `multiple_choice`, `standalone_calculation`, `multipart`, `multiple_case`, `lifecycle`, `comprehensive`, `memo_research` |
| `variation` | no | `core`, `number_variant`, `alternate_angle`, `counterfactual`, `diagnostic`, `long_path`, `independent_cases`, `staff_draft` |
| `formats` | recommended | Comma-separated pedagogical format IDs |
| `tags` | no | Comma-separated tags |

Close every question with `:::endquestion`.

## Part directive

`:::part id=a kind=number format=single_number points=2`

Every part needs `### Prompt` and `### Answer`. Optional sections are `### Options`, `### Columns`, `### Items`, `### Targets`, `### Accepted`, `### Rubric`, and `### Settings`. Close it with `:::endpart`.

### Editor kinds

| `kind` | Used for | Answer form |
|---|---|---|
| `single_choice` | A–D multiple choice | Option ID |
| `multiple_choice` | Select-all | Comma-separated option IDs |
| `number` | Amount, ratio, rate | Number; optional `tolerance` setting |
| `formula` | Formula or spreadsheet function | Formula text; optional `### Accepted` alternatives |
| `short_text` | Short exact response | Text; use `accepted` for automatic grading |
| `long_text` | Explanation, memo, disclosure, research | Model answer plus rubric; self-reviewed |
| `journal` | Journal entries | Markdown table answer |
| `table` | Schedules, statements, grids, worksheets | Markdown table answer |
| `matching` | Matching/classification | `leftID => targetID` lines |
| `ordering` | Ordering/ranking/timeline | Ordered list of item IDs |
| `true_false` | Assertion audit | `True` or `False`; correction in rubric |
| `no_entry` | Entry/no-entry judgment | `Entry` or `No entry`; rationale in rubric |

Use one bullet per `### Accepted` alternative when a short-text or formula answer has several valid forms. This is preferred for spreadsheet functions because formulas themselves contain commas:

```markdown
### Answer
=-PV(8%,3,0,10000)
### Accepted
- =PV(8%,3,0,-10000)
- =10000/(1+8%)^3
```

### Options, items, and targets

Use stable IDs followed by a pipe:

```markdown
### Options
- A | Expense immediately
- B | Capitalize as an asset
```

### Matching answer

```markdown
### Items
- cash | Cash
- inventory | Inventory
### Targets
- current | Current asset
- noncurrent | Noncurrent asset
### Answer
- cash => current
- inventory => current
```

### Ordering answer

```markdown
### Items
- recognize | Initial recognition
- measure | Subsequent measurement
- settle | Settlement
### Answer
- recognize
- measure
- settle
```

## Legacy Markdown

The importer recognizes large files organized with headings such as `## Item 42` or ``### `core_001_q1` ``, along with `**Question:**`, `**Required:**`, `**Answer:**`, and `**Answer key:**`. It automatically detects standard A–D multiple choice. If one item contains paired markers such as `**Question 1:**` / `**Question 2:**`, `**Question 4.1**`, or `**Q4A.**`, each question-and-answer pair becomes its own working part. Other legacy items open in a long-form response editor with the supplied answer key available for self-review.

For tables, journals, matching, ordering, numerical tolerances, and automatic grading, wrap the item in the structured directives above.

## Coverage principle

The format is intentionally compositional. A comprehensive question contains several parts, and each part selects one of twelve editor primitives. Together they implement all 35 catalogued response formats, including schedules, T-accounts, statements, effect grids, disclosures, proof/tie-outs, sensitivities, threshold tests, research memos, and AIS flows.

## Pedagogical format IDs

Use one of these values in a part’s `format=` attribute. A question’s `formats=` attribute can contain several comma-separated values.

| Format ID | Student work product |
|---|---|
| `multiple_choice` | Single-best-answer or select-all objective response |
| `single_number` | One accounting amount |
| `formula_setup` | Formula or spreadsheet-function construction |
| `initial_journal_entry` | Initial-recognition entry |
| `adjusting_journal_entry` | Period-end adjustment |
| `correcting_journal_entry` | Correction or prior-period adjustment |
| `closing_reversing_entry` | Closing or reversing entry |
| `settlement_entry` | Disposal, maturity, conversion, or settlement entry |
| `entry_or_no_entry` | Entry/no-entry judgment and rationale |
| `multi_period_schedule` | Multi-period schedule |
| `rollforward` | Beginning-to-ending bridge |
| `t_account` | T-account or ledger reconstruction |
| `backsolve` | Missing amount derived from other balances |
| `worksheet_trial_balance` | Worksheet or trial balance |
| `full_statement` | Complete financial statement |
| `partial_statement` | Face section, excerpt, or subtotal |
| `presentation_classification_grid` | Presentation or classification matrix |
| `effect_matrix` | Overstated/understated/no-effect matrix |
| `include_exclude_table` | Include/exclude discrimination table |
| `disclosure_drafting` | Footnote or accounting-policy draft |
| `reconciliation_proof` | Reconciliation, proof, or tie-out |
| `error_correction` | Identify, quantify, and correct errors |
| `correct_versus_incorrect` | Correct treatment versus a wrong method |
| `alternative_method_comparison` | Two-or-more-method comparison |
| `sensitivity_changed_fact` | What-if or one-variable sensitivity |
| `threshold_criteria_test` | Apply a threshold or numbered criteria |
| `ranking_sequential_inclusion` | Rank and add candidates to a cutoff |
| `ordering_timeline` | Chronological or process sequencing |
| `ratio_analysis` | Ratio calculation and interpretation |
| `short_explanation` | Concise justification |
| `claim_evaluation` | Evaluate an intern/controller/CFO assertion |
| `true_false_correction` | True/false plus correction |
| `matching_mapping_sorting` | Matching, mapping, or sorting |
| `codification_research` | Research navigation, citation, or memo |
| `ais_source_document_flow` | Source document, journal, posting, and AIS flow |
