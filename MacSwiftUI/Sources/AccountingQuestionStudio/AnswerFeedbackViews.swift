import AccountingQuestionKit
import SwiftUI

struct GradeFeedbackBanner: View {
    let result: GradeResult
    let isSelfReviewed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: displayedStatus.systemImage)
                .font(.title3)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayedTitle)
                    .font(.subheadline.weight(.semibold))
                Text(result.feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private var displayedStatus: GradeStatus {
        if result.status == .needsSelfReview && isSelfReviewed {
            return .correct
        }
        return result.status
    }

    private var displayedTitle: LocalizedStringResource {
        if result.status == .needsSelfReview && isSelfReviewed {
            return "Self-Review Complete"
        }
        return displayedStatus.localizedName
    }

    private var statusColor: Color {
        switch displayedStatus {
        case .correct: .green
        case .incorrect: .red
        case .needsSelfReview: .orange
        case .unanswered: .secondary
        }
    }
}

struct AnswerRevealView: View {
    let part: QuestionPart

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RevealedModelAnswer(part: part)

            if !part.rubricMarkdown.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Rubric", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                    MarkdownText(
                        markdown: part.rubricMarkdown,
                        font: .callout,
                        fontDesign: .default
                    )
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RevealedModelAnswer: View {
    let part: QuestionPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Model Answer", systemImage: "lightbulb.max")
                .font(.subheadline.weight(.semibold))

            switch part.kind {
            case .singleChoice, .multipleChoice:
                RevealedSelections(
                    selectionIDs: part.expected.selections,
                    options: part.options
                )
            case .number, .formula, .shortText, .longText, .trueFalse, .noEntry:
                MarkdownText(
                    markdown: part.expected.scalar.isEmpty
                        ? String(localized: "No model answer was supplied.")
                        : part.expected.scalar,
                    font: .body,
                    fontDesign: part.kind == .longText ? .serif : .monospaced
                )
            case .journal, .table:
                ReadOnlyAnswerTable(
                    columns: part.columns,
                    rows: part.expected.rows
                )
            case .matching:
                RevealedPairs(
                    pairs: part.expected.pairs,
                    items: part.items,
                    targets: part.targets
                )
            case .ordering:
                RevealedOrder(
                    order: part.expected.order,
                    items: part.items
                )
            }
        }
    }
}

private struct RevealedSelections: View {
    let selectionIDs: [String]
    let options: [QuestionOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if selectionIDs.isEmpty {
                Text("No model answer was supplied.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(identifiedStrings(selectionIDs)) { selection in
                    Label(
                        selectionText(for: selection.value),
                        systemImage: "checkmark"
                    )
                }
            }
        }
    }

    private func selectionText(for selectionID: String) -> String {
        let optionText = options.first(where: { $0.id == selectionID })?.text
        guard let optionText else { return selectionID }
        return "\(selectionID) — \(optionText)"
    }
}

private struct ReadOnlyAnswerTable: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        if columns.isEmpty || rows.isEmpty {
            Text("No model answer was supplied.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            Text(column)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 112, alignment: .leading)
                        }
                    }
                    Divider()
                    ForEach(identifiedRows(rows)) { identifiedRow in
                        GridRow {
                            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                                Text(
                                    identifiedRow.values.indices.contains(index)
                                        ? identifiedRow.values[index]
                                        : ""
                                )
                                .font(.body.monospaced())
                                .frame(minWidth: 112, alignment: .leading)
                                .accessibilityLabel(
                                    "\(column), row \(identifiedRow.position + 1)"
                                )
                            }
                        }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .background(
                .background.opacity(0.65),
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
    }
}

private struct RevealedPairs: View {
    let pairs: [String: String]
    let items: [QuestionOption]
    let targets: [QuestionOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if pairs.isEmpty {
                Text("No model answer was supplied.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    if let targetID = pairs[item.id] {
                        LabeledContent(item.text) {
                            Text(targetText(for: targetID))
                        }
                    }
                }
            }
        }
    }

    private func targetText(for targetID: String) -> String {
        targets.first(where: { $0.id == targetID })?.text ?? targetID
    }
}

private struct RevealedOrder: View {
    let order: [String]
    let items: [QuestionOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if order.isEmpty {
                Text("No model answer was supplied.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(identifiedStrings(order)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.position + 1, format: .number)
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(
                            items.first(where: { $0.id == item.value })?.text
                                ?? item.value
                        )
                    }
                }
            }
        }
    }
}

private struct IdentifiedStringOccurrence: Identifiable {
    let value: String
    let position: Int
    let occurrence: Int

    var id: String { "\(value)\u{1F}\(occurrence)" }
}

private func identifiedStrings(_ values: [String]) -> [IdentifiedStringOccurrence] {
    var occurrences: [String: Int] = [:]
    return values.enumerated().map { position, value in
        let occurrence = occurrences[value, default: 0]
        occurrences[value] = occurrence + 1
        return IdentifiedStringOccurrence(
            value: value,
            position: position,
            occurrence: occurrence
        )
    }
}

private struct IdentifiedTableRow: Identifiable {
    struct ID: Hashable {
        let values: [String]
        let occurrence: Int
    }

    let values: [String]
    let position: Int
    let occurrence: Int

    var id: ID { ID(values: values, occurrence: occurrence) }
}

private func identifiedRows(_ rows: [[String]]) -> [IdentifiedTableRow] {
    var occurrences: [[String]: Int] = [:]
    return rows.enumerated().map { position, values in
        let occurrence = occurrences[values, default: 0]
        occurrences[values] = occurrence + 1
        return IdentifiedTableRow(
            values: values,
            position: position,
            occurrence: occurrence
        )
    }
}
