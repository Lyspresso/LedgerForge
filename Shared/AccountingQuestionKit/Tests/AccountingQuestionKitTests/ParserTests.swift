import Foundation
import Testing
@testable import AccountingQuestionKit

@Test func parsesStructuredQuestionAndGradesNumber() throws {
    let markdown = """
    :::question id=demo shell=multipart variation=core formats=single_number tags=demo
    # Demo Question
    ## Scenario
    A company has assets of $120 and liabilities of $45.
    :::part id=a kind=number format=single_number points=2
    ### Prompt
    Compute equity.
    ### Answer
    75
    ### Settings
    tolerance: 0
    :::endpart
    :::endquestion
    """

    let result = try QuestionMarkdownParser.parse(markdown, sourceName: "Fixture")
    #expect(result.pack.questions.count == 1)
    let part = try #require(result.pack.questions.first?.parts.first)
    #expect(part.expected.scalar == "75")
    #expect(AnswerGrader.grade(StudentAnswer(scalar: "$75"), for: part).status == .correct)
}

@Test func parsesJournalTable() throws {
    let markdown = """
    :::question id=journal shell=multipart formats=initial_journal_entry
    # Journal
    ## Scenario
    Paid cash for supplies.
    :::part id=a kind=journal format=initial_journal_entry
    ### Prompt
    Record the entry.
    ### Columns
    Account | Debit | Credit
    ### Answer
    | Account | Debit | Credit |
    |---|---:|---:|
    | Supplies | 100 | |
    | Cash | | 100 |
    :::endpart
    :::endquestion
    """
    let part = try #require(QuestionMarkdownParser.parse(markdown).pack.questions.first?.parts.first)
    #expect(part.expected.rows.count == 2)
    let answer = StudentAnswer(rows: [["Supplies", "100", ""], ["Cash", "", "100"]])
    #expect(AnswerGrader.grade(answer, for: part).status == .correct)
}

@Test func legacyMultipleChoiceUsesChoiceEditor() throws {
    let markdown = """
    ## Item 12: Classification
    **Question:** Which answer is correct?
    - A) First
    - B) Second
    - C) Third
    - D) Fourth
    **Answer:** **B.** Second.
    """
    let question = try #require(QuestionMarkdownParser.parse(markdown).pack.questions.first)
    #expect(question.parts.first?.kind == .singleChoice)
    #expect(question.parts.first?.expected.selections == ["B"])
}

@Test func legacyTransportHeadingBecomesAReadableQuestionTitle() throws {
    let markdown = """
    ### `acct343-c0017-q1` — ORIGINAL-VERIFIED — LO 14-2 — Subsequent measurement schedule (discount amortization) + period-end FVA + disposal under FV-NI

    **LO:** LO 14-2
    **Concept:** Subsequent measurement schedule (discount amortization) + period-end FVA + disposal under FV-NI
    **Set position:** Group 17 of 2343 · Question 1 of 2
    **Set status:** ORIGINAL-VERIFIED
    **Provenance:** `ACCOUNT343_COMPLETE.md` · source `core_003_q3`
    **Source-unit handling:** complete cleaned source item
    > **Derived-verification requirement:** Reconcile every result to the supplied facts.

    ### Q3 — CORE — Discount TS: effective-interest amortized cost, year-end FVA, disposal

    **Scenario:** Westbrook purchases bonds.
    **Required:** Prepare the entries.
    **Answer:** Debit the investment and credit cash.
    """

    let question = try #require(QuestionMarkdownParser.parse(markdown).pack.questions.first)
    #expect(question.title == "Discount TS: effective-interest amortized cost, year-end FVA, disposal")
    #expect(question.displayTitle == question.title)
    #expect(question.titlePresentation.learningObjective == "LO 14-2")
    #expect(question.titlePresentation.verification == "Original · verified")
    #expect(question.parts.first?.promptPresentation.body.hasPrefix("**Scenario:** Westbrook") == true)
    #expect(question.parts.first?.promptPresentation.importDetails.count == 7)
}

@Test func duplicateLegacyIDsAreRenamedInsteadOfCrashingLibraryMerges() throws {
    let markdown = """
    ## Item 12: First
    **Question:** Explain the first item.
    **Answer:** First answer.

    ## Item 12: Second
    **Question:** Explain the second item.
    **Answer:** Second answer.
    """

    let result = try QuestionMarkdownParser.parse(markdown, sourceName: "Duplicate fixture")

    #expect(result.pack.questions.map(\.id) == ["item-12", "item-12-2"])
    #expect(result.warnings.contains { $0.message.contains("Duplicate legacy id") })
}

@Test func numberedLegacyItemTitleKeepsOnlyItsReadableSubject() throws {
    let markdown = """
    ## Item 12: Classification of the investment
    **Question:** Which category applies?
    **Answer:** Trading security.
    """
    let question = try #require(QuestionMarkdownParser.parse(markdown).pack.questions.first)
    #expect(question.title == "Classification of the investment")
}

@Test func pairedLegacyMultipleChoiceBecomesTwoAnswerableParts() throws {
    let markdown = """
    ### `core_demo_q4` — Demo
    **Question 1:** Which account normally has a debit balance?
    - A) Cash
    - B) Revenue
    - C) Common Stock
    - D) Accounts Payable
    **Answer:** **A.** Cash normally has a debit balance.

    **Question 2:** Which statement reports cash flows?
    - A) Balance sheet
    - B) Statement of cash flows
    - C) Income statement
    - D) Statement of retained earnings
    **Answer:** **B.** The statement of cash flows reports cash flows.
    """

    let question = try #require(
        QuestionMarkdownParser.parse(markdown, sourceName: "Paired fixture").pack.questions.first
    )

    #expect(question.parts.map(\.id) == ["choice-1", "choice-2"])
    #expect(question.parts.map(\.expected.selections) == [["A"], ["B"]])
    #expect(question.parts.allSatisfy { $0.options.count == 4 })
}

@Test func everyPedagogicalFormatIsRepresentable() {
    #expect(QuestionFormat.allCases.count == 35)
    #expect(ResponseKind.allCases.count == 12)
}

@Test func completeSamplerCoversEveryFormat() throws {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sampleURL = testDirectory
        .appending(path: "../../../../Samples/ALL_FORMATS_SAMPLE.md")
        .standardizedFileURL
    let markdown = try String(contentsOf: sampleURL, encoding: .utf8)
    let result = try QuestionMarkdownParser.parse(markdown, sourceName: "Complete sampler")
    let coveredFormats = Set(result.pack.questions.flatMap { $0.formats })

    #expect(result.pack.questions.count == 35)
    #expect(coveredFormats == Set(QuestionFormat.allCases))
    #expect(result.warnings.isEmpty)
    #expect(QuestionValidator.validate(result.pack).isEmpty)
}

@Test func completeSamplerAnswerKeysExerciseEveryGraderPath() throws {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sampleURL = testDirectory
        .appending(path: "../../../../Samples/ALL_FORMATS_SAMPLE.md")
        .standardizedFileURL
    let markdown = try String(contentsOf: sampleURL, encoding: .utf8)
    let pack = try QuestionMarkdownParser.parse(markdown).pack
    let parts = pack.questions.flatMap { $0.parts }
    let exercisedKinds = Set(parts.map(\.kind))

    for part in parts {
        let answer = StudentAnswer(
            scalar: part.expected.scalar,
            selections: part.expected.selections,
            rows: part.expected.rows,
            pairs: part.expected.pairs,
            order: part.expected.order,
            notes: part.rubricMarkdown.isEmpty ? "" : "Rubric reviewed"
        )
        let result = AnswerGrader.grade(answer, for: part)
        #expect(result.status == .correct || result.status == .needsSelfReview)
    }

    #expect(exercisedKinds == Set(ResponseKind.allCases))
}

@Test func falseAssertionRoutesItsCorrectionToSelfReview() {
    let part = QuestionPart(
        id: "assertion",
        kind: .trueFalse,
        format: .trueFalseCorrection,
        promptMarkdown: "A trial balance proves every transaction is correct.",
        expected: ExpectedAnswer(scalar: "False"),
        rubricMarkdown: "A trial balance only tests debit-credit equality."
    )

    let correctDecision = StudentAnswer(scalar: "False", notes: "It does not detect omissions.")
    let wrongDecision = StudentAnswer(scalar: "True")

    #expect(AnswerGrader.grade(correctDecision, for: part).status == .needsSelfReview)
    #expect(AnswerGrader.grade(wrongDecision, for: part).status == .incorrect)
}
