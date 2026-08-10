import AccountingQuestionKit
import SwiftUI

extension QuestionShell {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .standaloneCalculation: "Calculation"
        case .multipart: "Multipart"
        case .multipleCase: "Multiple case"
        case .lifecycle: "Lifecycle"
        case .comprehensive: "Comprehensive"
        case .memoResearch: "Memo and research"
        }
    }

    var symbolName: String {
        switch self {
        case .multipleChoice: "checkmark.circle"
        case .standaloneCalculation: "function"
        case .multipart: "list.number"
        case .multipleCase: "square.grid.2x2"
        case .lifecycle: "arrow.trianglehead.2.clockwise.rotate.90"
        case .comprehensive: "doc.text.magnifyingglass"
        case .memoResearch: "text.book.closed"
        }
    }
}

extension VariationStyle {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .core: "Core"
        case .numberVariant: "Number variant"
        case .alternateAngle: "Alternate angle"
        case .counterfactual: "Counterfactual"
        case .diagnostic: "Diagnostic"
        case .longPath: "Long path"
        case .independentCases: "Independent cases"
        case .staffDraft: "Staff draft"
        }
    }
}

extension ResponseKind {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .singleChoice: "Single choice"
        case .multipleChoice: "Multiple choice"
        case .number: "Number"
        case .formula: "Formula"
        case .shortText: "Short response"
        case .longText: "Long response"
        case .journal: "Journal entry"
        case .table: "Table"
        case .matching: "Matching"
        case .ordering: "Ordering"
        case .trueFalse: "True or false"
        case .noEntry: "Entry or no entry"
        }
    }

    var symbolName: String {
        switch self {
        case .singleChoice: "smallcircle.filled.circle"
        case .multipleChoice: "checklist.checked"
        case .number: "number"
        case .formula: "function"
        case .shortText: "text.cursor"
        case .longText: "text.alignleft"
        case .journal: "book.pages"
        case .table: "tablecells"
        case .matching: "arrow.left.arrow.right"
        case .ordering: "list.number"
        case .trueFalse: "checkmark.circle.trianglebadge.exclamationmark"
        case .noEntry: "questionmark.diamond"
        }
    }
}

extension QuestionFormat {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .singleNumber: "Single-number computation"
        case .formulaSetup: "Formula setup"
        case .initialJournalEntry: "Initial-recognition entry"
        case .adjustingJournalEntry: "Adjusting entry"
        case .correctingJournalEntry: "Correcting entry"
        case .closingReversingEntry: "Closing or reversing entry"
        case .settlementEntry: "Settlement entry"
        case .entryOrNoEntry: "Entry-or-no-entry judgment"
        case .multiPeriodSchedule: "Multi-period schedule"
        case .rollforward: "Rollforward"
        case .tAccount: "T-account"
        case .backsolve: "Back-solving"
        case .worksheetTrialBalance: "Worksheet or trial balance"
        case .fullStatement: "Full financial statement"
        case .partialStatement: "Partial statement"
        case .presentationClassificationGrid: "Classification grid"
        case .effectMatrix: "Effect matrix"
        case .includeExcludeTable: "Include or exclude"
        case .disclosureDrafting: "Disclosure drafting"
        case .reconciliationProof: "Reconciliation or proof"
        case .errorCorrection: "Error correction"
        case .correctVersusIncorrect: "Correct versus incorrect"
        case .alternativeMethodComparison: "Method comparison"
        case .sensitivityChangedFact: "Sensitivity analysis"
        case .thresholdCriteriaTest: "Threshold test"
        case .rankingSequentialInclusion: "Ranking"
        case .orderingTimeline: "Timeline ordering"
        case .ratioAnalysis: "Ratio analysis"
        case .shortExplanation: "Short explanation"
        case .claimEvaluation: "Claim evaluation"
        case .trueFalseCorrection: "True or false with correction"
        case .matchingMappingSorting: "Matching, mapping, or sorting"
        case .codificationResearch: "Codification research"
        case .aisSourceDocumentFlow: "AIS document flow"
        case .multipleChoice: "Multiple choice"
        }
    }
}

extension LibraryStudyStatus {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .completed: "Completed"
        }
    }

    var symbolName: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        }
    }
}

extension GradeStatus {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .correct: "Correct"
        case .incorrect: "Keep working"
        case .needsSelfReview: "Self-review needed"
        case .unanswered: "Response needed"
        }
    }

    var symbolName: String {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .incorrect: "arrow.clockwise.circle.fill"
        case .needsSelfReview: "person.crop.circle.badge.questionmark"
        case .unanswered: "pencil.circle"
        }
    }

    var tint: Color {
        switch self {
        case .correct: .green
        case .incorrect: .orange
        case .needsSelfReview: .blue
        case .unanswered: .secondary
        }
    }
}

extension QuestionPart {
    var startsWithSelfReview: Bool {
        switch kind {
        case .longText:
            true
        case .shortText:
            expected.accepted.isEmpty
        default:
            false
        }
    }

    var requiresSelfReview: Bool {
        startsWithSelfReview
            || (kind == .trueFalse
                && expected.scalar.caseInsensitiveCompare("False") == .orderedSame
                && !rubricMarkdown.isEmpty)
            || (kind == .noEntry && !rubricMarkdown.isEmpty)
    }

    var stableColumns: [StableColumn] {
        let sourceColumns = columns.isEmpty ? [String(localized: "Response")] : columns
        return sourceColumns.enumerated().map { index, title in
            StableColumn(id: "\(id)-column-\(index)", title: title)
        }
    }
}
