import Foundation

public struct QuestionTitlePresentation: Equatable, Sendable {
    public let title: String
    public let learningObjective: String?
    public let verification: String?
}

public struct QuestionPromptPresentation: Equatable, Sendable {
    public let body: String
    public let importDetails: [(label: String, value: String)]

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.body == rhs.body
            && lhs.importDetails.map { [$0.label, $0.value] }
                == rhs.importDetails.map { [$0.label, $0.value] }
    }
}

public extension AccountingQuestion {
    var titlePresentation: QuestionTitlePresentation {
        TitlePresentation.title(
            rawTitle: title,
            prompt: parts.first?.promptMarkdown ?? "",
            fallbackID: id
        )
    }

    var displayTitle: String { titlePresentation.title }
}

public extension QuestionPart {
    var promptPresentation: QuestionPromptPresentation {
        TitlePresentation.prompt(promptMarkdown)
    }
}

enum TitlePresentation {
    static func title(rawTitle: String, prompt: String, fallbackID: String) -> QuestionTitlePresentation {
        let learningObjective = extractLearningObjective(rawTitle)
            ?? metadataValue(prompt, label: "LO").flatMap(extractLearningObjective)
        let verification = extractVerification(rawTitle)
            ?? metadataValue(prompt, label: "Set status").map(humanizeVerification)
        let outer = cleanTransportTitle(rawTitle)
        let candidate = embeddedQuestionTitle(prompt) ?? outer
        let cleaned = normalizePunctuation(candidate)
        return QuestionTitlePresentation(
            title: cleaned.isEmpty ? humanizeFallbackID(fallbackID) : cleaned,
            learningObjective: learningObjective,
            verification: verification
        )
    }

    static func prompt(_ markdown: String) -> QuestionPromptPresentation {
        let knownLabels: Set<String> = [
            "lo", "concept", "set position", "set status", "provenance",
            "source-unit handling", "derived from", "derivation",
            "derived-verification requirement", "question-set status"
        ]
        let lines = markdown.components(separatedBy: .newlines)
        var bodyStart = 0
        var details: [(label: String, value: String)] = []
        var sawPreamble = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if sawPreamble { bodyStart = index + 1 }
                continue
            }
            if isTransportHeading(trimmed) {
                sawPreamble = true
                bodyStart = index + 1
                continue
            }
            if let detail = metadataLine(trimmed), knownLabels.contains(detail.label.lowercased()) {
                details.append(detail)
                sawPreamble = true
                bodyStart = index + 1
                continue
            }
            break
        }

        while bodyStart < lines.count,
              lines[bodyStart].trimmingCharacters(in: .whitespaces).isEmpty {
            bodyStart += 1
        }
        if bodyStart < lines.count, isEmbeddedBankHeading(lines[bodyStart]) {
            bodyStart += 1
            while bodyStart < lines.count,
                  lines[bodyStart].trimmingCharacters(in: .whitespaces).isEmpty {
                bodyStart += 1
            }
        }
        let body = lines.dropFirst(bodyStart).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return QuestionPromptPresentation(
            body: body.isEmpty ? markdown.trimmingCharacters(in: .whitespacesAndNewlines) : body,
            importDetails: details
        )
    }

    static func normalizedImportTitle(_ rawTitle: String, prompt: String, fallbackID: String) -> String {
        title(rawTitle: rawTitle, prompt: prompt, fallbackID: fallbackID).title
    }

    private static func embeddedQuestionTitle(_ prompt: String) -> String? {
        for line in prompt.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let heading: String
            if trimmed.hasPrefix("### ") {
                heading = String(trimmed.dropFirst(4))
            } else if trimmed.hasPrefix("## ") {
                heading = String(trimmed.dropFirst(3))
            } else {
                continue
            }
            guard !isTransportHeading(trimmed) else { continue }
            let cleaned = cleanInline(heading)
            let lowered = cleaned.lowercased()
            guard !["scenario", "required", "answer", "answer key", "model answer"].contains(lowered) else {
                continue
            }
            let segments = cleaned.split(separator: "—").map { $0.trimmingCharacters(in: .whitespaces) }
            if segments.count >= 2, isQuestionMarker(segments[0]) || isBankStatus(segments[0]) {
                let semantic = segments.drop(while: { isQuestionMarker($0) || isBankStatus($0) })
                    .joined(separator: " — ")
                if !semantic.isEmpty { return semantic }
            } else if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private static func cleanTransportTitle(_ raw: String) -> String {
        let cleaned = cleanInline(raw.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
        let segments = cleaned.split(separator: "—").map { $0.trimmingCharacters(in: .whitespaces) }
        guard segments.count > 1 else { return stripNumberedItemPrefix(cleaned) ?? cleaned }
        let semantic = segments.filter {
            !isIdentifier($0) && !isBankStatus($0) && extractLearningObjective($0) == nil
        }.joined(separator: " — ")
        return semantic.isEmpty ? cleaned : semantic
    }

    private static func stripNumberedItemPrefix(_ value: String) -> String? {
        let lowered = value.lowercased()
        guard lowered.hasPrefix("item ") else { return nil }
        let suffix = value.dropFirst(5)
        let digits = suffix.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let semantic = suffix.dropFirst(digits.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":—- "))
        return semantic.isEmpty ? nil : semantic
    }

    private static func isTransportHeading(_ line: String) -> Bool {
        let heading: String
        if line.hasPrefix("### ") { heading = String(line.dropFirst(4)) }
        else if line.hasPrefix("## ") { heading = String(line.dropFirst(3)) }
        else { return false }
        let segments = cleanInline(heading).split(separator: "—").map(String.init)
        return segments.contains(where: isIdentifier)
            || (segments.contains(where: { extractLearningObjective($0) != nil })
                && segments.contains(where: isBankStatus))
    }

    private static func metadataLine(_ line: String) -> (label: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let unquoted = trimmed.hasPrefix(">")
            ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            : trimmed
        guard unquoted.hasPrefix("**") else { return nil }
        let content = unquoted.dropFirst(2)
        guard let range = content.range(of: ":**") else { return nil }
        let label = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let value = cleanInline(String(content[range.upperBound...]))
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return (label, value)
    }

    private static func isEmbeddedBankHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let heading: String
        if trimmed.hasPrefix("### ") { heading = String(trimmed.dropFirst(4)) }
        else if trimmed.hasPrefix("## ") { heading = String(trimmed.dropFirst(3)) }
        else { return false }
        let segments = cleanInline(heading).split(separator: "—").map(String.init)
        return segments.first.map(isQuestionMarker) == true && segments.contains(where: isBankStatus)
    }

    private static func metadataValue(_ prompt: String, label: String) -> String? {
        prompt.components(separatedBy: .newlines).compactMap(metadataLine).first {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }?.value
    }

    private static func extractLearningObjective(_ value: String) -> String? {
        let words = cleanInline(value).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for index in words.indices.dropLast() where words[index].caseInsensitiveCompare("LO") == .orderedSame {
            let number = words[index + 1]
            if !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "-" }) {
                return "LO \(number)"
            }
        }
        return nil
    }

    private static func extractVerification(_ value: String) -> String? {
        value.split(separator: "—").map(String.init).first(where: isBankStatus).map(humanizeVerification)
    }

    private static func humanizeVerification(_ value: String) -> String {
        let lowered = cleanInline(value).replacingOccurrences(of: "-", with: " ").lowercased()
        if lowered.contains("derived") && lowered.contains("verified") { return "Derived · verified" }
        if lowered.contains("original") && lowered.contains("verified") { return "Original · verified" }
        if lowered.contains("unverified") { return "Needs verification" }
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }

    private static func isQuestionMarker(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespaces).lowercased()
        if lowered.hasPrefix("q") { return lowered.dropFirst().allSatisfy(\.isNumber) }
        if lowered.hasPrefix("question ") { return lowered.dropFirst(9).allSatisfy(\.isNumber) }
        return false
    }

    private static func isIdentifier(_ value: String) -> Bool {
        let lowered = cleanInline(value).lowercased()
        return lowered.hasPrefix("acct343-") || lowered.hasPrefix("core_")
            || lowered.hasPrefix("item-") || lowered.hasPrefix("item ") || lowered.hasPrefix("legacy-")
    }

    private static func isBankStatus(_ value: String) -> Bool {
        [
            "CORE", "CORE DEMO", "CORE DEMO (VERIFIED)", "ORIGINAL-VERIFIED",
            "DERIVED-VERIFIED", "ORIGINAL VERIFIED", "DERIVED VERIFIED", "VERIFIED", "UNVERIFIED"
        ].contains(cleanInline(value).uppercased())
    }

    private static func normalizePunctuation(_ value: String) -> String {
        cleanInline(value.replacingOccurrences(of: " + ", with: " and "))
            .trimmingCharacters(in: CharacterSet(charactersIn: "—-: "))
    }

    private static func cleanInline(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func humanizeFallbackID(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = words.first else { return "Untitled question" }
        return first.uppercased() + words.dropFirst()
    }
}
