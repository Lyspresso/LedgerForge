import AccountingQuestionKit
import XCTest
@testable import AccountingQuestionSuite

@MainActor
final class PersistenceAndImportTests: XCTestCase {
    func testJSONPersistenceRoundTripsPacksAndAttempts() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }

        let question = sampleQuestion()
        let pack = ImportedQuestionPack(
            sourceFileName: "sample.md",
            pack: QuestionPack(title: "Sample", questions: [question])
        )
        let answer = StudentAnswer(scalar: "10000")
        let attempt = AttemptRecord(
            questionID: question.id,
            answers: ["a": answer]
        )
        let state = PersistedAppState(packs: [pack], attempts: [attempt])
        let persistence = JSONAppPersistence(baseDirectory: directory)

        try await persistence.save(state)
        let loaded = try await persistence.load()
        let storageURL = try await persistence.storageURL()

        XCTAssertEqual(loaded, state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testStoreImportsMarkdownAndRestoresAttemptState() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let markdownURL = directory.appending(path: "questions.md")
        try Data(sampleMarkdown.utf8).write(to: markdownURL, options: .atomic)

        let persistence = JSONAppPersistence(baseDirectory: directory.appending(path: "state"))
        let store = AccountingSuiteStore(persistence: persistence)
        await store.loadIfNeeded()
        await store.importMarkdown(from: markdownURL)

        XCTAssertTrue(
            store.librarySections.flatMap(\.questions).contains { $0.id == "cash-001" }
        )

        store.updateAnswer(
            StudentAnswer(scalar: "10000"),
            questionID: "cash-001",
            partID: "a"
        )
        await store.flushPersistence()

        let restoredStore = AccountingSuiteStore(persistence: persistence)
        await restoredStore.loadIfNeeded()

        XCTAssertGreaterThanOrEqual(restoredStore.questionCount, 1)
        XCTAssertEqual(restoredStore.answer(questionID: "cash-001", partID: "a").scalar, "10000")
        XCTAssertEqual(restoredStore.attemptSummaries.first?.answeredPartCount, 1)
    }

    func testLoadedPackAndQuestionCollisionsMigrateWithoutSharingAnswers() async throws {
        let directory = temporaryDirectory(named: #function)
        defer { try? FileManager.default.removeItem(at: directory) }
        let duplicatePackID = UUID()
        let question = sampleQuestion()
        let state = PersistedAppState(
            packs: [
                ImportedQuestionPack(
                    id: duplicatePackID,
                    sourceFileName: "first.md",
                    pack: QuestionPack(title: "First", questions: [question])
                ),
                ImportedQuestionPack(
                    id: duplicatePackID,
                    sourceFileName: "second.md",
                    pack: QuestionPack(title: "Second", questions: [question])
                )
            ],
            attempts: [
                AttemptRecord(
                    questionID: question.id,
                    answers: ["a": StudentAnswer(scalar: "10000")]
                )
            ]
        )
        let persistence = JSONAppPersistence(baseDirectory: directory)
        try await persistence.save(state)

        let store = AccountingSuiteStore(persistence: persistence)
        await store.loadIfNeeded()

        let packIDs = store.packs.map(\.id)
        let questionIDs = store.librarySections.flatMap(\.questions).map(\.id)
        XCTAssertEqual(Set(packIDs).count, 2)
        XCTAssertEqual(Set(questionIDs).count, 2)
        XCTAssertEqual(store.answer(questionID: "cash-001", partID: "a").scalar, "10000")
        let migratedID = try XCTUnwrap(questionIDs.first { $0 != "cash-001" })
        XCTAssertTrue(migratedID.hasPrefix("cash-001--pack-"))
        XCTAssertTrue(store.answer(questionID: migratedID, partID: "a").isBlank)

        let persisted = try await persistence.load()
        XCTAssertEqual(Set(persisted.packs.map(\.id)).count, 2)
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AccountingQuestionSuiteTests", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func sampleQuestion() -> AccountingQuestion {
        AccountingQuestion(
            id: "cash-001",
            title: "Owner investment",
            shell: .multipart,
            formats: [.singleNumber],
            scenarioMarkdown: "The owner invests $10,000.",
            parts: [
                QuestionPart(
                    id: "a",
                    kind: .number,
                    format: .singleNumber,
                    promptMarkdown: "Compute the equity increase.",
                    expected: ExpectedAnswer(scalar: "10000")
                )
            ]
        )
    }

    private var sampleMarkdown: String {
        """
        :::question id=cash-001 shell=multipart variation=core formats=single_number
        # Owner investment
        ## Scenario
        The owner invests **$10,000** cash.

        :::part id=a kind=number format=single_number points=1
        ### Prompt
        Compute the equity increase.
        ### Answer
        10000
        ### Settings
        tolerance: 0
        :::endpart
        :::endquestion
        """
    }
}
