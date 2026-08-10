import AccountingQuestionKit
import Foundation

struct ImportedQuestionPack: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var sourceFileName: String
    var importedAt: Date
    var pack: QuestionPack

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        importedAt: Date = .now,
        pack: QuestionPack
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.pack = pack
    }
}

struct PersistedAppState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var packs: [ImportedQuestionPack]
    var attempts: [AttemptRecord]

    init(
        version: Int = currentVersion,
        packs: [ImportedQuestionPack] = [],
        attempts: [AttemptRecord] = []
    ) {
        self.version = version
        self.packs = packs
        self.attempts = attempts
    }

    static let empty = PersistedAppState()
}

struct LibraryQuestionItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let shell: QuestionShell
    let variation: VariationStyle
    let formats: [QuestionFormat]
    let partCount: Int
    let answeredPartCount: Int
    let searchableText: String

    var status: LibraryStudyStatus {
        if answeredPartCount == 0 {
            return .notStarted
        }
        if answeredPartCount >= partCount {
            return .completed
        }
        return .inProgress
    }
}

struct LibrarySectionModel: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let sourceFileName: String
    let importedAt: Date
    let questions: [LibraryQuestionItem]
}

struct QuestionScreenModel: Equatable, Sendable {
    let packID: UUID
    let questionID: String
    let title: String
    let shell: QuestionShell
    let variation: VariationStyle
    let scenarioMarkdown: String
    let parts: [QuestionPart]
}

struct AttemptSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let packID: UUID?
    let questionID: String
    let title: String
    let answeredPartCount: Int
    let totalPartCount: Int
    let updatedAt: Date

    var progress: Double {
        guard totalPartCount > 0 else { return 0 }
        return Double(answeredPartCount) / Double(totalPartCount)
    }
}

enum AppRoute: Hashable {
    case attempts
    case question(packID: UUID, questionID: String)
}

enum LibraryStudyStatus: String, CaseIterable, Equatable, Hashable, Sendable {
    case notStarted
    case inProgress
    case completed
}

enum AppLoadPhase: Equatable {
    case idle
    case loading
    case ready
    case failed(message: String)
}

enum MarkdownImportPhase: Equatable {
    case idle
    case importing(fileName: String)
    case succeeded(fileName: String, questionCount: Int, warnings: [ImportNotice])
    case failed(message: String)
}

struct ImportNotice: Equatable, Identifiable, Sendable {
    let id: String
    let message: String
    let line: Int?
}

struct AnswerKey: Equatable, Hashable, Sendable {
    let questionID: String
    let partID: String
}

struct AnswerCell: Equatable, Hashable, Sendable {
    let row: Int
    let column: Int
}

struct StableColumn: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}
