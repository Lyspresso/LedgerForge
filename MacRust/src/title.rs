//! Deterministic presentation cleanup for imported question titles and metadata.
//!
//! Imports remain lossless: these helpers derive a human-facing presentation from
//! the stored title and prompt without changing IDs, provenance, or answer text.

use crate::AccountingQuestion;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct QuestionTitlePresentation {
    pub title: String,
    pub learning_objective: Option<String>,
    pub verification: Option<String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct PromptPresentation {
    pub body: String,
    pub import_details: Vec<(String, String)>,
}

/// Builds the title shown in the library and question canvas.
///
/// Legacy banks often use their heading as a transport envelope:
/// `id — verification — LO — concept`. When an embedded question heading exists,
/// it is more descriptive and becomes the visible title. The stored title remains
/// untouched so old state files and exact source provenance stay compatible.
pub fn question_title_presentation(question: &AccountingQuestion) -> QuestionTitlePresentation {
    let prompt = question
        .parts
        .first()
        .map(|part| part.prompt_markdown.as_str())
        .unwrap_or_default();
    title_presentation(&question.title, prompt, &question.id)
}

pub fn normalized_import_title(raw_title: &str, prompt: &str, fallback_id: &str) -> String {
    title_presentation(raw_title, prompt, fallback_id).title
}

pub fn title_presentation(
    raw_title: &str,
    prompt: &str,
    fallback_id: &str,
) -> QuestionTitlePresentation {
    let learning_objective = extract_learning_objective(raw_title)
        .or_else(|| extract_metadata_value(prompt, "LO"))
        .map(|value| normalize_learning_objective(&value));
    let verification = extract_verification(raw_title)
        .or_else(|| extract_metadata_value(prompt, "Set status"))
        .map(|value| humanize_verification(&value));

    let cleaned_outer = clean_transport_title(raw_title);
    let embedded = embedded_question_title(prompt);
    let title = embedded
        .filter(|candidate| !candidate.eq_ignore_ascii_case(&cleaned_outer))
        .unwrap_or(cleaned_outer);
    let title = normalize_title_punctuation(&title);
    let title = if title.trim().is_empty() {
        humanize_fallback_id(fallback_id)
    } else {
        title
    };

    QuestionTitlePresentation {
        title,
        learning_objective,
        verification,
    }
}

/// Separates bank-authoring metadata from the student-facing question body.
/// Metadata is returned for a collapsed disclosure instead of occupying the first
/// screenful of every written-response card.
pub fn prompt_presentation(markdown: &str) -> PromptPresentation {
    const METADATA_LABELS: &[&str] = &[
        "LO",
        "Concept",
        "Set position",
        "Set status",
        "Provenance",
        "Source-unit handling",
        "Derived from",
        "Derivation",
        "Derived-verification requirement",
        "Question-set status",
    ];

    let lines: Vec<&str> = markdown.lines().collect();
    let mut body_start = 0;
    let mut details = Vec::new();
    let mut saw_preamble = false;

    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            if saw_preamble {
                body_start = index + 1;
            }
            continue;
        }
        if is_transport_heading(trimmed) {
            saw_preamble = true;
            body_start = index + 1;
            continue;
        }
        if let Some((label, value)) = parse_metadata_line(trimmed)
            && METADATA_LABELS
                .iter()
                .any(|known| label.eq_ignore_ascii_case(known))
        {
            details.push((label, value));
            saw_preamble = true;
            body_start = index + 1;
            continue;
        }
        break;
    }

    while body_start < lines.len() && lines[body_start].trim().is_empty() {
        body_start += 1;
    }
    if body_start < lines.len() && is_embedded_bank_heading(lines[body_start].trim()) {
        body_start += 1;
        while body_start < lines.len() && lines[body_start].trim().is_empty() {
            body_start += 1;
        }
    }
    let body = lines[body_start..].join("\n").trim().to_owned();
    PromptPresentation {
        body: if body.is_empty() {
            markdown.trim().to_owned()
        } else {
            body
        },
        import_details: details,
    }
}

fn embedded_question_title(prompt: &str) -> Option<String> {
    prompt.lines().find_map(|line| {
        let trimmed = line.trim();
        let heading = trimmed
            .strip_prefix("### ")
            .or_else(|| trimmed.strip_prefix("## "))?;
        if is_transport_heading(trimmed) {
            return None;
        }
        let cleaned = clean_inline(heading);
        let lowered = cleaned.to_ascii_lowercase();
        if matches!(
            lowered.as_str(),
            "scenario" | "required" | "answer" | "answer key" | "model answer"
        ) {
            return None;
        }

        let segments: Vec<&str> = cleaned
            .split('—')
            .map(str::trim)
            .filter(|segment| !segment.is_empty())
            .collect();
        if segments.len() >= 2
            && (is_question_marker(segments[0]) || is_bank_status_segment(segments[0]))
        {
            let semantic = segments
                .into_iter()
                .skip_while(|segment| {
                    is_question_marker(segment) || is_bank_status_segment(segment)
                })
                .collect::<Vec<_>>()
                .join(" — ");
            return (!semantic.is_empty()).then_some(semantic);
        }
        (!cleaned.is_empty()).then_some(cleaned)
    })
}

fn clean_transport_title(raw: &str) -> String {
    let cleaned = clean_inline(raw.trim_start_matches('#').trim());
    let segments: Vec<&str> = cleaned
        .split('—')
        .map(str::trim)
        .filter(|segment| !segment.is_empty())
        .collect();
    if segments.len() <= 1 {
        return strip_numbered_item_prefix(&cleaned).unwrap_or(cleaned);
    }

    let semantic = segments
        .iter()
        .filter(|segment| {
            !is_identifier_segment(segment)
                && !is_bank_status_segment(segment)
                && extract_learning_objective(segment).is_none()
        })
        .copied()
        .collect::<Vec<_>>()
        .join(" — ");
    if semantic.is_empty() {
        cleaned
    } else {
        semantic
    }
}

fn strip_numbered_item_prefix(value: &str) -> Option<String> {
    let lowercase = value.to_ascii_lowercase();
    lowercase.strip_prefix("item ")?;
    let suffix = value.get(5..)?;
    let digit_count = suffix.chars().take_while(char::is_ascii_digit).count();
    if digit_count == 0 {
        return None;
    }
    let semantic = suffix[digit_count..]
        .trim_start_matches([':', '—', '-', ' '])
        .trim();
    (!semantic.is_empty()).then(|| semantic.to_owned())
}

fn is_transport_heading(line: &str) -> bool {
    let Some(heading) = line
        .strip_prefix("### ")
        .or_else(|| line.strip_prefix("## "))
    else {
        return false;
    };
    let cleaned = clean_inline(heading);
    let segments = cleaned.split('—').map(str::trim).collect::<Vec<_>>();
    segments
        .iter()
        .any(|segment| is_identifier_segment(segment))
        || (segments
            .iter()
            .any(|segment| extract_learning_objective(segment).is_some())
            && segments
                .iter()
                .any(|segment| is_bank_status_segment(segment)))
}

fn parse_metadata_line(line: &str) -> Option<(String, String)> {
    let line = line
        .trim()
        .strip_prefix('>')
        .map(str::trim)
        .unwrap_or_else(|| line.trim());
    let content = line.strip_prefix("**")?;
    let (label, value) = content.split_once(":**")?;
    let value = clean_inline(value.trim());
    (!label.trim().is_empty() && !value.is_empty()).then(|| (label.trim().to_owned(), value))
}

fn is_embedded_bank_heading(line: &str) -> bool {
    let Some(heading) = line
        .strip_prefix("### ")
        .or_else(|| line.strip_prefix("## "))
    else {
        return false;
    };
    let segments = clean_inline(heading)
        .split('—')
        .map(str::trim)
        .map(str::to_owned)
        .collect::<Vec<_>>();
    segments
        .first()
        .is_some_and(|value| is_question_marker(value))
        && segments.iter().any(|value| is_bank_status_segment(value))
}

fn extract_metadata_value(prompt: &str, wanted_label: &str) -> Option<String> {
    prompt.lines().find_map(|line| {
        let (label, value) = parse_metadata_line(line)?;
        label.eq_ignore_ascii_case(wanted_label).then_some(value)
    })
}

fn extract_learning_objective(value: &str) -> Option<String> {
    let normalized = clean_inline(value);
    let words: Vec<&str> = normalized.split_whitespace().collect();
    for window in words.windows(2) {
        if window[0].eq_ignore_ascii_case("LO")
            && window[1]
                .chars()
                .all(|character| character.is_ascii_digit() || character == '-')
        {
            return Some(format!("LO {}", window[1]));
        }
    }
    None
}

fn normalize_learning_objective(value: &str) -> String {
    extract_learning_objective(value).unwrap_or_else(|| clean_inline(value))
}

fn extract_verification(value: &str) -> Option<String> {
    value.split('—').find_map(|segment| {
        let cleaned = clean_inline(segment.trim());
        is_bank_status_segment(&cleaned).then_some(cleaned)
    })
}

fn humanize_verification(value: &str) -> String {
    let normalized = clean_inline(value).replace(['_', '-'], " ");
    let lowercase = normalized.to_ascii_lowercase();
    if lowercase.contains("derived") && lowercase.contains("verified") {
        "Derived · verified".to_owned()
    } else if lowercase.contains("original") && lowercase.contains("verified") {
        "Original · verified".to_owned()
    } else if lowercase.contains("unverified") {
        "Needs verification".to_owned()
    } else {
        sentence_case(&normalized)
    }
}

fn is_question_marker(value: &str) -> bool {
    let trimmed = value.trim();
    let lowercase = trimmed.to_ascii_lowercase();
    if let Some(number) = lowercase.strip_prefix('q') {
        return !number.is_empty() && number.chars().all(|character| character.is_ascii_digit());
    }
    lowercase
        .strip_prefix("question ")
        .is_some_and(|number| number.chars().all(|character| character.is_ascii_digit()))
}

fn is_identifier_segment(value: &str) -> bool {
    let lowercase = clean_inline(value).to_ascii_lowercase();
    lowercase.starts_with("acct343-")
        || lowercase.starts_with("core_")
        || lowercase.starts_with("item-")
        || lowercase.starts_with("item ")
        || lowercase.starts_with("legacy-")
}

fn is_bank_status_segment(value: &str) -> bool {
    let uppercase = clean_inline(value).to_ascii_uppercase();
    matches!(
        uppercase.as_str(),
        "CORE"
            | "CORE DEMO"
            | "CORE DEMO (VERIFIED)"
            | "ORIGINAL-VERIFIED"
            | "DERIVED-VERIFIED"
            | "ORIGINAL VERIFIED"
            | "DERIVED VERIFIED"
            | "VERIFIED"
            | "UNVERIFIED"
    )
}

fn normalize_title_punctuation(value: &str) -> String {
    let value = value.replace(" + ", " and ");
    collapse_whitespace(&value)
        .trim_matches(|character: char| matches!(character, '—' | '-' | ':' | ' '))
        .to_owned()
}

fn clean_inline(value: &str) -> String {
    collapse_whitespace(&value.replace('`', "").replace("**", "").replace("__", ""))
}

fn collapse_whitespace(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn sentence_case(value: &str) -> String {
    let mut characters = value.chars();
    let Some(first) = characters.next() else {
        return String::new();
    };
    first.to_uppercase().collect::<String>() + characters.as_str()
}

fn humanize_fallback_id(value: &str) -> String {
    let humanized = value.replace(['-', '_'], " ");
    let result = sentence_case(&collapse_whitespace(&humanized));
    if result.is_empty() {
        "Untitled question".to_owned()
    } else {
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LEGACY_PROMPT: &str = r#"### `acct343-c0017-q1` — ORIGINAL-VERIFIED — LO 14-2 — Subsequent measurement schedule (discount amortization) + period-end FVA + disposal under FV-NI

**LO:** LO 14-2
**Concept:** Subsequent measurement schedule (discount amortization) + period-end FVA + disposal under FV-NI
**Set position:** Group 17 of 2343 · Question 1 of 2
**Set status:** ORIGINAL-VERIFIED
**Provenance:** `ACCOUNT343_COMPLETE.md` · source `core_003_q3`
**Source-unit handling:** complete cleaned source item
> **Derived-verification requirement:** Reconcile every result to the supplied facts.

### Q3 — CORE — Discount TS: effective-interest amortized cost, year-end FVA, disposal

**Scenario:** Westbrook purchases bonds.

**Required:** Prepare the entries."#;

    #[test]
    fn promotes_embedded_question_heading_over_transport_title() {
        let presentation = title_presentation(
            "`acct343-c0017-q1` — ORIGINAL-VERIFIED — LO 14-2 — Subsequent measurement schedule (discount amortization) + period-end FVA + disposal under FV-NI",
            LEGACY_PROMPT,
            "acct343-c0017-q1",
        );
        assert_eq!(
            presentation.title,
            "Discount TS: effective-interest amortized cost, year-end FVA, disposal"
        );
        assert_eq!(presentation.learning_objective.as_deref(), Some("LO 14-2"));
        assert_eq!(
            presentation.verification.as_deref(),
            Some("Original · verified")
        );
    }

    #[test]
    fn cleans_transport_title_when_no_embedded_heading_exists() {
        assert_eq!(
            normalized_import_title(
                "`acct343-c0001-q2-derived` — DERIVED-VERIFIED — LO 13-8 — Initial recognition + amortization",
                "**Required:** Prepare entries.",
                "acct343-c0001-q2-derived",
            ),
            "Initial recognition and amortization"
        );
    }

    #[test]
    fn separates_authoring_metadata_without_changing_question_body() {
        let presentation = prompt_presentation(LEGACY_PROMPT);
        assert!(presentation.body.starts_with("**Scenario:** Westbrook"));
        assert!(presentation.body.contains("**Scenario:** Westbrook"));
        assert_eq!(presentation.import_details.len(), 7);
        assert_eq!(
            presentation.import_details[0],
            ("LO".to_owned(), "LO 14-2".to_owned())
        );
        assert!(!presentation.body.contains("raw block"));
    }

    #[test]
    fn leaves_normal_authored_title_intact() {
        assert_eq!(
            normalized_import_title(
                "Prepare the lease amortization schedule",
                "## Scenario\nFacts",
                "lease-1",
            ),
            "Prepare the lease amortization schedule"
        );
    }

    #[test]
    fn removes_numbered_item_envelope_but_keeps_its_subject() {
        assert_eq!(
            normalized_import_title(
                "Item 12: Classification of the investment",
                "**Question:** Which category applies?",
                "item-12",
            ),
            "Classification of the investment"
        );
    }
}
