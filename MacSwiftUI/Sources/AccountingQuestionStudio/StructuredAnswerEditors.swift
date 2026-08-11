import AccountingQuestionKit
import AppKit
import SwiftUI

private extension StudentAnswer {
    subscript(pairFor itemID: String) -> String {
        get { pairs[itemID, default: ""] }
        set {
            if newValue.isEmpty {
                pairs.removeValue(forKey: itemID)
            } else {
                pairs[itemID] = newValue
            }
        }
    }
}

struct JournalEntryEditor: View {
    let columns: [String]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Journal Entry", systemImage: "book.closed")
                .font(.subheadline.weight(.semibold))
            EditableAccountingGrid(
                columns: columns,
                minimumRowCount: 2,
                addButtonTitle: "Add Journal Line",
                rows: $answer.rows
            )
        }
    }
}

struct AccountingTableEditor: View {
    let columns: [String]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accounting Schedule", systemImage: "tablecells")
                .font(.subheadline.weight(.semibold))
            EditableAccountingGrid(
                columns: columns,
                minimumRowCount: 1,
                addButtonTitle: "Add Row",
                rows: $answer.rows
            )
        }
    }
}

private struct EditableAccountingGrid: View {
    let columns: [String]
    let minimumRowCount: Int
    let addButtonTitle: LocalizedStringResource
    @Binding var rows: [[String]]

    @State private var rowIDs: [UUID] = []
    @State private var selectedCell: SpreadsheetCellCoordinate?
    @FocusState private var focusedCell: SpreadsheetCellCoordinate?

    var body: some View {
        let evaluation = SpreadsheetEngine.evaluate(rows: rows)

        VStack(alignment: .leading, spacing: 10) {
            spreadsheetFormulaBar(evaluation: evaluation)

            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    AccountingGridHeader(columns: effectiveColumns)

                    Divider()

                    ForEach(Array(rowIDs.enumerated()), id: \.element) { rowIndex, _ in
                        if rows.indices.contains(rowIndex) {
                            AccountingGridRow(
                                rowIndex: rowIndex,
                                columns: effectiveColumns,
                                cells: $rows[rowIndex],
                                evaluation: evaluation,
                                focusedCell: $focusedCell,
                                canDelete: rows.count > minimumRowCount,
                                select: { coordinate in
                                    selectedCell = coordinate
                                },
                                submit: { coordinate in
                                    moveDown(from: coordinate)
                                },
                                delete: {
                                    removeRow(at: rowIndex)
                                }
                            )
                        }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }

            HStack(spacing: 12) {
                Button {
                    addRow()
                } label: {
                    LocalizedSystemLabel(title: addButtonTitle, systemImage: "plus")
                }
                .controlSize(.small)

                Button("Paste Cells", systemImage: "doc.on.clipboard") {
                    pasteCellsFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .controlSize(.small)
                .disabled(selectedCell == nil)
                .help("Paste tab- or line-separated cells starting at the selected cell")

                Text("Tab moves across cells; Return moves down. Shift-Command-V pastes a cell range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            prepareRows()
        }
        .onChange(of: rows.count) { _, _ in
            synchronizeRowIDs()
        }
        .onChange(of: columns) { _, _ in
            prepareRows()
        }
        .onChange(of: focusedCell) { _, newValue in
            guard let newValue else { return }
            selectedCell = newValue
        }
    }

    private var effectiveColumns: [String] {
        columns.isEmpty ? [String(localized: "Response")] : columns
    }

    private func prepareRows() {
        let targetCount = max(rows.count, minimumRowCount)
        while rows.count < targetCount {
            rows.append(blankRow())
        }
        for index in rows.indices {
            normalizeCellCount(at: index)
        }
        synchronizeRowIDs()
        normalizeSelection()
    }

    private func addRow() {
        rows.append(blankRow())
        rowIDs.append(UUID())
        let coordinate = SpreadsheetCellCoordinate(
            row: rows.index(before: rows.endIndex),
            column: 0
        )
        selectedCell = coordinate
        focusedCell = coordinate
    }

    private func removeRow(at index: Int) {
        guard rows.indices.contains(index), rowIDs.indices.contains(index) else {
            return
        }
        rows.remove(at: index)
        rowIDs.remove(at: index)
        normalizeSelection(afterRemovingRow: index)
    }

    private func blankRow() -> [String] {
        Array(repeating: "", count: effectiveColumns.count)
    }

    private func normalizeCellCount(at index: Int) {
        guard rows.indices.contains(index) else { return }
        if rows[index].count < effectiveColumns.count {
            rows[index].append(
                contentsOf: Array(
                    repeating: "",
                    count: effectiveColumns.count - rows[index].count
                )
            )
        } else if rows[index].count > effectiveColumns.count {
            rows[index].removeLast(rows[index].count - effectiveColumns.count)
        }
    }

    private func synchronizeRowIDs() {
        if rowIDs.count < rows.count {
            rowIDs.append(
                contentsOf: (rowIDs.count..<rows.count).map { _ in UUID() }
            )
        } else if rowIDs.count > rows.count {
            rowIDs.removeLast(rowIDs.count - rows.count)
        }
    }

    @ViewBuilder
    private func spreadsheetFormulaBar(
        evaluation: SpreadsheetEvaluation
    ) -> some View {
        if let selectedCell,
           rows.indices.contains(selectedCell.row),
           rows[selectedCell.row].indices.contains(selectedCell.column) {
            SpreadsheetFormulaBar(
                coordinate: selectedCell,
                rawValue: $rows[selectedCell.row][selectedCell.column],
                value: evaluation[
                    row: selectedCell.row,
                    column: selectedCell.column
                ]
            )
        } else {
            HStack(spacing: 8) {
                Text("—")
                    .font(.body.monospaced().weight(.semibold))
                    .frame(width: 42, alignment: .leading)
                Text("Select a cell to inspect or edit its raw value and calculated result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func moveDown(from coordinate: SpreadsheetCellCoordinate) {
        guard effectiveColumns.indices.contains(coordinate.column) else { return }
        if coordinate.row == rows.index(before: rows.endIndex) {
            rows.append(blankRow())
            rowIDs.append(UUID())
        }
        let destination = SpreadsheetCellCoordinate(
            row: min(coordinate.row + 1, rows.index(before: rows.endIndex)),
            column: coordinate.column
        )
        selectedCell = destination
        focusedCell = destination
    }

    private func pasteCellsFromClipboard() {
        guard let selectedCell,
              let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else { return }
        let lastCell = SpreadsheetGridOperations.paste(
            clipboardText,
            startingAt: selectedCell,
            columnCount: effectiveColumns.count,
            into: &rows
        )
        synchronizeRowIDs()
        if let lastCell {
            self.selectedCell = lastCell
            focusedCell = lastCell
        }
    }

    private func normalizeSelection(afterRemovingRow removedRow: Int? = nil) {
        guard !rows.isEmpty, !effectiveColumns.isEmpty else {
            selectedCell = nil
            focusedCell = nil
            return
        }
        guard var selectedCell else { return }
        if let removedRow, selectedCell.row > removedRow {
            selectedCell.row -= 1
        }
        selectedCell.row = min(selectedCell.row, rows.index(before: rows.endIndex))
        selectedCell.column = min(
            selectedCell.column,
            effectiveColumns.index(before: effectiveColumns.endIndex)
        )
        self.selectedCell = selectedCell
        if focusedCell != nil {
            focusedCell = selectedCell
        }
    }
}

struct SpreadsheetCellCoordinate: Hashable, Sendable {
    var row: Int
    var column: Int
}

enum SpreadsheetGridOperations {
    static func parsedCells(from text: String) -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.map { $0.components(separatedBy: "\t") }
    }

    @discardableResult
    static func paste(
        _ text: String,
        startingAt start: SpreadsheetCellCoordinate,
        columnCount: Int,
        into rows: inout [[String]]
    ) -> SpreadsheetCellCoordinate? {
        guard start.row >= 0, start.column >= 0, columnCount > 0 else {
            return nil
        }
        let pastedRows = parsedCells(from: text)
        guard !pastedRows.isEmpty, start.column < columnCount else { return nil }

        let requiredRowCount = start.row + pastedRows.count
        while rows.count < requiredRowCount {
            rows.append(Array(repeating: "", count: columnCount))
        }
        for rowIndex in rows.indices {
            if rows[rowIndex].count < columnCount {
                rows[rowIndex].append(
                    contentsOf: Array(
                        repeating: "",
                        count: columnCount - rows[rowIndex].count
                    )
                )
            } else if rows[rowIndex].count > columnCount {
                rows[rowIndex].removeLast(rows[rowIndex].count - columnCount)
            }
        }

        var lastCoordinate: SpreadsheetCellCoordinate?
        for (rowOffset, pastedRow) in pastedRows.enumerated() {
            let destinationRow = start.row + rowOffset
            for (columnOffset, value) in pastedRow.enumerated() {
                let destinationColumn = start.column + columnOffset
                guard destinationColumn < columnCount else { break }
                rows[destinationRow][destinationColumn] = value
                lastCoordinate = SpreadsheetCellCoordinate(
                    row: destinationRow,
                    column: destinationColumn
                )
            }
        }
        return lastCoordinate
    }
}

private struct SpreadsheetFormulaBar: View {
    let coordinate: SpreadsheetCellCoordinate
    @Binding var rawValue: String
    let value: SpreadsheetValue

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(
                    SpreadsheetEngine.address(
                        row: coordinate.row,
                        column: coordinate.column
                    )
                )
                .font(.body.monospaced().weight(.semibold))
                .frame(width: 42, alignment: .leading)
                .accessibilityLabel("Selected cell")
                .accessibilityValue(
                    SpreadsheetEngine.address(
                        row: coordinate.row,
                        column: coordinate.column
                    )
                )

                Image(systemName: "function")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Cell value or formula", text: $rawValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .accessibilityLabel("Raw value for selected cell")
                    .accessibilityHint(
                        "Start formulas with an equals sign. A1 references, arithmetic, ranges, and common accounting functions are supported."
                    )
                    .help(
                        "Start formulas with =. Supports A1 references, arithmetic, ranges, SUM, AVERAGE, MIN, MAX, ROUND, ABS, IF, PV, FV, PMT, and NPV."
                    )
            }

            if isFormula {
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
                .foregroundStyle(value.error == nil ? Color.secondary : Color.red)
            }
        }
    }

    private var isFormula: Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=")
    }
}

private struct AccountingGridHeader: View {
    let columns: [String]

    var body: some View {
        GridRow {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text("\(SpreadsheetEngine.columnName(for: index)) · \(column)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 132, alignment: .leading)
            }
            Color.clear
                .frame(width: 24, height: 1)
                .accessibilityHidden(true)
        }
    }
}

private struct AccountingGridRow: View {
    let rowIndex: Int
    let columns: [String]
    @Binding var cells: [String]
    let evaluation: SpreadsheetEvaluation
    let focusedCell: FocusState<SpreadsheetCellCoordinate?>.Binding
    let canDelete: Bool
    let select: (SpreadsheetCellCoordinate) -> Void
    let submit: (SpreadsheetCellCoordinate) -> Void
    let delete: () -> Void

    var body: some View {
        GridRow {
            ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, column in
                if cells.indices.contains(columnIndex) {
                    let coordinate = SpreadsheetCellCoordinate(
                        row: rowIndex,
                        column: columnIndex
                    )
                    let evaluatedValue = evaluation[
                        row: rowIndex,
                        column: columnIndex
                    ]
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(column, text: $cells[columnIndex])
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .focused(focusedCell, equals: coordinate)
                            .onTapGesture {
                                select(coordinate)
                            }
                            .onSubmit {
                                submit(coordinate)
                            }
                            .accessibilityLabel(
                                "\(column), row \(rowIndex + 1), \(SpreadsheetEngine.address(row: rowIndex, column: columnIndex))"
                            )
                            .accessibilityValue(
                                accessibilityValue(
                                    rawValue: cells[columnIndex],
                                    evaluatedValue: evaluatedValue
                                )
                            )
                            .accessibilityHint("Press Return to move to the cell below.")

                        if isFormula(cells[columnIndex]) {
                            Text(evaluatedValue.displayString)
                                .font(.caption.monospaced())
                                .foregroundStyle(
                                    evaluatedValue.error == nil
                                        ? Color.secondary
                                        : Color.red
                                )
                                .lineLimit(1)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minWidth: 132)
                }
            }

            Button("Delete Row", systemImage: "minus.circle", role: .destructive) {
                delete()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help("Delete this row")
            .accessibilityLabel("Delete row \(rowIndex + 1)")
        }
    }

    private func isFormula(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=")
    }

    private func accessibilityValue(
        rawValue: String,
        evaluatedValue: SpreadsheetValue
    ) -> Text {
        if isFormula(rawValue) {
            if let error = evaluatedValue.error {
                return Text("Formula \(rawValue). Error \(error.rawValue)")
            }
            return Text("Formula \(rawValue). Calculated value \(evaluatedValue.displayString)")
        }
        return rawValue.isEmpty ? Text("Empty") : Text(rawValue)
    }
}

struct MatchingAnswerEditor: View {
    let items: [QuestionOption]
    let targets: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                MatchingAnswerRow(
                    item: item,
                    targets: targets,
                    selection: $answer[pairFor: item.id]
                )
            }
        }
        .onAppear {
            normalizePairs()
        }
        .onChange(of: items) { _, _ in
            normalizePairs()
        }
        .onChange(of: targets) { _, _ in
            normalizePairs()
        }
    }

    private func normalizePairs() {
        let itemIDs = Set(items.map(\.id))
        let targetIDs = Set(targets.map(\.id))
        let normalized = answer.pairs.filter { itemID, targetID in
            itemIDs.contains(itemID) && targetIDs.contains(targetID)
        }
        if normalized != answer.pairs {
            answer.pairs = normalized
        }
    }
}

private struct MatchingAnswerRow: View {
    let item: QuestionOption
    let targets: [QuestionOption]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                Text(item.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Picker("Match for \(item.text)", selection: $selection) {
                Text("Choose…").tag("")
                ForEach(targets) { target in
                    Text(target.text).tag(target.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 190)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct OrderingAnswerEditor: View {
    let items: [QuestionOption]
    @Binding var answer: StudentAnswer

    var body: some View {
        let displayedOrder = presentedOrder
        VStack(alignment: .leading, spacing: 8) {
            Text("Move the items into the required order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(displayedOrder) { row in
                OrderingAnswerRow(
                    itemID: row.itemID,
                    title: title(for: row.itemID),
                    position: row.position,
                    totalCount: displayedOrder.count,
                    moveEarlier: { move(from: row.position, offset: -1) },
                    moveLater: { move(from: row.position, offset: 1) }
                )
            }

            Button {
                answer.order = items.map(\.id)
            } label: {
                LocalizedSystemLabel(
                    title: orderButtonTitle,
                    systemImage: orderButtonImage
                )
            }
            .controlSize(.small)
        }
        .onAppear {
            normalizeOrder()
        }
        .onChange(of: items) { _, _ in
            normalizeOrder()
        }
    }

    private func normalizeOrder() {
        guard !answer.order.isEmpty else { return }
        let itemIDs = items.map(\.id)
        let knownIDs = Set(itemIDs)
        var seen = Set<String>()
        var normalized = answer.order.filter { itemID in
            knownIDs.contains(itemID) && seen.insert(itemID).inserted
        }
        for itemID in itemIDs where !normalized.contains(itemID) {
            normalized.append(itemID)
        }
        if normalized != answer.order {
            answer.order = normalized
        }
    }

    private func title(for itemID: String) -> String {
        items.first(where: { $0.id == itemID })?.text ?? itemID
    }

    private func move(from source: Int, offset: Int) {
        var order = presentedOrder.map(\.itemID)
        let destination = source + offset
        guard order.indices.contains(source),
              order.indices.contains(destination) else { return }
        order.swapAt(source, destination)
        answer.order = order
    }

    private var presentedOrder: [PresentedOrderItem] {
        let order = answer.order.isEmpty ? items.map(\.id) : answer.order
        var occurrences: [String: Int] = [:]
        return order.enumerated().map { position, itemID in
            let occurrence = occurrences[itemID, default: 0]
            occurrences[itemID] = occurrence + 1
            return PresentedOrderItem(
                itemID: itemID,
                position: position,
                occurrence: occurrence
            )
        }
    }

    private var orderButtonTitle: LocalizedStringResource {
        answer.order.isEmpty ? "Use This Order" : "Reset Order"
    }

    private var orderButtonImage: String {
        answer.order.isEmpty ? "checkmark" : "arrow.counterclockwise"
    }
}

private struct PresentedOrderItem: Identifiable {
    let itemID: String
    let position: Int
    let occurrence: Int

    var id: String { "\(itemID)\u{1F}\(occurrence)" }
}

private struct OrderingAnswerRow: View {
    let itemID: String
    let title: String
    let position: Int
    let totalCount: Int
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(position + 1, format: .number)
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(itemID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ControlGroup {
                Button("Move Earlier", systemImage: "chevron.up") {
                    moveEarlier()
                }
                .disabled(position == 0)
                Button("Move Later", systemImage: "chevron.down") {
                    moveLater()
                }
                .disabled(position >= totalCount - 1)
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}
