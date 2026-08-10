import Foundation

public enum SpreadsheetError: String, Error, Equatable, Sendable {
    case reference = "#REF!"
    case value = "#VALUE!"
    case divideByZero = "#DIV/0!"
    case name = "#NAME?"
    case cycle = "#CYCLE!"
    case number = "#NUM!"
    case parse = "#PARSE!"
}

public enum SpreadsheetValue: Equatable, Sendable {
    case blank
    case number(Double)
    case text(String)
    case boolean(Bool)
    case error(SpreadsheetError)

    public var number: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var error: SpreadsheetError? {
        guard case let .error(error) = self else { return nil }
        return error
    }

    public var displayString: String {
        switch self {
        case .blank:
            ""
        case let .number(value):
            Self.format(value)
        case let .text(value):
            value
        case let .boolean(value):
            value ? "TRUE" : "FALSE"
        case let .error(error):
            error.rawValue
        }
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return SpreadsheetError.number.rawValue }
        if value == 0 { return "0" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000000001,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return String(Int64(rounded))
        }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

public struct SpreadsheetEvaluation: Equatable, Sendable {
    public let values: [[SpreadsheetValue]]

    public init(values: [[SpreadsheetValue]]) {
        self.values = values
    }

    public var displayRows: [[String]] {
        values.map { $0.map(\.displayString) }
    }

    public subscript(row row: Int, column column: Int) -> SpreadsheetValue {
        guard values.indices.contains(row), values[row].indices.contains(column) else {
            return .error(.reference)
        }
        return values[row][column]
    }
}

public enum SpreadsheetEngine {
    public static func evaluate(rows: [[String]]) -> SpreadsheetEvaluation {
        let context = EvaluationContext(rows: rows)
        let columnCount = rows.map(\.count).max() ?? 0
        let values = rows.indices.map { row in
            (0..<columnCount).map { column in
                context.value(at: CellAddress(row: row, column: column))
            }
        }
        return SpreadsheetEvaluation(values: values)
    }

    public static func evaluateFormula(
        _ formula: String,
        rows: [[String]] = []
    ) -> SpreadsheetValue {
        EvaluationContext(rows: rows).evaluateFormula(formula)
    }

    /// Replaces formulas and numeric spreadsheet literals with their evaluated values.
    /// Text labels remain unchanged. This representation is used only for grading;
    /// the student's raw formulas continue to be persisted in `StudentAnswer.rows`.
    public static func resolvedRowsForGrading(_ rows: [[String]]) -> [[String]] {
        let evaluation = evaluate(rows: rows)
        return rows.indices.map { row in
            rows[row].indices.map { column in
                let raw = rows[row][column]
                let value = evaluation[row: row, column: column]
                switch value {
                case .number, .boolean, .blank, .error:
                    return value.displayString
                case .text:
                    return raw
                }
            }
        }
    }

    public static func columnName(for zeroBasedColumn: Int) -> String {
        guard zeroBasedColumn >= 0 else { return "" }
        var value = zeroBasedColumn + 1
        var result = ""
        while value > 0 {
            value -= 1
            guard let scalar = UnicodeScalar(65 + value % 26) else { return "" }
            result.insert(Character(scalar), at: result.startIndex)
            value /= 26
        }
        return result
    }

    public static func address(row zeroBasedRow: Int, column zeroBasedColumn: Int) -> String {
        guard zeroBasedRow >= 0, zeroBasedColumn >= 0 else { return "" }
        return "\(columnName(for: zeroBasedColumn))\(zeroBasedRow + 1)"
    }
}

private struct CellAddress: Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    init?(_ identifier: String) {
        let cleaned = identifier.replacingOccurrences(of: "$", with: "")
        let letters = cleaned.prefix { $0.isLetter }
        let digits = cleaned.dropFirst(letters.count)
        guard !letters.isEmpty,
              !digits.isEmpty,
              digits.allSatisfy(\.isNumber),
              let oneBasedRow = Int(digits),
              oneBasedRow > 0 else { return nil }
        var column = 0
        for scalar in letters.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            column = column * 26 + Int(scalar.value - 64)
        }
        self.row = oneBasedRow - 1
        self.column = column - 1
    }
}

private final class EvaluationContext {
    private let rows: [[String]]
    private let columnCount: Int
    private var cache: [CellAddress: SpreadsheetValue] = [:]
    private var visiting: Set<CellAddress> = []

    init(rows: [[String]]) {
        self.rows = rows
        self.columnCount = rows.map(\.count).max() ?? 0
    }

    func value(at address: CellAddress) -> SpreadsheetValue {
        guard address.row >= 0,
              address.column >= 0,
              rows.indices.contains(address.row),
              address.column < columnCount else {
            return .error(.reference)
        }
        if let cached = cache[address] { return cached }
        guard visiting.insert(address).inserted else { return .error(.cycle) }
        defer { visiting.remove(address) }

        let raw = rows[address.row].indices.contains(address.column)
            ? rows[address.row][address.column]
            : ""
        let result = evaluateCell(raw)
        cache[address] = result
        return result
    }

    func evaluateFormula(_ formula: String) -> SpreadsheetValue {
        let expressionText = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = expressionText.hasPrefix("=")
            ? String(expressionText.dropFirst())
            : expressionText
        guard !body.isEmpty else { return .error(.parse) }
        do {
            var lexer = FormulaLexer(body)
            let tokens = try lexer.tokenize()
            var parser = FormulaParser(tokens: tokens)
            let expression = try parser.parse()
            return evaluate(expression)
        } catch let error as SpreadsheetError {
            return .error(error)
        } catch {
            return .error(.parse)
        }
    }

    private func evaluateCell(_ raw: String) -> SpreadsheetValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blank }
        if trimmed.hasPrefix("=") { return evaluateFormula(trimmed) }
        if let number = spreadsheetNumber(trimmed) { return .number(number) }
        if trimmed.caseInsensitiveCompare("TRUE") == .orderedSame { return .boolean(true) }
        if trimmed.caseInsensitiveCompare("FALSE") == .orderedSame { return .boolean(false) }
        return .text(raw)
    }

    private func evaluate(_ expression: FormulaExpression) -> SpreadsheetValue {
        switch expression {
        case let .number(value):
            return finite(value)
        case let .text(value):
            return .text(value)
        case let .boolean(value):
            return .boolean(value)
        case let .cell(address):
            return value(at: address)
        case .range:
            return .error(.value)
        case let .name(name):
            if name.caseInsensitiveCompare("TRUE") == .orderedSame { return .boolean(true) }
            if name.caseInsensitiveCompare("FALSE") == .orderedSame { return .boolean(false) }
            return .error(.name)
        case let .unary(operation, child):
            let value = evaluate(child)
            guard let number = numeric(value, blankAsZero: true) else {
                return propagatedError(value) ?? .error(.value)
            }
            return finite(operation == .minus ? -number : number)
        case let .binary(operation, left, right):
            return evaluateBinary(operation, left: left, right: right)
        case let .function(name, arguments):
            return evaluateFunction(name, arguments: arguments)
        }
    }

    private func evaluateBinary(
        _ operation: BinaryOperator,
        left: FormulaExpression,
        right: FormulaExpression
    ) -> SpreadsheetValue {
        let leftValue = evaluate(left)
        if let error = propagatedError(leftValue) { return error }
        let rightValue = evaluate(right)
        if let error = propagatedError(rightValue) { return error }

        switch operation {
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            let comparison = compare(leftValue, rightValue)
            guard let comparison else { return .error(.value) }
            let result: Bool = switch operation {
            case .equal: comparison == 0
            case .notEqual: comparison != 0
            case .less: comparison < 0
            case .lessEqual: comparison <= 0
            case .greater: comparison > 0
            case .greaterEqual: comparison >= 0
            default: false
            }
            return .boolean(result)
        default:
            guard let leftNumber = numeric(leftValue, blankAsZero: true),
                  let rightNumber = numeric(rightValue, blankAsZero: true) else {
                return .error(.value)
            }
            switch operation {
            case .add: return finite(leftNumber + rightNumber)
            case .subtract: return finite(leftNumber - rightNumber)
            case .multiply: return finite(leftNumber * rightNumber)
            case .divide:
                guard rightNumber != 0 else { return .error(.divideByZero) }
                return finite(leftNumber / rightNumber)
            case .power:
                return finite(pow(leftNumber, rightNumber))
            default:
                return .error(.value)
            }
        }
    }

    private func evaluateFunction(
        _ rawName: String,
        arguments: [FormulaExpression]
    ) -> SpreadsheetValue {
        let name = rawName.uppercased()
        if name == "IF" {
            guard arguments.count == 3 else { return .error(.value) }
            let condition = evaluate(arguments[0])
            guard let truth = truthy(condition) else {
                return propagatedError(condition) ?? .error(.value)
            }
            return evaluate(arguments[truth ? 1 : 2])
        }

        switch name {
        case "SUM", "AVERAGE", "MIN", "MAX":
            let values = arguments.flatMap(values(in:))
            if let error = values.compactMap(\.error).first { return .error(error) }
            let numbers = values.compactMap { numeric($0, blankAsZero: false) }
            switch name {
            case "SUM": return finite(numbers.reduce(0, +))
            case "AVERAGE":
                guard !numbers.isEmpty else { return .error(.divideByZero) }
                return finite(numbers.reduce(0, +) / Double(numbers.count))
            case "MIN": return finite(numbers.min() ?? 0)
            default: return finite(numbers.max() ?? 0)
            }
        case "ABS":
            guard arguments.count == 1,
                  let value = requiredNumber(arguments[0]) else { return .error(.value) }
            return finite(abs(value))
        case "ROUND":
            guard arguments.count == 2,
                  let value = requiredNumber(arguments[0]),
                  let digitsValue = requiredNumber(arguments[1]),
                  digitsValue.isFinite else { return .error(.value) }
            let digits = Int(digitsValue.rounded(.towardZero))
            guard (-308...308).contains(digits) else { return .error(.number) }
            let factor = pow(10, Double(digits))
            return finite((value * factor).rounded() / factor)
        case "PV":
            return financial(arguments, minimum: 3, maximum: 5) { values in
                presentValue(
                    rate: values[0],
                    periods: values[1],
                    payment: values[2],
                    futureValue: values[safe: 3] ?? 0,
                    type: values[safe: 4] ?? 0
                )
            }
        case "FV":
            return financial(arguments, minimum: 3, maximum: 5) { values in
                futureValue(
                    rate: values[0],
                    periods: values[1],
                    payment: values[2],
                    presentValue: values[safe: 3] ?? 0,
                    type: values[safe: 4] ?? 0
                )
            }
        case "PMT":
            return financial(arguments, minimum: 3, maximum: 5) { values in
                payment(
                    rate: values[0],
                    periods: values[1],
                    presentValue: values[2],
                    futureValue: values[safe: 3] ?? 0,
                    type: values[safe: 4] ?? 0
                )
            }
        case "NPV":
            guard arguments.count >= 2,
                  let rate = requiredNumber(arguments[0]),
                  rate > -1 else { return .error(.number) }
            let cashFlowValues = arguments.dropFirst().flatMap(values(in:))
            if let error = cashFlowValues.compactMap(\.error).first { return .error(error) }
            let cashFlows = cashFlowValues.compactMap { numeric($0, blankAsZero: false) }
            var result = 0.0
            for (offset, cashFlow) in cashFlows.enumerated() {
                result += cashFlow / pow(1 + rate, Double(offset + 1))
            }
            return finite(result)
        default:
            return .error(.name)
        }
    }

    private func financial(
        _ arguments: [FormulaExpression],
        minimum: Int,
        maximum: Int,
        calculation: ([Double]) -> Double?
    ) -> SpreadsheetValue {
        guard (minimum...maximum).contains(arguments.count) else { return .error(.value) }
        var values: [Double] = []
        for argument in arguments {
            guard let value = requiredNumber(argument) else { return .error(.value) }
            values.append(value)
        }
        guard let result = calculation(values) else { return .error(.number) }
        return finite(result)
    }

    private func values(in expression: FormulaExpression) -> [SpreadsheetValue] {
        guard case let .range(start, end) = expression else { return [evaluate(expression)] }
        let rowRange = min(start.row, end.row)...max(start.row, end.row)
        let columnRange = min(start.column, end.column)...max(start.column, end.column)
        return rowRange.flatMap { row in
            columnRange.map { column in value(at: CellAddress(row: row, column: column)) }
        }
    }

    private func requiredNumber(_ expression: FormulaExpression) -> Double? {
        numeric(evaluate(expression), blankAsZero: true)
    }

    private func numeric(_ value: SpreadsheetValue, blankAsZero: Bool) -> Double? {
        switch value {
        case let .number(number): number
        case let .boolean(boolean): boolean ? 1 : 0
        case .blank: blankAsZero ? 0 : nil
        case .text, .error: nil
        }
    }

    private func truthy(_ value: SpreadsheetValue) -> Bool? {
        switch value {
        case let .boolean(value): value
        case let .number(value): value != 0
        case .blank: false
        case let .text(value): !value.isEmpty
        case .error: nil
        }
    }

    private func compare(_ left: SpreadsheetValue, _ right: SpreadsheetValue) -> Int? {
        if let leftNumber = numeric(left, blankAsZero: true),
           let rightNumber = numeric(right, blankAsZero: true) {
            if abs(leftNumber - rightNumber) < 0.000000000001 { return 0 }
            return leftNumber < rightNumber ? -1 : 1
        }
        let leftText = left.displayString.lowercased()
        let rightText = right.displayString.lowercased()
        if leftText == rightText { return 0 }
        return leftText < rightText ? -1 : 1
    }

    private func propagatedError(_ value: SpreadsheetValue) -> SpreadsheetValue? {
        guard case .error = value else { return nil }
        return value
    }

    private func finite(_ value: Double) -> SpreadsheetValue {
        value.isFinite ? .number(value) : .error(.number)
    }
}

private func spreadsheetNumber(_ raw: String) -> Double? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let parentheticalNegative = value.hasPrefix("(") && value.hasSuffix(")")
    let percent = value.hasSuffix("%")
    value = value
        .replacingOccurrences(of: "$", with: "")
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .replacingOccurrences(of: "%", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard var number = Double(value) else { return nil }
    if parentheticalNegative { number = -number }
    if percent { number /= 100 }
    return number
}

private func presentValue(
    rate: Double,
    periods: Double,
    payment: Double,
    futureValue: Double,
    type: Double
) -> Double? {
    guard periods.isFinite, periods >= 0, type == 0 || type == 1 else { return nil }
    if rate == 0 { return -(futureValue + payment * periods) }
    guard rate > -1 else { return nil }
    let growth = pow(1 + rate, periods)
    return -(futureValue + payment * (1 + rate * type) * (growth - 1) / rate) / growth
}

private func futureValue(
    rate: Double,
    periods: Double,
    payment: Double,
    presentValue: Double,
    type: Double
) -> Double? {
    guard periods.isFinite, periods >= 0, type == 0 || type == 1 else { return nil }
    if rate == 0 { return -(presentValue + payment * periods) }
    guard rate > -1 else { return nil }
    let growth = pow(1 + rate, periods)
    return -(presentValue * growth + payment * (1 + rate * type) * (growth - 1) / rate)
}

private func payment(
    rate: Double,
    periods: Double,
    presentValue: Double,
    futureValue: Double,
    type: Double
) -> Double? {
    guard periods.isFinite, periods > 0, type == 0 || type == 1 else { return nil }
    if rate == 0 { return -(presentValue + futureValue) / periods }
    guard rate > -1 else { return nil }
    let growth = pow(1 + rate, periods)
    let denominator = (1 + rate * type) * (growth - 1)
    guard denominator != 0 else { return nil }
    return -(presentValue * growth + futureValue) * rate / denominator
}

private indirect enum FormulaExpression {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case cell(CellAddress)
    case range(CellAddress, CellAddress)
    case name(String)
    case unary(UnaryOperator, FormulaExpression)
    case binary(BinaryOperator, FormulaExpression, FormulaExpression)
    case function(String, [FormulaExpression])
}

private enum UnaryOperator {
    case plus
    case minus
}

private enum BinaryOperator {
    case add
    case subtract
    case multiply
    case divide
    case power
    case equal
    case notEqual
    case less
    case lessEqual
    case greater
    case greaterEqual
}

private enum FormulaToken: Equatable {
    case number(Double)
    case string(String)
    case identifier(String)
    case plus
    case minus
    case multiply
    case divide
    case power
    case leftParenthesis
    case rightParenthesis
    case comma
    case colon
    case equal
    case notEqual
    case less
    case lessEqual
    case greater
    case greaterEqual
    case end
}

private struct FormulaLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [FormulaToken] {
        var tokens: [FormulaToken] = []
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber || character == "." {
                tokens.append(try number())
                continue
            }
            if character.isLetter || character == "$" || character == "_" {
                tokens.append(identifier())
                continue
            }
            if character == "\"" {
                tokens.append(try string())
                continue
            }
            index += 1
            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*": tokens.append(.multiply)
            case "/": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "(": tokens.append(.leftParenthesis)
            case ")": tokens.append(.rightParenthesis)
            case ",": tokens.append(.comma)
            case ":": tokens.append(.colon)
            case "=": tokens.append(.equal)
            case "<":
                if consume("=") { tokens.append(.lessEqual) }
                else if consume(">") { tokens.append(.notEqual) }
                else { tokens.append(.less) }
            case ">":
                tokens.append(consume("=") ? .greaterEqual : .greater)
            default:
                throw SpreadsheetError.parse
            }
        }
        tokens.append(.end)
        return tokens
    }

    private mutating func number() throws -> FormulaToken {
        let start = index
        var sawExponent = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "." {
                index += 1
            } else if (character == "e" || character == "E") && !sawExponent {
                sawExponent = true
                index += 1
                if index < characters.count,
                   characters[index] == "+" || characters[index] == "-" {
                    index += 1
                }
            } else {
                break
            }
        }
        let text = String(characters[start..<index])
        guard var value = Double(text) else { throw SpreadsheetError.parse }
        if index < characters.count, characters[index] == "%" {
            value /= 100
            index += 1
        }
        return .number(value)
    }

    private mutating func identifier() -> FormulaToken {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber
                    || character == "$" || character == "_" || character == "." else { break }
            index += 1
        }
        return .identifier(String(characters[start..<index]))
    }

    private mutating func string() throws -> FormulaToken {
        index += 1
        var result = ""
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "\"" {
                if index < characters.count, characters[index] == "\"" {
                    result.append("\"")
                    index += 1
                    continue
                }
                return .string(result)
            }
            result.append(character)
        }
        throw SpreadsheetError.parse
    }

    private mutating func consume(_ expected: Character) -> Bool {
        guard index < characters.count, characters[index] == expected else { return false }
        index += 1
        return true
    }
}

private struct FormulaParser {
    private let tokens: [FormulaToken]
    private var index = 0

    init(tokens: [FormulaToken]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> FormulaExpression {
        let expression = try comparison()
        guard current == .end else { throw SpreadsheetError.parse }
        return expression
    }

    private mutating func comparison() throws -> FormulaExpression {
        var expression = try addition()
        while true {
            let operation: BinaryOperator? = switch current {
            case .equal: .equal
            case .notEqual: .notEqual
            case .less: .less
            case .lessEqual: .lessEqual
            case .greater: .greater
            case .greaterEqual: .greaterEqual
            default: nil
            }
            guard let operation else { return expression }
            advance()
            expression = .binary(operation, expression, try addition())
        }
    }

    private mutating func addition() throws -> FormulaExpression {
        var expression = try multiplication()
        while current == .plus || current == .minus {
            let operation: BinaryOperator = current == .plus ? .add : .subtract
            advance()
            expression = .binary(operation, expression, try multiplication())
        }
        return expression
    }

    private mutating func multiplication() throws -> FormulaExpression {
        var expression = try power()
        while current == .multiply || current == .divide {
            let operation: BinaryOperator = current == .multiply ? .multiply : .divide
            advance()
            expression = .binary(operation, expression, try power())
        }
        return expression
    }

    private mutating func power() throws -> FormulaExpression {
        var expression = try unary()
        if current == .power {
            advance()
            expression = .binary(.power, expression, try power())
        }
        return expression
    }

    private mutating func unary() throws -> FormulaExpression {
        if current == .plus || current == .minus {
            let operation: UnaryOperator = current == .plus ? .plus : .minus
            advance()
            return .unary(operation, try unary())
        }
        return try primary()
    }

    private mutating func primary() throws -> FormulaExpression {
        let expression: FormulaExpression
        switch current {
        case let .number(value):
            expression = .number(value)
            advance()
        case let .string(value):
            expression = .text(value)
            advance()
        case let .identifier(identifier):
            advance()
            if current == .leftParenthesis {
                advance()
                var arguments: [FormulaExpression] = []
                if current != .rightParenthesis {
                    repeat {
                        arguments.append(try comparison())
                    } while consume(.comma)
                }
                try require(.rightParenthesis)
                expression = .function(identifier, arguments)
            } else if let address = CellAddress(identifier) {
                expression = .cell(address)
            } else if identifier.caseInsensitiveCompare("TRUE") == .orderedSame {
                expression = .boolean(true)
            } else if identifier.caseInsensitiveCompare("FALSE") == .orderedSame {
                expression = .boolean(false)
            } else {
                expression = .name(identifier)
            }
        case .leftParenthesis:
            advance()
            expression = try comparison()
            try require(.rightParenthesis)
        default:
            throw SpreadsheetError.parse
        }

        if current == .colon {
            guard case let .cell(start) = expression else { throw SpreadsheetError.parse }
            advance()
            guard case let .identifier(identifier) = current,
                  let end = CellAddress(identifier) else { throw SpreadsheetError.parse }
            advance()
            return .range(start, end)
        }
        return expression
    }

    private var current: FormulaToken { tokens[index] }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    private mutating func consume(_ token: FormulaToken) -> Bool {
        guard current == token else { return false }
        advance()
        return true
    }

    private mutating func require(_ token: FormulaToken) throws {
        guard consume(token) else { throw SpreadsheetError.parse }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
