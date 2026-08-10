import AccountingQuestionKit
import CryptoKit
import Foundation

enum QuestionImportServiceError: Error, LocalizedError {
    case unsupportedTextEncoding(String)
    case invalidStructuredDocument(fileName: String, issues: [String])

    var errorDescription: String? {
        switch self {
        case let .unsupportedTextEncoding(fileName):
            return String(localized: "\(fileName) is not a UTF-8 Markdown file.")
        case let .invalidStructuredDocument(fileName, issues):
            let summary = issues.prefix(5).formatted()
            return String(
                localized: "\(fileName) contains invalid structured question data: \(summary)"
            )
        }
    }
}

/// Canonical question IDs keep attempts isolated by source document while
/// preserving the author's original ID for display and migration.
enum QuestionIdentity {
    private static let prefix = "aqs2"

    static func canonicalID(
        originalID: String,
        sourceURL: URL,
        occurrence: Int = 0
    ) -> String {
        let source = sourceIdentity(for: sourceURL)
            + (occurrence == 0 ? "" : "|occurrence:\(occurrence)")
        let digest = SHA256.hash(data: Data(source.utf8))
        let scope = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        let encodedID = Data(originalID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(prefix):\(scope):\(encodedID)"
    }

    static func originalID(from libraryID: String) -> String {
        let components = libraryID.split(separator: ":", maxSplits: 2)
        guard components.count == 3, components[0] == Substring(prefix) else {
            return libraryID
        }
        var encoded = String(components[2])
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: encoded),
              let originalID = String(data: data, encoding: .utf8) else {
            return libraryID
        }
        return originalID
    }

    static func isCanonical(_ libraryID: String) -> Bool {
        originalID(from: libraryID) != libraryID
    }

    private static func sourceIdentity(for url: URL) -> String {
        "path:\(url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false))"
    }
}

struct QuestionImportService: Sendable {
    func importFiles(at urls: [URL]) async throws -> [ImportResult] {
        try await Task.detached(priority: .userInitiated) {
            try urls.map(Self.importFile(at:))
        }.value
    }

    private static func importFile(at url: URL) throws -> ImportResult {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw QuestionImportServiceError.unsupportedTextEncoding(url.lastPathComponent)
        }

        var result = try QuestionMarkdownParser.parse(
            markdown,
            sourceName: url.lastPathComponent
        )
        let validationIssues = QuestionValidator.validate(result.pack)
        let isStructured = markdown.contains(":::question")
        let errors = validationIssues.filter { $0.severity == .error }
        if isStructured, !errors.isEmpty {
            throw QuestionImportServiceError.invalidStructuredDocument(
                fileName: url.lastPathComponent,
                issues: errors.map(Self.validationMessage(for:))
            )
        }

        result.warnings.append(contentsOf: validationIssues.map { issue in
            let severity = issue.severity == .error
                ? String(localized: "Error")
                : String(localized: "Warning")
            return ImportWarning(
                "\(severity): \(Self.validationMessage(for: issue))"
            )
        })
        var occurrencesByOriginalID: [String: Int] = [:]
        result.pack.questions = result.pack.questions.map { question in
            let originalID = QuestionIdentity.originalID(from: question.id)
            let occurrence = occurrencesByOriginalID[originalID, default: 0]
            occurrencesByOriginalID[originalID] = occurrence + 1
            return Self.canonicalized(
                question,
                originalID: originalID,
                occurrence: occurrence,
                sourceURL: url
            )
        }
        return result
    }

    private static func canonicalized(
        _ question: AccountingQuestion,
        originalID: String,
        occurrence: Int,
        sourceURL: URL
    ) -> AccountingQuestion {
        AccountingQuestion(
            id: QuestionIdentity.canonicalID(
                originalID: originalID,
                sourceURL: sourceURL,
                occurrence: occurrence
            ),
            title: question.title,
            shell: question.shell,
            variation: question.variation,
            formats: question.formats,
            scenarioMarkdown: question.scenarioMarkdown,
            parts: question.parts,
            tags: question.tags,
            sourceName: question.sourceName
        )
    }

    private static func validationMessage(for issue: ValidationIssue) -> String {
        if let partID = issue.partID {
            return String(
                localized: "Question \(issue.questionID), part \(partID): \(issue.message)"
            )
        }
        return String(localized: "Question \(issue.questionID): \(issue.message)")
    }
}
