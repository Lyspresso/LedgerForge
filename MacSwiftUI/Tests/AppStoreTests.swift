import AccountingQuestionKit
import Foundation
import XCTest
@testable import AccountingQuestionStudio

final class AppStoreTests: XCTestCase {
    @MainActor
    func testCompleteSamplerBootsAndPersistsAllFormats() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = LibraryPersistence(
            fileURL: directory.appending(path: "library.json")
        )
        let store = AppStore(persistence: persistence)

        await store.importFiles(at: [completeSamplerURL])

        XCTAssertNil(store.alert?.title == "Import Failed" ? store.alert : nil)
        XCTAssertEqual(store.questions.count, 35)
        XCTAssertEqual(
            Set(store.questions.flatMap(\.formats)),
            Set(QuestionFormat.allCases)
        )
        XCTAssertEqual(
            Set(store.questions.flatMap(\.parts).map(\.kind)),
            Set(ResponseKind.allCases)
        )
        XCTAssertNotNil(store.selectedQuestion)
        XCTAssertTrue(store.questions.allSatisfy {
            QuestionIdentity.isCanonical($0.id)
        })

        let snapshot = try await persistence.load()
        XCTAssertEqual(snapshot.questions.count, 35)
    }

    @MainActor
    func testSpreadsheetPracticeSamplerImports() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(
            persistence: LibraryPersistence(
                fileURL: directory.appending(path: "library.json")
            )
        )

        await store.importFiles(at: [spreadsheetPracticeURL])

        XCTAssertNil(store.alert?.title == "Import Failed" ? store.alert : nil)
        XCTAssertFalse(store.questions.isEmpty)
        XCTAssertTrue(store.questions.contains { question in
            question.parts.contains { $0.kind == .table || $0.kind == .formula }
        })
    }

    @MainActor
    func testOverlappingIDsFromDifferentSourcesKeepIndependentAttempts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstDirectory = directory.appending(path: "first", directoryHint: .isDirectory)
        let secondDirectory = directory.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstURL = firstDirectory.appending(path: "bank.md")
        let secondURL = secondDirectory.appending(path: "bank.md")
        try structuredNumberFixture(title: "First source", answer: "10")
            .write(to: firstURL, atomically: true, encoding: .utf8)
        try structuredNumberFixture(title: "Second source", answer: "20")
            .write(to: secondURL, atomically: true, encoding: .utf8)

        let persistence = LibraryPersistence(
            fileURL: directory.appending(path: "library.json")
        )
        let store = AppStore(persistence: persistence)
        await store.importFiles(at: [firstURL, secondURL])

        XCTAssertEqual(store.questions.count, 2)
        let first = try XCTUnwrap(store.questions.first(where: {
            $0.title == "First source"
        }))
        let second = try XCTUnwrap(store.questions.first(where: {
            $0.title == "Second source"
        }))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(QuestionIdentity.originalID(from: first.id), "overlap")
        XCTAssertEqual(QuestionIdentity.originalID(from: second.id), "overlap")

        store[answerFor: first.id, partID: "a"] = StudentAnswer(scalar: "10")
        store[answerFor: second.id, partID: "a"] = StudentAnswer(scalar: "20")
        store.check(part: try XCTUnwrap(first.parts.first), in: first.id)
        store.check(part: try XCTUnwrap(second.parts.first), in: second.id)

        XCTAssertEqual(store.gradeResult(for: first.id, partID: "a")?.status, .correct)
        XCTAssertEqual(store.gradeResult(for: second.id, partID: "a")?.status, .correct)
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertEqual(store.answer(for: first.id, partID: "a").scalar, "10")
        XCTAssertEqual(store.answer(for: second.id, partID: "a").scalar, "20")

        await store.flushPendingSave()
        let restored = AppStore(persistence: persistence)
        await restored.restore()
        XCTAssertEqual(restored.questions.count, 2)
        XCTAssertEqual(restored.answer(for: first.id, partID: "a").scalar, "10")
        XCTAssertEqual(restored.answer(for: second.id, partID: "a").scalar, "20")

        await store.importFiles(at: [firstURL])
        XCTAssertEqual(store.questions.count, 2, "Re-importing one source updates it in place.")
        XCTAssertEqual(store.answer(for: first.id, partID: "a").scalar, "10")
    }

    func testCanonicalIdentityDisambiguatesRepeatedIDsWithinOneSource() {
        let sourceURL = URL(fileURLWithPath: "/tmp/repeated-legacy-bank.md")
        let first = QuestionIdentity.canonicalID(
            originalID: "repeated",
            sourceURL: sourceURL
        )
        let second = QuestionIdentity.canonicalID(
            originalID: "repeated",
            sourceURL: sourceURL,
            occurrence: 1
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(QuestionIdentity.originalID(from: first), "repeated")
        XCTAssertEqual(QuestionIdentity.originalID(from: second), "repeated")
    }

    @MainActor
    func testPairedLegacyQuestionSupportsTwoIndependentActiveParts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appending(path: "paired.md")
        try pairedLegacyFixture.write(to: fixtureURL, atomically: true, encoding: .utf8)
        let store = AppStore(
            persistence: LibraryPersistence(
                fileURL: directory.appending(path: "library.json")
            )
        )

        await store.importFiles(at: [fixtureURL])

        let question = try XCTUnwrap(store.questions.first)
        XCTAssertEqual(question.parts.map(\.id), ["choice-1", "choice-2"])
        XCTAssertEqual(store.activePartID, "choice-1")
        store[answerFor: question.id, partID: "choice-1"] = StudentAnswer(
            selections: ["A"]
        )
        store.activatePart("choice-2")
        store[answerFor: question.id, partID: "choice-2"] = StudentAnswer(
            selections: ["B"]
        )
        store.checkActivePart()
        store.activatePart("choice-1")
        store.checkActivePart()

        XCTAssertEqual(store.answer(for: question.id, partID: "choice-1").selections, ["A"])
        XCTAssertEqual(store.answer(for: question.id, partID: "choice-2").selections, ["B"])
        XCTAssertEqual(store.gradeResult(for: question.id, partID: "choice-1")?.status, .correct)
        XCTAssertEqual(store.gradeResult(for: question.id, partID: "choice-2")?.status, .correct)
        XCTAssertEqual(store.progress(for: question).completedParts, 2)
    }

    @MainActor
    func testAnswerAutosaveRestoresWithoutManualFlush() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appending(path: "autosave.md")
        try structuredNumberFixture(title: "Autosave", answer: "42")
            .write(to: fixtureURL, atomically: true, encoding: .utf8)
        let persistence = LibraryPersistence(
            fileURL: directory.appending(path: "library.json")
        )
        let store = AppStore(persistence: persistence)
        await store.importFiles(at: [fixtureURL])
        let question = try XCTUnwrap(store.questions.first)

        store[answerFor: question.id, partID: "a"] = StudentAnswer(scalar: "42")
        try await Task.sleep(for: .milliseconds(700))

        let restored = AppStore(persistence: persistence)
        await restored.restore()
        XCTAssertEqual(restored.answer(for: question.id, partID: "a").scalar, "42")
        XCTAssertEqual(restored.gradeResult(for: question.id, partID: "a")?.status, .correct)
    }

    @MainActor
    func testTrueFalseCorrectionRequiresWrittenSelfReviewSupport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(
            persistence: LibraryPersistence(
                fileURL: directory.appending(path: "library.json")
            )
        )
        await store.importFiles(at: [completeSamplerURL])
        let question = try XCTUnwrap(store.questions.first(where: {
            QuestionIdentity.originalID(from: $0.id) == "fmt-31-true-false"
        }))
        let part = try XCTUnwrap(question.parts.first)

        store[answerFor: question.id, partID: part.id] = StudentAnswer(
            scalar: "False"
        )
        store.check(part: part, in: question.id)
        XCTAssertEqual(
            store.gradeResult(for: question.id, partID: part.id)?.status,
            .needsSelfReview
        )
        XCTAssertTrue(store.isRevealed(questionID: question.id, partID: part.id))
        XCTAssertFalse(store.canCompleteSelfReview(questionID: question.id, partID: part.id))
        store[selfReviewFor: question.id, partID: part.id] = true
        XCTAssertFalse(store[selfReviewFor: question.id, partID: part.id])

        store[answerFor: question.id, partID: part.id] = StudentAnswer(
            scalar: "False",
            notes: "A trial balance only tests debit-credit equality."
        )
        store.check(part: part, in: question.id)
        store[selfReviewFor: question.id, partID: part.id] = true
        XCTAssertTrue(store[selfReviewFor: question.id, partID: part.id])
        XCTAssertEqual(store.progress(for: question).completedParts, 1)
    }

    func testMalformedStructuredPackIsRejectedWithContext() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appending(path: "invalid.md")
        let markdown = """
        :::question id=bad shell=multipart formats=multi_period_schedule
        # Invalid
        :::part id=a kind=table format=multi_period_schedule
        ### Prompt
        Complete the table.
        :::endpart
        :::endquestion
        """
        try markdown.write(to: fixtureURL, atomically: true, encoding: .utf8)

        do {
            _ = try await QuestionImportService().importFiles(at: [fixtureURL])
            XCTFail("Expected structured validation to reject the pack.")
        } catch let error as QuestionImportServiceError {
            guard case let .invalidStructuredDocument(fileName, issues) = error else {
                return XCTFail("Unexpected import error: \(error)")
            }
            XCTAssertEqual(fileName, "invalid.md")
            XCTAssertTrue(issues.contains(where: { $0.contains("no columns") }))
        }
    }

    @MainActor
    func testSpreadsheetFormulaGradesAndPersistsRawExpression() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appending(path: "formula-table.md")
        try structuredFormulaTableFixture.write(
            to: fixtureURL,
            atomically: true,
            encoding: .utf8
        )
        let persistence = LibraryPersistence(
            fileURL: directory.appending(path: "library.json")
        )
        let store = AppStore(persistence: persistence)
        await store.importFiles(at: [fixtureURL])
        let question = try XCTUnwrap(store.questions.first)
        let part = try XCTUnwrap(question.parts.first)
        let rawRows = [
            ["Beginning", "10"],
            ["Addition", "20"],
            ["Ending", "=SUM(B1:B2)"]
        ]

        store[answerFor: question.id, partID: part.id] = StudentAnswer(
            rows: rawRows
        )
        store.check(part: part, in: question.id)

        XCTAssertEqual(
            store.gradeResult(for: question.id, partID: part.id)?.status,
            .correct
        )
        XCTAssertEqual(
            store.answer(for: question.id, partID: part.id).rows,
            rawRows,
            "Grading must not replace the student's raw formula."
        )
        XCTAssertEqual(
            SpreadsheetEngine.evaluate(rows: rawRows)[row: 2, column: 1],
            .number(30)
        )
        XCTAssertEqual(
            SpreadsheetEngine.evaluateFormula("=1/0").error,
            .divideByZero
        )

        await store.flushPendingSave()
        let restored = AppStore(persistence: persistence)
        await restored.restore()
        XCTAssertEqual(
            restored.answer(for: question.id, partID: part.id).rows,
            rawRows
        )
        XCTAssertEqual(
            restored.gradeResult(for: question.id, partID: part.id)?.status,
            .correct
        )
    }

    func testSpreadsheetPasteExpandsRowsPreservesFormulasAndClipsColumns() {
        var rows = [["Existing", "1", "keep"]]

        let lastCell = SpreadsheetGridOperations.paste(
            "Cash\t10\textra\tclipped\r\nTotal\t=SUM(B1:B1)",
            startingAt: SpreadsheetCellCoordinate(row: 1, column: 0),
            columnCount: 3,
            into: &rows
        )

        XCTAssertEqual(
            rows,
            [
                ["Existing", "1", "keep"],
                ["Cash", "10", "extra"],
                ["Total", "=SUM(B1:B1)", ""]
            ]
        )
        XCTAssertEqual(lastCell, SpreadsheetCellCoordinate(row: 2, column: 1))
        XCTAssertEqual(
            SpreadsheetGridOperations.parsedCells(from: "A\t\n\n"),
            [["A", ""]]
        )
    }

    func testStandaloneFormulaPreviewEvaluatesFinancialFormulaAndError() throws {
        let presentValue = try XCTUnwrap(
            StandaloneFormulaPreview.value(
                for: "=PV(8%,5,0,10000)"
            )?.number
        )

        XCTAssertEqual(
            presentValue,
            -10_000 / pow(1.08, 5),
            accuracy: 0.000000001
        )
        XCTAssertEqual(
            StandaloneFormulaPreview.value(for: "=1/0")?.error,
            .divideByZero
        )
        XCTAssertNil(
            StandaloneFormulaPreview.value(for: "BI + purchases - EI"),
            "Non-spreadsheet formula text should not show a misleading parser error."
        )
    }

    func testExternalAccountingBanksWhenProvided() throws {
        guard let completeURL = externalFixtureURL(
            environmentKey: "ACCOUNT343_COMPLETE_PATH",
            fileName: "ACCOUNT343_COMPLETE.md"
        ), let needsHumanURL = externalFixtureURL(
            environmentKey: "ACCOUNT343_NEEDS_HUMAN_PATH",
            fileName: "ACCOUNT343_NEEDS_HUMAN.md"
        ) else {
            throw XCTSkip(
                "Set ACCOUNT343_FIXTURE_DIR or both ACCOUNT343_*_PATH values to run the read-only full-bank validator."
            )
        }

        try assertBank(
            at: completeURL,
            questionCount: 3_088,
            singleChoicePartCount: 754,
            longTextPartCount: 2_474
        )
        try assertBank(
            at: needsHumanURL,
            questionCount: 78,
            singleChoicePartCount: 9,
            longTextPartCount: 71
        )
    }

    private var completeSamplerURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../Samples/ALL_FORMATS_SAMPLE.md")
            .standardizedFileURL
    }

    private var spreadsheetPracticeURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../Samples/SPREADSHEET_PRACTICE.md")
            .standardizedFileURL
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AccountingQuestionStudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func structuredNumberFixture(title: String, answer: String) -> String {
        """
        :::question id=overlap shell=standalone_calculation formats=single_number
        # \(title)
        :::part id=a kind=number format=single_number
        ### Prompt
        Enter the source-specific amount.
        ### Answer
        \(answer)
        :::endpart
        :::endquestion
        """
    }

    private var pairedLegacyFixture: String {
        """
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
    }

    private var structuredFormulaTableFixture: String {
        """
        :::question id=formula-table shell=multipart formats=rollforward
        # Formula schedule
        :::part id=a kind=table format=rollforward
        ### Prompt
        Complete the rollforward using a spreadsheet formula where helpful.
        ### Columns
        Item | Amount
        ### Answer
        | Item | Amount |
        |---|---:|
        | Beginning | 10 |
        | Addition | 20 |
        | Ending | 30 |
        :::endpart
        :::endquestion
        """
    }

    private func externalFixtureURL(
        environmentKey: String,
        fileName: String
    ) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment[environmentKey], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let directory = environment["ACCOUNT343_FIXTURE_DIR"],
           !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: fileName)
        return FileManager.default.fileExists(atPath: downloadsURL.path)
            ? downloadsURL
            : nil
    }

    private func assertBank(
        at url: URL,
        questionCount: Int,
        singleChoicePartCount: Int,
        longTextPartCount: Int
    ) throws {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let pack = try QuestionMarkdownParser.parse(
            markdown,
            sourceName: url.lastPathComponent
        ).pack
        let parts = pack.questions.flatMap(\.parts)
        XCTAssertEqual(pack.questions.count, questionCount, url.lastPathComponent)
        XCTAssertEqual(
            parts.count(where: { $0.kind == .singleChoice }),
            singleChoicePartCount,
            url.lastPathComponent
        )
        XCTAssertEqual(
            parts.count(where: { $0.kind == .longText }),
            longTextPartCount,
            url.lastPathComponent
        )
    }
}
