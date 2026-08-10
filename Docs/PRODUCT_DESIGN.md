# Three-App Product Design

## Shared learning model

All three applications use the same Markdown v1 contract and the same learning loop:

1. Import one or more `.md` question packs.
2. Browse and filter the library by shell, response format, variation style, tag, or source.
3. Open a question and answer each part with the editor appropriate to that part.
4. Check deterministic work immediately. Long explanations, disclosures, memos, and research responses reveal a model answer and rubric for self-review.
5. Save attempts locally and resume them later.

The product treats an accounting problem as a composition of parts rather than forcing every question into one text field. Twelve editor primitives cover all 35 response formats.

## App 1 — LedgerForge Rust for macOS

**Character:** a fast, keyboard-friendly accounting workbench built in Rust with `eframe/egui`.

**Desktop layout:**

- Left rail: imported packs, search, format filters, question list.
- Main canvas: scenario, progress, and the active answer editor.
- Right review panel: grade state, expected answer, rubric, and self-review controls.
- Native file picker for Markdown import and local JSON persistence.

**Why it is distinct:** it favors dense information, fast switching, explicit status color, and predictable cross-platform-style controls while still packaging as a real `.app` for macOS.

## App 2 — Statement Studio for macOS (SwiftUI/Xcode)

**Character:** a fully native Mac document workspace.

**Desktop layout:**

- `NavigationSplitView` sidebar for sources and questions.
- Flexible detail column for the active problem.
- Native inspector for metadata, answer status, and rubric.
- Standard File > Import command, toolbar import button, searchable library, resizable columns, and keyboard shortcuts.

**Native behaviors:** file import uses the system picker; menus remain the primary command surface; selection is persistent; large reading content has a constrained measure; window resizing never hides the editor.

## App 3 — Ledger Pocket for iPhone/iPad (SwiftUI/Xcode)

**Character:** a focused study companion rather than a desktop UI squeezed onto a phone.

**Mobile layout:**

- Library landing screen with progress cards and format chips.
- One question part at a time, with scenario available in a collapsible sheet/card.
- Sticky bottom action area for Check, Reveal, and Next.
- Files-based Markdown import.
- On iPad, long-form content stays within a readable maximum width.

**Visual language:** warm paper-like accent wash, system semantic surfaces, serif question prose, rounded progress numerals, monospaced accounting amounts, Dynamic Type, dark mode, VoiceOver labels, reduced-motion behavior, and additive success/error haptics.

## Editor mapping

| Editor primitive | Formats served |
|---|---|
| Single choice | Single-best-answer MC |
| Multiple choice | Select-all objective questions |
| Number | Amounts, ratios, back-solving |
| Formula | Formula construction and spreadsheet-input work |
| Short text | Exact terminology and concise explanations |
| Long text | Memos, disclosures, research, claim evaluation, error explanations |
| Journal | Initial, adjusting, correcting, closing, settlement entries |
| Table | Spreadsheet-enabled schedules, rollforwards, T-accounts, worksheets, statements, effect grids, comparisons, sensitivities, criteria tests, reconciliations |
| Matching | Classification, mapping, include/exclude, AIS flows |
| Ordering | Ranking, sequential inclusion, timelines |
| True/false + notes | Assertion audits with correction |
| Entry/no-entry + notes | Recognition judgment with rationale |

## Grading policy

- Choice, number, formula, journal, table, matching, ordering, true/false, and the entry decision are machine-checked.
- Numerical answers support an author-specified tolerance.
- Journal/table authors can allow arbitrary row order.
- Short text can list accepted alternatives.
- Judgment-heavy writing is deliberately self-reviewed against an answer and rubric; the apps do not pretend exact string matching can grade professional reasoning.

## Import policy

- Structured Markdown activates every specialized editor and grading rule.
- Existing ACCOUNT343-style Markdown imports without rewriting. Standard A–D MC is detected automatically; other unstructured items use a complete long-form response and model-answer review.
- Stable question and part IDs allow attempts to survive re-imports and library restarts.
- Import warnings are visible and never silently discard a question.
