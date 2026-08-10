import Foundation

enum AppPersistenceError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            String(
                localized: "This library was saved by a newer app version (schema \(version)).",
                comment: "Persistence error. The variable is a JSON schema version number."
            )
        }
    }
}

actor JSONAppPersistence {
    private let baseDirectory: URL?
    private let directoryName = "AccountingQuestionSuite"
    private let fileName = "library-state.json"

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func load() throws -> PersistedAppState {
        let fileURL = try stateFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let state = try JSONDecoder().decode(PersistedAppState.self, from: data)
        guard state.version <= PersistedAppState.currentVersion else {
            throw AppPersistenceError.unsupportedVersion(state.version)
        }
        return state
    }

    func save(_ state: PersistedAppState) throws {
        let fileURL = try stateFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    func storageURL() throws -> URL {
        try stateFileURL()
    }

    private func stateFileURL() throws -> URL {
        let directoryURL: URL
        if let baseDirectory {
            directoryURL = baseDirectory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directoryURL = applicationSupport.appending(path: directoryName, directoryHint: .isDirectory)
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appending(path: fileName, directoryHint: .notDirectory)
    }
}

