import AccountingQuestionKit
import Foundation

enum MarkdownDocumentImportError: LocalizedError, Equatable {
    case invalidUTF8
    case invalidQuestionPack(String)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            String(
                localized: "The selected file is not valid UTF-8 Markdown.",
                comment: "Import error shown when a Markdown file cannot be decoded as UTF-8."
            )
        case let .invalidQuestionPack(summary):
            String(
                localized: "The question pack is not usable: \(summary)",
                comment: "Import error. The variable summarizes structural validation errors in a Markdown question pack."
            )
        }
    }
}

actor MarkdownDocumentImporter {
    func importDocument(at url: URL) throws -> ImportResult {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw MarkdownDocumentImportError.invalidUTF8
        }

        let result = try QuestionMarkdownParser.parse(
            markdown,
            sourceName: url.deletingPathExtension().lastPathComponent
        )
        let validationIssues = QuestionValidator.validate(result.pack)
        var identityErrors: [String] = []
        for question in result.pack.questions {
            for part in question.parts {
                if part.options.uniqueByID.count != part.options.count {
                    identityErrors.append("\(question.id)/\(part.id) has duplicate option identifiers")
                }
                if part.items.uniqueByID.count != part.items.count {
                    identityErrors.append("\(question.id)/\(part.id) has duplicate item identifiers")
                }
                if part.targets.uniqueByID.count != part.targets.count {
                    identityErrors.append("\(question.id)/\(part.id) has duplicate target identifiers")
                }
            }
        }
        let errors = validationIssues
            .filter { $0.severity == .error }
            .map { issue in
                let part = issue.partID.map { "/\($0)" } ?? ""
                return "\(issue.questionID)\(part): \(issue.message)"
            } + identityErrors
        guard errors.isEmpty else {
            let summary = errors.prefix(3).joined(separator: "; ")
            throw MarkdownDocumentImportError.invalidQuestionPack(summary)
        }
        let warnings = result.warnings + validationIssues
            .filter { $0.severity == .warning }
            .map { issue in
                let part = issue.partID.map { "/\($0)" } ?? ""
                return ImportWarning("\(issue.questionID)\(part): \(issue.message)")
            }
        return ImportResult(pack: result.pack, warnings: warnings)
    }
}
