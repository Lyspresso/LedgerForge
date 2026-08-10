use std::collections::{BTreeMap, HashSet};
use std::str::FromStr;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::domain::{
    AccountingQuestion, ExpectedAnswer, QuestionFormat, QuestionOption, QuestionPack, QuestionPart,
    QuestionShell, ResponseKind, VariationStyle,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportWarning {
    pub message: String,
    pub line: Option<usize>,
}

impl ImportWarning {
    fn new(message: impl Into<String>, line: Option<usize>) -> Self {
        Self {
            message: message.into(),
            line,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportResult {
    pub pack: QuestionPack,
    pub warnings: Vec<ImportWarning>,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum MarkdownImportError {
    #[error("the Markdown document is empty")]
    EmptyDocument,
    #[error("malformed directive at line {line}: {text}")]
    MalformedDirective { text: String, line: usize },
    #[error("question at line {line} has no id")]
    MissingQuestionId { line: usize },
    #[error("part at line {line} has no id")]
    MissingPartId { line: usize },
    #[error("unknown {field} '{value}' at line {line}")]
    InvalidEnum {
        field: String,
        value: String,
        line: usize,
    },
    #[error("the question id '{id}' occurs more than once")]
    DuplicateQuestionId { id: String },
    #[error("part id '{id}' occurs more than once in question '{question_id}'")]
    DuplicatePartId { question_id: String, id: String },
}

/// Parse either Accounting Question Markdown v1 or ordinary textbook-style Markdown.
pub fn parse_markdown(
    markdown: &str,
    source_name: impl Into<String>,
) -> Result<ImportResult, MarkdownImportError> {
    if markdown.trim().is_empty() {
        return Err(MarkdownImportError::EmptyDocument);
    }
    let source_name = source_name.into();
    let structured = markdown
        .lines()
        .any(|line| is_directive(line.trim(), ":::question"));
    if structured {
        parse_structured(markdown, &source_name)
    } else {
        Ok(parse_legacy(markdown, &source_name))
    }
}

fn parse_structured(
    markdown: &str,
    source_name: &str,
) -> Result<ImportResult, MarkdownImportError> {
    let lines: Vec<&str> = markdown.lines().collect();
    let mut index = 0;
    let mut questions = Vec::new();
    let mut warnings = Vec::new();

    while index < lines.len() {
        if !is_directive(lines[index].trim(), ":::question") {
            index += 1;
            continue;
        }

        let question_line = index + 1;
        let attributes = directive_attributes(lines[index], ":::question", question_line)?;
        let id = attributes
            .get("id")
            .filter(|value| !value.is_empty())
            .cloned()
            .ok_or(MarkdownImportError::MissingQuestionId {
                line: question_line,
            })?;
        let shell = enum_attribute(&attributes, "shell", "multipart", question_line)?;
        let variation = enum_attribute(&attributes, "variation", "core", question_line)?;
        let declared_formats = unique(comma_enum_values(
            attributes.get("formats").map(String::as_str).unwrap_or(""),
            "formats",
            question_line,
        )?);
        let tags = comma_strings(attributes.get("tags").map(String::as_str).unwrap_or(""));
        index += 1;

        let mut title = "Untitled Question".to_owned();
        let mut scenario_lines = Vec::new();
        let mut parts = Vec::new();
        let mut in_scenario = false;

        while index < lines.len() && lines[index].trim() != ":::endquestion" {
            let trimmed = lines[index].trim();
            if is_directive(trimmed, ":::question") {
                warnings.push(ImportWarning::new(
                    format!(
                        "Question '{id}' has no :::endquestion marker before the next question."
                    ),
                    Some(question_line),
                ));
                break;
            }
            if let Some(question_title) = trimmed.strip_prefix("# ") {
                let question_title = question_title.trim();
                if question_title.is_empty() {
                    warnings.push(ImportWarning::new(
                        format!("Question '{id}' has an empty title."),
                        Some(index + 1),
                    ));
                } else {
                    title = question_title.to_owned();
                }
                index += 1;
                continue;
            }
            if trimmed.eq_ignore_ascii_case("## Scenario") {
                in_scenario = true;
                index += 1;
                continue;
            }
            if is_directive(trimmed, ":::part") {
                let parsed = parse_part(&lines, index)?;
                if parts
                    .iter()
                    .any(|part: &QuestionPart| part.id == parsed.part.id)
                {
                    return Err(MarkdownImportError::DuplicatePartId {
                        question_id: id.clone(),
                        id: parsed.part.id,
                    });
                }
                warnings.extend(parsed.warnings);
                parts.push(parsed.part);
                index = parsed.next_index;
                continue;
            }
            if in_scenario {
                scenario_lines.push(lines[index]);
            }
            index += 1;
        }

        if index == lines.len() {
            warnings.push(ImportWarning::new(
                format!("Question '{id}' has no :::endquestion marker."),
                Some(question_line),
            ));
        } else if lines[index].trim() == ":::endquestion" {
            index += 1;
        }
        if parts.is_empty() {
            warnings.push(ImportWarning::new(
                format!("Question '{id}' contains no parts."),
                Some(question_line),
            ));
        }

        let inferred_formats = unique(parts.iter().map(|part| part.format));
        questions.push(AccountingQuestion {
            id,
            title,
            shell,
            variation,
            formats: if declared_formats.is_empty() {
                inferred_formats
            } else {
                declared_formats
            },
            scenario_markdown: clean_lines(&scenario_lines),
            parts,
            tags,
            source_name: source_name.to_owned(),
        });
    }

    let mut seen = HashSet::new();
    for question in &questions {
        if !seen.insert(question.id.as_str()) {
            return Err(MarkdownImportError::DuplicateQuestionId {
                id: question.id.clone(),
            });
        }
    }

    Ok(ImportResult {
        pack: QuestionPack {
            version: 1,
            title: source_name.to_owned(),
            questions,
        },
        warnings,
    })
}

struct ParsedPart {
    part: QuestionPart,
    next_index: usize,
    warnings: Vec<ImportWarning>,
}

fn parse_part(lines: &[&str], start: usize) -> Result<ParsedPart, MarkdownImportError> {
    let line_number = start + 1;
    let attributes = directive_attributes(lines[start], ":::part", line_number)?;
    let id = attributes
        .get("id")
        .filter(|value| !value.is_empty())
        .cloned()
        .ok_or(MarkdownImportError::MissingPartId { line: line_number })?;
    let kind: ResponseKind = enum_attribute(&attributes, "kind", "long_text", line_number)?;
    let format: QuestionFormat = match attributes.get("format") {
        Some(value) => parse_enum(value, "format", line_number)?,
        None => kind.default_format(),
    };
    let mut warnings = Vec::new();
    let points = match attributes.get("points") {
        None => 1.0,
        Some(value) => match value.parse::<f64>() {
            Ok(points) if points.is_finite() && points >= 0.0 => points,
            _ => {
                warnings.push(ImportWarning::new(
                    format!("Part '{id}' has invalid points '{value}'; 1 point was used."),
                    Some(line_number),
                ));
                1.0
            }
        },
    };
    let mut index = start + 1;
    let mut section: Option<String> = None;
    let mut content: BTreeMap<String, Vec<&str>> = BTreeMap::new();

    while index < lines.len()
        && lines[index].trim() != ":::endpart"
        && lines[index].trim() != ":::endquestion"
    {
        let trimmed = lines[index].trim();
        if is_directive(trimmed, ":::part") || is_directive(trimmed, ":::question") {
            break;
        }
        if let Some(heading) = trimmed.strip_prefix("### ") {
            let key = heading.trim().to_ascii_lowercase();
            content.entry(key.clone()).or_default();
            section = Some(key);
        } else if let Some(section) = &section {
            content
                .entry(section.clone())
                .or_default()
                .push(lines[index]);
        }
        index += 1;
    }

    if index == lines.len() || lines[index].trim() != ":::endpart" {
        warnings.push(ImportWarning::new(
            format!("Part '{id}' has no :::endpart marker."),
            Some(line_number),
        ));
    } else {
        index += 1;
    }
    if !content.contains_key("prompt") {
        warnings.push(ImportWarning::new(
            format!("Part '{id}' has no ### Prompt section."),
            Some(line_number),
        ));
    }
    if !content.contains_key("answer") {
        warnings.push(ImportWarning::new(
            format!("Part '{id}' has no ### Answer section."),
            Some(line_number),
        ));
    }

    let mut options = parse_options(content.get("options"));
    let mut items = parse_options(content.get("items"));
    let mut targets = parse_options(content.get("targets"));
    deduplicate_options(&mut options, "option", &id, line_number, &mut warnings);
    deduplicate_options(&mut items, "item", &id, line_number, &mut warnings);
    deduplicate_options(&mut targets, "target", &id, line_number, &mut warnings);
    let mut columns = parse_columns(content.get("columns"));
    let settings = parse_settings(content.get("settings"));
    let answer_lines = content.get("answer").cloned().unwrap_or_default();
    let tolerance = settings
        .get("tolerance")
        .and_then(|value| match value.parse::<f64>() {
            Ok(tolerance) if tolerance.is_finite() && tolerance >= 0.0 => Some(tolerance),
            _ => {
                warnings.push(ImportWarning::new(
                    format!("Part '{id}' has invalid tolerance '{value}'; exact grading was used."),
                    Some(line_number),
                ));
                None
            }
        });
    let mut expected = ExpectedAnswer {
        tolerance,
        ..ExpectedAnswer::default()
    };

    match kind {
        ResponseKind::SingleChoice | ResponseKind::MultipleChoice => {
            expected.selections = comma_strings(&clean_lines(&answer_lines));
        }
        ResponseKind::Journal | ResponseKind::Table => {
            let parsed_table = parse_markdown_table(&answer_lines);
            if columns.is_empty() {
                columns = parsed_table.columns;
            }
            expected.rows = parsed_table.rows;
            let width = columns
                .len()
                .max(expected.rows.iter().map(Vec::len).max().unwrap_or(0));
            for row in &mut expected.rows {
                row.resize(width, String::new());
            }
        }
        ResponseKind::Matching => {
            expected.pairs = parse_pairs(&answer_lines);
        }
        ResponseKind::Ordering => {
            expected.order = parse_list_ids(&answer_lines);
        }
        _ => {
            expected.scalar = clean_lines(&answer_lines);
            let section_accepted = parse_accepted(content.get("accepted"));
            let settings_accepted = settings
                .get("accepted")
                .map(|value| comma_strings(value))
                .unwrap_or_default();
            expected.accepted =
                unique_strings(section_accepted.into_iter().chain(settings_accepted));
        }
    }

    validate_part_metadata(
        &id,
        kind,
        &options,
        &items,
        &targets,
        &expected,
        line_number,
        &mut warnings,
    );

    Ok(ParsedPart {
        part: QuestionPart {
            id,
            kind,
            format,
            points,
            prompt_markdown: clean_lines(content.get("prompt").map(Vec::as_slice).unwrap_or(&[])),
            options,
            columns,
            items,
            targets,
            expected,
            rubric_markdown: clean_lines(content.get("rubric").map(Vec::as_slice).unwrap_or(&[])),
            settings,
        },
        next_index: index,
        warnings,
    })
}

fn parse_legacy(markdown: &str, source_name: &str) -> ImportResult {
    let lines: Vec<&str> = markdown.lines().collect();
    let marker_indices: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter_map(|(index, line)| {
            let trimmed = line.trim_start();
            (trimmed.starts_with("## Item ") || trimmed.starts_with("### `")).then_some(index)
        })
        .collect();
    let ranges: Vec<(usize, usize)> = if marker_indices.is_empty() {
        vec![(0, lines.len())]
    } else {
        marker_indices
            .iter()
            .enumerate()
            .map(|(offset, start)| {
                let end = marker_indices
                    .get(offset + 1)
                    .copied()
                    .unwrap_or(lines.len());
                (*start, end)
            })
            .collect()
    };

    let mut questions = Vec::new();
    let mut warnings = vec![ImportWarning::new(
        "Legacy Markdown was imported heuristically. Add :::question metadata to receive specialized editors and automatic grading.",
        None,
    )];
    let mut used_ids = HashSet::new();

    for (offset, (start, end)) in ranges.into_iter().enumerate() {
        let block_lines = &lines[start..end];
        let block = clean_lines(block_lines);
        if block.is_empty() {
            continue;
        }
        let heading = block_lines
            .iter()
            .find(|line| line.trim_start().starts_with('#'))
            .copied()
            .unwrap_or("");
        let title = if heading.is_empty() {
            format!("Imported Question {}", offset + 1)
        } else {
            heading.trim_start_matches('#').trim().to_owned()
        };
        let base_id = extract_legacy_id(heading)
            .unwrap_or_else(|| format!("legacy-{}-{}", offset + 1, slug(&title)));
        let mut natural_id = base_id.clone();
        let mut suffix = 2;
        while !used_ids.insert(natural_id.clone()) {
            natural_id = format!("{base_id}-{suffix}");
            suffix += 1;
        }
        if natural_id != base_id {
            warnings.push(ImportWarning::new(
                format!("Duplicate legacy id '{base_id}' was renamed '{natural_id}'."),
                Some(start + 1),
            ));
        }

        let choice_parts = parse_legacy_choices(&block);
        if !choice_parts.is_empty() {
            questions.push(AccountingQuestion {
                id: natural_id,
                title,
                shell: QuestionShell::MultipleChoice,
                variation: VariationStyle::Core,
                formats: vec![QuestionFormat::MultipleChoice],
                scenario_markdown: String::new(),
                parts: choice_parts,
                tags: vec!["legacy-import".to_owned()],
                source_name: source_name.to_owned(),
            });
        } else {
            let (question_text, answer_text) = split_legacy_answer(&block);
            let inferred = infer_formats(&question_text);
            let primary_format = inferred
                .first()
                .copied()
                .unwrap_or(QuestionFormat::ShortExplanation);
            let part = QuestionPart {
                id: "response".to_owned(),
                kind: ResponseKind::LongText,
                format: primary_format,
                points: 1.0,
                prompt_markdown: question_text.clone(),
                expected: ExpectedAnswer {
                    scalar: answer_text.clone(),
                    ..ExpectedAnswer::default()
                },
                rubric_markdown: answer_text,
                settings: BTreeMap::from([("legacy".to_owned(), "true".to_owned())]),
                ..QuestionPart::default()
            };
            questions.push(AccountingQuestion {
                id: natural_id,
                title,
                shell: if question_text.to_ascii_lowercase().contains("required") {
                    QuestionShell::Multipart
                } else {
                    QuestionShell::MemoResearch
                },
                variation: VariationStyle::Core,
                formats: inferred,
                scenario_markdown: String::new(),
                parts: vec![part],
                tags: vec!["legacy-import".to_owned(), "self-review".to_owned()],
                source_name: source_name.to_owned(),
            });
        }
    }

    ImportResult {
        pack: QuestionPack {
            version: 1,
            title: source_name.to_owned(),
            questions,
        },
        warnings,
    }
}

fn parse_legacy_choices(block: &str) -> Vec<QuestionPart> {
    #[derive(Debug)]
    struct Segment<'a> {
        question: Vec<&'a str>,
        answer: Vec<&'a str>,
    }

    let mut segments = Vec::new();
    let mut current: Option<Segment<'_>> = None;
    let mut reading_answer = false;
    for line in block.lines() {
        if is_legacy_question_marker(line) {
            if let Some(segment) = current.take() {
                segments.push(segment);
            }
            current = Some(Segment {
                question: vec![line],
                answer: Vec::new(),
            });
            reading_answer = false;
            continue;
        }
        let Some(segment) = &mut current else {
            continue;
        };
        let lowered = line.trim().to_ascii_lowercase();
        if lowered.starts_with("**answer:**") || lowered.starts_with("**answer key:**") {
            reading_answer = true;
        }
        if reading_answer {
            segment.answer.push(line);
        } else {
            segment.question.push(line);
        }
    }
    if let Some(segment) = current {
        segments.push(segment);
    }

    let choice_count = segments
        .iter()
        .filter(|segment| contains_legacy_options(&segment.question))
        .count();
    let mut choice_index = 0;
    segments
        .into_iter()
        .filter_map(|segment| {
            if !contains_legacy_options(&segment.question) {
                return None;
            }
            choice_index += 1;
            let part_id = if choice_count == 1 {
                "choice".to_owned()
            } else {
                format!("choice-{choice_index}")
            };
            parse_legacy_choice(
                &clean_lines(&segment.question),
                &clean_lines(&segment.answer),
                part_id,
            )
        })
        .collect()
}

fn is_legacy_question_marker(line: &str) -> bool {
    let lowered = line.trim().to_ascii_lowercase();
    lowered.starts_with("**question") || is_short_legacy_question_marker(&lowered)
}

fn is_short_legacy_question_marker(lowered: &str) -> bool {
    let Some(rest) = lowered.strip_prefix("**q") else {
        return false;
    };
    if !rest
        .chars()
        .next()
        .is_some_and(|character| character.is_ascii_digit())
    {
        return false;
    }
    let Some(end) = rest.find("**") else {
        return false;
    };
    !rest[..end].contains('*')
}

fn contains_legacy_options(lines: &[&str]) -> bool {
    lines
        .iter()
        .filter(|line| parse_legacy_option_marker(line).is_some())
        .take(2)
        .count()
        >= 2
}

fn parse_legacy_choice(
    question_text: &str,
    answer_text: &str,
    part_id: String,
) -> Option<QuestionPart> {
    let mut options = Vec::new();
    let mut prompt_lines = Vec::new();
    let mut current_option: Option<(String, Vec<String>)> = None;
    for line in question_text.lines() {
        if let Some((id, text)) = parse_legacy_option_marker(line) {
            if let Some((id, lines)) = current_option.take() {
                options.push(QuestionOption::new(id, clean_owned_lines(&lines)));
            }
            current_option = Some((id, (!text.is_empty()).then_some(text).into_iter().collect()));
        } else if let Some((_, lines)) = &mut current_option {
            if !line.trim().is_empty() {
                lines.push(line.trim().to_owned());
            }
        } else {
            prompt_lines.push(line);
        }
    }
    if let Some((id, lines)) = current_option {
        options.push(QuestionOption::new(id, clean_owned_lines(&lines)));
    }
    if options.len() < 2 {
        return None;
    }
    let option_ids: HashSet<&str> = options.iter().map(|option| option.id.as_str()).collect();
    let selection = extract_choice_id(answer_text, &option_ids);
    Some(QuestionPart {
        id: part_id,
        kind: ResponseKind::SingleChoice,
        format: QuestionFormat::MultipleChoice,
        points: 1.0,
        prompt_markdown: clean_lines(&prompt_lines),
        options,
        expected: ExpectedAnswer {
            selections: selection.into_iter().collect(),
            ..ExpectedAnswer::default()
        },
        rubric_markdown: answer_text.trim().to_owned(),
        settings: BTreeMap::from([("legacy".to_owned(), "true".to_owned())]),
        ..QuestionPart::default()
    })
}

#[cfg(test)]
fn parse_legacy_option_line(line: &str) -> Option<QuestionOption> {
    let (id, text) = parse_legacy_option_marker(line)?;
    (!text.is_empty()).then(|| QuestionOption::new(id, text))
}

fn parse_legacy_option_marker(line: &str) -> Option<(String, String)> {
    let trimmed = line.trim();
    let without_bullet = trimmed
        .strip_prefix('-')
        .or_else(|| trimmed.strip_prefix('*'))
        .filter(|rest| rest.starts_with(char::is_whitespace))
        .map(str::trim_start)
        .unwrap_or(trimmed);
    let mut chars = without_bullet.char_indices();
    let (_, id) = chars.next()?;
    if !('A'..='H').contains(&id) {
        return None;
    }
    let (separator_index, separator) = chars.next()?;
    if separator != ')' && separator != '.' {
        return None;
    }
    let text = without_bullet[separator_index + separator.len_utf8()..].trim();
    Some((id.to_string(), text.to_owned()))
}

fn clean_owned_lines(lines: &[String]) -> String {
    lines.join("\n").trim().to_owned()
}

fn extract_choice_id(answer: &str, option_ids: &HashSet<&str>) -> Option<String> {
    let chars: Vec<char> = answer.chars().collect();
    for (index, character) in chars.iter().enumerate() {
        if !('A'..='H').contains(character) {
            continue;
        }
        let before_is_boundary = index == 0 || !chars[index - 1].is_ascii_alphanumeric();
        let after_is_boundary =
            index + 1 == chars.len() || !chars[index + 1].is_ascii_alphanumeric();
        let candidate = character.to_string();
        if before_is_boundary && after_is_boundary && option_ids.contains(candidate.as_str()) {
            return Some(candidate);
        }
    }
    None
}

fn infer_formats(text: &str) -> Vec<QuestionFormat> {
    let lowered = text.to_ascii_lowercase();
    let mappings = [
        ("adjusting entr", QuestionFormat::AdjustingJournalEntry),
        ("correcting entr", QuestionFormat::CorrectingJournalEntry),
        ("closing entr", QuestionFormat::ClosingReversingEntry),
        ("reversing entr", QuestionFormat::ClosingReversingEntry),
        ("settlement entr", QuestionFormat::SettlementEntry),
        ("journal entr", QuestionFormat::InitialJournalEntry),
        ("no entry", QuestionFormat::EntryOrNoEntry),
        ("schedule", QuestionFormat::MultiPeriodSchedule),
        ("rollforward", QuestionFormat::Rollforward),
        ("t-account", QuestionFormat::TAccount),
        ("back-solv", QuestionFormat::Backsolve),
        ("trial balance", QuestionFormat::WorksheetTrialBalance),
        ("worksheet", QuestionFormat::WorksheetTrialBalance),
        ("financial statement", QuestionFormat::FullStatement),
        ("statement excerpt", QuestionFormat::PartialStatement),
        ("classif", QuestionFormat::PresentationClassificationGrid),
        ("overstated", QuestionFormat::EffectMatrix),
        ("understated", QuestionFormat::EffectMatrix),
        ("include or exclude", QuestionFormat::IncludeExcludeTable),
        ("disclos", QuestionFormat::DisclosureDrafting),
        ("reconcil", QuestionFormat::ReconciliationProof),
        ("tie-out", QuestionFormat::ReconciliationProof),
        ("prove", QuestionFormat::ReconciliationProof),
        ("error", QuestionFormat::ErrorCorrection),
        ("incorrect method", QuestionFormat::CorrectVersusIncorrect),
        (
            "alternative method",
            QuestionFormat::AlternativeMethodComparison,
        ),
        ("sensitivity", QuestionFormat::SensitivityChangedFact),
        ("suppose instead", QuestionFormat::SensitivityChangedFact),
        ("threshold", QuestionFormat::ThresholdCriteriaTest),
        ("criteria", QuestionFormat::ThresholdCriteriaTest),
        ("rank", QuestionFormat::RankingSequentialInclusion),
        ("sequence", QuestionFormat::OrderingTimeline),
        ("timeline", QuestionFormat::OrderingTimeline),
        ("ratio", QuestionFormat::RatioAnalysis),
        ("claim", QuestionFormat::ClaimEvaluation),
        ("true or false", QuestionFormat::TrueFalseCorrection),
        ("match", QuestionFormat::MatchingMappingSorting),
        ("codification", QuestionFormat::CodificationResearch),
        ("research memo", QuestionFormat::CodificationResearch),
        ("source document", QuestionFormat::AisSourceDocumentFlow),
        ("journal flow", QuestionFormat::AisSourceDocumentFlow),
        ("formula", QuestionFormat::FormulaSetup),
        ("compute", QuestionFormat::SingleNumber),
        ("calculate", QuestionFormat::SingleNumber),
    ];
    let matches = mappings
        .iter()
        .filter_map(|(needle, format)| lowered.contains(needle).then_some(*format));
    let formats = unique(matches);
    if formats.is_empty() {
        vec![QuestionFormat::ShortExplanation]
    } else {
        formats
    }
}

fn is_directive(line: &str, directive: &str) -> bool {
    line == directive
        || line
            .strip_prefix(directive)
            .is_some_and(|suffix| suffix.starts_with(char::is_whitespace))
}

fn directive_attributes(
    line: &str,
    directive: &str,
    line_number: usize,
) -> Result<BTreeMap<String, String>, MarkdownImportError> {
    let trimmed = line.trim();
    let suffix =
        trimmed
            .strip_prefix(directive)
            .ok_or_else(|| MarkdownImportError::MalformedDirective {
                text: line.to_owned(),
                line: line_number,
            })?;
    let mut result = BTreeMap::new();
    for token in suffix.split_whitespace() {
        let Some((key, raw_value)) = token.split_once('=') else {
            return Err(MarkdownImportError::MalformedDirective {
                text: line.to_owned(),
                line: line_number,
            });
        };
        let raw_value = raw_value.trim();
        let value = if let Some(quote) = raw_value
            .chars()
            .next()
            .filter(|character| matches!(character, '"' | '\''))
        {
            if raw_value.len() < 2 || !raw_value.ends_with(quote) {
                return Err(MarkdownImportError::MalformedDirective {
                    text: line.to_owned(),
                    line: line_number,
                });
            }
            raw_value[quote.len_utf8()..raw_value.len() - quote.len_utf8()].trim()
        } else {
            if raw_value.contains(['"', '\'']) {
                return Err(MarkdownImportError::MalformedDirective {
                    text: line.to_owned(),
                    line: line_number,
                });
            }
            raw_value
        };
        if key.is_empty() || value.is_empty() || result.contains_key(key) {
            return Err(MarkdownImportError::MalformedDirective {
                text: line.to_owned(),
                line: line_number,
            });
        }
        result.insert(key.to_owned(), value.to_owned());
    }
    Ok(result)
}

fn enum_attribute<T>(
    attributes: &BTreeMap<String, String>,
    key: &str,
    default: &str,
    line: usize,
) -> Result<T, MarkdownImportError>
where
    T: FromStr,
{
    parse_enum(
        attributes.get(key).map(String::as_str).unwrap_or(default),
        key,
        line,
    )
}

fn parse_enum<T>(value: &str, field: &str, line: usize) -> Result<T, MarkdownImportError>
where
    T: FromStr,
{
    value.parse().map_err(|_| MarkdownImportError::InvalidEnum {
        field: field.to_owned(),
        value: value.to_owned(),
        line,
    })
}

fn comma_enum_values<T>(
    value: &str,
    field: &str,
    line: usize,
) -> Result<Vec<T>, MarkdownImportError>
where
    T: FromStr,
{
    comma_strings(value)
        .iter()
        .map(|item| parse_enum(item, field, line))
        .collect()
}

fn comma_strings(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_owned)
        .collect()
}

fn parse_options(lines: Option<&Vec<&str>>) -> Vec<QuestionOption> {
    lines
        .into_iter()
        .flatten()
        .filter_map(|line| {
            let cleaned = strip_list_marker(line.trim());
            let (id, text) = cleaned.split_once('|')?;
            let id = id.trim();
            let text = text.trim();
            (!id.is_empty() && !text.is_empty()).then(|| QuestionOption::new(id, text))
        })
        .collect()
}

fn deduplicate_options(
    options: &mut Vec<QuestionOption>,
    label: &str,
    part_id: &str,
    line: usize,
    warnings: &mut Vec<ImportWarning>,
) {
    let mut seen = HashSet::new();
    options.retain(|option| {
        if seen.insert(option.id.clone()) {
            true
        } else {
            warnings.push(ImportWarning::new(
                format!(
                    "Part '{part_id}' repeats {label} id '{}'; the later value was ignored.",
                    option.id
                ),
                Some(line),
            ));
            false
        }
    });
}

#[allow(clippy::too_many_arguments)]
fn validate_part_metadata(
    id: &str,
    kind: ResponseKind,
    options: &[QuestionOption],
    items: &[QuestionOption],
    targets: &[QuestionOption],
    expected: &ExpectedAnswer,
    line: usize,
    warnings: &mut Vec<ImportWarning>,
) {
    match kind {
        ResponseKind::SingleChoice | ResponseKind::MultipleChoice => {
            if options.is_empty() {
                warnings.push(ImportWarning::new(
                    format!(
                        "Part '{id}' has no valid options; a manual choice-ID editor will be used."
                    ),
                    Some(line),
                ));
            }
            for selection in &expected.selections {
                if !options.is_empty() && !options.iter().any(|option| option.id == *selection) {
                    warnings.push(ImportWarning::new(
                        format!("Part '{id}' answer references unknown option id '{selection}'."),
                        Some(line),
                    ));
                }
            }
        }
        ResponseKind::Journal | ResponseKind::Table => {
            if expected.rows.is_empty() {
                warnings.push(ImportWarning::new(
                    format!("Part '{id}' has no valid answer-table rows."),
                    Some(line),
                ));
            }
        }
        ResponseKind::Matching => {
            if items.is_empty() || targets.is_empty() {
                warnings.push(ImportWarning::new(
                    format!(
                        "Part '{id}' is missing valid Items or Targets; a manual mapping editor will be used."
                    ),
                    Some(line),
                ));
            }
        }
        ResponseKind::Ordering => {
            if items.is_empty() {
                warnings.push(ImportWarning::new(
                    format!(
                        "Part '{id}' has no valid Items; a manual sequence editor will be used."
                    ),
                    Some(line),
                ));
            }
        }
        ResponseKind::Number
        | ResponseKind::Formula
        | ResponseKind::ShortText
        | ResponseKind::LongText
        | ResponseKind::TrueFalse
        | ResponseKind::NoEntry => {}
    }
}

fn parse_columns(lines: Option<&Vec<&str>>) -> Vec<String> {
    lines
        .map(|lines| clean_lines(lines))
        .unwrap_or_default()
        .split('|')
        .map(str::trim)
        .filter(|column| !column.is_empty())
        .map(str::to_owned)
        .collect()
}

fn parse_settings(lines: Option<&Vec<&str>>) -> BTreeMap<String, String> {
    let mut result = BTreeMap::new();
    for line in lines.into_iter().flatten() {
        if let Some((key, value)) = line.split_once(':') {
            let key = key.trim();
            if !key.is_empty() {
                result.insert(key.to_owned(), value.trim().to_owned());
            }
        }
    }
    result
}

fn parse_pairs(lines: &[&str]) -> BTreeMap<String, String> {
    let mut result = BTreeMap::new();
    for line in lines {
        let cleaned = strip_list_marker(line.trim());
        if let Some((left, right)) = cleaned.split_once("=>") {
            let left = left.trim();
            let right = right.trim();
            if !left.is_empty() && !right.is_empty() {
                result.insert(left.to_owned(), right.to_owned());
            }
        }
    }
    result
}

fn parse_list_ids(lines: &[&str]) -> Vec<String> {
    lines
        .iter()
        .map(|line| strip_list_marker(line.trim()).trim())
        .filter(|item| !item.is_empty())
        .map(str::to_owned)
        .collect()
}

fn parse_accepted(lines: Option<&Vec<&str>>) -> Vec<String> {
    lines
        .into_iter()
        .flatten()
        .map(|line| strip_list_marker(line.trim()).trim())
        .filter(|item| !item.is_empty())
        .map(str::to_owned)
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedMarkdownTable {
    columns: Vec<String>,
    rows: Vec<Vec<String>>,
}

fn parse_markdown_table(lines: &[&str]) -> ParsedMarkdownTable {
    let parsed: Vec<Vec<String>> = lines
        .iter()
        .filter(|line| line.contains('|'))
        .map(|line| {
            line.trim()
                .trim_matches('|')
                .split('|')
                .map(|cell| cell.trim().to_owned())
                .collect()
        })
        .collect();
    let mut columns = Vec::new();
    let mut rows = Vec::new();
    let mut index = 0;
    while index < parsed.len() {
        if is_alignment_row(&parsed[index]) {
            index += 1;
            continue;
        }
        if parsed
            .get(index + 1)
            .is_some_and(|next| is_alignment_row(next))
        {
            if columns.is_empty() {
                columns.clone_from(&parsed[index]);
            }
            index += 2;
            continue;
        }
        rows.push(parsed[index].clone());
        index += 1;
    }
    ParsedMarkdownTable { columns, rows }
}

fn is_alignment_row(cells: &[String]) -> bool {
    !cells.is_empty()
        && cells.iter().all(|cell| {
            !cell.is_empty()
                && cell
                    .chars()
                    .all(|character| character == '-' || character == ':')
                && cell.contains('-')
        })
}

fn strip_list_marker(value: &str) -> &str {
    value
        .strip_prefix("- ")
        .or_else(|| value.strip_prefix("* "))
        .unwrap_or(value)
}

fn split_legacy_answer(block: &str) -> (String, String) {
    let lower = block.to_ascii_lowercase();
    let marker = ["**answer key:**", "**answer:**"]
        .iter()
        .filter_map(|marker| lower.find(marker).map(|index| (index, marker.len())))
        .min_by_key(|(index, _)| *index);
    match marker {
        Some((index, length)) => (
            block[..index].trim().to_owned(),
            block[index + length..].trim().to_owned(),
        ),
        None => (block.trim().to_owned(), String::new()),
    }
}

fn clean_lines(lines: &[&str]) -> String {
    lines.join("\n").trim().to_owned()
}

fn unique<T>(values: impl IntoIterator<Item = T>) -> Vec<T>
where
    T: Copy + Eq + std::hash::Hash,
{
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter(|value| seen.insert(*value))
        .collect()
}

fn unique_strings(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter(|value| seen.insert(value.clone()))
        .collect()
}

fn extract_legacy_id(heading: &str) -> Option<String> {
    if let Some(after_open) = heading.split_once('`').map(|(_, rest)| rest)
        && let Some((id, _)) = after_open.split_once('`')
        && !id.trim().is_empty()
    {
        return Some(id.trim().to_owned());
    }
    let suffix = heading.trim_start().strip_prefix("## Item ")?;
    let number: String = suffix.chars().take_while(char::is_ascii_digit).collect();
    (!number.is_empty()).then(|| format!("item-{number}"))
}

fn slug(value: &str) -> String {
    let converted: String = value
        .to_ascii_lowercase()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character
            } else {
                '-'
            }
        })
        .collect();
    converted
        .split('-')
        .filter(|segment| !segment.is_empty())
        .take(6)
        .collect::<Vec<_>>()
        .join("-")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn alignment_rows_are_detected_without_dropping_empty_cells() {
        let table = parse_markdown_table(&[
            "| Account | Debit | Credit |",
            "|---|---:|---:|",
            "| Cash | 100 | |",
            "| Revenue | | 100 |",
        ]);
        assert_eq!(table.columns, ["Account", "Debit", "Credit"]);
        assert_eq!(table.rows[0], ["Cash", "100", ""]);
        assert_eq!(table.rows[1], ["Revenue", "", "100"]);
    }

    #[test]
    fn headerless_tables_keep_their_first_data_row() {
        let table = parse_markdown_table(&["Cash | 100", "Revenue | 200"]);
        assert!(table.columns.is_empty());
        assert_eq!(table.rows.len(), 2);
    }

    #[test]
    fn option_parser_accepts_period_or_parenthesis() {
        assert_eq!(parse_legacy_option_line("- A) First").unwrap().id, "A");
        assert_eq!(
            parse_legacy_option_line("B. Second").unwrap().text,
            "Second"
        );
    }
}
