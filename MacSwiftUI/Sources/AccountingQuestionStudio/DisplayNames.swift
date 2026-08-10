import AccountingQuestionKit
import Foundation

extension QuestionShell {
    var localizedName: LocalizedStringResource {
        switch self {
        case .multipleChoice: "Multiple Choice"
        case .standaloneCalculation: "Standalone Calculation"
        case .multipart: "Multipart Problem"
        case .multipleCase: "Multiple Cases"
        case .lifecycle: "Lifecycle Problem"
        case .comprehensive: "Comprehensive Case"
        case .memoResearch: "Memo or Research"
        }
    }
}

extension VariationStyle {
    var localizedName: LocalizedStringResource {
        switch self {
        case .core: "Core"
        case .numberVariant: "Number Variant"
        case .alternateAngle: "Alternate Angle"
        case .counterfactual: "Counterfactual"
        case .diagnostic: "Diagnostic"
        case .longPath: "Long Multi-Period"
        case .independentCases: "Independent Cases"
        case .staffDraft: "Staff Draft Correction"
        }
    }
}

extension ResponseKind {
    var localizedName: LocalizedStringResource {
        switch self {
        case .singleChoice: "Single Choice"
        case .multipleChoice: "Multiple Choice"
        case .number: "Number"
        case .formula: "Formula"
        case .shortText: "Short Text"
        case .longText: "Long Text"
        case .journal: "Journal Entry"
        case .table: "Table"
        case .matching: "Matching"
        case .ordering: "Ordering"
        case .trueFalse: "True or False"
        case .noEntry: "Entry or No Entry"
        }
    }
}

extension QuestionFormat {
    var localizedName: LocalizedStringResource {
        switch self {
        case .singleNumber: "Single-Number Computation"
        case .formulaSetup: "Formula or Function Setup"
        case .initialJournalEntry: "Initial-Recognition Entry"
        case .adjustingJournalEntry: "Adjusting Entry"
        case .correctingJournalEntry: "Correcting or Restatement Entry"
        case .closingReversingEntry: "Closing or Reversing Entry"
        case .settlementEntry: "Settlement Entry"
        case .entryOrNoEntry: "Entry or No Entry"
        case .multiPeriodSchedule: "Multi-Period Schedule"
        case .rollforward: "Rollforward"
        case .tAccount: "T-Account or Ledger"
        case .backsolve: "Missing Amount or Back-Solving"
        case .worksheetTrialBalance: "Worksheet or Trial Balance"
        case .fullStatement: "Full Financial Statement"
        case .partialStatement: "Partial Statement or Excerpt"
        case .presentationClassificationGrid: "Presentation or Classification Grid"
        case .effectMatrix: "Effect Matrix"
        case .includeExcludeTable: "Include or Exclude Table"
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
        case .codificationResearch: "Codification Research"
        case .aisSourceDocumentFlow: "AIS Document and Journal Flow"
        case .multipleChoice: "Single-Best-Answer Multiple Choice"
        }
    }
}

extension GradeStatus {
    var localizedName: LocalizedStringResource {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Needs Another Look"
        case .needsSelfReview: "Self-Review Needed"
        case .unanswered: "Not Answered"
        }
    }

    var systemImage: String {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        case .needsSelfReview: "person.crop.circle.badge.questionmark"
        case .unanswered: "circle.dashed"
        }
    }
}
