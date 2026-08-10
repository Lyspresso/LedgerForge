import AccountingQuestionKit
import Foundation
import Observation

struct AppAlert: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String

    init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

struct ImportNotice: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceName: String
    let warning: ImportWarning

    init(
        id: UUID = UUID(),
        sourceName: String,
        warning: ImportWarning
    ) {
        self.id = id
        self.sourceName = sourceName
        self.warning = warning
    }
}

struct QuestionPartKey: Hashable, Sendable {
    let questionID: String
    let partID: String
}

struct QuestionProgress: Equatable, Sendable {
    let answeredParts: Int
    let completedParts: Int
    let totalParts: Int
    let earnedPoints: Double
    let totalPoints: Double

    static let empty = QuestionProgress(
        answeredParts: 0,
        completedParts: 0,
        totalParts: 0,
        earnedPoints: 0,
        totalPoints: 0
    )

    var fractionAnswered: Double {
        guard totalParts > 0 else { return 0 }
        return Double(answeredParts) / Double(totalParts)
    }

    var isComplete: Bool {
        totalParts > 0 && completedParts == totalParts
    }
}

@MainActor
@Observable
final class AppStore {
    private(set) var questions: [AccountingQuestion] = []
    private(set) var visibleQuestions: [AccountingQuestion] = []
    private(set) var selectedQuestion: AccountingQuestion?
    private(set) var attempts: [AttemptRecord] = []
    private(set) var selectedFormats: Set<QuestionFormat> = []
    private(set) var gradeResults: [QuestionPartKey: GradeResult] = [:]
    private(set) var revealedParts: Set<QuestionPartKey> = []
    private(set) var lastImportWarnings: [ImportNotice] = []

    var selectedQuestionID: AccountingQuestion.ID? {
        didSet { recomputeSelectedQuestion() }
    }
    var activePartID: QuestionPart.ID?
    var searchText = "" {
        didSet {
            recomputeVisibleQuestions()
            ensureVisibleSelection()
        }
    }
    var isImporterPresented = false
    var isInspectorPresented = true
    var isImporting = false
    var alert: AppAlert?

    var isAlertPresented: Bool {
        get { alert != nil }
        set {
            if !newValue {
                alert = nil
            }
        }
    }

    var canCheckActivePart: Bool {
        guard let question = selectedQuestion,
              let part = activePart(in: question) else { return false }
        return canCheck(part: part, in: question.id)
    }

    var canRevealActivePart: Bool {
        guard let question = selectedQuestion else { return false }
        return activePart(in: question) != nil
    }

    var hasActiveFilters: Bool {
        !selectedFormats.isEmpty
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSelectPreviousQuestion: Bool {
        guard let selectedQuestionID,
              let index = visibleQuestions.firstIndex(where: {
                  $0.id == selectedQuestionID
              }) else { return false }
        return index > visibleQuestions.startIndex
    }

    var canSelectNextQuestion: Bool {
        guard let selectedQuestionID,
              let index = visibleQuestions.firstIndex(where: {
                  $0.id == selectedQuestionID
              }) else { return false }
        return index < visibleQuestions.index(before: visibleQuestions.endIndex)
    }

    @ObservationIgnored private let persistence: LibraryPersistence
    @ObservationIgnored private let importService: QuestionImportService
    @ObservationIgnored private var hasRestored = false
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var saveGeneration = 0
    @ObservationIgnored private var savedGeneration = 0
    @ObservationIgnored private var attemptIndexByQuestionID: [String: Int] = [:]

    init(
        persistence: LibraryPersistence = LibraryPersistence(),
        importService: QuestionImportService = QuestionImportService()
    ) {
        self.persistence = persistence
        self.importService = importService
    }

    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true

        do {
            let snapshot = try await persistence.load()
            questions = Self.deduplicatedQuestions(snapshot.questions)
            attempts = Self.deduplicatedAttempts(snapshot.attempts)
            rebuildAttemptIndex()
            rebuildGradesForStoredAnswers()
            refreshDerivedState(selectFirstWhenNeeded: true)
        } catch {
            hasRestored = false
            alert = AppAlert(
                title: String(localized: "Couldn’t Open Library"),
                message: error.localizedDescription
            )
        }
    }

    func presentImporter() {
        guard !isImporting else { return }
        isImporterPresented = true
    }

    func receiveImportSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            Task {
                await importFiles(at: urls)
            }
        case let .failure(error):
            alert = AppAlert(
                title: String(localized: "Import Failed"),
                message: error.localizedDescription
            )
        }
    }

    func loadCompleteFormatSample() {
        loadBundledSample(named: "ALL_FORMATS_SAMPLE")
    }

    func loadSpreadsheetPracticeSample() {
        loadBundledSample(named: "SPREADSHEET_PRACTICE")
    }

    private func loadBundledSample(named resourceName: String) {
        guard !isImporting else { return }
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "md"
        ) else {
            alert = AppAlert(
                title: String(localized: "Sample Unavailable"),
                message: String(localized: "The selected sample is missing from this app build.")
            )
            return
        }

        Task {
            await importFiles(at: [url])
        }
    }

    func importFiles(at urls: [URL]) async {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let results = try await importService.importFiles(at: urls)
            lastImportWarnings = results.flatMap { result in
                result.warnings.map { warning in
                    ImportNotice(
                        sourceName: result.pack.title,
                        warning: warning
                    )
                }
            }
            merge(results: results)
            try await saveSnapshot()

            let importedCount = results.reduce(0) { count, result in
                count + result.pack.questions.count
            }
            let warningCount = lastImportWarnings.count
            let message = warningCount == 0
                ? String(localized: "Imported \(importedCount) questions.")
                : String(
                    localized: "Imported \(importedCount) questions. \(warningCount) import warnings are available in the inspector."
                )
            alert = AppAlert(
                title: String(localized: "Import Complete"),
                message: message
            )
        } catch {
            alert = AppAlert(
                title: String(localized: "Import Failed"),
                message: error.localizedDescription
            )
        }
    }

    subscript(answerFor questionID: String, partID partID: String) -> StudentAnswer {
        get { answer(for: questionID, partID: partID) }
        set {
            guard newValue != answer(for: questionID, partID: partID) else { return }
            updateAttempt(questionID: questionID) { attempt in
                attempt.answers[partID] = newValue
                attempt.selfReviews[partID] = false
            }
            let key = QuestionPartKey(questionID: questionID, partID: partID)
            gradeResults[key] = nil
            scheduleSave()
        }
    }

    subscript(selfReviewFor questionID: String, partID partID: String) -> Bool {
        get {
            attempt(for: questionID)?.selfReviews[partID] ?? false
        }
        set {
            guard newValue != self[selfReviewFor: questionID, partID: partID] else {
                return
            }
            if newValue,
               !canCompleteSelfReview(questionID: questionID, partID: partID) {
                return
            }
            updateAttempt(questionID: questionID) { attempt in
                attempt.selfReviews[partID] = newValue
            }
            scheduleSave()
        }
    }

    func answer(for questionID: String, partID: String) -> StudentAnswer {
        attempt(for: questionID)?.answers[partID] ?? StudentAnswer()
    }

    func gradeResult(for questionID: String, partID: String) -> GradeResult? {
        gradeResults[QuestionPartKey(questionID: questionID, partID: partID)]
    }

    func isRevealed(questionID: String, partID: String) -> Bool {
        revealedParts.contains(
            QuestionPartKey(questionID: questionID, partID: partID)
        )
    }

    func canCompleteSelfReview(questionID: String, partID: String) -> Bool {
        guard let part = questions
            .first(where: { $0.id == questionID })?
            .parts.first(where: { $0.id == partID }) else {
            return false
        }
        let answer = answer(for: questionID, partID: partID)
        return selfReviewRequirementsMet(answer, for: part)
    }

    private func selfReviewRequirementsMet(
        _ answer: StudentAnswer,
        for part: QuestionPart
    ) -> Bool {
        switch part.kind {
        case .trueFalse:
            let decision = answer.scalar.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if decision.localizedCaseInsensitiveCompare("False") == .orderedSame {
                return !answer.notes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
            return true
        case .noEntry:
            return !answer.notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        default:
            return true
        }
    }

    func canCheck(part: QuestionPart, in questionID: String) -> Bool {
        let answer = answer(for: questionID, partID: part.id)
        return isAnswerReady(answer, for: part)
    }

    private func isAnswerReady(
        _ answer: StudentAnswer,
        for part: QuestionPart
    ) -> Bool {
        switch part.kind {
        case .singleChoice, .multipleChoice:
            return !answer.selections.isEmpty
        case .number, .formula, .shortText, .longText, .trueFalse, .noEntry:
            return !answer.scalar.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        case .matching:
            return answer.pairs.values.contains(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        case .journal, .table, .ordering:
            return !answer.isBlank
        }
    }

    func activatePart(_ partID: String) {
        activePartID = partID
    }

    func check(part: QuestionPart, in questionID: String) {
        activePartID = part.id
        guard canCheck(part: part, in: questionID) else { return }
        let key = QuestionPartKey(questionID: questionID, partID: part.id)
        let result = grade(
            answer(for: questionID, partID: part.id),
            for: part
        )
        gradeResults[key] = result
        if result.status == .needsSelfReview {
            revealedParts.insert(key)
        }
    }

    func checkActivePart() {
        guard let question = selectedQuestion,
              let part = activePart(in: question) else { return }
        check(part: part, in: question.id)
    }

    func toggleReveal(partID: String, in questionID: String) {
        activePartID = partID
        let key = QuestionPartKey(questionID: questionID, partID: partID)
        if revealedParts.contains(key) {
            revealedParts.remove(key)
        } else {
            revealedParts.insert(key)
        }
    }

    func toggleActiveReveal() {
        guard let question = selectedQuestion,
              let part = activePart(in: question) else { return }
        toggleReveal(partID: part.id, in: question.id)
    }

    func toggleFormat(_ format: QuestionFormat) {
        if selectedFormats.contains(format) {
            selectedFormats.remove(format)
        } else {
            selectedFormats.insert(format)
        }
        recomputeVisibleQuestions()
        ensureVisibleSelection()
    }

    func clearFormatFilters() {
        selectedFormats.removeAll()
        recomputeVisibleQuestions()
        ensureVisibleSelection()
    }

    func clearAllFilters() {
        searchText = ""
        selectedFormats.removeAll()
        recomputeVisibleQuestions()
        ensureVisibleSelection()
    }

    func selectAdjacentQuestion(offset: Int) {
        guard !visibleQuestions.isEmpty else { return }
        let currentIndex = selectedQuestionID.flatMap { selectedID in
            visibleQuestions.firstIndex(where: { $0.id == selectedID })
        } ?? 0
        let destination = min(
            max(currentIndex + offset, visibleQuestions.startIndex),
            visibleQuestions.index(before: visibleQuestions.endIndex)
        )
        selectedQuestionID = visibleQuestions[destination].id
    }

    func progress(for question: AccountingQuestion) -> QuestionProgress {
        guard !question.parts.isEmpty else { return .empty }
        let attempt = attempt(for: question.id)
        var answeredParts = 0
        var completedParts = 0
        var earnedPoints = 0.0

        for part in question.parts {
            let answer = attempt?.answers[part.id] ?? StudentAnswer()
            guard isAnswerReady(answer, for: part) else { continue }
            answeredParts += 1

            let key = QuestionPartKey(questionID: question.id, partID: part.id)
            let result = gradeResults[key] ?? grade(answer, for: part)
            let isReviewed = attempt?.selfReviews[part.id] ?? false
            let isComplete = result.status == .correct
                || (result.status == .needsSelfReview
                    && isReviewed
                    && selfReviewRequirementsMet(answer, for: part))
            if isComplete {
                completedParts += 1
                earnedPoints += part.points
            }
        }

        return QuestionProgress(
            answeredParts: answeredParts,
            completedParts: completedParts,
            totalParts: question.parts.count,
            earnedPoints: earnedPoints,
            totalPoints: question.parts.reduce(0) { $0 + $1.points }
        )
    }

    func dismissAlert() {
        alert = nil
    }

    func flushPendingSave() async {
        guard savedGeneration < saveGeneration else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        do {
            try await persistence.save(
                LibrarySnapshot(questions: questions, attempts: attempts)
            )
            savedGeneration = saveGeneration
        } catch {
            alert = AppAlert(
                title: String(localized: "Couldn’t Save Library"),
                message: error.localizedDescription
            )
        }
    }

    private func activePart(in question: AccountingQuestion) -> QuestionPart? {
        if let activePartID,
           let active = question.parts.first(where: { $0.id == activePartID }) {
            return active
        }
        return question.parts.first
    }

    private func updateAttempt(
        questionID: String,
        update: (inout AttemptRecord) -> Void
    ) {
        if let index = attemptIndexByQuestionID[questionID],
           attempts.indices.contains(index) {
            update(&attempts[index])
            attempts[index].updatedAt = .now
        } else {
            var attempt = AttemptRecord(questionID: questionID)
            update(&attempt)
            attempts.append(attempt)
            attemptIndexByQuestionID[questionID] = attempts.index(before: attempts.endIndex)
        }
    }

    private func attempt(for questionID: String) -> AttemptRecord? {
        guard let index = attemptIndexByQuestionID[questionID],
              attempts.indices.contains(index) else { return nil }
        return attempts[index]
    }

    private func rebuildAttemptIndex() {
        attemptIndexByQuestionID = Dictionary(
            uniqueKeysWithValues: attempts.enumerated().map { index, attempt in
                (attempt.questionID, index)
            }
        )
    }

    private func merge(results: [ImportResult]) {
        let importedQuestions = results.flatMap(\.pack.questions)
        var questionsByID: [String: AccountingQuestion] = [:]
        var orderedIDs: [String] = []
        for question in questions {
            if questionsByID[question.id] == nil {
                orderedIDs.append(question.id)
            }
            questionsByID[question.id] = question
        }

        for question in importedQuestions {
            if questionsByID[question.id] == nil {
                orderedIDs.append(question.id)
            }
            questionsByID[question.id] = question
        }

        questions = orderedIDs.compactMap { questionsByID[$0] }
        rebuildGradesForStoredAnswers()
        refreshDerivedState(selectFirstWhenNeeded: true)
    }

    private func refreshDerivedState(selectFirstWhenNeeded: Bool) {
        recomputeVisibleQuestions()

        if selectFirstWhenNeeded,
           selectedQuestionID == nil
            || !visibleQuestions.contains(where: { $0.id == selectedQuestionID }) {
            selectedQuestionID = visibleQuestions.first?.id
        } else {
            recomputeSelectedQuestion()
        }
    }

    private func recomputeVisibleQuestions() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleQuestions = questions.filter { question in
            let matchesSearch = query.isEmpty
                || question.title.localizedStandardContains(query)
                || QuestionIdentity.originalID(from: question.id)
                    .localizedStandardContains(query)
                || question.sourceName.localizedStandardContains(query)
                || question.tags.contains(where: {
                    $0.localizedStandardContains(query)
                })
            let matchesFormats = selectedFormats.isEmpty
                || !Set(question.formats).isDisjoint(with: selectedFormats)
            return matchesSearch && matchesFormats
        }
    }

    private func ensureVisibleSelection() {
        guard !visibleQuestions.contains(where: { $0.id == selectedQuestionID }) else {
            return
        }
        selectedQuestionID = visibleQuestions.first?.id
    }

    private func recomputeSelectedQuestion() {
        guard let selectedQuestionID else {
            selectedQuestion = nil
            activePartID = nil
            return
        }
        selectedQuestion = questions.first(where: { $0.id == selectedQuestionID })
        guard let selectedQuestion else {
            activePartID = nil
            return
        }
        if activePartID == nil
            || !selectedQuestion.parts.contains(where: { $0.id == activePartID }) {
            activePartID = selectedQuestion.parts.first?.id
        }
    }

    private func rebuildGradesForStoredAnswers() {
        var rebuilt: [QuestionPartKey: GradeResult] = [:]
        for question in questions {
            guard let attempt = attempt(for: question.id) else { continue }
            for part in question.parts {
                guard let answer = attempt.answers[part.id],
                      isAnswerReady(answer, for: part) else {
                    continue
                }
                rebuilt[QuestionPartKey(
                    questionID: question.id,
                    partID: part.id
                )] = grade(answer, for: part)
            }
        }
        gradeResults = rebuilt
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = LibrarySnapshot(
            questions: questions,
            attempts: attempts
        )
        let persistence = persistence
        pendingSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                try await persistence.save(snapshot)
                savedGeneration = max(savedGeneration, generation)
            } catch is CancellationError {
                return
            } catch {
                alert = AppAlert(
                    title: String(localized: "Couldn’t Save Answer"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func saveSnapshot() async throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        try await persistence.save(
            LibrarySnapshot(questions: questions, attempts: attempts)
        )
        savedGeneration = saveGeneration
    }

    private func grade(_ answer: StudentAnswer, for part: QuestionPart) -> GradeResult {
        let result = AnswerGrader.grade(answer, for: part)
        let expectedDecision = part.expected.scalar.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if part.kind == .trueFalse,
           result.status == .correct,
           expectedDecision.localizedCaseInsensitiveCompare("False") == .orderedSame,
           !part.rubricMarkdown.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            return GradeResult(
                status: .needsSelfReview,
                feedback: String(
                    localized: "The decision is correct. Compare your correction with the model rubric."
                )
            )
        }
        return result
    }

    private static func deduplicatedAttempts(
        _ attempts: [AttemptRecord]
    ) -> [AttemptRecord] {
        var latestByQuestionID: [String: AttemptRecord] = [:]
        var orderedIDs: [String] = []
        for attempt in attempts {
            if latestByQuestionID[attempt.questionID] == nil {
                orderedIDs.append(attempt.questionID)
            }
            if let existing = latestByQuestionID[attempt.questionID],
               existing.updatedAt > attempt.updatedAt {
                continue
            }
            latestByQuestionID[attempt.questionID] = attempt
        }
        return orderedIDs.compactMap { latestByQuestionID[$0] }
    }

    private static func deduplicatedQuestions(
        _ questions: [AccountingQuestion]
    ) -> [AccountingQuestion] {
        var latestByID: [String: AccountingQuestion] = [:]
        var orderedIDs: [String] = []
        for question in questions {
            if latestByID[question.id] == nil {
                orderedIDs.append(question.id)
            }
            latestByID[question.id] = question
        }
        return orderedIDs.compactMap { latestByID[$0] }
    }
}
