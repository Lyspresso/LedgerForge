use std::path::Path;
use std::time::Instant;

use accounting_question_core::{
    GradeStatus, ResponseKind, StudentAnswer, grade_answer, parse_markdown, prompt_presentation,
    question_title_presentation,
};

fn exercise_bank(
    variable: &str,
    expected_questions: usize,
    expected_choices: usize,
    expected_long_text: usize,
    expected_unverified: usize,
) {
    let path = std::env::var_os(variable).unwrap_or_else(|| {
        panic!(
            "{variable} is required for this ignored QA test; set it to the absolute path of the corresponding private Markdown bank and rerun the test"
        )
    });
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
#[ignore = "requires LEDGERFORGE_QA_COMPLETE to point to the private complete question bank"]
fn supplied_complete_bank_has_all_3088_questions_and_754_choice_parts() {
    exercise_bank("LEDGERFORGE_QA_COMPLETE", 3_088, 754, 2_474, 0);
}

#[test]
#[ignore = "requires LEDGERFORGE_QA_NEEDS_HUMAN to point to the private human-review question bank"]
fn supplied_human_review_bank_has_all_78_questions_and_9_choice_parts() {
    exercise_bank("LEDGERFORGE_QA_NEEDS_HUMAN", 78, 9, 71, 2);
}

#[test]
#[ignore = "requires LEDGERFORGE_QA_TWO_PER_CONCEPT to point to the private two-per-concept bank"]
fn supplied_two_per_concept_bank_has_readable_titles_and_collapsed_provenance() {
    let path = std::env::var_os("LEDGERFORGE_QA_TWO_PER_CONCEPT").unwrap_or_else(|| {
        panic!(
            "LEDGERFORGE_QA_TWO_PER_CONCEPT is required for this ignored QA test; set it to the absolute Markdown path"
        )
    });
    let markdown = std::fs::read_to_string(&path).expect("two-per-concept bank should be readable");
    let result = parse_markdown(&markdown, Path::new(&path).to_string_lossy())
        .expect("two-per-concept bank should parse");
    assert_eq!(result.pack.questions.len(), 4_686);

    for question in &result.pack.questions {
        let presentation = question_title_presentation(question);
        let lowercase = presentation.title.to_ascii_lowercase();
        assert!(!presentation.title.trim().is_empty(), "{}", question.id);
        assert!(!lowercase.contains("acct343-"), "{}", question.id);
        assert!(!lowercase.contains("original-verified"), "{}", question.id);
        assert!(!lowercase.contains("derived-verified"), "{}", question.id);
        for part in &question.parts {
            let prompt = prompt_presentation(&part.prompt_markdown);
            assert!(
                !prompt.body.trim().is_empty(),
                "{} / {}",
                question.id,
                part.id
            );
            assert!(
                !prompt.body.starts_with("### `acct343-"),
                "{} / {}",
                question.id,
                part.id
            );
        }
    }
}
