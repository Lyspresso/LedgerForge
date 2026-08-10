use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::domain::{AccountingQuestion, AttemptRecord, QuestionPart, ResponseKind, StudentAnswer};
use crate::spreadsheet::{CellValue, evaluate_grid};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GradeStatus {
    Correct,
    Incorrect,
    NeedsSelfReview,
    Unverified,
    Unanswered,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GradeResult {
    pub status: GradeStatus,
    pub feedback: String,
}

impl GradeResult {
    fn new(status: GradeStatus, feedback: impl Into<String>) -> Self {
        Self {
            status,
            feedback: feedback.into(),
        }
    }
}

/// Grade a single response deterministically. Long-form work never uses fuzzy scoring;
/// it is explicitly routed to self-review against the model answer and rubric.
pub fn grade_answer(answer: &StudentAnswer, part: &QuestionPart) -> GradeResult {
    if answer.is_blank() {
        return GradeResult::new(
            GradeStatus::Unanswered,
            "Enter a response before checking it.",
        );
    }
    if !has_gradable_key(part) {
        return GradeResult::new(
            GradeStatus::Unverified,
            "This imported part has no answer key or rubric. Your response is saved, but LedgerForge cannot verify or award mastery for it.",
        );
    }

    match part.kind {
        ResponseKind::SingleChoice => {
            exact_selection(&answer_selections(answer), &part.expected.selections, false)
        }
        ResponseKind::MultipleChoice => {
            exact_selection(&answer_selections(answer), &part.expected.selections, true)
        }
        ResponseKind::Number => grade_number(
            &answer.scalar,
            &part.expected.scalar,
            part.expected.tolerance.unwrap_or(0.0).abs(),
        ),
        ResponseKind::Formula => exact_scalar(
            &answer.scalar,
            &part.expected.scalar,
            &part.expected.accepted,
            normalize_formula,
        ),
        ResponseKind::ShortText => {
            if part.expected.accepted.is_empty() {
                self_review()
            } else {
                exact_scalar(
                    &answer.scalar,
                    &part.expected.scalar,
                    &part.expected.accepted,
                    normalize_text,
                )
            }
        }
        ResponseKind::LongText => self_review(),
        ResponseKind::Journal | ResponseKind::Table => {
            let evaluated_answer = evaluate_grid(&answer.rows);
            if evaluated_answer
                .iter()
                .flatten()
                .any(|value| matches!(value, CellValue::Error(_)))
            {
                return GradeResult::new(
                    GradeStatus::Incorrect,
                    "Resolve the spreadsheet error shown beneath the formula cell before checking this grid.",
                );
            }
            let evaluated_expected = evaluate_grid(&part.expected.rows);
            if evaluated_expected
                .iter()
                .flatten()
                .any(|value| matches!(value, CellValue::Error(_)))
            {
                return GradeResult::new(
                    GradeStatus::Unverified,
                    "The imported answer grid contains a spreadsheet error, so LedgerForge cannot verify this response.",
                );
            }
            let actual = display_rows(&evaluated_answer);
            let expected = display_rows(&evaluated_expected);
            grade_rows(
                &actual,
                &expected,
                part.settings
                    .get("row_order")
                    .is_some_and(|value| value.eq_ignore_ascii_case("any")),
            )
        }
        ResponseKind::Matching => {
            if normalize_pairs(&answer_pairs(answer)) == normalize_pairs(&part.expected.pairs) {
                GradeResult::new(GradeStatus::Correct, "Every match is correct.")
            } else {
                GradeResult::new(
                    GradeStatus::Incorrect,
                    "One or more matches need another look.",
                )
            }
        }
        ResponseKind::Ordering => {
            if normalize_order(&answer_order(answer)) == normalize_order(&part.expected.order) {
                GradeResult::new(GradeStatus::Correct, "The complete sequence is correct.")
            } else {
                GradeResult::new(GradeStatus::Incorrect, "The sequence is not yet correct.")
            }
        }
        ResponseKind::TrueFalse => {
            let result = exact_scalar(
                &answer.scalar,
                &part.expected.scalar,
                &part.expected.accepted,
                normalize_text,
            );
            if result.status == GradeStatus::Correct
                && normalize_text(&part.expected.scalar) == "false"
                && !part.rubric_markdown.trim().is_empty()
            {
                if answer.notes.trim().is_empty() {
                    return GradeResult::new(
                        GradeStatus::Incorrect,
                        "The false choice is correct; add the required correction before self-review.",
                    );
                }
                GradeResult::new(
                    GradeStatus::NeedsSelfReview,
                    "The true/false choice is correct. Compare your correction with the rubric.",
                )
            } else {
                result
            }
        }
        ResponseKind::NoEntry => {
            let result = exact_scalar(
                &answer.scalar,
                &part.expected.scalar,
                &part.expected.accepted,
                normalize_text,
            );
            if result.status == GradeStatus::Correct && !part.rubric_markdown.trim().is_empty() {
                if answer.notes.trim().is_empty() {
                    return GradeResult::new(
                        GradeStatus::Incorrect,
                        "The entry decision is correct; add the required rationale before self-review.",
                    );
                }
                GradeResult::new(
                    GradeStatus::NeedsSelfReview,
                    "The entry decision is correct. Compare your rationale with the rubric.",
                )
            } else {
                result
            }
        }
    }
}

fn display_rows(rows: &[Vec<CellValue>]) -> Vec<Vec<String>> {
    rows.iter()
        .map(|row| row.iter().map(CellValue::display_text).collect())
        .collect()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PartGrade {
    pub part_id: String,
    pub result: GradeResult,
    pub awarded_points: f64,
    pub possible_points: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttemptGrade {
    pub parts: Vec<PartGrade>,
    pub earned_points: f64,
    pub possible_points: f64,
    pub complete: bool,
}

/// Produce a stable whole-question score. A positive self-review awards the points for a
/// judgment response; automatic responses award points only when exactly correct.
pub fn grade_question(question: &AccountingQuestion, attempt: &AttemptRecord) -> AttemptGrade {
    let mut parts = Vec::with_capacity(question.parts.len());
    let mut earned_points = 0.0;
    let mut possible_points = 0.0;
    let mut complete = !question.parts.is_empty();

    for part in &question.parts {
        let possible = if part.points.is_finite() && part.points >= 0.0 {
            part.points
        } else {
            0.0
        };
        let answer = attempt.answers.get(&part.id).cloned().unwrap_or_default();
        let mut result = grade_answer(&answer, part);
        let self_reviewed = attempt.self_reviews.get(&part.id).copied().unwrap_or(false);
        let awarded_points = match result.status {
            GradeStatus::Correct => possible,
            GradeStatus::NeedsSelfReview if self_reviewed => {
                result = GradeResult::new(
                    GradeStatus::Correct,
                    "Self-review recorded against the model answer and rubric.",
                );
                possible
            }
            GradeStatus::Unanswered | GradeStatus::NeedsSelfReview | GradeStatus::Unverified => {
                complete = false;
                0.0
            }
            GradeStatus::Incorrect => {
                complete = false;
                0.0
            }
        };
        earned_points += awarded_points;
        possible_points += possible;
        parts.push(PartGrade {
            part_id: part.id.clone(),
            result,
            awarded_points,
            possible_points: possible,
        });
    }

    AttemptGrade {
        parts,
        earned_points,
        possible_points,
        complete,
    }
}

fn has_gradable_key(part: &QuestionPart) -> bool {
    match part.kind {
        ResponseKind::SingleChoice | ResponseKind::MultipleChoice => {
            !part.expected.selections.is_empty()
        }
        ResponseKind::Number | ResponseKind::Formula => !part.expected.scalar.trim().is_empty(),
        ResponseKind::ShortText | ResponseKind::LongText => {
            !part.expected.scalar.trim().is_empty()
                || !part.expected.accepted.is_empty()
                || !part.rubric_markdown.trim().is_empty()
        }
        ResponseKind::Journal | ResponseKind::Table => !part.expected.rows.is_empty(),
        ResponseKind::Matching => !part.expected.pairs.is_empty(),
        ResponseKind::Ordering => !part.expected.order.is_empty(),
        ResponseKind::TrueFalse | ResponseKind::NoEntry => !part.expected.scalar.trim().is_empty(),
    }
}

fn answer_selections(answer: &StudentAnswer) -> Vec<String> {
    if !answer.selections.is_empty() {
        return answer.selections.clone();
    }
    answer
        .scalar
        .split(|character: char| character == ',' || character.is_whitespace())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .collect()
}

fn answer_pairs(answer: &StudentAnswer) -> BTreeMap<String, String> {
    if !answer.pairs.is_empty() {
        return answer.pairs.clone();
    }
    answer
        .scalar
        .lines()
        .filter_map(|line| {
            line.trim()
                .trim_start_matches(['-', '*'])
                .trim()
                .split_once("=>")
        })
        .map(|(left, right)| (left.trim().to_owned(), right.trim().to_owned()))
        .filter(|(left, right)| !left.is_empty() && !right.is_empty())
        .collect()
}

fn answer_order(answer: &StudentAnswer) -> Vec<String> {
    if !answer.order.is_empty() {
        return answer.order.clone();
    }
    answer
        .scalar
        .lines()
        .map(|line| line.trim().trim_start_matches(['-', '*']).trim())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .collect()
}

fn exact_selection(actual: &[String], expected: &[String], unordered: bool) -> GradeResult {
    let mut actual = normalize_selections(actual);
    let mut expected = normalize_selections(expected);
    if unordered {
        actual.sort();
        expected.sort();
    }
    if actual == expected {
        GradeResult::new(GradeStatus::Correct, "Correct selection.")
    } else {
        GradeResult::new(GradeStatus::Incorrect, "That selection is not correct yet.")
    }
}

fn normalize_selections(values: &[String]) -> Vec<String> {
    values
        .iter()
        .map(|value| value.trim().to_ascii_uppercase())
        .filter(|value| !value.is_empty())
        .collect()
}

fn exact_scalar(
    actual: &str,
    expected: &str,
    accepted: &[String],
    normalizer: fn(&str) -> String,
) -> GradeResult {
    let normalized_actual = normalizer(actual);
    let matches = std::iter::once(expected)
        .chain(accepted.iter().map(String::as_str))
        .any(|candidate| normalizer(candidate) == normalized_actual);
    if matches {
        GradeResult::new(GradeStatus::Correct, "Correct.")
    } else {
        GradeResult::new(
            GradeStatus::Incorrect,
            "Compare the response with the required form and try again.",
        )
    }
}

fn grade_number(actual: &str, expected: &str, tolerance: f64) -> GradeResult {
    let (Some(actual), Some(expected)) = (accounting_number(actual), accounting_number(expected))
    else {
        return GradeResult::new(GradeStatus::Incorrect, "Enter a valid accounting number.");
    };
    if (actual - expected).abs() <= tolerance {
        GradeResult::new(
            GradeStatus::Correct,
            "Correct within the allowed tolerance.",
        )
    } else {
        GradeResult::new(
            GradeStatus::Incorrect,
            "The amount is outside the allowed tolerance.",
        )
    }
}

fn grade_rows(
    actual: &[Vec<String>],
    expected: &[Vec<String>],
    row_order_any: bool,
) -> GradeResult {
    let mut actual = normalized_rows(actual);
    let mut expected = normalized_rows(expected);
    if row_order_any {
        actual.sort();
        expected.sort();
    }
    if actual == expected {
        GradeResult::new(GradeStatus::Correct, "Every required cell is correct.")
    } else {
        GradeResult::new(
            GradeStatus::Incorrect,
            "At least one row or cell differs from the answer key.",
        )
    }
}

fn normalized_rows(rows: &[Vec<String>]) -> Vec<Vec<String>> {
    rows.iter()
        .map(|row| row.iter().map(|cell| normalize_cell(cell)).collect())
        .filter(|row: &Vec<String>| row.iter().any(|cell| !cell.is_empty()))
        .collect()
}

fn normalize_pairs(values: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    values
        .iter()
        .map(|(left, right)| (left.trim().to_owned(), right.trim().to_owned()))
        .collect()
}

fn normalize_order(values: &[String]) -> Vec<String> {
    values
        .iter()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .collect()
}

fn normalize_text(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn normalize_formula(value: &str) -> String {
    let normalized = normalize_text(value);
    normalized
        .strip_prefix('=')
        .unwrap_or(&normalized)
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect()
}

fn normalize_cell(value: &str) -> String {
    if let Some(number) = accounting_number(value) {
        let number = if number.abs() < 0.000_000_5 {
            0.0
        } else {
            number
        };
        format!("{number:.6}")
    } else {
        normalize_text(value)
    }
}

fn accounting_number(input: &str) -> Option<f64> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return None;
    }
    let negative_parentheses = trimmed.starts_with('(') && trimmed.ends_with(')');
    let cleaned: String = trimmed
        .chars()
        .filter(|character| !matches!(character, '$' | ',' | '%' | '(' | ')'))
        .collect();
    let number = cleaned.trim().parse::<f64>().ok()?;
    if !number.is_finite() {
        return None;
    }
    Some(if negative_parentheses {
        -number.abs()
    } else {
        number
    })
}

fn self_review() -> GradeResult {
    GradeResult::new(
        GradeStatus::NeedsSelfReview,
        "This response requires judgment. Reveal the answer and mark your own work.",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{ExpectedAnswer, QuestionFormat};

    fn part(kind: ResponseKind, scalar: &str) -> QuestionPart {
        QuestionPart {
            id: "a".to_owned(),
            kind,
            format: QuestionFormat::SingleNumber,
            expected: ExpectedAnswer {
                scalar: scalar.to_owned(),
                ..ExpectedAnswer::default()
            },
            ..QuestionPart::default()
        }
    }

    #[test]
    fn accounting_numbers_accept_currency_commas_and_parentheses() {
        assert_eq!(accounting_number("$12,500.25"), Some(12_500.25));
        assert_eq!(accounting_number("($450)"), Some(-450.0));
    }

    #[test]
    fn non_finite_numbers_are_rejected() {
        assert_eq!(accounting_number("NaN"), None);
        assert_eq!(accounting_number("inf"), None);
    }

    #[test]
    fn numerical_tolerance_is_inclusive() {
        let mut part = part(ResponseKind::Number, "100");
        part.expected.tolerance = Some(0.5);
        let answer = StudentAnswer {
            scalar: "100.5".to_owned(),
            ..StudentAnswer::default()
        };
        assert_eq!(grade_answer(&answer, &part).status, GradeStatus::Correct);
    }

    #[test]
    fn formula_normalization_removes_only_one_leading_equals_sign() {
        assert_eq!(
            normalize_formula("= PV(8%, 3, 0, -10000)"),
            "pv(8%,3,0,-10000)"
        );
        assert_eq!(
            normalize_formula("==PV(8%,3,0,-10000)"),
            "=pv(8%,3,0,-10000)"
        );
        assert_ne!(
            normalize_formula("==PV(8%,3,0,-10000)"),
            normalize_formula("=PV(8%,3,0,-10000)")
        );
    }

    #[test]
    fn false_assertion_with_correction_rubric_requires_self_review() {
        let mut part = part(ResponseKind::TrueFalse, "False");
        part.rubric_markdown =
            "A trial balance does not detect omitted or equal-offset errors.".to_owned();
        let answer = StudentAnswer {
            scalar: "false".to_owned(),
            notes: "It only establishes debit-credit equality.".to_owned(),
            ..StudentAnswer::default()
        };
        assert_eq!(
            grade_answer(&answer, &part).status,
            GradeStatus::NeedsSelfReview
        );
    }

    #[test]
    fn correction_and_entry_rationales_must_be_written_before_self_review() {
        for (kind, expected) in [
            (ResponseKind::TrueFalse, "False"),
            (ResponseKind::NoEntry, "No entry"),
        ] {
            let mut part = part(kind, expected);
            part.rubric_markdown = "Explain the recognition conclusion.".to_owned();
            let answer = StudentAnswer {
                scalar: expected.to_owned(),
                ..StudentAnswer::default()
            };
            assert_eq!(grade_answer(&answer, &part).status, GradeStatus::Incorrect);
        }
    }

    #[test]
    fn whole_question_scoring_requires_every_automatic_or_reviewed_part() {
        let automatic = QuestionPart {
            points: 1.0,
            ..part(ResponseKind::Number, "10")
        };
        let written = QuestionPart {
            id: "b".to_owned(),
            points: 2.0,
            expected: ExpectedAnswer {
                scalar: "Model reasoning".to_owned(),
                ..ExpectedAnswer::default()
            },
            ..part(ResponseKind::LongText, "")
        };
        let question = AccountingQuestion {
            parts: vec![automatic, written],
            ..AccountingQuestion::default()
        };
        let mut attempt = AttemptRecord {
            answers: BTreeMap::from([
                (
                    "a".to_owned(),
                    StudentAnswer {
                        scalar: "10".to_owned(),
                        ..StudentAnswer::default()
                    },
                ),
                (
                    "b".to_owned(),
                    StudentAnswer {
                        scalar: "My reasoning".to_owned(),
                        ..StudentAnswer::default()
                    },
                ),
            ]),
            ..AttemptRecord::default()
        };
        let before_review = grade_question(&question, &attempt);
        assert_eq!(before_review.earned_points, 1.0);
        assert_eq!(before_review.possible_points, 3.0);
        assert!(!before_review.complete);

        attempt.self_reviews.insert("b".to_owned(), true);
        let after_review = grade_question(&question, &attempt);
        assert_eq!(after_review.earned_points, 3.0);
        assert!(after_review.complete);
    }

    #[test]
    fn unverified_parts_never_award_points_from_a_self_review_checkbox() {
        let question = AccountingQuestion {
            parts: vec![part(ResponseKind::LongText, "")],
            ..AccountingQuestion::default()
        };
        let attempt = AttemptRecord {
            answers: BTreeMap::from([(
                "a".to_owned(),
                StudentAnswer {
                    scalar: "Unverifiable response".to_owned(),
                    ..StudentAnswer::default()
                },
            )]),
            self_reviews: BTreeMap::from([("a".to_owned(), true)]),
            ..AttemptRecord::default()
        };
        let grade = grade_question(&question, &attempt);
        assert_eq!(grade.parts[0].result.status, GradeStatus::Unverified);
        assert_eq!(grade.earned_points, 0.0);
        assert!(!grade.complete);
    }

    #[test]
    fn spreadsheet_errors_in_the_answer_key_are_unverified() {
        let part = QuestionPart {
            kind: ResponseKind::Table,
            expected: ExpectedAnswer {
                rows: vec![vec!["=1/0".to_owned()]],
                ..ExpectedAnswer::default()
            },
            ..QuestionPart::default()
        };
        let answer = StudentAnswer {
            rows: vec![vec!["#DIV/0!".to_owned()]],
            ..StudentAnswer::default()
        };
        assert_eq!(grade_answer(&answer, &part).status, GradeStatus::Unverified);
    }
}
