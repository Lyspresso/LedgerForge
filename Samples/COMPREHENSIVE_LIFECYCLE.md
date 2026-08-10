# Comprehensive Lifecycle Demonstration

:::question id=demo-note-lifecycle shell=lifecycle variation=long_path formats=single_number,initial_journal_entry,multi_period_schedule,adjusting_journal_entry,settlement_entry,partial_statement,reconciliation_proof tags=demo,lifecycle,note
# Two-Year Note: Recognition Through Settlement
## Scenario
On January 1, Year 1, Harbor Works lends **$10,000 cash** to a customer in exchange for a two-year, **6% annual-interest note**. Interest is payable each December 31. Principal is due December 31, Year 2. Use simple annual interest and assume every required cash payment occurs on time.

:::part id=a kind=number format=single_number points=1
### Prompt
Compute the annual cash interest.
### Answer
600
### Settings
tolerance: 0
:::endpart

:::part id=b kind=journal format=initial_journal_entry points=2
### Prompt
Record issuance of the note on January 1, Year 1.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Notes Receivable | 10000 | |
| Cash | | 10000 |
### Settings
row_order: any
:::endpart

:::part id=c kind=table format=multi_period_schedule points=3
### Prompt
Prepare the complete annual interest and carrying-amount schedule.
### Columns
Year | Beginning carrying amount | Cash interest | Interest revenue | Ending carrying amount
### Answer
| Year | Beginning carrying amount | Cash interest | Interest revenue | Ending carrying amount |
|---|---:|---:|---:|---:|
| 1 | 10000 | 600 | 600 | 10000 |
| 2 | 10000 | 600 | 600 | 10000 |
:::endpart

:::part id=d kind=journal format=adjusting_journal_entry points=2
### Prompt
Record the December 31, Year 1 interest receipt.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Cash | 600 | |
| Interest Revenue | | 600 |
### Settings
row_order: any
:::endpart

:::part id=e kind=journal format=settlement_entry points=2
### Prompt
After separately recording Year 2 interest, record collection of principal on December 31, Year 2.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Cash | 10000 | |
| Notes Receivable | | 10000 |
### Settings
row_order: any
:::endpart

:::part id=f kind=table format=partial_statement points=2
### Prompt
Present the note on the December 31, Year 1 balance sheet immediately after the interest receipt.
### Columns
Caption | Classification | Amount
### Answer
| Caption | Classification | Amount |
|---|---|---:|
| Notes receivable | Current asset | 10000 |
:::endpart

:::part id=g kind=table format=reconciliation_proof points=2
### Prompt
Prove total cash received over the note’s life and reconcile it to principal plus total interest revenue.
### Columns
Component | Amount
### Answer
| Component | Amount |
|---|---:|
| Principal collected | 10000 |
| Year 1 interest | 600 |
| Year 2 interest | 600 |
| Total cash received | 11200 |
| Principal plus total interest revenue | 11200 |
:::endpart
:::endquestion
