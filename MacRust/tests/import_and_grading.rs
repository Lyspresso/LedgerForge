use std::collections::BTreeMap;

use accounting_question_core::{
    BUILT_IN_SAMPLE, BUILT_IN_SAMPLE_NAME, ExpectedAnswer, GradeStatus, MarkdownImportError,
    QuestionFormat, QuestionPart, ResponseKind, StudentAnswer, grade_answer, parse_markdown,
};

const STRUCTURED_FIXTURE: &str = r#"
:::question id=equation-001 shell=multipart variation=core formats=single_number,initial_journal_entry tags=chapter-2,equation
# Accounting Equation and Entry
## Scenario
A company receives **$10,000 cash** from its owner in exchange for common shares.

:::part id=a kind=number format=single_number points=1
### Prompt
By how much does total equity increase?
### Answer
10000
### Settings
tolerance: 0
:::endpart

:::part id=b kind=journal format=initial_journal_entry points=2
### Prompt
Prepare the journal entry.
### Columns
Account | Debit | Credit
### Answer
| Account | Debit | Credit |
|---|---:|---:|
| Cash | 10000 | |
| Common Stock | | 10000 |
### Settings
row_order: any
:::endpart
:::endquestion
"#;

#[test]
fn bundled_sampler_is_warning_free_and_covers_all_35_formats() {
    let result = parse_markdown(BUILT_IN_SAMPLE, BUILT_IN_SAMPLE_NAME).unwrap();
    assert_eq!(result.pack.questions.len(), 35);
    assert_eq!(
        result
            .pack
            .questions
            .iter()
            .flat_map(|question| &question.parts)
            .count(),
        36
    );
    assert!(result.warnings.is_empty());
    let covered = result
        .pack
        .questions
        .iter()
        .flat_map(|question| &question.formats)
        .copied()
        .collect::<std::collections::HashSet<_>>();
    assert_eq!(covered.len(), QuestionFormat::ALL.len());
}

#[test]
fn structured_question_matches_shared_markdown_contract() {
    let result = parse_markdown(STRUCTURED_FIXTURE, "Fixture.md").unwrap();
    assert!(result.warnings.is_empty());
    assert_eq!(result.pack.questions.len(), 1);
    let question = &result.pack.questions[0];
    assert_eq!(question.id, "equation-001");
    assert_eq!(question.formats.len(), 2);
    assert_eq!(question.parts[0].expected.scalar, "10000");
    assert_eq!(question.parts[1].columns, ["Account", "Debit", "Credit"]);
    assert_eq!(
        question.parts[1].expected.rows,
        [
            vec!["Cash".to_owned(), "10000".to_owned(), String::new()],
            vec!["Common Stock".to_owned(), String::new(), "10000".to_owned()]
        ]
    );

    let number = StudentAnswer {
        scalar: "$10,000".to_owned(),
        ..StudentAnswer::default()
    };
    assert_eq!(
        grade_answer(&number, &question.parts[0]).status,
        GradeStatus::Correct
    );

    let reversed_entry = StudentAnswer {
        rows: vec![
            vec!["Common Stock".to_owned(), String::new(), "10000".to_owned()],
            vec!["Cash".to_owned(), "10,000".to_owned(), String::new()],
        ],
        ..StudentAnswer::default()
    };
    assert_eq!(
        grade_answer(&reversed_entry, &question.parts[1]).status,
        GradeStatus::Correct
    );
}

#[test]
fn accepted_section_preserves_formula_commas_and_settings_remain_supported() {
    let markdown = r#"
:::question id=accepted-alternatives
:::part id=formula kind=formula
### Prompt
Enter a present-value formula.
### Answer
=PV(0.08,3,0,-10000)
### Accepted
- =PV(8%,3,0,-10000)
- =PV(0.08,3,0,-10000)
### Settings
accepted: =PV(8%,3,0,-10000), present value
:::endpart
:::endquestion
"#;
    let part = &parse_markdown(markdown, "Accepted.md")
        .unwrap()
        .pack
        .questions[0]
        .parts[0];

    assert_eq!(part.expected.accepted[0], "=PV(8%,3,0,-10000)");
    assert_eq!(part.expected.accepted[1], "=PV(0.08,3,0,-10000)");
    assert!(part.expected.accepted.contains(&"present value".to_owned()));
    assert!(part.expected.accepted.contains(&"=PV(8%".to_owned()));

    let answer = StudentAnswer {
        scalar: "=PV(8%,3,0,-10000)".to_owned(),
        ..StudentAnswer::default()
    };
    assert_eq!(grade_answer(&answer, part).status, GradeStatus::Correct);
}

#[test]
fn matching_and_ordering_sections_parse_to_stable_ids() {
    let markdown = r#"
:::question id=map shell=multipart formats=matching_mapping_sorting,ordering_timeline
# Classification and Timeline
## Scenario
Complete both parts.
:::part id=a kind=matching format=matching_mapping_sorting
### Prompt
Classify each item.
### Items
- cash | Cash
- building | Building
### Targets
- current | Current asset
- noncurrent | Noncurrent asset
### Answer
- cash => current
- building => noncurrent
:::endpart
:::part id=b kind=ordering format=ordering_timeline
### Prompt
Order the events.
### Items
- recognize | Initial recognition
- measure | Subsequent measurement
- settle | Settlement
### Answer
- recognize
- measure
- settle
:::endpart
:::endquestion
"#;
    let question = &parse_markdown(markdown, "Map.md").unwrap().pack.questions[0];
    assert_eq!(question.parts[0].expected.pairs["cash"], "current");
    assert_eq!(
        question.parts[1].expected.order,
        ["recognize", "measure", "settle"]
    );
}

#[test]
fn legacy_multiple_choice_gets_an_automatic_editor() {
    let markdown = r#"
## Item 12: Classification
**Question:** Which answer is correct?
- A) First
- B) Second
- C) Third
- D) Fourth
**Answer:** **B.** Second.
"#;
    let result = parse_markdown(markdown, "Legacy.md").unwrap();
    let question = &result.pack.questions[0];
    assert_eq!(question.id, "item-12");
    assert_eq!(question.parts[0].kind, ResponseKind::SingleChoice);
    assert_eq!(question.parts[0].expected.selections, ["B"]);
    assert_eq!(question.parts[0].options.len(), 4);
    assert_eq!(result.warnings.len(), 1);
}

#[test]
fn legacy_long_form_keeps_answer_as_rubric_for_self_review() {
    let markdown = r#"
### `core_001_q1`
**Question:** Prepare a reconciliation and explain the difference.
**Required:** Show all work.
**Answer key:** The ending balances agree after the outstanding item is included.
"#;
    let question = &parse_markdown(markdown, "Legacy.md")
        .unwrap()
        .pack
        .questions[0];
    let part = &question.parts[0];
    assert_eq!(question.id, "core_001_q1");
    assert_eq!(part.kind, ResponseKind::LongText);
    assert!(
        question
            .formats
            .contains(&QuestionFormat::ReconciliationProof)
    );
    assert!(part.rubric_markdown.contains("ending balances agree"));
}

#[test]
fn duplicate_structured_ids_are_rejected() {
    let markdown = r#"
:::question id=same
# First
:::endquestion
:::question id=same
# Second
:::endquestion
"#;
    assert!(matches!(
        parse_markdown(markdown, "Duplicate.md"),
        Err(MarkdownImportError::DuplicateQuestionId { id }) if id == "same"
    ));
}

#[test]
fn empty_and_malformed_documents_fail_without_panicking() {
    assert_eq!(
        parse_markdown(" \n\t", "Empty.md"),
        Err(MarkdownImportError::EmptyDocument)
    );
    assert!(matches!(
        parse_markdown(":::question id=\"unterminated\n", "Malformed.md"),
        Err(MarkdownImportError::MalformedDirective { line: 1, .. })
    ));
}

#[test]
fn missing_end_markers_do_not_swallow_later_parts_or_questions() {
    let markdown = r#"
:::question id=first
:::part id=a kind=number
### Prompt
First part.
### Answer
1
:::part id=b kind=number
### Prompt
Second part.
### Answer
2
:::endpart
:::question id=second
:::part id=a kind=number
### Prompt
Third part.
### Answer
3
:::endpart
:::endquestion
"#;
    let result = parse_markdown(markdown, "Recovery.md").unwrap();
    assert_eq!(result.pack.questions.len(), 2);
    assert_eq!(result.pack.questions[0].parts.len(), 2);
    assert_eq!(result.pack.questions[1].parts.len(), 1);
    assert!(
        result
            .warnings
            .iter()
            .any(|warning| { warning.message.contains("no :::endpart") })
    );
    assert!(
        result
            .warnings
            .iter()
            .any(|warning| { warning.message.contains("no :::endquestion") })
    );
}

#[test]
fn paired_legacy_multiple_choice_becomes_two_answerable_parts() {
    let markdown = r#"
### `core_demo_q4` — Demo
**Question 1:** Which account normally has a debit balance?
- A) Cash
- B) Revenue
- C) Common Stock
- D) Accounts Payable
**Answer:** **A.** Cash normally has a debit balance.

**Q4A.** Which statement reports cash flows?
- A) Balance sheet
- B) Statement of cash flows
- C) Income statement
- D) Statement of retained earnings
**Answer:** **B.** The statement of cash flows reports cash flows.
"#;
    let result = parse_markdown(markdown, "Paired.md").unwrap();
    let question = &result.pack.questions[0];
    assert_eq!(question.parts.len(), 2);
    assert_eq!(question.parts[0].id, "choice-1");
    assert_eq!(question.parts[1].id, "choice-2");
    assert_eq!(question.parts[0].expected.selections, ["A"]);
    assert_eq!(question.parts[1].expected.selections, ["B"]);
}

#[test]
fn duplicate_part_ids_are_rejected_before_answers_can_collide() {
    let markdown = r#"
:::question id=duplicate-parts
:::part id=a kind=number
### Prompt
First.
### Answer
1
:::endpart
:::part id=a kind=number
### Prompt
Second.
### Answer
2
:::endpart
:::endquestion
"#;
    assert!(matches!(
        parse_markdown(markdown, "Duplicate-parts.md"),
        Err(MarkdownImportError::DuplicatePartId { question_id, id })
            if question_id == "duplicate-parts" && id == "a"
    ));
}

#[test]
fn invalid_non_finite_scoring_settings_fall_back_safely() {
    let markdown = r#"
:::question id=safe-numbers
:::part id=a kind=number points=NaN
### Prompt
Enter one.
### Answer
1
### Settings
tolerance: NaN
:::endpart
:::endquestion
"#;
    let result = parse_markdown(markdown, "Safe.md").unwrap();
    let part = &result.pack.questions[0].parts[0];
    assert_eq!(part.points, 1.0);
    assert_eq!(part.expected.tolerance, None);
    assert_eq!(result.warnings.len(), 2);
}

fn part(kind: ResponseKind, expected: ExpectedAnswer) -> QuestionPart {
    QuestionPart {
        id: "a".to_owned(),
        kind,
        format: kind.default_format(),
        expected,
        ..QuestionPart::default()
    }
}

#[test]
fn all_twelve_response_primitives_have_a_deterministic_grade_path() {
    let exact = |kind, answer: StudentAnswer, expected: ExpectedAnswer| {
        assert_eq!(
            grade_answer(&answer, &part(kind, expected)).status,
            GradeStatus::Correct,
            "failed kind {kind:?}"
        );
    };

    exact(
        ResponseKind::SingleChoice,
        StudentAnswer {
            selections: vec!["a".to_owned()],
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            selections: vec!["A".to_owned()],
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::MultipleChoice,
        StudentAnswer {
            selections: vec!["C".to_owned(), "A".to_owned()],
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            selections: vec!["A".to_owned(), "C".to_owned()],
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::Number,
        StudentAnswer {
            scalar: "(250)".to_owned(),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            scalar: "-250".to_owned(),
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::Formula,
        StudentAnswer {
            scalar: "= PV(rate, nper, pmt)".to_owned(),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            scalar: "PV(rate,nper,pmt)".to_owned(),
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::ShortText,
        StudentAnswer {
            scalar: "Current Asset".to_owned(),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            scalar: String::new(),
            accepted: vec!["current asset".to_owned()],
            ..ExpectedAnswer::default()
        },
    );
    for kind in [ResponseKind::Journal, ResponseKind::Table] {
        exact(
            kind,
            StudentAnswer {
                rows: vec![vec!["Cash".to_owned(), "$100".to_owned()]],
                ..StudentAnswer::default()
            },
            ExpectedAnswer {
                rows: vec![vec!["cash".to_owned(), "100.00".to_owned()]],
                ..ExpectedAnswer::default()
            },
        );
    }
    exact(
        ResponseKind::Matching,
        StudentAnswer {
            pairs: BTreeMap::from([("cash".to_owned(), "current".to_owned())]),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            pairs: BTreeMap::from([("cash".to_owned(), "current".to_owned())]),
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::Ordering,
        StudentAnswer {
            order: vec!["first".to_owned(), "second".to_owned()],
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            order: vec!["first".to_owned(), "second".to_owned()],
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::TrueFalse,
        StudentAnswer {
            scalar: "TRUE".to_owned(),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            scalar: "True".to_owned(),
            ..ExpectedAnswer::default()
        },
    );
    exact(
        ResponseKind::NoEntry,
        StudentAnswer {
            scalar: "No entry".to_owned(),
            ..StudentAnswer::default()
        },
        ExpectedAnswer {
            scalar: "No entry".to_owned(),
            ..ExpectedAnswer::default()
        },
    );

    let long_text = part(
        ResponseKind::LongText,
        ExpectedAnswer {
            scalar: "Model response".to_owned(),
            ..ExpectedAnswer::default()
        },
    );
    assert_eq!(
        grade_answer(
            &StudentAnswer {
                scalar: "Reasoned response".to_owned(),
                ..StudentAnswer::default()
            },
            &long_text
        )
        .status,
        GradeStatus::NeedsSelfReview
    );
    assert_eq!(ResponseKind::ALL.len(), 12);
    assert_eq!(QuestionFormat::ALL.len(), 35);
}

#[test]
fn spreadsheet_formulas_are_graded_by_evaluated_cell_value() {
    let table = part(
        ResponseKind::Table,
        ExpectedAnswer {
            rows: vec![vec!["10".to_owned(), "20".to_owned(), "30".to_owned()]],
            ..ExpectedAnswer::default()
        },
    );
    let answer = StudentAnswer {
        rows: vec![vec![
            "10".to_owned(),
            "=A1*2".to_owned(),
            "=SUM(A1:B1)".to_owned(),
        ]],
        ..StudentAnswer::default()
    };
    assert_eq!(grade_answer(&answer, &table).status, GradeStatus::Correct);
    assert_eq!(answer.rows[0][1], "=A1*2");
}
