import AccountingQuestionKit
import Foundation

enum ResponseEditorFamily: String, CaseIterable, Equatable, Sendable {
    case singleChoice
    case multipleChoice
    case number
    case formula
    case shortText
    case longText
    case journalEntry
    case table
    case matching
    case ordering
    case trueFalseCorrection
    case noEntryDecision
}

enum ResponseEditorPolicy {
    static func family(for kind: ResponseKind) -> ResponseEditorFamily {
        switch kind {
        case .singleChoice: .singleChoice
        case .multipleChoice: .multipleChoice
        case .number: .number
        case .formula: .formula
        case .shortText: .shortText
        case .longText: .longText
        case .journal: .journalEntry
        case .table: .table
        case .matching: .matching
        case .ordering: .ordering
        case .trueFalse: .trueFalseCorrection
        case .noEntry: .noEntryDecision
        }
    }

    static func initialRowCount(for part: QuestionPart) -> Int {
        switch part.kind {
        case .journal:
            max(part.expected.rows.count, 2)
        case .table:
            max(part.expected.rows.count, 1)
        default:
            0
        }
    }
}

enum ResponseCompletionPolicy {
    static func incompleteResult(
        for answer: StudentAnswer,
        part: QuestionPart
    ) -> GradeResult? {
        let decision = answer.scalar.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesAreEmpty = answer.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if part.kind == .trueFalse,
           decision.caseInsensitiveCompare("False") == .orderedSame,
           notesAreEmpty {
            return GradeResult(
                status: .unanswered,
                feedback: String(
                    localized: "Add a correction or explanation for a false statement before checking it.",
                    comment: "Validation feedback for a true-or-false response whose False choice requires an explanation."
                )
            )
        }

        if part.kind == .noEntry, !decision.isEmpty, notesAreEmpty {
            return GradeResult(
                status: .unanswered,
                feedback: String(
                    localized: "Add a rationale for the entry decision before checking it.",
                    comment: "Validation feedback for an entry-or-no-entry response with no rationale."
                )
            )
        }

        return nil
    }
}

enum SelectionAnswerPolicy {
    static func normalizedSelections(
        _ selections: [String],
        options: [QuestionOption],
        allowsMultiple: Bool
    ) -> [String] {
        let validIDs = Set(options.map(\.id))
        var seen = Set<String>()
        let validSelections = selections.filter { selection in
            validIDs.contains(selection) && seen.insert(selection).inserted
        }
        return allowsMultiple ? validSelections : Array(validSelections.prefix(1))
    }
}

enum MatchingAnswerPolicy {
    static func normalizedPairs(
        _ pairs: [String: String],
        items: [QuestionOption],
        targets: [QuestionOption]
    ) -> [String: String] {
        let itemIDs = Set(items.map(\.id))
        let targetIDs = Set(targets.map(\.id))
        return pairs.filter { itemIDs.contains($0.key) && targetIDs.contains($0.value) }
    }
}

enum OrderingAnswerPolicy {
    static func normalizedOrder(
        _ order: [String],
        items: [QuestionOption]
    ) -> [String] {
        guard !order.isEmpty else { return [] }
        let itemIDs = items.map(\.id)
        let validIDs = Set(itemIDs)
        var seen = Set<String>()
        var normalized = order.filter { identifier in
            validIDs.contains(identifier) && seen.insert(identifier).inserted
        }
        normalized.append(contentsOf: itemIDs.filter { seen.insert($0).inserted })
        return normalized
    }
}

extension Array where Element == QuestionOption {
    var uniqueByID: [QuestionOption] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension StudentAnswer {
    subscript(selection optionID: String) -> Bool {
        get { selections.contains(optionID) }
        set {
            if newValue {
                if !selections.contains(optionID) {
                    selections.append(optionID)
                }
            } else {
                selections.removeAll { $0 == optionID }
            }
        }
    }

    subscript(matchFor itemID: String) -> String {
        get { pairs[itemID] ?? "" }
        set {
            if newValue.isEmpty {
                pairs.removeValue(forKey: itemID)
            } else {
                pairs[itemID] = newValue
            }
        }
    }

    subscript(cell coordinate: AnswerCell) -> String {
        get {
            guard rows.indices.contains(coordinate.row),
                  rows[coordinate.row].indices.contains(coordinate.column) else {
                return ""
            }
            return rows[coordinate.row][coordinate.column]
        }
        set {
            ensureRows(coordinate.row + 1, columnCount: coordinate.column + 1)
            rows[coordinate.row][coordinate.column] = newValue
        }
    }

    mutating func ensureRows(_ count: Int, columnCount: Int) {
        guard count > 0, columnCount > 0 else { return }
        while rows.count < count {
            rows.append(Array(repeating: "", count: columnCount))
        }
        for rowIndex in rows.indices where rows[rowIndex].count < columnCount {
            rows[rowIndex].append(
                contentsOf: Array(
                    repeating: "",
                    count: columnCount - rows[rowIndex].count
                )
            )
        }
    }

    mutating func appendRow(columnCount: Int) {
        guard columnCount > 0 else { return }
        rows.append(Array(repeating: "", count: columnCount))
    }

    mutating func removeRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    mutating func moveOrderItem(from source: Int, to destination: Int) {
        guard order.indices.contains(source), order.indices.contains(destination), source != destination else {
            return
        }
        let item = order.remove(at: source)
        order.insert(item, at: destination)
    }
}
