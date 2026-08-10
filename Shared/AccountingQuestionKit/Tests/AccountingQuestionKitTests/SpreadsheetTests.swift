import Testing
@testable import AccountingQuestionKit

@Test func spreadsheetEvaluatesReferencesRangesAndCommonFunctions() {
    let rows = [
        ["10", "20", "=A1+B1", "=SUM(A1:C1)"],
        ["5", "=AVERAGE(A1:B1)", "=MIN(A1:B2)", "=MAX(A1:B2)"],
        ["=ROUND(10/3,2)", "=ABS(-7)", "=IF(A1>5,100,0)", "=A1^2"]
    ]
    let result = SpreadsheetEngine.evaluate(rows: rows)

    #expect(result[row: 0, column: 2].number == 30)
    #expect(result[row: 0, column: 3].number == 60)
    #expect(result[row: 1, column: 1].number == 15)
    #expect(result[row: 1, column: 2].number == 5)
    #expect(result[row: 1, column: 3].number == 20)
    #expect(abs((result[row: 2, column: 0].number ?? 0) - 3.33) < 0.000001)
    #expect(result[row: 2, column: 1].number == 7)
    #expect(result[row: 2, column: 2].number == 100)
    #expect(result[row: 2, column: 3].number == 100)
}

@Test func spreadsheetFinancialFunctionsMatchExcelSignConvention() {
    let pv = SpreadsheetEngine.evaluateFormula("=PV(10%,2,0,121)")
    let fv = SpreadsheetEngine.evaluateFormula("=FV(10%,2,0,-100)")
    let pmt = SpreadsheetEngine.evaluateFormula("=PMT(10%,2,100)")
    let npv = SpreadsheetEngine.evaluateFormula("=NPV(10%,55,60.5)")

    #expect(abs((pv.number ?? 0) - -100) < 0.000001)
    #expect(abs((fv.number ?? 0) - 121) < 0.000001)
    #expect(abs((pmt.number ?? 0) - -57.619047619) < 0.000001)
    #expect(abs((npv.number ?? 0) - 100) < 0.000001)
}

@Test func spreadsheetReportsSafeErrorsAndShortCircuitsIf() {
    let rows = [["=B1", "=A1", "=1/0", "=Z99", "=NOPE(1)", "=IF(FALSE,1/0,5)"]]
    let result = SpreadsheetEngine.evaluate(rows: rows)

    #expect(result[row: 0, column: 0].error == .cycle)
    #expect(result[row: 0, column: 1].error == .cycle)
    #expect(result[row: 0, column: 2].error == .divideByZero)
    #expect(result[row: 0, column: 3].error == .reference)
    #expect(result[row: 0, column: 4].error == .name)
    #expect(result[row: 0, column: 5].number == 5)
}

@Test func spreadsheetFormulaCellsGradeByEvaluatedValueWithoutLosingRawFormula() {
    let part = QuestionPart(
        id: "schedule",
        kind: .table,
        format: .multiPeriodSchedule,
        promptMarkdown: "Complete the schedule.",
        columns: ["Beginning", "Reduction", "Ending"],
        expected: ExpectedAnswer(rows: [["100", "25", "75"]])
    )
    let rawRows = [["100", "25", "=A1-B1"]]
    let answer = StudentAnswer(rows: rawRows)

    #expect(AnswerGrader.grade(answer, for: part).status == .correct)
    #expect(answer.rows[0][2] == "=A1-B1")
}

@Test func spreadsheetAddressesAdvanceBeyondColumnZ() {
    #expect(SpreadsheetEngine.columnName(for: 0) == "A")
    #expect(SpreadsheetEngine.columnName(for: 25) == "Z")
    #expect(SpreadsheetEngine.columnName(for: 26) == "AA")
    #expect(SpreadsheetEngine.address(row: 4, column: 27) == "AB5")
}

@Test func acceptedFormulaAlternativesCanContainArgumentCommas() throws {
    let markdown = """
    :::question id=formula-alternatives formats=formula_setup
    # Formula alternatives
    :::part id=a kind=formula format=formula_setup
    ### Prompt
    Compute present value.
    ### Answer
    =-PV(8%,3,0,10000)
    ### Accepted
    - =PV(8%,3,0,-10000)
    - =10000/(1+8%)^3
    :::endpart
    :::endquestion
    """

    let part = try #require(
        QuestionMarkdownParser.parse(markdown).pack.questions.first?.parts.first
    )
    #expect(part.expected.accepted == ["=PV(8%,3,0,-10000)", "=10000/(1+8%)^3"])
    #expect(
        AnswerGrader.grade(StudentAnswer(scalar: "=PV(8%,3,0,-10000)"), for: part).status
            == .correct
    )
}

@Test func formulaGradingPreservesComparisonOperators() {
    let part = QuestionPart(
        id: "formula",
        kind: .formula,
        format: .formulaSetup,
        promptMarkdown: "Enter the IF formula.",
        expected: ExpectedAnswer(scalar: "=IF(A1=1,2,3)")
    )

    #expect(
        AnswerGrader.grade(StudentAnswer(scalar: "IF(A1=1, 2, 3)"), for: part).status
            == .correct
    )
    #expect(
        AnswerGrader.grade(StudentAnswer(scalar: "=IF(A1==1,2,3)"), for: part).status
            == .incorrect
    )
}
