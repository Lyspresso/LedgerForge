import AccountingQuestionKit
import XCTest
@testable import AccountingQuestionSuite

@MainActor
final class StudyExperienceTests: XCTestCase {
    func testEveryResponseKindHasADedicatedEditorFamily() {
        let mappedFamilies = Set(ResponseKind.allCases.map(ResponseEditorPolicy.family(for:)))

        XCTAssertEqual(mappedFamilies, Set(ResponseEditorFamily.allCases))
        XCTAssertEqual(mappedFamilies.count, ResponseKind.allCases.count)
    }

    func testAnswerEditingSupportsSelectionsCellsMatchesAndOrdering() {
        var answer = StudentAnswer()

        answer[selection: "cash"] = true
        XCTAssertEqual(answer.selections, ["cash"])
        answer[selection: "cash"] = false
        XCTAssertTrue(answer.selections.isEmpty)

        answer[cell: AnswerCell(row: 1, column: 2)] = "1,250"
        XCTAssertEqual(answer.rows.count, 2)
        XCTAssertEqual(answer.rows[1], ["", "", "1,250"])

        answer[matchFor: "asset"] = "debit"
        XCTAssertEqual(answer.pairs["asset"], "debit")
        answer[matchFor: "asset"] = ""
        XCTAssertNil(answer.pairs["asset"])

        answer.order = ["recognize", "measure", "derecognize"]
        answer.moveOrderItem(from: 2, to: 0)
        XCTAssertEqual(answer.order, ["derecognize", "recognize", "measure"])
    }

    func testSpreadsheetEditorEvaluatesWithoutReplacingRawFormulaAndTraversesCells() {
        var answer = StudentAnswer(
            rows: [["100", "200", "=SUM(A1:B1)", "=Z99"]]
        )
        let presentation = SpreadsheetPresentationEngine.evaluate(rows: answer.rows)

        XCTAssertEqual(answer[cell: AnswerCell(row: 0, column: 2)], "=SUM(A1:B1)")
        XCTAssertEqual(
            presentation[AnswerCell(row: 0, column: 2)],
            SpreadsheetCellPresentation(
                displayText: "300",
                errorMessage: nil,
                isFormula: true
            )
        )
        XCTAssertEqual(
            presentation[AnswerCell(row: 0, column: 3)].errorMessage,
            "Invalid cell reference (#REF!)"
        )

        let first = AnswerCell(row: 0, column: 0)
        let endOfFirstRow = AnswerCell(row: 0, column: 2)
        let startOfSecondRow = AnswerCell(row: 1, column: 0)
        XCTAssertEqual(
            SpreadsheetCellNavigator.next(
                after: endOfFirstRow,
                rowCount: 2,
                columnCount: 3
            ),
            startOfSecondRow
        )
        XCTAssertEqual(
            SpreadsheetCellNavigator.previous(
                before: startOfSecondRow,
                rowCount: 2,
                columnCount: 3
            ),
            endOfFirstRow
        )
        XCTAssertEqual(first.spreadsheetReference, "A1")

        let part = QuestionPart(
            id: "worksheet",
            kind: .table,
            format: .worksheetTrialBalance,
            promptMarkdown: "Complete the worksheet.",
            columns: ["Debit", "Credit", "Total"],
            expected: ExpectedAnswer(rows: [["100", "200", "300"]])
        )
        answer.rows = [["100", "200", "=SUM(A1:B1)"]]
        XCTAssertEqual(AnswerGrader.grade(answer, for: part).status, .correct)
        XCTAssertEqual(answer.rows[0][2], "=SUM(A1:B1)")
    }

    func testStandaloneFormulaPreviewUsesSharedEvaluatorAndRejectsCellReferences() throws {
        let preview = try XCTUnwrap(
            StandaloneFormulaPresentationEngine.evaluate("=PV(10%,2,0,121)")
        )
        XCTAssertEqual(preview.displayText, "-100")
        XCTAssertNil(preview.errorMessage)

        let reference = try XCTUnwrap(
            StandaloneFormulaPresentationEngine.evaluate("=A1+1")
        )
        XCTAssertEqual(reference.displayText, "#REF!")
        XCTAssertTrue(reference.errorMessage?.contains("spreadsheet responses") == true)
        XCTAssertNil(StandaloneFormulaPresentationEngine.evaluate("   "))
    }

    func testSpreadsheetPresentationCoversFunctionsRangesAndSafeErrors() {
        let rows = [
            ["10", "20", "=A1+B1", "=SUM(A1:C1)", "=AVERAGE(A1:B1)", "=MIN(A1:B1)", "=MAX(A1:B1)"],
            ["=ROUND(10/3,2)", "=ABS(-7)", "=IF(A1>5,100,0)", "=PV(10%,2,0,121)", "=FV(10%,2,0,-100)", "=PMT(10%,2,100)", "=NPV(10%,55,60.5)"],
            ["=B3", "=A3", "=1/0", "=Z99", "=NOPE(1)", "=(", "=IF(FALSE,1/0,5)"]
        ]
        let result = SpreadsheetPresentationEngine.evaluate(rows: rows)

        XCTAssertEqual(result[AnswerCell(row: 0, column: 3)].displayText, "60")
        XCTAssertEqual(result[AnswerCell(row: 0, column: 4)].displayText, "15")
        XCTAssertEqual(result[AnswerCell(row: 0, column: 5)].displayText, "10")
        XCTAssertEqual(result[AnswerCell(row: 0, column: 6)].displayText, "20")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 0)].displayText, "3.33")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 1)].displayText, "7")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 2)].displayText, "100")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 3)].displayText, "-100")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 4)].displayText, "121")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 5)].displayText, "-57.619047619")
        XCTAssertEqual(result[AnswerCell(row: 1, column: 6)].displayText, "100")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 0)].errorMessage, "Circular cell reference (#CYCLE!)")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 2)].errorMessage, "Cannot divide by zero (#DIV/0!)")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 3)].errorMessage, "Invalid cell reference (#REF!)")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 4)].errorMessage, "Unknown function or name (#NAME?)")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 5)].errorMessage, "Formula could not be parsed (#PARSE!)")
        XCTAssertEqual(result[AnswerCell(row: 2, column: 6)].displayText, "5")
    }

    func testDecisionExplanationsAndAdvancePolicyFollowActualGradeStatus() {
        let falsePart = QuestionPart(
            id: "tf",
            kind: .trueFalse,
            format: .trueFalseCorrection,
            promptMarkdown: "Evaluate the claim.",
            expected: ExpectedAnswer(scalar: "False"),
            rubricMarkdown: "Correct the claim."
        )
        let noEntryPart = QuestionPart(
            id: "ne",
            kind: .noEntry,
            format: .entryOrNoEntry,
            promptMarkdown: "Choose the treatment.",
            expected: ExpectedAnswer(scalar: "No entry"),
            rubricMarkdown: "Explain the rationale."
        )

        XCTAssertEqual(
            ResponseCompletionPolicy.incompleteResult(
                for: StudentAnswer(scalar: "False"),
                part: falsePart
            )?.status,
            .unanswered
        )
        XCTAssertNil(
            ResponseCompletionPolicy.incompleteResult(
                for: StudentAnswer(scalar: "False", notes: "The corrected statement."),
                part: falsePart
            )
        )
        XCTAssertEqual(
            ResponseCompletionPolicy.incompleteResult(
                for: StudentAnswer(scalar: "No entry"),
                part: noEntryPart
            )?.status,
            .unanswered
        )
        XCTAssertTrue(StudyAdvancePolicy.canAdvance(gradeStatus: .correct, selfReviewComplete: false))
        XCTAssertFalse(StudyAdvancePolicy.canAdvance(gradeStatus: .needsSelfReview, selfReviewComplete: false))
        XCTAssertTrue(StudyAdvancePolicy.canAdvance(gradeStatus: .needsSelfReview, selfReviewComplete: true))
    }

    func testMalformedPersistedEditorStateIsNormalizedToStableIdentifiers() {
        let options = [
            QuestionOption(id: "a", text: "A"),
            QuestionOption(id: "b", text: "B")
        ]
        XCTAssertEqual(
            SelectionAnswerPolicy.normalizedSelections(
                ["missing", "b", "b", "a"],
                options: options,
                allowsMultiple: true
            ),
            ["b", "a"]
        )
        XCTAssertEqual(
            OrderingAnswerPolicy.normalizedOrder(["b", "b", "missing"], items: options),
            ["b", "a"]
        )
        XCTAssertEqual(
            MatchingAnswerPolicy.normalizedPairs(
                ["a": "b", "missing": "b", "b": "missing"],
                items: options,
                targets: options
            ),
            ["a": "b"]
        )
    }

    func testEmptyLibraryBootsBundledAllFormatsSample() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountingSuiteStore(
            persistence: JSONAppPersistence(baseDirectory: directory)
        )

        await store.loadIfNeeded()

        XCTAssertEqual(store.loadPhase, .ready)
        XCTAssertEqual(store.questionCount, 35)
        XCTAssertEqual(store.packs.first?.sourceFileName, "ALL_FORMATS_SAMPLE.md")
        let kinds = Set(
            store.questionScreensByRoute.values
                .flatMap(\.parts)
                .map(\.kind)
        )
        XCTAssertEqual(kinds, Set(ResponseKind.allCases))
    }

    func testBundledSpreadsheetPracticeCanBeLoadedDirectly() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountingSuiteStore(
            persistence: JSONAppPersistence(baseDirectory: directory)
        )

        await store.loadIfNeeded()
        await store.importBundledSample(.spreadsheetPractice)

        XCTAssertEqual(store.loadPhase, .ready)
        XCTAssertEqual(store.questionCount, 37)
        XCTAssertEqual(
            Set(store.packs.map(\.sourceFileName)),
            ["ALL_FORMATS_SAMPLE.md", "SPREADSHEET_PRACTICE.md"]
        )
        XCTAssertNotNil(
            store.librarySections
                .flatMap(\.questions)
                .first { $0.id == "sheet-warranty" }
        )
        guard case let .succeeded(fileName, questionCount, warnings) = store.importPhase else {
            return XCTFail("Expected the bundled spreadsheet sample to import successfully")
        }
        XCTAssertEqual(fileName, "SPREADSHEET_PRACTICE.md")
        XCTAssertEqual(questionCount, 2)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testLibrarySearchAndFormatShellStatusFiltersCompose() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountingSuiteStore(
            persistence: JSONAppPersistence(baseDirectory: directory)
        )
        await store.loadIfNeeded()

        store.libraryFormatFilter = .ratioAnalysis
        XCTAssertEqual(visibleQuestionIDs(in: store), ["fmt-28-ratio"])

        store.libraryShellFilter = .standaloneCalculation
        store.librarySearchText = "current ratio"
        XCTAssertEqual(visibleQuestionIDs(in: store), ["fmt-28-ratio"])

        store.updateAnswer(
            StudentAnswer(scalar: "1.5"),
            questionID: "fmt-28-ratio",
            partID: "a"
        )
        store.libraryStatusFilter = .completed
        XCTAssertEqual(visibleQuestionIDs(in: store), ["fmt-28-ratio"])

        store.libraryStatusFilter = .notStarted
        XCTAssertTrue(store.visibleLibrarySections.isEmpty)

        store.clearLibraryFilters()
        XCTAssertEqual(store.visibleLibrarySections.flatMap(\.questions).count, 35)
    }

    func testLegacyImportSurfacesNonBlockingWarningDetails() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let markdownURL = directory.appending(path: "legacy.md")
        let markdown = """
        # Legacy prompt
        Explain why revenues normally carry credit balances.
        """
        try Data(markdown.utf8).write(to: markdownURL, options: .atomic)
        let store = AccountingSuiteStore(
            persistence: JSONAppPersistence(baseDirectory: directory.appending(path: "state"))
        )
        await store.loadIfNeeded()

        await store.importMarkdown(from: markdownURL)

        guard case let .succeeded(fileName, questionCount, warnings) = store.importPhase else {
            return XCTFail("Expected a successful import with warnings")
        }
        XCTAssertEqual(fileName, "legacy.md")
        XCTAssertEqual(questionCount, 1)
        XCTAssertTrue(
            warnings.contains {
                $0.message.localizedCaseInsensitiveContains("heuristically")
            }
        )
    }

    func testPairedLegacyChoicesReachDistinctOnePartAtATimeSteps() async throws {
        let markdown = """
        ### `core_demo_q4` — Demo
        **Question 4.1:** Which account normally has a debit balance?
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
        """
        let result = try QuestionMarkdownParser.parse(markdown, sourceName: "Paired fixture")
        let question = try XCTUnwrap(result.pack.questions.first)
        XCTAssertEqual(question.parts.map(\.id), ["choice-1", "choice-2"])

        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        let packID = UUID()
        let persistence = JSONAppPersistence(baseDirectory: directory)
        try await persistence.save(
            PersistedAppState(
                packs: [
                    ImportedQuestionPack(
                        id: packID,
                        sourceFileName: "paired.md",
                        pack: result.pack
                    )
                ]
            )
        )
        let store = AccountingSuiteStore(persistence: persistence)
        await store.loadIfNeeded()
        let screen = try XCTUnwrap(
            store.questionScreen(for: .question(packID: packID, questionID: question.id))
        )

        XCTAssertEqual(screen.parts.count, 2)
        let session = QuestionStudySession()
        XCTAssertEqual(screen.parts[session.currentPartIndex].id, "choice-1")
        session.move(to: 1)
        XCTAssertEqual(screen.parts[session.currentPartIndex].id, "choice-2")

        store.updateAnswer(
            StudentAnswer(selections: ["A"]),
            questionID: question.id,
            partID: "choice-1"
        )
        XCTAssertEqual(store.resumePartIndex(for: screen), 1)
        store.updateAnswer(
            StudentAnswer(selections: ["B"]),
            questionID: question.id,
            partID: "choice-2"
        )
        XCTAssertEqual(store.grade(questionID: question.id, partID: "choice-1")?.status, .correct)
        XCTAssertEqual(store.grade(questionID: question.id, partID: "choice-2")?.status, .correct)
    }

    func testDuplicateQuestionIDsAcrossPacksKeepAnswersAndGradesSeparate() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstURL = directory.appending(path: "first.md")
        let secondURL = directory.appending(path: "second.md")
        try Data(markdown(questionID: "same", answer: "1").utf8)
            .write(to: firstURL, options: .atomic)
        try Data(markdown(questionID: "same", answer: "2").utf8)
            .write(to: secondURL, options: .atomic)

        let store = AccountingSuiteStore(
            persistence: JSONAppPersistence(baseDirectory: directory.appending(path: "state"))
        )
        await store.loadIfNeeded()
        await store.importMarkdown(from: firstURL)
        await store.importMarkdown(from: secondURL)

        let firstID = try XCTUnwrap(
            store.librarySections
                .first(where: { $0.sourceFileName == "first.md" })?
                .questions.first?.id
        )
        let secondID = try XCTUnwrap(
            store.librarySections
                .first(where: { $0.sourceFileName == "second.md" })?
                .questions.first?.id
        )
        XCTAssertEqual(firstID, "same")
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertTrue(secondID.hasPrefix("same--pack-"))

        store.updateAnswer(StudentAnswer(scalar: "1"), questionID: firstID, partID: "a")
        store.updateAnswer(StudentAnswer(scalar: "2"), questionID: secondID, partID: "a")

        XCTAssertEqual(store.grade(questionID: firstID, partID: "a")?.status, .correct)
        XCTAssertEqual(store.grade(questionID: secondID, partID: "a")?.status, .correct)
        XCTAssertEqual(store.answer(questionID: firstID, partID: "a").scalar, "1")
        XCTAssertEqual(store.answer(questionID: secondID, partID: "a").scalar, "2")

        store.updateAnswer(StudentAnswer(scalar: "2"), questionID: firstID, partID: "a")
        XCTAssertEqual(store.grade(questionID: firstID, partID: "a")?.status, .incorrect)
        XCTAssertEqual(store.grade(questionID: secondID, partID: "a")?.status, .correct)
    }

    private func visibleQuestionIDs(in store: AccountingSuiteStore) -> [String] {
        store.visibleLibrarySections.flatMap(\.questions).map(\.id)
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AccountingQuestionSuiteTests", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func markdown(questionID: String, answer: String) -> String {
        """
        :::question id=\(questionID) shell=standalone_calculation variation=core formats=single_number
        # Duplicate ID regression
        ## Scenario
        Compute the requested amount.
        :::part id=a kind=number format=single_number points=1
        ### Prompt
        Enter the amount.
        ### Answer
        \(answer)
        ### Settings
        tolerance: 0
        :::endpart
        :::endquestion
        """
    }
}
