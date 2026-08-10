import AccountingQuestionKit
import Foundation
import Observation

@MainActor
@Observable
final class AccountingSuiteStore {
    private(set) var loadPhase: AppLoadPhase = .idle
    private(set) var importPhase: MarkdownImportPhase = .idle
    private(set) var saveFailureMessage: String?

    private(set) var packs: [ImportedQuestionPack] = []
    private(set) var attemptsByQuestionID: [String: AttemptRecord] = [:]
    private(set) var librarySections: [LibrarySectionModel] = []
    private(set) var visibleLibrarySections: [LibrarySectionModel] = []
    private(set) var questionScreensByRoute: [AppRoute: QuestionScreenModel] = [:]
    private(set) var attemptSummaries: [AttemptSummary] = []

    var librarySearchText = "" {
        didSet { rebuildVisibleLibrary() }
    }
    var libraryFormatFilter: QuestionFormat? {
        didSet { rebuildVisibleLibrary() }
    }
    var libraryShellFilter: QuestionShell? {
        didSet { rebuildVisibleLibrary() }
    }
    var libraryStatusFilter: LibraryStudyStatus? {
        didSet { rebuildVisibleLibrary() }
    }

    @ObservationIgnored private let persistence: JSONAppPersistence
    @ObservationIgnored private let importer: MarkdownDocumentImporter
    @ObservationIgnored private let sampleLoader: BundledSampleLoader
    @ObservationIgnored private var initialLoadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var partsByAnswerKey: [AnswerKey: QuestionPart] = [:]
    @ObservationIgnored private var questionSummaryLocations: [String: (packID: UUID, title: String, partCount: Int)] = [:]
    @ObservationIgnored private var libraryQuestionLocations: [String: (section: Int, question: Int)] = [:]

    init(
        persistence: JSONAppPersistence = JSONAppPersistence(),
        importer: MarkdownDocumentImporter = MarkdownDocumentImporter(),
        sampleLoader: BundledSampleLoader = BundledSampleLoader()
    ) {
        self.persistence = persistence
        self.importer = importer
        self.sampleLoader = sampleLoader
    }

    var questionCount: Int {
        librarySections.reduce(0) { $0 + $1.questions.count }
    }

    var hasActiveLibraryFilters: Bool {
        !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || libraryFormatFilter != nil
            || libraryShellFilter != nil
            || libraryStatusFilter != nil
    }

    func clearLibraryFilters() {
        librarySearchText = ""
        libraryFormatFilter = nil
        libraryShellFilter = nil
        libraryStatusFilter = nil
    }

    func loadIfNeeded() async {
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }
        guard loadPhase == .idle else { return }

        let task = Task { @MainActor [self] in
            await performInitialLoad()
        }
        initialLoadTask = task
        await task.value
        initialLoadTask = nil
    }

    private func performInitialLoad() async {
        loadPhase = .loading

        do {
            let state = try await persistence.load()
            var shouldPersistNormalizedState = false
            if state.packs.isEmpty {
                let bundledSample = BundledSample.allFormats
                let sample = try await sampleLoader.load(bundledSample)
                packs = [
                    ImportedQuestionPack(
                        sourceFileName: bundledSample.fileName,
                        pack: sample.pack
                    )
                ]
                shouldPersistNormalizedState = true
            } else {
                let normalized = canonicalizeLoadedPacks(state.packs)
                packs = normalized.packs
                shouldPersistNormalizedState = normalized.didChange
            }
            attemptsByQuestionID = Dictionary(
                state.attempts.map { ($0.questionID, $0) },
                uniquingKeysWith: { first, second in
                    first.updatedAt >= second.updatedAt ? first : second
                }
            )
            rebuildDerivedState()
            loadPhase = .ready
            if shouldPersistNormalizedState {
                do {
                    try await persistence.save(snapshot())
                    saveFailureMessage = nil
                } catch {
                    saveFailureMessage = error.localizedDescription
                }
            }
        } catch {
            loadPhase = .failed(message: error.localizedDescription)
        }
    }

    func importMarkdown(from url: URL) async {
        let sourceFileName = url.lastPathComponent
        importPhase = .importing(fileName: sourceFileName)

        do {
            let result = try await importer.importDocument(at: url)
            await applyImportResult(result, sourceFileName: sourceFileName)
        } catch {
            importPhase = .failed(message: error.localizedDescription)
        }
    }

    func importBundledSample(_ sample: BundledSample) async {
        importPhase = .importing(fileName: sample.fileName)

        do {
            let result = try await sampleLoader.load(sample)
            await applyImportResult(result, sourceFileName: sample.fileName)
        } catch {
            importPhase = .failed(message: error.localizedDescription)
        }
    }

    func reportImportPickerFailure(_ error: any Error) {
        importPhase = .failed(message: error.localizedDescription)
    }

    func clearImportStatus() {
        importPhase = .idle
    }

    private func applyImportResult(
        _ result: ImportResult,
        sourceFileName: String
    ) async {
        let importedPack: ImportedQuestionPack
        let existing = packs.first(where: { $0.sourceFileName == sourceFileName })
        let packID = existing?.id ?? UUID()
        let canonicalPack = canonicalizedPack(
            result.pack,
            packID: packID,
            excludingPackID: existing?.id
        )

        if let existing {
            importedPack = ImportedQuestionPack(
                id: existing.id,
                sourceFileName: sourceFileName,
                importedAt: .now,
                pack: canonicalPack
            )
            packs.replace(importedPack, where: { $0.id == existing.id })
        } else {
            importedPack = ImportedQuestionPack(
                id: packID,
                sourceFileName: sourceFileName,
                pack: canonicalPack
            )
            packs.append(importedPack)
        }

        rebuildDerivedState()
        loadPhase = .ready
        do {
            try await persistence.save(snapshot())
            saveFailureMessage = nil
        } catch {
            saveFailureMessage = error.localizedDescription
        }
        importPhase = .succeeded(
            fileName: sourceFileName,
            questionCount: canonicalPack.questions.count,
            warnings: result.warnings.enumerated().map { index, warning in
                ImportNotice(
                    id: "\(sourceFileName)-warning-\(index)",
                    message: warning.message,
                    line: warning.line
                )
            }
        )
    }

    func questionScreen(for route: AppRoute) -> QuestionScreenModel? {
        questionScreensByRoute[route]
    }

    func beginAttempt(questionID: String) {
        guard attemptsByQuestionID[questionID] == nil else { return }
        attemptsByQuestionID[questionID] = AttemptRecord(questionID: questionID)
        rebuildAttemptSummaries()
        scheduleSave()
    }

    func hasAttempt(questionID: String) -> Bool {
        attemptsByQuestionID[questionID] != nil
    }

    func answer(questionID: String, partID: String) -> StudentAnswer {
        attemptsByQuestionID[questionID]?.answers[partID] ?? StudentAnswer()
    }

    subscript(answerFor key: AnswerKey) -> StudentAnswer {
        get {
            answer(questionID: key.questionID, partID: key.partID)
        }
        set {
            updateAnswer(newValue, questionID: key.questionID, partID: key.partID)
        }
    }

    func updateAnswer(_ answer: StudentAnswer, questionID: String, partID: String) {
        let previousAnswer = self.answer(questionID: questionID, partID: partID)
        guard previousAnswer != answer else { return }
        var attempt = attemptsByQuestionID[questionID] ?? AttemptRecord(questionID: questionID)
        attempt.answers[partID] = answer
        attempt.updatedAt = .now
        attemptsByQuestionID[questionID] = attempt
        rebuildAttemptSummaries()
        if previousAnswer.isBlank != answer.isBlank {
            updateLibraryProgress(questionID: questionID)
        }
        scheduleSave()
    }

    func markSelfReview(_ completed: Bool, questionID: String, partID: String) {
        var attempt = attemptsByQuestionID[questionID] ?? AttemptRecord(questionID: questionID)
        guard (attempt.selfReviews[partID] ?? false) != completed else { return }
        attempt.selfReviews[partID] = completed
        attempt.updatedAt = .now
        attemptsByQuestionID[questionID] = attempt
        rebuildAttemptSummaries()
        scheduleSave()
    }

    func isSelfReviewComplete(questionID: String, partID: String) -> Bool {
        attemptsByQuestionID[questionID]?.selfReviews[partID] ?? false
    }

    subscript(selfReviewFor key: AnswerKey) -> Bool {
        get {
            isSelfReviewComplete(questionID: key.questionID, partID: key.partID)
        }
        set {
            markSelfReview(newValue, questionID: key.questionID, partID: key.partID)
        }
    }

    func grade(questionID: String, partID: String) -> GradeResult? {
        let key = AnswerKey(questionID: questionID, partID: partID)
        guard let part = partsByAnswerKey[key] else { return nil }
        let answer = answer(questionID: questionID, partID: partID)
        if let incomplete = ResponseCompletionPolicy.incompleteResult(for: answer, part: part) {
            return incomplete
        }
        return AnswerGrader.grade(answer, for: part)
    }

    func resumePartIndex(for question: QuestionScreenModel) -> Int {
        guard !question.parts.isEmpty else { return 0 }
        return question.parts.firstIndex { part in
            answer(questionID: question.questionID, partID: part.id).isBlank
        } ?? max(question.parts.count - 1, 0)
    }

    func flushPersistence() async {
        guard loadPhase == .ready else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        do {
            try await persistence.save(snapshot())
            saveFailureMessage = nil
        } catch {
            saveFailureMessage = error.localizedDescription
        }
    }

    private func rebuildDerivedState() {
        var screens: [AppRoute: QuestionScreenModel] = [:]
        var parts: [AnswerKey: QuestionPart] = [:]
        var summaryLocations: [String: (packID: UUID, title: String, partCount: Int)] = [:]
        for imported in packs {
            for question in imported.pack.questions {
                let route = AppRoute.question(
                    packID: imported.id,
                    questionID: question.id
                )
                screens[route] = QuestionScreenModel(
                    packID: imported.id,
                    questionID: question.id,
                    title: question.title,
                    shell: question.shell,
                    variation: question.variation,
                    scenarioMarkdown: question.scenarioMarkdown,
                    parts: question.parts
                )
                summaryLocations[question.id] = (
                    imported.id,
                    question.title,
                    question.parts.count
                )
                for part in question.parts {
                    let key = AnswerKey(questionID: question.id, partID: part.id)
                    if parts[key] == nil {
                        parts[key] = part
                    }
                }
            }
        }
        questionScreensByRoute = screens
        partsByAnswerKey = parts
        questionSummaryLocations = summaryLocations
        rebuildAttemptSummaries()
        rebuildLibrarySections()
    }

    private func rebuildLibrarySections() {
        var locations: [String: (section: Int, question: Int)] = [:]
        librarySections = packs.enumerated().map { sectionIndex, imported in
            let questions = imported.pack.questions.enumerated().map { questionIndex, question in
                locations[question.id] = (sectionIndex, questionIndex)
                return LibraryQuestionItem(
                    id: question.id,
                    title: question.title,
                    shell: question.shell,
                    variation: question.variation,
                    formats: question.formats,
                    partCount: question.parts.count,
                    answeredPartCount: answeredPartCount(questionID: question.id),
                    searchableText: searchableText(for: question)
                )
            }
            return LibrarySectionModel(
                id: imported.id,
                title: imported.pack.title,
                sourceFileName: imported.sourceFileName,
                importedAt: imported.importedAt,
                questions: questions
            )
        }
        libraryQuestionLocations = locations
        rebuildVisibleLibrary()
    }

    private func updateLibraryProgress(questionID: String) {
        guard let location = libraryQuestionLocations[questionID],
              librarySections.indices.contains(location.section),
              librarySections[location.section].questions.indices.contains(location.question) else {
            rebuildLibrarySections()
            return
        }

        let section = librarySections[location.section]
        var questions = section.questions
        let current = questions[location.question]
        questions[location.question] = LibraryQuestionItem(
            id: current.id,
            title: current.title,
            shell: current.shell,
            variation: current.variation,
            formats: current.formats,
            partCount: current.partCount,
            answeredPartCount: answeredPartCount(questionID: questionID),
            searchableText: current.searchableText
        )
        librarySections[location.section] = LibrarySectionModel(
            id: section.id,
            title: section.title,
            sourceFileName: section.sourceFileName,
            importedAt: section.importedAt,
            questions: questions
        )
        rebuildVisibleLibrary()
    }

    private func answeredPartCount(questionID: String) -> Int {
        attemptsByQuestionID[questionID]?.answers.values.reduce(into: 0) { count, answer in
            if !answer.isBlank { count += 1 }
        } ?? 0
    }

    private func rebuildVisibleLibrary() {
        let query = foldedSearchText(librarySearchText)
        visibleLibrarySections = librarySections.compactMap { section in
            let sectionMatchesQuery = query.isEmpty
                || foldedSearchText(section.title).contains(query)
                || foldedSearchText(section.sourceFileName).contains(query)
            let questions = section.questions.filter { question in
                let matchesQuery = sectionMatchesQuery
                    || question.searchableText.contains(query)
                let matchesFormat = libraryFormatFilter.map {
                    question.formats.contains($0)
                } ?? true
                let matchesShell = libraryShellFilter.map {
                    question.shell == $0
                } ?? true
                let matchesStatus = libraryStatusFilter.map {
                    question.status == $0
                } ?? true
                return matchesQuery && matchesFormat && matchesShell && matchesStatus
            }
            guard !questions.isEmpty else { return nil }
            return LibrarySectionModel(
                id: section.id,
                title: section.title,
                sourceFileName: section.sourceFileName,
                importedAt: section.importedAt,
                questions: questions
            )
        }
    }

    private func searchableText(for question: AccountingQuestion) -> String {
        var fragments = [
            question.title,
            question.scenarioMarkdown,
            question.tags.joined(separator: " "),
            String(localized: question.shell.localizedTitle)
        ]
        fragments.append(contentsOf: question.formats.map { String(localized: $0.localizedTitle) })
        for part in question.parts {
            fragments.append(part.promptMarkdown)
            fragments.append(contentsOf: part.options.map(\.text))
            fragments.append(contentsOf: part.items.map(\.text))
            fragments.append(contentsOf: part.targets.map(\.text))
        }
        return foldedSearchText(fragments.joined(separator: " "))
    }

    private func foldedSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
    }

    private func rebuildAttemptSummaries() {
        attemptSummaries = attemptsByQuestionID.values.map { attempt in
            let location = questionSummaryLocations[attempt.questionID]
            let answeredCount = attempt.answers.values.filter { !$0.isBlank }.count
            return AttemptSummary(
                id: attempt.id,
                packID: location?.packID,
                questionID: attempt.questionID,
                title: location?.title ?? attempt.questionID,
                answeredPartCount: answeredCount,
                totalPartCount: location?.partCount ?? 0,
                updatedAt: attempt.updatedAt
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func scheduleSave() {
        let state = snapshot()
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self, persistence] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                try await persistence.save(state)
                self?.saveFailureMessage = nil
            } catch is CancellationError {
                return
            } catch {
                self?.saveFailureMessage = error.localizedDescription
            }
        }
    }

    private func snapshot() -> PersistedAppState {
        PersistedAppState(
            packs: packs,
            attempts: Array(attemptsByQuestionID.values)
                .sorted { $0.questionID < $1.questionID }
        )
    }

    private func canonicalizeLoadedPacks(
        _ loadedPacks: [ImportedQuestionPack]
    ) -> (packs: [ImportedQuestionPack], didChange: Bool) {
        var usedPackIDs = Set<UUID>()
        var usedQuestionIDs = Set<String>()
        var didChange = false
        let normalizedPacks = loadedPacks.map { imported in
            let packID: UUID
            if usedPackIDs.insert(imported.id).inserted {
                packID = imported.id
            } else {
                packID = UUID()
                usedPackIDs.insert(packID)
                didChange = true
            }
            let questions = imported.pack.questions.map { question in
                let uniqueID = uniqueQuestionID(
                    preferredID: question.id,
                    packID: packID,
                    usedIDs: &usedQuestionIDs
                )
                guard uniqueID != question.id else { return question }
                didChange = true
                return question.replacingID(with: uniqueID)
            }
            return ImportedQuestionPack(
                id: packID,
                sourceFileName: imported.sourceFileName,
                importedAt: imported.importedAt,
                pack: QuestionPack(
                    version: imported.pack.version,
                    title: imported.pack.title,
                    questions: questions
                )
            )
        }
        return (normalizedPacks, didChange)
    }

    private func canonicalizedPack(
        _ pack: QuestionPack,
        packID: UUID,
        excludingPackID: UUID?
    ) -> QuestionPack {
        var usedQuestionIDs = Set(
            packs
                .filter { $0.id != excludingPackID }
                .flatMap(\.pack.questions)
                .map(\.id)
        )
        let questions = pack.questions.map { question in
            let uniqueID = uniqueQuestionID(
                preferredID: question.id,
                packID: packID,
                usedIDs: &usedQuestionIDs
            )
            return uniqueID == question.id
                ? question
                : question.replacingID(with: uniqueID)
        }
        return QuestionPack(version: pack.version, title: pack.title, questions: questions)
    }

    private func uniqueQuestionID(
        preferredID: String,
        packID: UUID,
        usedIDs: inout Set<String>
    ) -> String {
        if usedIDs.insert(preferredID).inserted {
            return preferredID
        }

        let base = "\(preferredID)--pack-\(packID.uuidString.lowercased())"
        var candidate = base
        var suffix = 2
        while !usedIDs.insert(candidate).inserted {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}

private extension Array {
    mutating func replace(_ newElement: Element, where predicate: (Element) -> Bool) {
        guard let index = firstIndex(where: predicate) else { return }
        self[index] = newElement
    }
}

private extension AccountingQuestion {
    func replacingID(with newID: String) -> AccountingQuestion {
        AccountingQuestion(
            id: newID,
            title: title,
            shell: shell,
            variation: variation,
            formats: formats,
            scenarioMarkdown: scenarioMarkdown,
            parts: parts,
            tags: tags,
            sourceName: sourceName
        )
    }
}
