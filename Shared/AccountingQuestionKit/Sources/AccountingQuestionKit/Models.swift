import Foundation

public enum QuestionShell: String, Codable, CaseIterable, Sendable {
    case multipleChoice = "multiple_choice"
    case standaloneCalculation = "standalone_calculation"
    case multipart = "multipart"
    case multipleCase = "multiple_case"
    case lifecycle = "lifecycle"
    case comprehensive = "comprehensive"
    case memoResearch = "memo_research"
}

public enum VariationStyle: String, Codable, CaseIterable, Sendable {
    case core
    case numberVariant = "number_variant"
    case alternateAngle = "alternate_angle"
    case counterfactual
    case diagnostic
    case longPath = "long_path"
    case independentCases = "independent_cases"
    case staffDraft = "staff_draft"
}

/// These are pedagogical formats. `ResponseKind` below controls the editor.
public enum QuestionFormat: String, Codable, CaseIterable, Sendable {
    case singleNumber = "single_number"
    case formulaSetup = "formula_setup"
    case initialJournalEntry = "initial_journal_entry"
    case adjustingJournalEntry = "adjusting_journal_entry"
    case correctingJournalEntry = "correcting_journal_entry"
    case closingReversingEntry = "closing_reversing_entry"
    case settlementEntry = "settlement_entry"
    case entryOrNoEntry = "entry_or_no_entry"
    case multiPeriodSchedule = "multi_period_schedule"
    case rollforward
    case tAccount = "t_account"
    case backsolve
    case worksheetTrialBalance = "worksheet_trial_balance"
    case fullStatement = "full_statement"
    case partialStatement = "partial_statement"
    case presentationClassificationGrid = "presentation_classification_grid"
    case effectMatrix = "effect_matrix"
    case includeExcludeTable = "include_exclude_table"
    case disclosureDrafting = "disclosure_drafting"
    case reconciliationProof = "reconciliation_proof"
    case errorCorrection = "error_correction"
    case correctVersusIncorrect = "correct_versus_incorrect"
    case alternativeMethodComparison = "alternative_method_comparison"
    case sensitivityChangedFact = "sensitivity_changed_fact"
    case thresholdCriteriaTest = "threshold_criteria_test"
    case rankingSequentialInclusion = "ranking_sequential_inclusion"
    case orderingTimeline = "ordering_timeline"
    case ratioAnalysis = "ratio_analysis"
    case shortExplanation = "short_explanation"
    case claimEvaluation = "claim_evaluation"
    case trueFalseCorrection = "true_false_correction"
    case matchingMappingSorting = "matching_mapping_sorting"
    case codificationResearch = "codification_research"
    case aisSourceDocumentFlow = "ais_source_document_flow"
    case multipleChoice = "multiple_choice"
}

/// Twelve editor primitives combine to express every pedagogical format.
public enum ResponseKind: String, Codable, CaseIterable, Sendable {
    case singleChoice = "single_choice"
    case multipleChoice = "multiple_choice"
    case number
    case formula
    case shortText = "short_text"
    case longText = "long_text"
    case journal
    case table
    case matching
    case ordering
    case trueFalse = "true_false"
    case noEntry = "no_entry"
}

public struct QuestionOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct ExpectedAnswer: Codable, Equatable, Sendable {
    public var scalar: String
    public var selections: [String]
    public var rows: [[String]]
    public var pairs: [String: String]
    public var order: [String]
    public var accepted: [String]
    public var tolerance: Double?

    public init(
        scalar: String = "",
        selections: [String] = [],
        rows: [[String]] = [],
        pairs: [String: String] = [:],
        order: [String] = [],
        accepted: [String] = [],
        tolerance: Double? = nil
    ) {
        self.scalar = scalar
        self.selections = selections
        self.rows = rows
        self.pairs = pairs
        self.order = order
        self.accepted = accepted
        self.tolerance = tolerance
    }
}

public struct QuestionPart: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var kind: ResponseKind
    public var format: QuestionFormat
    public var points: Double
    public var promptMarkdown: String
    public var options: [QuestionOption]
    public var columns: [String]
    public var items: [QuestionOption]
    public var targets: [QuestionOption]
    public var expected: ExpectedAnswer
    public var rubricMarkdown: String
    public var settings: [String: String]

    public init(
        id: String,
        kind: ResponseKind,
        format: QuestionFormat,
        points: Double = 1,
        promptMarkdown: String,
        options: [QuestionOption] = [],
        columns: [String] = [],
        items: [QuestionOption] = [],
        targets: [QuestionOption] = [],
        expected: ExpectedAnswer = ExpectedAnswer(),
        rubricMarkdown: String = "",
        settings: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.format = format
        self.points = points
        self.promptMarkdown = promptMarkdown
        self.options = options
        self.columns = columns
        self.items = items
        self.targets = targets
        self.expected = expected
        self.rubricMarkdown = rubricMarkdown
        self.settings = settings
    }
}

public struct AccountingQuestion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var shell: QuestionShell
    public var variation: VariationStyle
    public var formats: [QuestionFormat]
    public var scenarioMarkdown: String
    public var parts: [QuestionPart]
    public var tags: [String]
    public var sourceName: String

    public init(
        id: String,
        title: String,
        shell: QuestionShell,
        variation: VariationStyle = .core,
        formats: [QuestionFormat],
        scenarioMarkdown: String,
        parts: [QuestionPart],
        tags: [String] = [],
        sourceName: String = ""
    ) {
        self.id = id
        self.title = title
        self.shell = shell
        self.variation = variation
        self.formats = formats
        self.scenarioMarkdown = scenarioMarkdown
        self.parts = parts
        self.tags = tags
        self.sourceName = sourceName
    }
}

public struct QuestionPack: Codable, Equatable, Sendable {
    public var version: Int
    public var title: String
    public var questions: [AccountingQuestion]

    public init(version: Int = 1, title: String, questions: [AccountingQuestion]) {
        self.version = version
        self.title = title
        self.questions = questions
    }
}

public struct StudentAnswer: Codable, Equatable, Sendable {
    public var scalar: String
    public var selections: [String]
    public var rows: [[String]]
    public var pairs: [String: String]
    public var order: [String]
    public var notes: String

    public init(
        scalar: String = "",
        selections: [String] = [],
        rows: [[String]] = [],
        pairs: [String: String] = [:],
        order: [String] = [],
        notes: String = ""
    ) {
        self.scalar = scalar
        self.selections = selections
        self.rows = rows
        self.pairs = pairs
        self.order = order
        self.notes = notes
    }

    public var isBlank: Bool {
        scalar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selections.isEmpty
            && rows.allSatisfy { $0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
            && pairs.isEmpty
            && order.isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AttemptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let questionID: String
    public var answers: [String: StudentAnswer]
    public var selfReviews: [String: Bool]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        questionID: String,
        answers: [String: StudentAnswer] = [:],
        selfReviews: [String: Bool] = [:],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.questionID = questionID
        self.answers = answers
        self.selfReviews = selfReviews
        self.updatedAt = updatedAt
    }
}
