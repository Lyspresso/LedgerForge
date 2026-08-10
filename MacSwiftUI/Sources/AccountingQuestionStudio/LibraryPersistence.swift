import AccountingQuestionKit
import Foundation

enum LibraryPersistenceError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            String(
                localized: "This library uses unsupported data version \(version)."
            )
        }
    }
}

struct LibrarySnapshot: Codable, Equatable, Sendable {
    var version: Int
    var questions: [AccountingQuestion]
    var attempts: [AttemptRecord]

    init(
        version: Int = 1,
        questions: [AccountingQuestion] = [],
        attempts: [AttemptRecord] = []
    ) {
        self.version = version
        self.questions = questions
        self.attempts = attempts
    }
}

actor LibraryPersistence {
    private let fileURL: URL

    init(fileURL: URL = LibraryPersistence.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LibrarySnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
        guard snapshot.version == 1 else {
            throw LibraryPersistenceError.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appending(path: "Statement Studio", directoryHint: .isDirectory)
            .appending(path: "library.json", directoryHint: .notDirectory)
    }
}
