import Foundation

public enum GradeStatus: String, Codable, Equatable, Sendable {
    case correct
    case incorrect
    case needsSelfReview = "needs_self_review"
    case unanswered
}

public struct GradeResult: Codable, Equatable, Sendable {
    public var status: GradeStatus
    public var feedback: String

    public init(status: GradeStatus, feedback: String) {
        self.status = status
        self.feedback = feedback
    }
}

public enum AnswerGrader {
    public static func grade(_ answer: StudentAnswer, for part: QuestionPart) -> GradeResult {
        if answer.isBlank {
            return GradeResult(status: .unanswered, feedback: "Enter a response before checking it.")
        }

        switch part.kind {
        case .singleChoice:
            return exactSelection(answer.selections, part.expected.selections)
        case .multipleChoice:
            return exactSelection(answer.selections.sorted(), part.expected.selections.sorted())
        case .number:
            return gradeNumber(answer.scalar, expected: part.expected.scalar, tolerance: part.expected.tolerance ?? 0)
        case .formula:
            return exactScalar(answer.scalar, part.expected.scalar, accepted: part.expected.accepted, formula: true)
        case .shortText:
            if part.expected.accepted.isEmpty {
                return selfReview()
            }
            return exactScalar(answer.scalar, part.expected.scalar, accepted: part.expected.accepted)
        case .longText:
            return selfReview()
        case .journal, .table:
            return gradeRows(answer.rows, expected: part.expected.rows, rowOrderAny: part.settings["row_order"] == "any")
        case .matching:
            return answer.pairs == part.expected.pairs
                ? GradeResult(status: .correct, feedback: "Every match is correct.")
                : GradeResult(status: .incorrect, feedback: "One or more matches need another look.")
        case .ordering:
            return answer.order == part.expected.order
                ? GradeResult(status: .correct, feedback: "The complete sequence is correct.")
                : GradeResult(status: .incorrect, feedback: "The sequence is not yet correct.")
        case .trueFalse:
            let result = exactScalar(answer.scalar, part.expected.scalar, accepted: part.expected.accepted)
            if result.status == .correct,
               normalizeText(part.expected.scalar) == "false",
               !part.rubricMarkdown.isEmpty
            {
                return GradeResult(
                    status: .needsSelfReview,
                    feedback: "The true-or-false decision is correct. Compare your correction with the rubric."
                )
            }
            return result
        case .noEntry:
            let result = exactScalar(answer.scalar, part.expected.scalar, accepted: part.expected.accepted)
            if result.status == .correct && !part.rubricMarkdown.isEmpty {
                return GradeResult(status: .needsSelfReview, feedback: "The entry decision is correct. Compare your rationale with the rubric.")
            }
            return result
        }
    }

    private static func exactSelection(_ actual: [String], _ expected: [String]) -> GradeResult {
        actual == expected
            ? GradeResult(status: .correct, feedback: "Correct selection.")
            : GradeResult(status: .incorrect, feedback: "That selection is not correct yet.")
    }

    private static func exactScalar(
        _ actual: String,
        _ expected: String,
        accepted: [String] = [],
        formula: Bool = false
    ) -> GradeResult {
        let normalizer: (String) -> String = { value in
            formula ? normalizeFormula(value) : normalizeText(value)
        }
        let candidates = ([expected] + accepted).map(normalizer)
        return candidates.contains(normalizer(actual))
            ? GradeResult(status: .correct, feedback: "Correct.")
            : GradeResult(status: .incorrect, feedback: "Compare the response with the required form and try again.")
    }

    private static func gradeNumber(_ actual: String, expected: String, tolerance: Double) -> GradeResult {
        guard let actualValue = accountingNumber(actual), let expectedValue = accountingNumber(expected) else {
            return GradeResult(status: .incorrect, feedback: "Enter a valid accounting number.")
        }
        let difference = abs(actualValue - expectedValue)
        return difference <= tolerance
            ? GradeResult(status: .correct, feedback: "Correct within the allowed tolerance.")
            : GradeResult(status: .incorrect, feedback: "The amount is outside the allowed tolerance.")
    }

    private static func gradeRows(_ actual: [[String]], expected: [[String]], rowOrderAny: Bool) -> GradeResult {
        let normalizedActual = normalizedRows(
            SpreadsheetEngine.resolvedRowsForGrading(actual),
            sorted: rowOrderAny
        )
        let normalizedExpected = normalizedRows(
            SpreadsheetEngine.resolvedRowsForGrading(expected),
            sorted: rowOrderAny
        )
        return normalizedActual == normalizedExpected
            ? GradeResult(status: .correct, feedback: "Every required cell is correct.")
            : GradeResult(status: .incorrect, feedback: "At least one row or cell differs from the answer key.")
    }

    private static func normalizedRows(_ rows: [[String]], sorted: Bool) -> [[String]] {
        let normalized = rows
            .map { $0.map(normalizeCell) }
            .filter { !$0.allSatisfy(\.isEmpty) }
        return sorted ? normalized.sorted { $0.joined(separator: "|") < $1.joined(separator: "|") } : normalized
    }

    private static func normalizeText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizeFormula(_ value: String) -> String {
        var normalized = normalizeText(value)
            .replacingOccurrences(of: " ", with: "")
        if normalized.hasPrefix("=") {
            normalized.removeFirst()
        }
        return normalized
    }

    private static func normalizeCell(_ value: String) -> String {
        if let number = accountingNumber(value) {
            return String(format: "%.6f", number)
        }
        return normalizeText(value)
    }

    private static func accountingNumber(_ input: String) -> Double? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let negative = value.hasPrefix("(") && value.hasSuffix(")")
        value = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(value) else { return nil }
        return negative ? -number : number
    }

    private static func selfReview() -> GradeResult {
        GradeResult(
            status: .needsSelfReview,
            feedback: "This response requires judgment. Reveal the answer and mark your own work."
        )
    }
}
