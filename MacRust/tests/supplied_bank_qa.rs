use std::path::Path;
use std::time::Instant;

use accounting_question_core::{
    GradeStatus, ResponseKind, StudentAnswer, grade_answer, parse_markdown,
};

fn exercise_bank(
    variable: &str,
    expected_questions: usize,
    expected_choices: usize,
    expected_long_text: usize,
    expected_unverified: usize,
) {
    let Some(path) = std::env::var_os(variable) else {
        return;
    };
    let path = Path::new(&path);
    let started = Instant::now();
    let markdown = std::fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("could not read {}: {error}", path.display()));
    let result = parse_markdown(&markdown, path.to_string_lossy())
        .unwrap_or_else(|error| panic!("could not parse {}: {error}", path.display()));
    let choice_parts = result
        .pack
        .questions
        .iter()
        .flat_map(|question| &question.parts)
        .filter(|part| part.kind == ResponseKind::SingleChoice)
        .count();
    let long_text_parts = result
        .pack
        .questions
        .iter()
        .flat_map(|question| &question.parts)
        .filter(|part| part.kind == ResponseKind::LongText)
        .count();

    assert_eq!(result.pack.questions.len(), expected_questions);
    assert_eq!(choice_parts, expected_choices);
    assert_eq!(long_text_parts, expected_long_text);
    let unverified = result
        .pack
        .questions
        .iter()
        .flat_map(|question| &question.parts)
        .filter(|part| {
            grade_answer(
                &StudentAnswer {
                    scalar: "student response".to_owned(),
                    ..StudentAnswer::default()
                },
                part,
            )
            .status
                == GradeStatus::Unverified
        })
        .count();
    assert_eq!(unverified, expected_unverified);
    assert_eq!(result.warnings.len(), 1);
    eprintln!(
        "parsed {} questions and {} choice parts from {} in {:?}",
        expected_questions,
        expected_choices,
        path.display(),
        started.elapsed()
    );
}

#[test]
fn supplied_complete_bank_has_all_3088_questions_and_754_choice_parts() {
    exercise_bank("LEDGERFORGE_QA_COMPLETE", 3_088, 754, 2_474, 0);
}

#[test]
fn supplied_human_review_bank_has_all_78_questions_and_9_choice_parts() {
    exercise_bank("LEDGERFORGE_QA_NEEDS_HUMAN", 78, 9, 71, 2);
}
