import AccountingQuestionKit
import Foundation

enum BundledSample: String, CaseIterable, Identifiable, Sendable {
    case allFormats = "ALL_FORMATS_SAMPLE"
    case spreadsheetPractice = "SPREADSHEET_PRACTICE"

    var id: String { rawValue }
    var fileName: String { "\(rawValue).md" }

    var title: LocalizedStringResource {
        switch self {
        case .allFormats:
            "All Formats Sample"
        case .spreadsheetPractice:
            "Spreadsheet Practice"
        }
    }

    var sourceName: String {
        switch self {
        case .allFormats:
            "All Formats Sample"
        case .spreadsheetPractice:
            "Spreadsheet Practice"
        }
    }

    var systemImage: String {
        switch self {
        case .allFormats:
            "rectangle.3.group.bubble"
        case .spreadsheetPractice:
            "tablecells"
        }
    }
}

enum BundledSampleError: LocalizedError, Equatable {
    case missingResource(BundledSample)
    case invalidUTF8(BundledSample)

    var errorDescription: String? {
        switch self {
        case let .missingResource(sample):
            String(
                localized: "The built-in sample \(sample.fileName) is missing.",
                comment: "Error shown when a bundled sample Markdown resource cannot be found. The variable is its filename."
            )
        case let .invalidUTF8(sample):
            String(
                localized: "The built-in sample \(sample.fileName) is not valid UTF-8 Markdown.",
                comment: "Error shown when a bundled sample Markdown resource cannot be decoded. The variable is its filename."
            )
        }
    }
}

actor BundledSampleLoader {
    private let resourceURLs: [BundledSample: URL]
    private let markdownOverride: String?

    init(bundle: Bundle = .main) {
        self.resourceURLs = Dictionary(
            uniqueKeysWithValues: BundledSample.allCases.compactMap { sample in
                bundle.url(
                    forResource: sample.rawValue,
                    withExtension: "md"
                ).map { (sample, $0) }
            }
        )
        self.markdownOverride = nil
    }

    init(markdown: String) {
        self.resourceURLs = [:]
        self.markdownOverride = markdown
    }

    func load(_ sample: BundledSample = .allFormats) throws -> ImportResult {
        let markdown: String
        if let markdownOverride {
            markdown = markdownOverride
        } else {
            guard let resourceURL = resourceURLs[sample] else {
                throw BundledSampleError.missingResource(sample)
            }
            let data = try Data(contentsOf: resourceURL)
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw BundledSampleError.invalidUTF8(sample)
            }
            markdown = decoded
        }

        return try QuestionMarkdownParser.parse(
            markdown,
            sourceName: sample.sourceName
        )
    }
}
