import Foundation

public struct ImportWarning: Codable, Equatable, Sendable {
    public var message: String
    public var line: Int?

    public init(_ message: String, line: Int? = nil) {
        self.message = message
        self.line = line
    }
}

public struct ImportResult: Codable, Equatable, Sendable {
    public var pack: QuestionPack
    public var warnings: [ImportWarning]

    public init(pack: QuestionPack, warnings: [ImportWarning] = []) {
        self.pack = pack
        self.warnings = warnings
    }
}

public enum MarkdownImportError: Error, LocalizedError, Equatable {
    case emptyDocument
    case malformedDirective(String, Int)
    case missingQuestionID(Int)
    case missingPartID(Int)
    case invalidEnum(String, String, Int)
    case duplicateQuestionID(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument: "The Markdown document is empty."
        case let .malformedDirective(text, line): "Malformed directive at line \(line): \(text)"
        case let .missingQuestionID(line): "Question at line \(line) has no id."
        case let .missingPartID(line): "Part at line \(line) has no id."
        case let .invalidEnum(field, value, line): "Unknown \(field) '\(value)' at line \(line)."
        case let .duplicateQuestionID(id): "The question id '\(id)' occurs more than once."
        }
    }
}

public enum QuestionMarkdownParser {
    public static func parse(_ markdown: String, sourceName: String = "Imported Markdown") throws -> ImportResult {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkdownImportError.emptyDocument
        }
        if markdown.contains(":::question") {
            return try parseStructured(markdown, sourceName: sourceName)
        }
        return parseLegacy(markdown, sourceName: sourceName)
    }

    private static func parseStructured(_ markdown: String, sourceName: String) throws -> ImportResult {
        let lines = markdown.components(separatedBy: .newlines)
        var index = 0
        var questions: [AccountingQuestion] = []
        var warnings: [ImportWarning] = []

        while index < lines.count {
            guard lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(":::question") else {
                index += 1
                continue
            }
            let questionLine = index + 1
            let attributes = try directiveAttributes(lines[index], at: questionLine)
            guard let id = attributes["id"], !id.isEmpty else {
                throw MarkdownImportError.missingQuestionID(questionLine)
            }
            let shell = try enumValue(QuestionShell.self, field: "shell", value: attributes["shell"] ?? "multipart", line: questionLine)
            let variation = try enumValue(VariationStyle.self, field: "variation", value: attributes["variation"] ?? "core", line: questionLine)
            let declaredFormats = try commaValues(attributes["formats"] ?? "", as: QuestionFormat.self, field: "formats", line: questionLine)
            let tags = commaStrings(attributes["tags"] ?? "")
            index += 1

            var title = "Untitled Question"
            var scenarioLines: [String] = []
            var parts: [QuestionPart] = []
            var section = ""

            while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != ":::endquestion" {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    index += 1
                    continue
                }
                if trimmed == "## Scenario" {
                    section = "scenario"
                    index += 1
                    continue
                }
                if trimmed.hasPrefix(":::part") {
                    let parsed = try parsePart(lines, start: index)
                    parts.append(parsed.part)
                    index = parsed.nextIndex
                    continue
                }
                if section == "scenario" {
                    scenarioLines.append(lines[index])
                }
                index += 1
            }

            if index >= lines.count {
                warnings.append(ImportWarning("Question '\(id)' has no :::endquestion marker.", line: questionLine))
            } else {
                index += 1
            }
            if parts.isEmpty {
                warnings.append(ImportWarning("Question '\(id)' contains no parts.", line: questionLine))
            }
            let inferred = unique(parts.map(\.format))
            title = TitlePresentation.normalizedImportTitle(
                title,
                prompt: parts.first?.promptMarkdown ?? "",
                fallbackID: id
            )
            questions.append(
                AccountingQuestion(
                    id: id,
                    title: title,
                    shell: shell,
                    variation: variation,
                    formats: declaredFormats.isEmpty ? inferred : declaredFormats,
                    scenarioMarkdown: clean(scenarioLines),
                    parts: parts,
                    tags: tags,
                    sourceName: sourceName
                )
            )
        }

        var seen = Set<String>()
        for question in questions where !seen.insert(question.id).inserted {
            throw MarkdownImportError.duplicateQuestionID(question.id)
        }
        return ImportResult(pack: QuestionPack(title: sourceName, questions: questions), warnings: warnings)
    }

    private static func parsePart(_ lines: [String], start: Int) throws -> (part: QuestionPart, nextIndex: Int) {
        let lineNumber = start + 1
        let attributes = try directiveAttributes(lines[start], at: lineNumber)
        guard let id = attributes["id"], !id.isEmpty else {
            throw MarkdownImportError.missingPartID(lineNumber)
        }
        let kind = try enumValue(ResponseKind.self, field: "kind", value: attributes["kind"] ?? "long_text", line: lineNumber)
        let format = try enumValue(QuestionFormat.self, field: "format", value: attributes["format"] ?? defaultFormat(for: kind).rawValue, line: lineNumber)
        let points = Double(attributes["points"] ?? "1") ?? 1
        var index = start + 1
        var section = ""
        var content: [String: [String]] = [:]

        while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != ":::endpart" {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("### ") {
                section = String(trimmed.dropFirst(4)).lowercased()
                content[section] = []
            } else if !section.isEmpty {
                content[section, default: []].append(lines[index])
            }
            index += 1
        }
        if index < lines.count { index += 1 }

        let options = parseOptions(content["options"] ?? [])
        let items = parseOptions(content["items"] ?? [])
        let targets = parseOptions(content["targets"] ?? [])
        let columns = parseColumns(content["columns"] ?? [])
        let settings = parseSettings(content["settings"] ?? [])
        let answerLines = content["answer"] ?? []
        var expected = ExpectedAnswer(tolerance: settings["tolerance"].flatMap(Double.init))
        switch kind {
        case .singleChoice, .multipleChoice:
            expected.selections = commaStrings(clean(answerLines))
        case .journal, .table:
            expected.rows = parseMarkdownTable(answerLines)
        case .matching:
            expected.pairs = parsePairs(answerLines)
        case .ordering:
            expected.order = parseListIDs(answerLines)
        default:
            expected.scalar = clean(answerLines)
            expected.accepted = parseAccepted(
                content["accepted"] ?? [],
                setting: settings["accepted"] ?? ""
            )
        }
        return (
            QuestionPart(
                id: id,
                kind: kind,
                format: format,
                points: points,
                promptMarkdown: clean(content["prompt"] ?? []),
                options: options,
                columns: columns,
                items: items,
                targets: targets,
                expected: expected,
                rubricMarkdown: clean(content["rubric"] ?? []),
                settings: settings
            ),
            index
        )
    }

    private static func parseLegacy(_ markdown: String, sourceName: String) -> ImportResult {
        let lines = markdown.components(separatedBy: .newlines)
        let markerIndices = lines.indices.filter { index in
            let line = lines[index]
            return line.hasPrefix("## Item ") || line.hasPrefix("### `")
        }
        let ranges: [Range<Int>]
        if markerIndices.isEmpty {
            ranges = [0..<lines.count]
        } else {
            ranges = markerIndices.enumerated().map { offset, start in
                let end = offset + 1 < markerIndices.count ? markerIndices[offset + 1] : lines.count
                return start..<end
            }
        }

        var questions: [AccountingQuestion] = []
        var usedIDs: Set<String> = []
        var warnings = [
            ImportWarning(
                "Legacy Markdown was imported heuristically. Add :::question metadata to receive specialized editors and automatic grading."
            )
        ]
        for (offset, range) in ranges.enumerated() {
            let blockLines = Array(lines[range])
            let block = clean(blockLines)
            guard !block.isEmpty else { continue }
            let heading = blockLines.first(where: { $0.hasPrefix("#") }) ?? "Imported Question \(offset + 1)"
            let rawTitle = heading.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            let baseID = extractLegacyID(from: heading) ?? "legacy-\(offset + 1)-\(slug(rawTitle))"
            var naturalID = baseID
            var suffix = 2
            while usedIDs.contains(naturalID) {
                naturalID = "\(baseID)-\(suffix)"
                suffix += 1
            }
            if naturalID != baseID {
                warnings.append(
                    ImportWarning("Duplicate legacy id '\(baseID)' was renamed '\(naturalID)'.")
                )
            }
            usedIDs.insert(naturalID)
            let title = TitlePresentation.normalizedImportTitle(
                rawTitle,
                prompt: block,
                fallbackID: naturalID
            )
            let multipleChoiceParts = parseLegacyChoices(in: block)
            if !multipleChoiceParts.isEmpty {
                questions.append(
                    AccountingQuestion(
                        id: naturalID,
                        title: title,
                        shell: .multipleChoice,
                        formats: [.multipleChoice],
                        scenarioMarkdown: "",
                        parts: multipleChoiceParts,
                        tags: ["legacy-import"],
                        sourceName: sourceName
                    )
                )
            } else {
                let answerMarker = block.range(of: "**Answer key:**", options: .caseInsensitive)
                    ?? block.range(of: "**Answer:**", options: .caseInsensitive)
                let questionText: String
                let answerText: String
                if let answerMarker {
                    questionText = String(block[..<answerMarker.lowerBound])
                    answerText = String(block[answerMarker.upperBound...])
                } else {
                    questionText = block
                    answerText = ""
                }
                let inferred = inferFormats(from: questionText)
                let part = QuestionPart(
                    id: "response",
                    kind: .longText,
                    format: inferred.first ?? .shortExplanation,
                    promptMarkdown: questionText,
                    expected: ExpectedAnswer(scalar: answerText),
                    rubricMarkdown: answerText,
                    settings: ["legacy": "true"]
                )
                questions.append(
                    AccountingQuestion(
                        id: naturalID,
                        title: title,
                        shell: questionText.localizedCaseInsensitiveContains("required") ? .multipart : .memoResearch,
                        formats: inferred,
                        scenarioMarkdown: "",
                        parts: [part],
                        tags: ["legacy-import", "self-review"],
                        sourceName: sourceName
                    )
                )
            }
        }
        return ImportResult(pack: QuestionPack(title: sourceName, questions: questions), warnings: warnings)
    }

    private static func parseLegacyChoices(in block: String) -> [QuestionPart] {
        let lines = block.components(separatedBy: .newlines)
        var segments: [(question: [String], answer: [String])] = []
        var currentQuestion: [String]?
        var currentAnswer: [String] = []
        var readingAnswer = false

        for line in lines {
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            let startsQuestion = lowered.hasPrefix("**question")
                || isShortLegacyQuestionMarker(lowered)
            if startsQuestion {
                if let currentQuestion {
                    segments.append((currentQuestion, currentAnswer))
                }
                currentQuestion = [line]
                currentAnswer = []
                readingAnswer = false
                continue
            }
            guard currentQuestion != nil else { continue }
            let startsAnswer = lowered.hasPrefix("**answer:**")
                || lowered.hasPrefix("**answer key:**")
            if startsAnswer {
                readingAnswer = true
            }
            if readingAnswer {
                currentAnswer.append(line)
            } else {
                currentQuestion?.append(line)
            }
        }
        if let currentQuestion {
            segments.append((currentQuestion, currentAnswer))
        }

        let choiceCount = segments.reduce(into: 0) { count, segment in
            if containsLegacyOptions(segment.question) { count += 1 }
        }
        var choiceIndex = 0
        return segments.compactMap { segment in
            guard containsLegacyOptions(segment.question) else { return nil }
            choiceIndex += 1
            let partID = choiceCount == 1 ? "choice" : "choice-\(choiceIndex)"
            return parseLegacyChoice(
                questionText: clean(segment.question),
                answerText: clean(segment.answer),
                partID: partID
            )
        }
    }

    private static func isShortLegacyQuestionMarker(_ loweredLine: String) -> Bool {
        let pattern = try? NSRegularExpression(pattern: #"^\*\*q\d[^*]*\*\*"#)
        guard let pattern else { return false }
        let range = NSRange(loweredLine.startIndex..<loweredLine.endIndex, in: loweredLine)
        return pattern.firstMatch(in: loweredLine, range: range) != nil
    }

    private static func containsLegacyOptions(_ lines: [String]) -> Bool {
        let pattern = try? NSRegularExpression(pattern: #"^-\s*[A-H]\)\s+"#)
        guard let pattern else { return false }
        return lines.count { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return pattern.firstMatch(in: line, range: range) != nil
        } >= 2
    }

    private static func parseLegacyChoice(
        questionText: String,
        answerText: String,
        partID: String = "choice"
    ) -> QuestionPart? {
        let optionPattern = try? NSRegularExpression(pattern: #"(?m)^-\s*([A-H])\)\s+(.+)$"#)
        guard let optionPattern else { return nil }
        let range = NSRange(questionText.startIndex..<questionText.endIndex, in: questionText)
        let matches = optionPattern.matches(in: questionText, range: range)
        guard matches.count >= 2 else { return nil }
        let options = matches.compactMap { match -> QuestionOption? in
            guard let idRange = Range(match.range(at: 1), in: questionText),
                  let textRange = Range(match.range(at: 2), in: questionText) else { return nil }
            return QuestionOption(id: String(questionText[idRange]), text: String(questionText[textRange]))
        }
        let answerPattern = try? NSRegularExpression(pattern: #"(?i)\b([A-H])\b"#)
        let answerRange = NSRange(answerText.startIndex..<answerText.endIndex, in: answerText)
        let answer = answerPattern.flatMap { pattern in
            pattern.firstMatch(in: answerText, range: answerRange)
        }.flatMap { match -> String? in
            guard let swiftRange = Range(match.range(at: 1), in: answerText) else { return nil }
            return String(answerText[swiftRange]).uppercased()
        } ?? ""
        let prompt = questionText.components(separatedBy: "\n-").first ?? questionText
        return QuestionPart(
            id: partID,
            kind: .singleChoice,
            format: .multipleChoice,
            promptMarkdown: prompt,
            options: options,
            expected: ExpectedAnswer(selections: answer.isEmpty ? [] : [answer]),
            rubricMarkdown: answerText,
            settings: ["legacy": "true"]
        )
    }

    private static func inferFormats(from text: String) -> [QuestionFormat] {
        let lowered = text.lowercased()
        var formats: [QuestionFormat] = []
        let mappings: [(String, QuestionFormat)] = [
            ("journal entr", .initialJournalEntry),
            ("adjusting entr", .adjustingJournalEntry),
            ("schedule", .multiPeriodSchedule),
            ("rollforward", .rollforward),
            ("t-account", .tAccount),
            ("reconcil", .reconciliationProof),
            ("prove", .reconciliationProof),
            ("statement", .partialStatement),
            ("classif", .presentationClassificationGrid),
            ("disclos", .disclosureDrafting),
            ("error", .errorCorrection),
            ("ratio", .ratioAnalysis),
            ("codification", .codificationResearch),
            ("research memo", .codificationResearch),
            ("compute", .singleNumber),
            ("calculate", .singleNumber)
        ]
        for (needle, format) in mappings where lowered.contains(needle) {
            formats.append(format)
        }
        return unique(formats.isEmpty ? [.shortExplanation] : formats)
    }

    private static func directiveAttributes(_ line: String, at lineNumber: Int) throws -> [String: String] {
        let tokens = line.split(separator: " ").dropFirst()
        var result: [String: String] = [:]
        for token in tokens {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw MarkdownImportError.malformedDirective(line, lineNumber)
            }
            result[String(parts[0])] = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return result
    }

    private static func enumValue<T: RawRepresentable>(
        _ type: T.Type,
        field: String,
        value: String,
        line: Int
    ) throws -> T where T.RawValue == String {
        guard let result = T(rawValue: value) else {
            throw MarkdownImportError.invalidEnum(field, value, line)
        }
        return result
    }

    private static func commaValues<T: RawRepresentable>(
        _ value: String,
        as type: T.Type,
        field: String,
        line: Int
    ) throws -> [T] where T.RawValue == String {
        try commaStrings(value).map { try enumValue(type, field: field, value: $0, line: line) }
    }

    private static func commaStrings(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseOptions(_ lines: [String]) -> [QuestionOption] {
        lines.compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces).replacing(/^[-*]\s*/, with: "")
            let components = cleaned.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard components.count == 2 else { return nil }
            return QuestionOption(id: String(components[0]), text: String(components[1]))
        }
    }

    private static func parseAccepted(_ lines: [String], setting: String) -> [String] {
        let lineValues = lines.compactMap { line -> String? in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("- ") { value.removeFirst(2) }
            return value.isEmpty ? nil : value
        }
        if !lineValues.isEmpty { return lineValues }
        if setting.contains("||") {
            return setting
                .components(separatedBy: "||")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return commaStrings(setting)
    }

    private static func parseColumns(_ lines: [String]) -> [String] {
        clean(lines).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func parseSettings(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            let components = line.split(separator: ":", maxSplits: 1)
            guard components.count == 2 else { continue }
            result[String(components[0]).trimmingCharacters(in: .whitespaces)] = String(components[1]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func parsePairs(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            let cleaned = line.trimmingCharacters(in: .whitespaces).replacing(/^[-*]\s*/, with: "")
            let components = cleaned.components(separatedBy: "=>")
            guard components.count == 2 else { continue }
            result[components[0].trimmingCharacters(in: .whitespaces)] = components[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func parseListIDs(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces).replacing(/^[-*]\s*/, with: "") }.filter { !$0.isEmpty }
    }

    private static func parseMarkdownTable(_ lines: [String]) -> [[String]] {
        let parsed = lines.compactMap { line -> [String]? in
            guard line.contains("|") else { return nil }
            let cells = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) else { return nil }
            return cells
        }
        return parsed.count > 1 ? Array(parsed.dropFirst()) : parsed
    }

    private static func clean(_ lines: [String]) -> String {
        clean(lines.joined(separator: "\n"))
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func extractLegacyID(from heading: String) -> String? {
        if let start = heading.firstIndex(of: "`"),
           let end = heading[heading.index(after: start)...].firstIndex(of: "`") {
            return String(heading[heading.index(after: start)..<end])
        }
        if heading.hasPrefix("## Item ") {
            let suffix = heading.dropFirst("## Item ".count)
            return "item-" + suffix.prefix { $0.isNumber }
        }
        return nil
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .prefix(6)
            .joined(separator: "-")
    }

    private static func defaultFormat(for kind: ResponseKind) -> QuestionFormat {
        switch kind {
        case .singleChoice, .multipleChoice: .multipleChoice
        case .number: .singleNumber
        case .formula: .formulaSetup
        case .shortText, .longText: .shortExplanation
        case .journal: .initialJournalEntry
        case .table: .multiPeriodSchedule
        case .matching: .matchingMappingSorting
        case .ordering: .orderingTimeline
        case .trueFalse: .trueFalseCorrection
        case .noEntry: .entryOrNoEntry
        }
    }
}
