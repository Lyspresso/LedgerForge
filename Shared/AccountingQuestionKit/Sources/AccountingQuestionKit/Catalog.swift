import Foundation

public extension QuestionShell {
    var displayName: String {
        switch self {
        case .multipleChoice: "Multiple Choice"
        case .standaloneCalculation: "Standalone Calculation"
        case .multipart: "Multipart Applied Problem"
        case .multipleCase: "Multiple Cases"
        case .lifecycle: "Chronological Lifecycle"
        case .comprehensive: "Comprehensive Case"
        case .memoResearch: "Memo or Research"
        }
    }
}

public extension VariationStyle {
    var displayName: String {
        switch self {
        case .core: "Core"
        case .numberVariant: "Number Variant"
        case .alternateAngle: "Alternate Angle"
        case .counterfactual: "Changed Fact"
        case .diagnostic: "Diagnostic"
        case .longPath: "Long Path"
        case .independentCases: "Independent Cases"
        case .staffDraft: "Staff Draft Review"
        }
    }
}

public extension ResponseKind {
    var displayName: String {
        switch self {
        case .singleChoice: "Single Choice"
        case .multipleChoice: "Multiple Choice"
        case .number: "Number"
        case .formula: "Formula"
        case .shortText: "Short Response"
        case .longText: "Written Response"
        case .journal: "Journal Entry"
        case .table: "Accounting Table"
        case .matching: "Matching"
        case .ordering: "Ordering"
        case .trueFalse: "True or False"
        case .noEntry: "Entry Decision"
        }
    }
}

public extension QuestionFormat {
    var displayName: String {
        switch self {
        case .singleNumber: "Single-Number Computation"
        case .formulaSetup: "Formula or Function Setup"
        case .initialJournalEntry: "Initial-Recognition Entry"
        case .adjustingJournalEntry: "Adjusting Entry"
        case .correctingJournalEntry: "Correcting or Restatement Entry"
        case .closingReversingEntry: "Closing or Reversing Entry"
        case .settlementEntry: "Disposal, Maturity, Conversion, or Settlement Entry"
        case .entryOrNoEntry: "Entry-or-No-Entry Judgment"
        case .multiPeriodSchedule: "Multi-Period Schedule"
        case .rollforward: "Rollforward"
        case .tAccount: "T-Account or Ledger Reconstruction"
        case .backsolve: "Missing Amount or Back-Solving"
        case .worksheetTrialBalance: "Worksheet or Trial Balance"
        case .fullStatement: "Full Financial Statement"
        case .partialStatement: "Partial Statement or Excerpt"
        case .presentationClassificationGrid: "Presentation or Classification Grid"
        case .effectMatrix: "Overstated, Understated, or No-Effect Matrix"
        case .includeExcludeTable: "Include-or-Exclude Table"
        case .disclosureDrafting: "Disclosure or Footnote Drafting"
        case .reconciliationProof: "Reconciliation, Proof, or Tie-Out"
        case .errorCorrection: "Error Identification and Correction"
        case .correctVersusIncorrect: "Correct-versus-Incorrect Comparison"
        case .alternativeMethodComparison: "Alternative-Method Comparison"
        case .sensitivityChangedFact: "Sensitivity or Changed-Fact Analysis"
        case .thresholdCriteriaTest: "Threshold or Criteria Test"
        case .rankingSequentialInclusion: "Ranking or Sequential Inclusion"
        case .orderingTimeline: "Ordering or Timeline Reconstruction"
        case .ratioAnalysis: "Ratio Calculation and Interpretation"
        case .shortExplanation: "Short Explanation or Justification"
        case .claimEvaluation: "Claim or Assertion Evaluation"
        case .trueFalseCorrection: "True or False with Correction"
        case .matchingMappingSorting: "Matching, Mapping, or Sorting"
        case .codificationResearch: "Codification Research or Citation Decoding"
        case .aisSourceDocumentFlow: "AIS Source-Document and Journal Flow"
        case .multipleChoice: "Single-Best-Answer Multiple Choice"
        }
    }

    var recommendedKinds: Set<ResponseKind> {
        switch self {
        case .multipleChoice: [.singleChoice, .multipleChoice]
        case .singleNumber, .backsolve, .ratioAnalysis: [.number]
        case .formulaSetup: [.formula]
        case .initialJournalEntry, .adjustingJournalEntry, .correctingJournalEntry,
             .closingReversingEntry, .settlementEntry: [.journal]
        case .entryOrNoEntry: [.noEntry]
        case .multiPeriodSchedule, .rollforward, .tAccount, .worksheetTrialBalance,
             .fullStatement, .partialStatement, .effectMatrix, .reconciliationProof,
             .correctVersusIncorrect, .alternativeMethodComparison,
             .sensitivityChangedFact, .thresholdCriteriaTest: [.table]
        case .presentationClassificationGrid, .includeExcludeTable,
             .matchingMappingSorting, .aisSourceDocumentFlow: [.matching, .table]
        case .rankingSequentialInclusion, .orderingTimeline: [.ordering, .table]
        case .disclosureDrafting, .errorCorrection, .claimEvaluation,
             .codificationResearch: [.longText, .table]
        case .shortExplanation: [.shortText, .longText]
        case .trueFalseCorrection: [.trueFalse]
        }
    }
}

public enum ValidationSeverity: String, Codable, Sendable {
    case error
    case warning
}

public struct ValidationIssue: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(severity.rawValue):\(questionID):\(partID ?? "-"):\(message)" }
    public var severity: ValidationSeverity
    public var questionID: String
    public var partID: String?
    public var message: String

    public init(
        severity: ValidationSeverity,
        questionID: String,
        partID: String? = nil,
        message: String
    ) {
        self.severity = severity
        self.questionID = questionID
        self.partID = partID
        self.message = message
    }
}

public enum QuestionValidator {
    public static func validate(_ pack: QuestionPack) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var questionIDs = Set<String>()
        for question in pack.questions {
            if !questionIDs.insert(question.id).inserted {
                issues.append(.init(severity: .error, questionID: question.id, message: "Duplicate question id."))
            }
            if question.parts.isEmpty {
                issues.append(.init(severity: .error, questionID: question.id, message: "Question contains no answerable parts."))
            }
            var partIDs = Set<String>()
            for part in question.parts {
                if !partIDs.insert(part.id).inserted {
                    issues.append(.init(severity: .error, questionID: question.id, partID: part.id, message: "Duplicate part id."))
                }
                if part.promptMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.init(severity: .error, questionID: question.id, partID: part.id, message: "Part has no prompt."))
                }
                if part.settings["legacy"] != "true",
                   !part.format.recommendedKinds.contains(part.kind) {
                    issues.append(.init(
                        severity: .warning,
                        questionID: question.id,
                        partID: part.id,
                        message: "\(part.format.displayName) normally uses a different editor than \(part.kind.displayName)."
                    ))
                }
                issues.append(contentsOf: validateAnswerShape(questionID: question.id, part: part))
            }
        }
        return issues
    }

    private static func validateAnswerShape(questionID: String, part: QuestionPart) -> [ValidationIssue] {
        let issue: (ValidationSeverity, String) -> ValidationIssue = { severity, message in
            ValidationIssue(severity: severity, questionID: questionID, partID: part.id, message: message)
        }
        switch part.kind {
        case .singleChoice, .multipleChoice:
            if part.options.count < 2 { return [issue(.error, "Choice part needs at least two options.")] }
            if part.expected.selections.isEmpty { return [issue(.error, "Choice part has no expected selection.")] }
        case .number, .formula, .shortText, .trueFalse, .noEntry:
            if part.expected.scalar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [issue(.error, "Part has no expected scalar answer.")]
            }
        case .longText:
            if part.expected.scalar.isEmpty && part.rubricMarkdown.isEmpty {
                return [issue(.warning, "Written response has neither a model answer nor a rubric.")]
            }
        case .journal, .table:
            if part.columns.isEmpty { return [issue(.error, "Table-based part has no columns.")] }
            if part.expected.rows.isEmpty { return [issue(.error, "Table-based part has no expected rows.")] }
            if part.expected.rows.contains(where: { $0.count != part.columns.count }) {
                return [issue(.error, "An expected row does not match the declared column count.")]
            }
        case .matching:
            if part.items.isEmpty || part.targets.isEmpty || part.expected.pairs.isEmpty {
                return [issue(.error, "Matching part needs items, targets, and expected pairs.")]
            }
        case .ordering:
            if part.items.isEmpty || part.expected.order.isEmpty {
                return [issue(.error, "Ordering part needs items and an expected order.")]
            }
        }
        return []
    }
}
