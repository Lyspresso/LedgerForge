# Built-In Spreadsheet Basics

Every app includes a small local spreadsheet engine for schedule, worksheet, statement, rollforward, T-account, sensitivity, and journal-entry grids. It does not require Excel, Numbers, a server, or an account.

## Entering formulas

Begin a cell with `=`. Rows and columns use A1 coordinates: the first editable cell is `A1`, the second column is `B`, and columns continue through `Z`, `AA`, `AB`, and so on.

Examples:

```text
=A1-B1
=ROUND(C2*8%, 2)
=SUM(D2:D13)
=IF(B4>0, B4, 0)
=PV(8%, 5, 0, 10000)
```

Raw formulas remain in the saved attempt. The interface shows the evaluated result separately, and table/journal grading compares that result with the expected numeric cell. A correct formula can therefore earn credit without being replaced by its answer.

## Operators and references

- Arithmetic: `+`, `-`, `*`, `/`, `^`
- Grouping: parentheses
- Comparisons: `=`, `<>`, `<`, `<=`, `>`, `>=`
- Cell references: `A1`, `$A$1`, `AA12`
- Ranges: `A1:A12`, `B2:D8`
- Literals: numbers, percentages such as `8%`, quoted text, `TRUE`, and `FALSE`

## Supported functions

| Function | Purpose |
|---|---|
| `SUM` | Add numbers and ranges |
| `AVERAGE` | Arithmetic mean |
| `MIN`, `MAX` | Smallest or largest value |
| `ROUND` | Round to a specified number of digits |
| `ABS` | Absolute value |
| `IF` | Choose one result from a condition; the unused branch is not evaluated |
| `PV` | Present value using Excel-compatible cash-flow signs |
| `FV` | Future value using Excel-compatible cash-flow signs |
| `PMT` | Periodic payment using Excel-compatible cash-flow signs |
| `NPV` | Net present value of period-end cash flows |

The time-value functions use the familiar argument order:

```text
PV(rate, nper, pmt, [fv], [type])
FV(rate, nper, pmt, [pv], [type])
PMT(rate, nper, pv, [fv], [type])
NPV(rate, value1, [value2], ...)
```

For `PV`, `FV`, and `PMT`, `type` is `0` for end-of-period payments and `1` for beginning-of-period payments. Cash inflows and outflows use opposite signs, matching common spreadsheet convention.

## Errors

Formula errors are displayed in the grid and never crash the app:

- `#REF!` — cell outside the grid
- `#VALUE!` — wrong value or argument shape
- `#DIV/0!` — division or average by zero
- `#NAME?` — unsupported function or name
- `#CYCLE!` — circular cell reference
- `#NUM!` — invalid or non-finite numerical result
- `#PARSE!` — malformed formula

The engine is intentionally a focused study spreadsheet, not a full Excel clone. It covers the calculations used by the included intermediate-accounting formats while keeping attempts portable and deterministic across all three apps.
