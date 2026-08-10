# Accounting Question Suite — Visual Language

Statement Studio for macOS is the reference implementation for the suite. The
other apps should preserve their platform-native interaction patterns while
sharing its hierarchy, spacing, semantic colors, and component shapes.

## Character

- Calm, native study workspace rather than a branded dashboard.
- Neutral system surfaces with the platform accent color.
- Compact navigation chrome and generous space around question content.
- Status color is reserved for feedback: green for correct, red for incorrect,
  orange for self-review, and secondary gray for unchecked.

## Desktop structure

| Region | Minimum | Ideal | Maximum |
|---|---:|---:|---:|
| Question library | 220 | 270 | 380 |
| Reading canvas | flexible | max content width 900 | flexible |
| Inspector | 240 | 280 | 400 |

The reading column uses 34 points of horizontal padding, 30 points of vertical
padding, and 26 points between major sections. Desktop windows open at
approximately 1180 × 760 points and remain usable down to 760 × 540.

## Type

- Interface: the platform system font (SF on Apple platforms).
- Question prose: the platform serif reading face (New York on macOS/iOS).
- Accounting values and formulas: the platform monospaced face.
- Desktop sizes: large title 26, title 22/17, headline and body 13, callout 12,
  subheadline 11, caption 10.

Respect system text scaling. Use weight and spacing before adding larger type.

## Surfaces and color

- Use the user's system accent where the toolkit exposes it; Aqua blue is the
  fallback (`#007AFF` light, `#0A84FF` dark).
- Prefer system background, sidebar, label, secondary-label, and separator
  colors over hard-coded brand colors.
- Scenario surface: quaternary neutral fill at roughly 35%, radius 12.
- Part card: background surface, radius 14, padding 20, subtle 1-point stroke,
  and a very soft shadow. The current card uses a 1.5-point accent stroke.
- Answer reveal: regular-material equivalent, radius 10, padding 14.
- Feedback: status color at roughly 10% opacity, radius 9, without a heavy
  outline.

## Reusable components

- Toolbar: previous/next leading; Check, Reveal, Import, and Inspector trailing.
- Library row: document/completion icon, two-line title, shell plus progress
  caption, and a mini progress bar. Use a flat native-list selection treatment.
- Part header: 30-point numbered circle; format headline; editor and points as
  caption; status at the trailing edge.
- Choice row: padding 10, radius 8, no idle border, accent fill when selected.
- Text editor: padding 8, radius 8, one-point separator; long response minimum
  height 150 on desktop.
- Spreadsheet: 8-point cell gaps, 10-point outer padding, radius 8, compact
  formula bar, and raw formula plus evaluated result.

## Platform adaptation

- macOS SwiftUI: native `NavigationSplitView`, toolbar, inspector, materials,
  search field, keyboard shortcuts, and pointer behavior.
- macOS Rust/egui: reproduce the same three-region hierarchy and tokens; use
  Mac system fonts when available and safe fallbacks elsewhere. Approximate
  materials with semantic neutral fills rather than introducing new branding.
- iOS/iPadOS: retain the same cards, colors, type hierarchy, and feedback, but
  use touch-sized controls and collapse the desktop inspector into navigation
  destinations or sheets.

The apps need not be pixel-identical. A control should feel native on its
platform while remaining unmistakably part of the same suite.
