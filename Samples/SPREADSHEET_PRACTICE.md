:::question id=sheet-warranty shell=multipart variation=core formats=rollforward,reconciliation_proof tags=spreadsheet,warranty,rollforward
# Spreadsheet Practice — Warranty Rollforward
## Scenario
A warranty liability begins at **$12,000**. Current-year warranty expense is **$8,000** and claims paid are **$5,500**. Monthly claims were $1,200, $1,450, $1,350, and $1,500.

:::part id=a kind=table format=rollforward points=2
### Prompt
Complete the rollforward. In Ending liability, enter an A1 formula rather than typing the result.
### Columns
Label | Beginning | Additions | Claims | Ending liability
### Answer
| Label | Beginning | Additions | Claims | Ending liability |
|---|---:|---:|---:|---:|
| Warranty liability | 12000 | 8000 | 5500 | =B1+C1-D1 |
:::endpart

:::part id=b kind=table format=reconciliation_proof points=2
### Prompt
Enter the four monthly claims and use `SUM` for the total row.
### Columns
Month | Claims paid
### Answer
| Month | Claims paid |
|---|---:|
| Month 1 | 1200 |
| Month 2 | 1450 |
| Month 3 | 1350 |
| Month 4 | 1500 |
| Total | =SUM(B1:B4) |
:::endpart
:::endquestion

:::question id=sheet-tvm shell=multiple_case variation=counterfactual formats=formula_setup,sensitivity_changed_fact tags=spreadsheet,pv,sensitivity
# Spreadsheet Practice — Time Value and Sensitivity
## Scenario
A noninterest-bearing amount of **$10,000** is due in three years. Compare its present value at several annual discount rates. Payments occur at period end.

:::part id=a kind=formula format=formula_setup points=1
### Prompt
Enter a self-contained spreadsheet formula that returns the $10,000 amount's positive present value at 8%.
### Answer
=-PV(8%,3,0,10000)
### Accepted
- =PV(8%,3,0,-10000)
:::endpart

:::part id=b kind=table format=sensitivity_changed_fact points=3
### Prompt
Complete the sensitivity table. Use a formula in every Present value cell that refers to the rate in column A.
### Columns
Rate | Present value
### Answer
| Rate | Present value |
|---:|---:|
| 6% | =-PV(A1,3,0,10000) |
| 8% | =-PV(A2,3,0,10000) |
| 10% | =-PV(A3,3,0,10000) |
:::endpart

:::part id=c kind=table format=alternative_method_comparison points=2
### Prompt
Use `NPV` to calculate the present value of $3,000, $4,000, and $5,000 received at the ends of Years 1–3 at 8%. Use `IF` to label whether the result exceeds $9,500.
### Columns
PV of inflows | Decision
### Answer
| PV of inflows | Decision |
|---:|---|
| =NPV(8%,3000,4000,5000) | =IF(A1>9500,"Above threshold","Below threshold") |
:::endpart
:::endquestion
