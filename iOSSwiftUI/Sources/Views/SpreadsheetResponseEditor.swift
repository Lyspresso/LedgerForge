import AccountingQuestionKit
import SwiftUI

struct SpreadsheetCellPresentation: Equatable, Sendable {
    var displayText = ""
    var errorMessage: String?
    var isFormula = false

    var accessibilityDescription: String {
        if let errorMessage {
            return "Formula error: \(errorMessage)"
        }
        if isFormula, !displayText.isEmpty {
            return "Evaluated value: \(displayText)"
        }
        return displayText.isEmpty ? "Blank" : displayText
    }
}

struct SpreadsheetGridPresentation: Equatable, Sendable {
    var cells: [AnswerCell: SpreadsheetCellPresentation] = [:]

    subscript(_ cell: AnswerCell) -> SpreadsheetCellPresentation {
        cells[cell] ?? SpreadsheetCellPresentation()
    }
}

enum SpreadsheetCellNavigator {
    static func next(
        after cell: AnswerCell?,
        rowCount: Int,
        columnCount: Int
    ) -> AnswerCell? {
        guard rowCount > 0, columnCount > 0 else { return nil }
        guard let cell else { return AnswerCell(row: 0, column: 0) }
        let nextIndex = cell.row * columnCount + cell.column + 1
        guard nextIndex < rowCount * columnCount else { return nil }
        return AnswerCell(
            row: nextIndex / columnCount,
            column: nextIndex % columnCount
        )
    }

    static func previous(
        before cell: AnswerCell?,
        rowCount: Int,
        columnCount: Int
    ) -> AnswerCell? {
        guard rowCount > 0, columnCount > 0, let cell else { return nil }
        let previousIndex = cell.row * columnCount + cell.column - 1
        guard previousIndex >= 0 else { return nil }
        return AnswerCell(
            row: previousIndex / columnCount,
            column: previousIndex % columnCount
        )
    }
}

struct SpreadsheetResponseEditor: View {
    let partID: String
    let columns: [StableColumn]
    let suggestedRowCount: Int
    @Binding var answer: StudentAnswer
    @State private var rowIDs: [String]
    @State private var nextRowSequence: Int
    @State private var selectedCell: AnswerCell?
    @FocusState private var focusedCell: AnswerCell?
    @ScaledMetric(relativeTo: .body) private var cellWidth = 156.0
    @ScaledMetric(relativeTo: .body) private var rowHeaderWidth = 46.0

    init(
        partID: String,
        columns: [StableColumn],
        suggestedRowCount: Int,
        answer: Binding<StudentAnswer>
    ) {
        self.partID = partID
        self.columns = columns
        self.suggestedRowCount = suggestedRowCount
        self._answer = answer
        let initialCount = max(max(answer.wrappedValue.rows.count, suggestedRowCount), 1)
        self._rowIDs = State(
            initialValue: (0..<initialCount).map { "\(partID)-row-\($0)" }
        )
        self._nextRowSequence = State(initialValue: initialCount)
        self._selectedCell = State(
            initialValue: columns.isEmpty ? nil : AnswerCell(row: 0, column: 0)
        )
    }

    var body: some View {
        let presentation = SpreadsheetPresentationEngine.evaluate(rows: answer.rows)

        VStack(alignment: .leading, spacing: 12) {
            SpreadsheetFormulaBar(
                selectedCell: selectedCell,
                rawText: selectedCell.map(cellBinding),
                presentation: selectedCell.map { presentation[$0] },
                canMovePrevious: previousCell != nil,
                canMoveNext: nextCell != nil,
                movePrevious: movePrevious,
                moveNext: moveNext
            )

            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("ROW")
                            .font(.caption.smallCaps().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: rowHeaderWidth, alignment: .leading)
                        ForEach(columns) { column in
                            Text(column.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: cellWidth, alignment: .leading)
                        }
                        Color.clear
                            .frame(width: 44, height: 1)
                            .accessibilityHidden(true)
                    }

                    ForEach(Array(rowIDs.enumerated()), id: \.element) { rowIndex, rowID in
                        GridRow {
                            Text(rowIndex + 1, format: .number)
                                .font(.caption.bold())
                                .fontDesign(.monospaced)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: rowHeaderWidth, alignment: .leading)

                            ForEach(Array(columns.enumerated()), id: \.element.id) { columnIndex, column in
                                let cell = AnswerCell(row: rowIndex, column: columnIndex)
                                SpreadsheetCellEditor(
                                    coordinate: cell,
                                    columnTitle: column.title,
                                    rawText: cellBinding(cell),
                                    presentation: presentation[cell],
                                    width: cellWidth,
                                    focus: $focusedCell,
                                    select: {
                                        selectedCell = cell
                                    },
                                    moveNext: moveNext
                                )
                            }

                            Button(role: .destructive) {
                                removeRow(id: rowID)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(rowIDs.count == 1)
                            .accessibilityLabel("Remove row \(rowIndex + 1)")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 460)
            .scrollIndicators(.visible)
            .accessibilityLabel("Accounting spreadsheet")
            .accessibilityValue("\(rowIDs.count) rows and \(columns.count) columns")

            HStack(spacing: 10) {
                Button {
                    addRow()
                } label: {
                    Label("Add row", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Adds another blank spreadsheet row.")

                Spacer(minLength: 8)

                Label("Use = to enter a formula", systemImage: "function")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            answer.ensureRows(max(suggestedRowCount, 1), columnCount: columns.count)
        }
        .onChange(of: focusedCell) { _, newValue in
            if let newValue {
                selectedCell = newValue
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous", action: movePrevious)
                    .disabled(previousCell == nil)
                Button("Next", action: moveNext)
                    .disabled(nextCell == nil)
            }
        }
    }

    private var previousCell: AnswerCell? {
        SpreadsheetCellNavigator.previous(
            before: selectedCell,
            rowCount: rowIDs.count,
            columnCount: columns.count
        )
    }

    private var nextCell: AnswerCell? {
        SpreadsheetCellNavigator.next(
            after: selectedCell,
            rowCount: rowIDs.count,
            columnCount: columns.count
        )
    }

    private func cellBinding(_ cell: AnswerCell) -> Binding<String> {
        Binding(
            get: { answer[cell: cell] },
            set: { answer[cell: cell] = $0 }
        )
    }

    private func movePrevious() {
        guard let previousCell else { return }
        selectAndFocus(previousCell)
    }

    private func moveNext() {
        guard let nextCell else { return }
        selectAndFocus(nextCell)
    }

    private func selectAndFocus(_ cell: AnswerCell) {
        selectedCell = cell
        focusedCell = cell
    }

    private func addRow() {
        answer.appendRow(columnCount: columns.count)
        rowIDs.append("\(partID)-row-added-\(nextRowSequence)")
        nextRowSequence += 1
    }

    private func removeRow(id: String) {
        guard rowIDs.count > 1,
              let stableIndex = rowIDs.firstIndex(of: id) else { return }
        rowIDs.remove(at: stableIndex)
        answer.removeRow(at: stableIndex)
        adjustSelectionAfterRemovingRow(stableIndex)
    }

    private func adjustSelectionAfterRemovingRow(_ removedIndex: Int) {
        guard let selectedCell else { return }
        if selectedCell.row == removedIndex {
            let replacement = AnswerCell(
                row: min(removedIndex, rowIDs.count - 1),
                column: selectedCell.column
            )
            self.selectedCell = replacement
            focusedCell = replacement
        } else if selectedCell.row > removedIndex {
            let replacement = AnswerCell(
                row: selectedCell.row - 1,
                column: selectedCell.column
            )
            self.selectedCell = replacement
            if focusedCell != nil {
                focusedCell = replacement
            }
        }
    }
}

private struct SpreadsheetFormulaBar: View {
    let selectedCell: AnswerCell?
    let rawText: Binding<String>?
    let presentation: SpreadsheetCellPresentation?
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let movePrevious: () -> Void
    let moveNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Formula bar", systemImage: "function")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: movePrevious) {
                    Image(systemName: "chevron.backward")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canMovePrevious)
                .accessibilityLabel("Previous spreadsheet cell")
                Button(action: moveNext) {
                    Image(systemName: "chevron.forward")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveNext)
                .accessibilityLabel("Next spreadsheet cell")
            }

            if let selectedCell, let rawText {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(selectedCell.spreadsheetReference)
                        .font(.body.bold())
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tint)
                        .frame(minWidth: 38, alignment: .leading)
                    TextField("Value or =formula", text: rawText)
                        .font(.body)
                        .fontDesign(.monospaced)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit(moveNext)
                        .accessibilityLabel("Formula bar for \(selectedCell.spreadsheetReference)")
                }

                SpreadsheetEvaluationLabel(presentation: presentation)
            } else {
                Text("Select a cell to view or edit its exact input.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}

private struct SpreadsheetCellEditor: View {
    let coordinate: AnswerCell
    let columnTitle: String
    @Binding var rawText: String
    let presentation: SpreadsheetCellPresentation
    let width: CGFloat
    let focus: FocusState<AnswerCell?>.Binding
    let select: () -> Void
    let moveNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(columnTitle, text: $rawText)
                .font(.body)
                .fontDesign(.monospaced)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(rawText.hasPrefix("="))
                .submitLabel(.next)
                .onSubmit(moveNext)
                .focused(focus, equals: coordinate)
                .onTapGesture(perform: select)
                .frame(minHeight: 24)
                .accessibilityLabel("\(coordinate.spreadsheetReference), row \(coordinate.row + 1), \(columnTitle)")
                .accessibilityValue("Input \(rawText.isEmpty ? "blank" : rawText). \(presentation.accessibilityDescription)")
                .accessibilityHint("Enter a value or a formula beginning with equals. Return moves to the next cell.")

            if presentation.isFormula {
                SpreadsheetEvaluationLabel(presentation: presentation)
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 44, alignment: .leading)
        .modifier(ResponseFieldChrome(compact: true))
        .accessibilityElement(children: .contain)
    }
}

private struct SpreadsheetEvaluationLabel: View {
    let presentation: SpreadsheetCellPresentation?

    var body: some View {
        if let errorMessage = presentation?.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let presentation, presentation.isFormula, !presentation.displayText.isEmpty {
            Label(presentation.displayText, systemImage: "equal")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

extension AnswerCell {
    var spreadsheetReference: String {
        SpreadsheetEngine.address(row: row, column: column)
    }
}

enum SpreadsheetPresentationEngine {
    static func evaluate(rows: [[String]]) -> SpreadsheetGridPresentation {
        let evaluation = SpreadsheetEngine.evaluate(rows: rows)
        var result = SpreadsheetGridPresentation()
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, rawText) in row.enumerated() where !rawText.isEmpty {
                let cell = AnswerCell(row: rowIndex, column: columnIndex)
                let value = evaluation[row: rowIndex, column: columnIndex]
                result.cells[cell] = SpreadsheetCellPresentation(
                    displayText: value.displayString,
                    errorMessage: value.error?.studyMessage,
                    isFormula: rawText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=")
                )
            }
        }
        return result
    }
}

extension SpreadsheetError {
    var studyMessage: String {
        switch self {
        case .reference:
            String(
                localized: "Invalid cell reference (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token, such as #REF!."
            )
        case .value:
            String(
                localized: "A value has the wrong type (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token, such as #VALUE!."
            )
        case .divideByZero:
            String(
                localized: "Cannot divide by zero (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token #DIV/0!."
            )
        case .name:
            String(
                localized: "Unknown function or name (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token #NAME?."
            )
        case .cycle:
            String(
                localized: "Circular cell reference (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token #CYCLE!."
            )
        case .number:
            String(
                localized: "Invalid numeric result (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token #NUM!."
            )
        case .parse:
            String(
                localized: "Formula could not be parsed (\(rawValue))",
                comment: "Spreadsheet error. The variable is the spreadsheet error token #PARSE!."
            )
        }
    }
}
