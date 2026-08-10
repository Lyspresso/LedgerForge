# Accounting Question Studio — Complete Format Sampler

This original practice pack contains one compact, working example for every supported pedagogical format. Amounts are intentionally small so the response mechanics are easy to inspect.

:::question id=fmt-00-mc shell=multiple_choice variation=core formats=multiple_choice tags=sample,objective
# Single-best-answer multiple choice
## Scenario
A company pays a supplier for an amount previously recorded in Accounts Payable.
:::part id=a kind=single_choice format=multiple_choice points=1
### Prompt
Which account is debited?
### Options
- A | Cash
- B | Accounts Payable
- C | Service Revenue
- D | Accounts Receivable
### Answer
B
### Rubric
Paying an existing payable reduces the liability with a debit.
:::endpart
:::part id=b kind=multiple_choice format=multiple_choice points=2
### Prompt
Select every account that normally carries a debit balance.
### Options
- A | Cash
- B | Accounts Payable
- C | Supplies Expense
- D | Service Revenue
### Answer
A,C
### Rubric
Assets and expenses normally have debit balances; liabilities and revenues normally have credit balances.
:::endpart
:::endquestion

:::question id=fmt-01-number shell=standalone_calculation variation=core formats=single_number tags=sample,calculation
# Single-number computation
## Scenario
Assets are **$125,000** and liabilities are **$47,000**.
:::part id=a kind=number format=single_number points=1
### Prompt
Compute total equity.
### Answer
78000
### Settings
tolerance: 0
:::endpart
:::endquestion

:::question id=fmt-02-formula shell=standalone_calculation variation=core formats=formula_setup tags=sample,formula
# Formula or spreadsheet-function setup
## Scenario
Beginning inventory is $20,000, purchases are $70,000, and ending inventory is $18,000.
:::part id=a kind=formula format=formula_setup points=1
### Prompt
Enter the formula for cost of goods sold using the variable names `BI`, `P`, and `EI`.
### Answer
BI+P-EI
### Settings
accepted: BI + P - EI
:::endpart
:::endquestion

:::question id=fmt-03-initial-je shell=multipart variation=core formats=initial_journal_entry tags=sample,journal
# Initial-recognition journal entry
## Scenario
The company receives $10,000 cash from an owner for common shares.
:::part id=a kind=journal format=initial_journal_entry points=2
### Prompt
Record the issuance.
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

:::question id=fmt-04-adjusting-je shell=multipart variation=core formats=adjusting_journal_entry tags=sample,journal
# Adjusting journal entry
## Scenario
At year-end, $600 of supplies have been used. No adjustment has been recorded.
:::part id=a kind=journal format=adjusting_journal_entry points=2
### Prompt
Prepare the year-end adjustment.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Supplies Expense | 600 | |
| Supplies | | 600 |
### Settings
row_order: any
:::endpart
:::endquestion

:::question id=fmt-05-correcting-je shell=multipart variation=staff_draft formats=correcting_journal_entry tags=sample,journal,error
# Correcting journal entry
## Scenario
Equipment costing $4,000 was incorrectly debited to Repairs Expense. Cash was correctly credited.
:::part id=a kind=journal format=correcting_journal_entry points=2
### Prompt
Prepare the correcting entry, assuming the original entry has not been reversed.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Equipment | 4000 | |
| Repairs Expense | | 4000 |
### Settings
row_order: any
:::endpart
:::endquestion

:::question id=fmt-06-closing-je shell=multipart variation=core formats=closing_reversing_entry tags=sample,journal,closing
# Closing or reversing entry
## Scenario
Service Revenue has a $9,000 credit balance immediately before closing.
:::part id=a kind=journal format=closing_reversing_entry points=2
### Prompt
Close Service Revenue directly to Income Summary.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Service Revenue | 9000 | |
| Income Summary | | 9000 |
### Settings
row_order: any
:::endpart
:::endquestion

:::question id=fmt-07-settlement-je shell=lifecycle variation=long_path formats=settlement_entry tags=sample,journal,settlement
# Disposal, maturity, conversion, or settlement entry
## Scenario
A $5,000 note payable reaches maturity and is paid in cash. Ignore interest.
:::part id=a kind=journal format=settlement_entry points=2
### Prompt
Record settlement of principal.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Notes Payable | 5000 | |
| Cash | | 5000 |
### Settings
row_order: any
:::endpart
:::endquestion

:::question id=fmt-08-no-entry shell=multipart variation=alternate_angle formats=entry_or_no_entry tags=sample,judgment
# Entry-or-no-entry judgment
## Scenario
Management signs a noncancelable purchase order for ordinary inventory to be delivered next year. No cash or goods have changed hands.
:::part id=a kind=no_entry format=entry_or_no_entry points=2
### Prompt
Choose `Entry` or `No entry`, then explain your decision in the notes field.
### Answer
No entry
### Settings
accepted: no-entry,no entry required
### Rubric
An ordinary executory purchase commitment generally produces no journal entry when signed; disclose only if a separate disclosure requirement is triggered.
:::endpart
:::endquestion

:::question id=fmt-09-schedule shell=multipart variation=core formats=multi_period_schedule tags=sample,schedule
# Multi-period schedule
## Scenario
A $3,000 prepaid asset is expensed evenly over three years.
:::part id=a kind=table format=multi_period_schedule points=3
### Prompt
Complete the annual expense and ending-balance schedule.
### Columns
Year | Expense | Ending balance
### Answer
| Year | Expense | Ending balance |
|---|---:|---:|
| 1 | 1000 | 2000 |
| 2 | 1000 | 1000 |
| 3 | 1000 | 0 |
:::endpart
:::endquestion

:::question id=fmt-10-rollforward shell=multipart variation=core formats=rollforward tags=sample,rollforward
# Beginning-to-ending rollforward
## Scenario
The allowance begins at $400 credit, expense is $700, and write-offs are $300.
:::part id=a kind=table format=rollforward points=2
### Prompt
Prepare the rollforward.
### Columns
Beginning | Additions | Reductions | Ending
### Answer
| Beginning | Additions | Reductions | Ending |
|---:|---:|---:|---:|
| 400 | 700 | 300 | 800 |
:::endpart
:::endquestion

:::question id=fmt-11-t-account shell=multipart variation=alternate_angle formats=t_account tags=sample,t-account
# T-account or ledger reconstruction
## Scenario
Cash begins at $2,000. Receipts are $7,000 and payments are $5,500.
:::part id=a kind=table format=t_account points=2
### Prompt
Complete the Cash T-account summary.
### Columns
Beginning debit | Debit activity | Credit activity | Ending debit
### Answer
| Beginning debit | Debit activity | Credit activity | Ending debit |
|---:|---:|---:|---:|
| 2000 | 7000 | 5500 | 3500 |
:::endpart
:::endquestion

:::question id=fmt-12-backsolve shell=standalone_calculation variation=diagnostic formats=backsolve tags=sample,backsolve
# Missing-amount or back-solving problem
## Scenario
Beginning Accounts Receivable was $8,000, credit sales were $30,000, and ending Accounts Receivable was $6,500. There were no write-offs or other changes.
:::part id=a kind=number format=backsolve points=2
### Prompt
Compute cash collected from customers.
### Answer
31500
### Settings
tolerance: 0
:::endpart
:::endquestion

:::question id=fmt-13-worksheet shell=multipart variation=core formats=worksheet_trial_balance tags=sample,worksheet
# Worksheet or trial-balance completion
## Scenario
The unadjusted Supplies balance is $900 debit and the adjustment is $600 credit.
:::part id=a kind=table format=worksheet_trial_balance points=2
### Prompt
Complete this single-account adjusted-trial-balance row.
### Columns
Account | Unadjusted debit | Adjustment credit | Adjusted debit
### Answer
| Account | Unadjusted debit | Adjustment credit | Adjusted debit |
|---|---:|---:|---:|
| Supplies | 900 | 600 | 300 |
:::endpart
:::endquestion

:::question id=fmt-14-full-statement shell=comprehensive variation=core formats=full_statement tags=sample,statement
# Full financial-statement preparation
## Scenario
Cash is $4,000, equipment is $9,000, accounts payable is $3,000, and common stock is $10,000.
:::part id=a kind=table format=full_statement points=4
### Prompt
Prepare the complete classified balance sheet for this simplified company.
### Columns
Caption | Amount
### Answer
| Caption | Amount |
|---|---:|
| Cash | 4000 |
| Equipment | 9000 |
| Total assets | 13000 |
| Accounts payable | 3000 |
| Common stock | 10000 |
| Total liabilities and equity | 13000 |
:::endpart
:::endquestion

:::question id=fmt-15-partial-statement shell=multipart variation=core formats=partial_statement tags=sample,statement
# Partial statement or statement excerpt
## Scenario
Accounts Receivable is $12,000 and its allowance is $700 credit.
:::part id=a kind=table format=partial_statement points=2
### Prompt
Prepare the receivables section of current assets.
### Columns
Caption | Amount
### Answer
| Caption | Amount |
|---|---:|
| Accounts receivable | 12000 |
| Less allowance for doubtful accounts | 700 |
| Accounts receivable, net | 11300 |
:::endpart
:::endquestion

:::question id=fmt-16-classification shell=multiple_case variation=independent_cases formats=presentation_classification_grid tags=sample,classification
# Presentation and classification grid
## Scenario
Classify each listed balance at year-end.
:::part id=a kind=matching format=presentation_classification_grid points=3
### Prompt
Match each item to its balance-sheet classification.
### Items
- cash | Cash available for operations
- building | Building used in operations
- ap | Accounts payable due in 30 days
### Targets
- current_asset | Current asset
- noncurrent_asset | Noncurrent asset
- current_liability | Current liability
### Answer
- cash => current_asset
- building => noncurrent_asset
- ap => current_liability
:::endpart
:::endquestion

:::question id=fmt-17-effect-matrix shell=multiple_case variation=diagnostic formats=effect_matrix tags=sample,effects
# Overstated-understated-no-effect matrix
## Scenario
Year-end depreciation expense of $1,000 was omitted.
:::part id=a kind=table format=effect_matrix points=3
### Prompt
State the effect before correction. Use `O`, `U`, or `NE`.
### Columns
Account or total | Effect
### Answer
| Account or total | Effect |
|---|---|
| Net income | O |
| Total assets | O |
| Total liabilities | NE |
:::endpart
:::endquestion

:::question id=fmt-18-include-exclude shell=multiple_case variation=core formats=include_exclude_table tags=sample,classification
# Include-or-exclude discrimination table
## Scenario
Determine which items enter the cash-and-cash-equivalents total.
:::part id=a kind=matching format=include_exclude_table points=3
### Prompt
Classify each item as `include` or `exclude`.
### Items
- checking | Demand checking account
- stamp | Postage stamps
- ninety_day | Original-maturity 90-day Treasury bill
### Targets
- include | Include
- exclude | Exclude
### Answer
- checking => include
- stamp => exclude
- ninety_day => include
:::endpart
:::endquestion

:::question id=fmt-19-disclosure shell=memo_research variation=core formats=disclosure_drafting tags=sample,disclosure
# Disclosure or footnote drafting
## Scenario
Inventory is measured using FIFO. The carrying amount is $45,000.
:::part id=a kind=long_text format=disclosure_drafting points=3
### Prompt
Draft a concise accounting-policy disclosure.
### Answer
Inventories are stated at the lower of cost and net realizable value, with cost determined using the FIFO method. Inventory was $45,000 at year-end.
### Rubric
The response should name the measurement basis, FIFO cost-flow assumption, and year-end amount without claiming that FIFO determines physical flow.
:::endpart
:::endquestion

:::question id=fmt-20-reconciliation shell=multipart variation=core formats=reconciliation_proof tags=sample,reconciliation
# Reconciliation, proof, or tie-out
## Scenario
Beginning cash is $5,000, operating cash flow is $3,000, investing cash flow is $(1,500), and financing cash flow is $500.
:::part id=a kind=table format=reconciliation_proof points=3
### Prompt
Reconcile beginning cash to ending cash.
### Columns
Line | Amount
### Answer
| Line | Amount |
|---|---:|
| Beginning cash | 5000 |
| Operating cash flow | 3000 |
| Investing cash flow | -1500 |
| Financing cash flow | 500 |
| Ending cash | 7000 |
:::endpart
:::endquestion

:::question id=fmt-21-error shell=multipart variation=staff_draft formats=error_correction tags=sample,error
# Error identification and correction
## Scenario
An intern states: “Omitting accrued wages understates liabilities and understates net income.”
:::part id=a kind=long_text format=error_correction points=3
### Prompt
Identify and correct the error in the statement.
### Answer
Omitting accrued wages understates liabilities but overstates net income because wage expense was omitted.
### Rubric
Award credit for both directions and the causal explanation.
:::endpart
:::endquestion

:::question id=fmt-22-wrong-correct shell=multiple_case variation=diagnostic formats=correct_versus_incorrect tags=sample,diagnostic
# Correct-versus-incorrect method comparison
## Scenario
An asset costs $10,000 and has a $2,000 residual value over four years. An intern ignores residual value.
:::part id=a kind=table format=correct_versus_incorrect points=3
### Prompt
Compare correct and incorrect annual straight-line depreciation.
### Columns
Method | Annual depreciation | Misstatement
### Answer
| Method | Annual depreciation | Misstatement |
|---|---:|---:|
| Correct | 2000 | 0 |
| Intern | 2500 | 500 overstatement |
:::endpart
:::endquestion

:::question id=fmt-23-method-comparison shell=multiple_case variation=alternate_angle formats=alternative_method_comparison tags=sample,comparison
# Alternative-method comparison
## Scenario
Under Method A, expense is $8,000. Under Method B, expense is $6,500.
:::part id=a kind=table format=alternative_method_comparison points=2
### Prompt
Compare the income effect, assuming no tax.
### Columns
Method | Expense | Relative pretax income
### Answer
| Method | Expense | Relative pretax income |
|---|---:|---|
| A | 8000 | 1500 lower |
| B | 6500 | 1500 higher |
:::endpart
:::endquestion

:::question id=fmt-24-sensitivity shell=multiple_case variation=counterfactual formats=sensitivity_changed_fact tags=sample,sensitivity
# Sensitivity or changed-fact calculation
## Scenario
Base revenue is 1,000 units at $12 each. Consider price changes only.
:::part id=a kind=table format=sensitivity_changed_fact points=3
### Prompt
Complete the one-variable sensitivity table.
### Columns
Case | Price | Revenue | Change from base
### Answer
| Case | Price | Revenue | Change from base |
|---|---:|---:|---:|
| Base | 12 | 12000 | 0 |
| Price up | 13 | 13000 | 1000 |
| Price down | 11 | 11000 | -1000 |
:::endpart
:::endquestion

:::question id=fmt-25-threshold shell=multipart variation=core formats=threshold_criteria_test tags=sample,threshold
# Threshold or criteria test
## Scenario
A covenant requires a current ratio of at least 1.50. Current assets are $90,000 and current liabilities are $60,000.
:::part id=a kind=table format=threshold_criteria_test points=3
### Prompt
Compute the ratio and conclude whether the threshold is met.
### Columns
Current assets | Current liabilities | Ratio | Conclusion
### Answer
| Current assets | Current liabilities | Ratio | Conclusion |
|---:|---:|---:|---|
| 90000 | 60000 | 1.5 | Met |
:::endpart
:::endquestion

:::question id=fmt-26-ranking shell=multiple_case variation=core formats=ranking_sequential_inclusion tags=sample,ranking
# Ranking and sequential-inclusion problem
## Scenario
Three alternatives have incremental costs of A=$9, B=$4, and C=$7.
:::part id=a kind=ordering format=ranking_sequential_inclusion points=2
### Prompt
Rank the alternatives from lowest to highest incremental cost.
### Items
- A | Alternative A, cost 9
- B | Alternative B, cost 4
- C | Alternative C, cost 7
### Answer
- B
- C
- A
:::endpart
:::endquestion

:::question id=fmt-27-ordering shell=lifecycle variation=core formats=ordering_timeline tags=sample,timeline
# Ordering or timeline reconstruction
## Scenario
An accounting item passes through recognition, subsequent measurement, and derecognition.
:::part id=a kind=ordering format=ordering_timeline points=2
### Prompt
Place the stages in chronological order.
### Items
- derecognize | Derecognize the item
- recognize | Initially recognize the item
- measure | Perform subsequent measurement
### Answer
- recognize
- measure
- derecognize
:::endpart
:::endquestion

:::question id=fmt-28-ratio shell=standalone_calculation variation=core formats=ratio_analysis tags=sample,ratio
# Ratio calculation and interpretation
## Scenario
Current assets are $48,000 and current liabilities are $32,000.
:::part id=a kind=number format=ratio_analysis points=1
### Prompt
Compute the current ratio.
### Answer
1.5
### Settings
tolerance: 0.001
:::endpart
:::endquestion

:::question id=fmt-29-explanation shell=memo_research variation=core formats=short_explanation tags=sample,explanation
# Short explanation or justification
## Scenario
Cash was received before a promised service was performed.
:::part id=a kind=short_text format=short_explanation points=2
### Prompt
Name the balance-sheet element initially recognized.
### Answer
contract liability
### Settings
accepted: unearned revenue,deferred revenue
### Rubric
The response should identify a liability because performance remains owed.
:::endpart
:::endquestion

:::question id=fmt-30-claim shell=memo_research variation=staff_draft formats=claim_evaluation tags=sample,claim
# Claim or assertion evaluation
## Scenario
The controller claims, “A balanced journal entry must also be conceptually correct.”
:::part id=a kind=long_text format=claim_evaluation points=3
### Prompt
Evaluate the claim in two or three sentences.
### Answer
The claim is false. Equal debits and credits prove mechanical balance only; the accounts, amounts, timing, classification, and measurement can still be wrong.
### Rubric
Distinguish mechanical equality from faithful accounting treatment and provide at least one way a balanced entry can be wrong.
:::endpart
:::endquestion

:::question id=fmt-31-true-false shell=multiple_choice variation=diagnostic formats=true_false_correction tags=sample,assertion
# True-or-false with correction
## Scenario
Evaluate the assertion below.
:::part id=a kind=true_false format=true_false_correction points=2
### Prompt
“A trial balance proves that every transaction was recorded correctly.” Add a correction in the notes field if false.
### Answer
False
### Rubric
A trial balance tests debit-credit equality. It does not detect omitted transactions, equal-offset errors, or use of the wrong accounts.
:::endpart
:::endquestion

:::question id=fmt-32-matching shell=multiple_case variation=core formats=matching_mapping_sorting tags=sample,matching
# Matching, mapping, or sorting
## Scenario
Match each normal balance to the correct side.
:::part id=a kind=matching format=matching_mapping_sorting points=3
### Prompt
Match each account to `debit` or `credit`.
### Items
- cash | Cash
- payable | Accounts Payable
- revenue | Service Revenue
### Targets
- debit | Debit
- credit | Credit
### Answer
- cash => debit
- payable => credit
- revenue => credit
:::endpart
:::endquestion

:::question id=fmt-33-codification shell=memo_research variation=core formats=codification_research tags=sample,research
# Codification navigation or citation decoding
## Scenario
A citation is written as `ASC 330-10-35-1`.
:::part id=a kind=long_text format=codification_research points=3
### Prompt
Identify the Topic, Subtopic, Section, and paragraph represented by the citation.
### Answer
Topic 330, Subtopic 10, Section 35 (Subsequent Measurement), paragraph 1.
### Rubric
The response must correctly decode all four segments and recognize Section 35 as subsequent measurement.
:::endpart
:::endquestion

:::question id=fmt-34-ais shell=multipart variation=core formats=ais_source_document_flow tags=sample,ais
# AIS source-document and journal-flow problem
## Scenario
A business makes a credit sale to a customer.
:::part id=a kind=matching format=ais_source_document_flow points=3
### Prompt
Match each process stage to the appropriate artifact.
### Items
- evidence | Source evidence
- journal | Initial chronological record
- ledger | Account-by-account posting destination
### Targets
- invoice | Sales invoice
- sales_journal | Sales journal
- ar_ledger | Accounts receivable subsidiary ledger
### Answer
- evidence => invoice
- journal => sales_journal
- ledger => ar_ledger
:::endpart
:::endquestion
