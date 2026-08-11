# Adaptive Question Titles

LedgerForge treats Markdown headings as both authoring content and an interchange envelope. Some imported banks place a stable ID, verification state, learning objective, and concept in one heading. Those fields are useful for auditing, but they are not a readable question title.

## Import behavior

The Rust and Swift importers now apply the same deterministic presentation rules:

1. Preserve the question ID, source Markdown, answers, formats, tags, and provenance.
2. Remove transport-only segments such as `acct343-*`, `ORIGINAL-VERIFIED`, `DERIVED-VERIFIED`, and a leading `LO 14-2` from the visible title.
3. Prefer a nested question heading such as `Q3 — CORE — Discount TS: …` when it is more descriptive than the outer transport heading.
4. Keep accounting abbreviations, punctuation, and fact-specific wording unchanged.
5. Fall back to the cleaned outer heading, then a humanized stable ID, so a title is never empty.

The presentation layer applies the same rules to already-imported questions. Users do not need to delete or reimport an existing pack to see readable titles.

Bank-authoring metadata at the beginning of a written prompt is moved into a collapsed **Source details** disclosure. The student sees the scenario and requirements first, while the exact provenance remains available.

## Why title cleanup is deterministic

Automatic import cannot depend on a generative model. A model may be unavailable, may change after an operating-system update, or may paraphrase an accounting term in a way that changes meaning. Deterministic cleanup is fast, reproducible, testable across Rust and Swift, and works on every supported OS version.

Apple's Foundation Models framework remains a good future option for an explicit **Suggest a shorter title** command on macOS 26 and iOS 26. Such a command should:

- run only after checking `SystemLanguageModel.default.availability`;
- keep all processing on-device;
- show a preview and require user confirmation;
- never rewrite IDs, facts, answers, learning objectives, or provenance;
- fall back to the deterministic title when Apple Intelligence is unavailable.

References: [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), and [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession).

## Private-bank QA

The optional Rust QA test validates the full two-per-concept bank without committing it:

```sh
cd MacRust
LEDGERFORGE_QA_TWO_PER_CONCEPT=/absolute/path/ACCOUNT343_TWO_PER_CONCEPT.md \
  cargo test --locked --test supplied_bank_qa \
  supplied_two_per_concept_bank_has_readable_titles_and_collapsed_provenance \
  -- --ignored
```

The test requires 4,686 questions, rejects transport IDs and verification labels in visible titles, and verifies that every rendered prompt starts with student-facing content.
