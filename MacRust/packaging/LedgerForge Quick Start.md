# LedgerForge Quick Start

## Install and launch

1. Move `LedgerForge.app` to `/Applications`, or leave it in this extracted folder.
2. Control-click `LedgerForge.app`, choose **Open**, and confirm the first launch if macOS asks.
   This local release is ad-hoc signed but not notarized.
3. The built-in 35-format practice library appears automatically.

This release requires macOS 11.0 or later and an Apple-silicon Mac (`arm64`).

## Try the spreadsheet practice pack

1. In LedgerForge, click **Import Markdown…** or press `Command-O`.
2. Choose `LedgerForge Practice Packs/SPREADSHEET_PRACTICE.md` from this extracted folder.
3. Select **Spreadsheet Practice — Warranty Rollforward**.
4. In the Ending liability cell, enter `=B1+C1-D1`. The formula remains visible and its evaluated
   result appears below it.
5. Select **Spreadsheet Practice — Time Value and Sensitivity** to try `PV`, `NPV`, and `IF`.

You can also drag `.md` or `.markdown` practice packs onto the app window. Importing does not edit
the source document.

## Formula reference

Grid formulas support A1 references, ranges, `+`, `-`, `*`, `/`, `^`, parentheses, percentages,
comparisons, and these case-insensitive functions:

```text
SUM  AVERAGE  MIN  MAX  ROUND  ABS  IF  PV  FV  PMT  NPV
```

Examples:

```text
=SUM(B1:B4)
=IF(A1>9500,"Above threshold","Below threshold")
=-PV(8%,3,0,10000)
=NPV(8%,3000,4000,5000)
```

Formula errors remain visible as `#VALUE!`, `#REF!`, `#DIV/0!`, or `#CYCLE!`.

## Save location

LedgerForge autosaves locally at:

```text
~/Library/Application Support/com.openai.ledgerforge/state.json
```

Its atomic recovery copy is `.state.json.backup` in the same folder. No cloud account is required.
