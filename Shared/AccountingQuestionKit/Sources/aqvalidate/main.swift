import AccountingQuestionKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let showStats = arguments.contains("--stats")
let paths = arguments.filter { $0 != "--stats" }
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("Usage: aqvalidate [--stats] QUESTION.md […]\n".utf8))
    exit(64)
}

var hasFailure = false
for path in paths {
    let url = URL(fileURLWithPath: path)
    do {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let result = try QuestionMarkdownParser.parse(markdown, sourceName: url.lastPathComponent)
        let validationIssues = QuestionValidator.validate(result.pack)
        let errors = validationIssues.filter { $0.severity == .error }
        print("\(url.lastPathComponent): \(result.pack.questions.count) questions, \(result.warnings.count) import warnings, \(validationIssues.count) validation issues")
        if showStats {
            let parts = result.pack.questions.flatMap(\.parts)
            let counts = ResponseKind.allCases.compactMap { kind -> String? in
                let count = parts.count { $0.kind == kind }
                return count > 0 ? "\(kind.rawValue)=\(count)" : nil
            }
            print("  response kinds: \(counts.joined(separator: ", "))")
            let suspiciousLegacyChoices = result.pack.questions.filter { question in
                question.parts.contains { part in
                    part.settings["legacy"] == "true"
                        && part.kind == .longText
                        && part.promptMarkdown.contains("- A)")
                }
            }
            if !suspiciousLegacyChoices.isEmpty {
                print(
                    "  possible unrecognized legacy choices: "
                        + suspiciousLegacyChoices.map(\.id).joined(separator: ", ")
                )
            }
        }
        for warning in result.warnings.prefix(20) {
            let location = warning.line.map { "line \($0): " } ?? ""
            print("  warning: \(location)\(warning.message)")
        }
        for issue in validationIssues.prefix(50) {
            let part = issue.partID.map { "/\($0)" } ?? ""
            print("  \(issue.severity.rawValue): \(issue.questionID)\(part): \(issue.message)")
        }
        if result.warnings.count > 20 {
            print("  … \(result.warnings.count - 20) more import warnings")
        }
        if validationIssues.count > 50 {
            print("  … \(validationIssues.count - 50) more validation issues")
        }
        hasFailure = hasFailure || !errors.isEmpty
    } catch {
        hasFailure = true
        FileHandle.standardError.write(Data("\(url.lastPathComponent): \(error.localizedDescription)\n".utf8))
    }
}

exit(hasFailure ? 1 : 0)
