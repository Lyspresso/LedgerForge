# Replace this heading with your pack title

:::question id=your-stable-id shell=multipart variation=core formats=single_number,initial_journal_entry tags=chapter,topic
# Replace with the student-facing question title
## Scenario
Write the scenario in normal **Markdown**. Tables and bullet lists are welcome.

:::part id=a kind=number format=single_number points=1
### Prompt
Ask for the amount.
### Answer
0
### Settings
tolerance: 0
:::endpart

:::part id=b kind=journal format=initial_journal_entry points=2
### Prompt
Ask for the entry.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Debit account | 0 | |
| Credit account | | 0 |
### Settings
row_order: any
:::endpart

:::part id=c kind=long_text format=short_explanation points=2
### Prompt
Ask for an explanation.
### Answer
Provide the model response here.
### Rubric
List the facts or reasoning the student should include. Long-form work is self-reviewed.
:::endpart
:::endquestion
