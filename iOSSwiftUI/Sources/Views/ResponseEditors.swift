import AccountingQuestionKit
import SwiftUI

struct PartResponseEditor: View {
    let part: QuestionPart
    @Binding var answer: StudentAnswer
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch ResponseEditorPolicy.family(for: part.kind) {
            case .singleChoice:
                SingleChoiceEditor(options: part.options, answer: $answer)
            case .multipleChoice:
                MultipleChoiceEditor(options: part.options, answer: $answer)
            case .number:
                ScalarResponseEditor(
                    mode: .number,
                    answer: $answer,
                    onSubmit: onSubmit
                )
            case .formula:
                ScalarResponseEditor(
                    mode: .formula,
                    answer: $answer,
                    onSubmit: onSubmit
                )
            case .shortText:
                ScalarResponseEditor(
                    mode: .shortText,
                    answer: $answer,
                    onSubmit: onSubmit
                )
            case .longText:
                LongTextResponseEditor(answer: $answer)
            case .journalEntry, .table:
                SpreadsheetResponseEditor(
                    partID: part.id,
                    columns: part.stableColumns,
                    suggestedRowCount: ResponseEditorPolicy.initialRowCount(for: part),
                    answer: $answer
                )
            case .matching:
                MatchingResponseEditor(
                    items: part.items,
                    targets: part.targets,
                    answer: $answer
                )
            case .ordering:
                OrderingResponseEditor(items: part.items, answer: $answer)
            case .trueFalseCorrection:
                TrueFalseResponseEditor(answer: $answer)
            case .noEntryDecision:
                EntryDecisionResponseEditor(answer: $answer)
            }
        }
        .id(part.id)
    }
}

private struct SingleChoiceEditor: View {
    let options: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if options.isEmpty {
                MissingResponseConfiguration(
                    title: "No answer choices",
                    description: "This imported part does not contain any choices."
                )
            } else {
                ForEach(options.uniqueByID) { option in
                    ChoiceButton(
                        option: option,
                        isSelected: answer.selections == [option.id]
                    ) {
                        answer.selections = [option.id]
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answer choices")
        .task {
            let normalized = SelectionAnswerPolicy.normalizedSelections(
                answer.selections,
                options: options,
                allowsMultiple: false
            )
            if normalized != answer.selections {
                answer.selections = normalized
            }
        }
    }
}

private struct MultipleChoiceEditor: View {
    let options: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if options.isEmpty {
                MissingResponseConfiguration(
                    title: "No answer choices",
                    description: "This imported part does not contain any choices."
                )
            } else {
                ForEach(options.uniqueByID) { option in
                    Toggle(isOn: $answer[selection: option.id]) {
                        ChoiceLabel(option: option, isSelected: answer[selection: option.id])
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to include or remove this answer.")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Select all answers that apply")
        .task {
            let normalized = SelectionAnswerPolicy.normalizedSelections(
                answer.selections,
                options: options,
                allowsMultiple: true
            )
            if normalized != answer.selections {
                answer.selections = normalized
            }
        }
    }
}

private struct ChoiceButton: View {
    let option: QuestionOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChoiceLabel(option: option, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to choose this answer.")
    }
}

private struct ChoiceLabel: View {
    let option: QuestionOption
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(option.id)
                .font(.subheadline.bold())
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            Text(option.text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color(uiColor: .tertiarySystemGroupedBackground)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.55)
                        : Color(uiColor: .separator).opacity(0.25),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ScalarResponseEditor: View {
    enum Mode {
        case number
        case formula
        case shortText

        var prompt: LocalizedStringResource {
            switch self {
            case .number: "Enter amount"
            case .formula: "Enter formula"
            case .shortText: "Enter response"
            }
        }

        var accessibilityHint: LocalizedStringResource {
            switch self {
            case .number: "Accounting notation such as commas, parentheses, and decimals is accepted."
            case .formula: "Enter the requested variables and operators."
            case .shortText: "Enter a concise response, then press Return to check it."
            }
        }
    }

    let mode: Mode
    @Binding var answer: StudentAnswer
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(mode.prompt, text: $answer.scalar, axis: .vertical)
                .font(.title3)
                .fontDesign(mode == .shortText ? .default : .monospaced)
                .lineLimit(1...4)
                .textInputAutocapitalization(mode == .shortText ? .sentences : .never)
                .autocorrectionDisabled(mode != .shortText)
                .keyboardType(mode == .number ? .decimalPad : .default)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .modifier(ResponseFieldChrome())
                .accessibilityLabel(mode.prompt)
                .accessibilityHint(mode.accessibilityHint)

            if mode == .formula {
                StandaloneFormulaEvaluationLabel(
                    presentation: StandaloneFormulaPresentationEngine.evaluate(answer.scalar)
                )
            }
        }
    }
}

struct StandaloneFormulaPresentation: Equatable, Sendable {
    let displayText: String
    let errorMessage: String?
}

enum StandaloneFormulaPresentationEngine {
    static func evaluate(_ rawFormula: String) -> StandaloneFormulaPresentation? {
        let formula = rawFormula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formula.isEmpty else { return nil }
        let value = SpreadsheetEngine.evaluateFormula(formula)
        let errorMessage: String?
        if value.error == .reference {
            errorMessage = String(
                localized: "Cell references are available only in spreadsheet responses (#REF!).",
                comment: "Standalone formula validation error when the user enters an A1-style cell reference."
            )
        } else {
            errorMessage = value.error?.studyMessage
        }
        return StandaloneFormulaPresentation(
            displayText: value.displayString,
            errorMessage: errorMessage
        )
    }
}

private struct StandaloneFormulaEvaluationLabel: View {
    let presentation: StandaloneFormulaPresentation?

    var body: some View {
        if let errorMessage = presentation?.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Formula error: \(errorMessage)")
        } else if let presentation, !presentation.displayText.isEmpty {
            Label(presentation.displayText, systemImage: "equal")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("Evaluated value: \(presentation.displayText)")
        }
    }
}

private struct LongTextResponseEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your response")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $answer.scalar)
                .font(.body)
                .fontDesign(.serif)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 190)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                }
                .accessibilityLabel("Written response")
                .accessibilityHint("Write your answer before opening the rubric for self-review.")

            Text("\(answer.scalar.count) characters")
                .font(.caption)
                .fontDesign(.monospaced)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("\(answer.scalar.count) characters")
        }
    }
}

private struct MatchingResponseEditor: View {
    let items: [QuestionOption]
    let targets: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty || targets.isEmpty {
                MissingResponseConfiguration(
                    title: "Matching data unavailable",
                    description: "This imported part needs both items and matching targets."
                )
            }
            ForEach(items.uniqueByID) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.text)
                        .font(.body.weight(.medium))
                    Picker(
                        selection: $answer[matchFor: item.id],
                        content: {
                            Text("Choose a match").tag("")
                            ForEach(targets.uniqueByID) { target in
                                Text(target.text).tag(target.id)
                            }
                        },
                        label: {
                            Text("Match for \(item.text)")
                        }
                    )
                    .pickerStyle(.menu)
                    .accessibilityValue(matchedTarget(for: item.id))
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                }
            }
        }
        .task {
            let normalized = MatchingAnswerPolicy.normalizedPairs(
                answer.pairs,
                items: items,
                targets: targets
            )
            if normalized != answer.pairs {
                answer.pairs = normalized
            }
        }
    }

    private func matchedTarget(for itemID: String) -> String {
        guard let targetID = answer.pairs[itemID],
              let target = targets.first(where: { $0.id == targetID }) else {
            return String(localized: "No match selected")
        }
        return target.text
    }
}

private struct OrderingResponseEditor: View {
    let items: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                MissingResponseConfiguration(
                    title: "Sequence unavailable",
                    description: "This imported part does not contain any items to arrange."
                )
            } else if answer.order.isEmpty {
                ContentUnavailableView {
                    Label("Build the sequence", systemImage: "list.number")
                } description: {
                    Text("Start with the listed items, then move each one earlier or later.")
                } actions: {
                    Button("Start arranging") {
                        answer.order = items.map(\.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(Array(answer.order.enumerated()), id: \.element) { index, itemID in
                    OrderingRow(
                        position: index + 1,
                        title: title(for: itemID),
                        canMoveEarlier: index > 0,
                        canMoveLater: index < answer.order.count - 1,
                        moveEarlier: {
                            answer.moveOrderItem(from: index, to: index - 1)
                        },
                        moveLater: {
                            answer.moveOrderItem(from: index, to: index + 1)
                        }
                    )
                }

                Button("Reset order") {
                    answer.order = []
                }
                .buttonStyle(.borderless)
            }
        }
        .task {
            let normalized = OrderingAnswerPolicy.normalizedOrder(answer.order, items: items)
            if normalized != answer.order {
                answer.order = normalized
            }
        }
    }

    private func title(for itemID: String) -> String {
        items.first(where: { $0.id == itemID })?.text ?? itemID
    }
}

private struct OrderingRow: View {
    let position: Int
    let title: String
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(position, format: .number)
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: moveEarlier) {
                Image(systemName: "arrow.up")
            }
            .disabled(!canMoveEarlier)
            .accessibilityLabel("Move \(title) earlier")
            Button(action: moveLater) {
                Image(systemName: "arrow.down")
            }
            .disabled(!canMoveLater)
            .accessibilityLabel("Move \(title) later")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TrueFalseResponseEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DecisionPicker(
                title: "Choose true or false",
                choices: [
                    DecisionChoice(id: "True", title: "True"),
                    DecisionChoice(id: "False", title: "False")
                ],
                selection: $answer.scalar
            )
            NotesResponseEditor(
                title: "Correction or explanation",
                prompt: "If the statement is false, explain the correction.",
                notes: $answer.notes
            )
        }
    }
}

private struct EntryDecisionResponseEditor: View {
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DecisionPicker(
                title: "Choose the accounting treatment",
                choices: [
                    DecisionChoice(id: "Entry", title: "Entry"),
                    DecisionChoice(id: "No entry", title: "No entry")
                ],
                selection: $answer.scalar
            )
            NotesResponseEditor(
                title: "Rationale",
                prompt: "Explain why the event does or does not require recognition.",
                notes: $answer.notes
            )
        }
    }
}

private struct DecisionChoice: Identifiable {
    let id: String
    let title: LocalizedStringResource
}

private struct DecisionPicker: View {
    let title: LocalizedStringResource
    let choices: [DecisionChoice]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Picker(
                selection: $selection,
                content: {
                    ForEach(choices) { choice in
                        Text(choice.title).tag(choice.id)
                    }
                },
                label: {
                    Text(title)
                }
            )
            .pickerStyle(.segmented)
            .accessibilityValue(accessibilityValue)
        }
    }

    private var accessibilityValue: Text {
        guard let selectedChoice = choices.first(where: { $0.id == selection }) else {
            return Text("No decision selected")
        }
        return Text(selectedChoice.title)
    }
}

private struct NotesResponseEditor: View {
    let title: LocalizedStringResource
    let prompt: LocalizedStringResource
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 17)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $notes)
                    .font(.body)
                    .fontDesign(.serif)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(6)
                    .accessibilityLabel(title)
                    .accessibilityHint(prompt)
            }
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

private struct MissingResponseConfiguration: View {
    let title: LocalizedStringResource
    let description: LocalizedStringResource

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResponseFieldChrome: ViewModifier {
    var compact = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 9 : 13)
            .background {
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.40), lineWidth: 0.5)
            }
    }
}
