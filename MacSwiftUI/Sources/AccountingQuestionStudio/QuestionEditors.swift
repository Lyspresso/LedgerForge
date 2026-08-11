import AccountingQuestionKit
import SwiftUI

struct QuestionEditorRouter: View {
    let part: QuestionPart
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issue = configurationIssue {
                LocalizedSystemLabel(
                    title: issue,
                    systemImage: "exclamationmark.triangle"
                )
                    .foregroundStyle(.orange)
                    .accessibilityAddTraits(.isHeader)
            } else {
                switch part.kind {
                case .singleChoice:
                    SingleChoiceEditor(options: part.options, answer: $answer)
                case .multipleChoice:
                    MultipleChoiceEditor(options: part.options, answer: $answer)
                case .number:
                    NumberAnswerEditor(answer: $answer)
                case .formula:
                    FormulaAnswerEditor(answer: $answer)
                case .shortText:
                    ShortTextAnswerEditor(answer: $answer)
                case .longText:
                    LongTextAnswerEditor(answer: $answer)
                case .journal:
                    JournalEntryEditor(columns: part.columns, answer: $answer)
                case .table:
                    AccountingTableEditor(columns: part.columns, answer: $answer)
                case .matching:
                    MatchingAnswerEditor(
                        items: part.items,
                        targets: part.targets,
                        answer: $answer
                    )
                case .ordering:
                    OrderingAnswerEditor(items: part.items, answer: $answer)
                case .trueFalse:
                    TrueFalseAnswerEditor(answer: $answer)
                case .noEntry:
                    EntryDecisionEditor(answer: $answer)
                }
            }
        }
    }

    private var configurationIssue: LocalizedStringResource? {
        switch part.kind {
        case .singleChoice, .multipleChoice:
            guard part.options.count >= 2 else {
                return "This choice question does not contain enough options."
            }
            guard Set(part.options.map(\.id)).count == part.options.count else {
                return "This choice question contains duplicate option IDs."
            }
        case .journal, .table:
            guard !part.columns.isEmpty else {
                return "This table question does not define any columns."
            }
        case .matching:
            guard !part.items.isEmpty, !part.targets.isEmpty else {
                return "This matching question is missing items or targets."
            }
            guard Set(part.items.map(\.id)).count == part.items.count,
                  Set(part.targets.map(\.id)).count == part.targets.count else {
                return "This matching question contains duplicate IDs."
            }
        case .ordering:
            guard !part.items.isEmpty else {
                return "This ordering question does not contain any items."
            }
            guard Set(part.items.map(\.id)).count == part.items.count else {
                return "This ordering question contains duplicate item IDs."
            }
        case .number, .formula, .shortText, .longText, .trueFalse, .noEntry:
            break
        }
        return nil
    }
}

struct SingleChoiceEditor: View {
    let options: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                ChoiceButton(
                    optionID: option.id,
                    text: option.text,
                    isSelected: answer.selections == [option.id],
                    allowsMultipleSelection: false
                ) {
                    answer.selections = [option.id]
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answer choices")
    }
}

struct MultipleChoiceEditor: View {
    let options: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select every answer that applies.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                ChoiceButton(
                    optionID: option.id,
                    text: option.text,
                    isSelected: answer.selections.contains(option.id),
                    allowsMultipleSelection: true
                ) {
                    toggle(option.id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Multiple answer choices")
    }

    private func toggle(_ optionID: String) {
        if answer.selections.contains(optionID) {
            answer.selections.removeAll(where: { $0 == optionID })
        } else {
            answer.selections.append(optionID)
        }
    }
}

private struct ChoiceButton: View {
    let optionID: String
    let text: String
    let isSelected: Bool
    let allowsMultipleSelection: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selectionImage)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(optionID)
                    .font(.body.monospaced())
                    .fontWeight(.semibold)
                    .frame(minWidth: 22, alignment: .leading)
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(optionID), \(text)")
        .accessibilityValue(selectionAccessibilityValue)
    }

    private var selectionImage: String {
        if allowsMultipleSelection {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }

    private var selectionAccessibilityValue: Text {
        isSelected ? Text("Selected") : Text("Not selected")
    }
}

struct NumberAnswerEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Amount, ratio, or rate")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Enter a number", text: $answer.scalar)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .monospacedDigit()
                .accessibilityHint("Accounting notation such as commas, currency symbols, and parentheses is accepted.")
        }
    }
}

struct FormulaAnswerEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Formula or spreadsheet function")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "function")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Enter a formula", text: $answer.scalar)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .accessibilityHint(
                        "Spreadsheet formulas beginning with an equals sign show a calculated preview."
                    )
            }

            if let value = StandaloneFormulaPreview.value(for: answer.scalar) {
                Label {
                    if let error = value.error {
                        Text("Formula error: \(error.rawValue)")
                    } else {
                        Text("Calculated value: \(value.displayString)")
                    }
                } icon: {
                    Image(
                        systemName: value.error == nil
                            ? "equal.circle"
                            : "exclamationmark.triangle.fill"
                    )
                }
                .font(.caption)
                .foregroundStyle(
                    value.error == nil ? Color.secondary : Color.red
                )
            }
        }
    }
}

enum StandaloneFormulaPreview {
    static func value(for rawFormula: String) -> SpreadsheetValue? {
        let formula = rawFormula.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard formula.hasPrefix("=") else { return nil }
        return SpreadsheetEngine.evaluateFormula(formula)
    }
}

struct ShortTextAnswerEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        TextField("Enter a concise response", text: $answer.scalar, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
    }
}

struct LongTextAnswerEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Write your analysis")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $answer.scalar)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }
                .accessibilityLabel("Written analysis")
        }
    }
}

struct TrueFalseAnswerEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Decision", selection: $answer.scalar) {
                Text("Choose…").tag("")
                Text("True").tag("True")
                Text("False").tag("False")
            }
            .pickerStyle(.segmented)

            TextField(
                "If false, write the corrected statement",
                text: $answer.notes,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
        }
    }
}

struct EntryDecisionEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Recognition decision", selection: $answer.scalar) {
                Text("Choose…").tag("")
                Text("Record an Entry").tag("Entry")
                Text("No Entry").tag("No entry")
            }
            .pickerStyle(.segmented)

            TextEditor(text: $answer.notes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 90)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }
                .accessibilityLabel("Rationale")
                .accessibilityHint(
                    "Explain why an entry should or should not be recorded."
                )
        }
    }
}
