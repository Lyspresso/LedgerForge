use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseEnumError {
    pub enum_name: &'static str,
    pub value: String,
}

impl fmt::Display for ParseEnumError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "unknown {} value '{}'",
            self.enum_name, self.value
        )
    }
}

impl std::error::Error for ParseEnumError {}

macro_rules! string_enum {
    (
        $(#[$meta:meta])*
        pub enum $name:ident {
            $($(#[$variant_meta:meta])* $variant:ident => $value:literal),+ $(,)?
        }
    ) => {
        $(#[$meta])*
        pub enum $name {
            $($(#[$variant_meta])* #[serde(rename = $value)] $variant),+
        }

        impl $name {
            pub const ALL: &'static [Self] = &[$(Self::$variant),+];

            pub const fn as_str(self) -> &'static str {
                match self {
                    $(Self::$variant => $value),+
                }
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str(self.as_str())
            }
        }

        impl FromStr for $name {
            type Err = ParseEnumError;

            fn from_str(value: &str) -> Result<Self, Self::Err> {
                match value {
                    $($value => Ok(Self::$variant)),+,
                    _ => Err(ParseEnumError {
                        enum_name: stringify!($name),
                        value: value.to_owned(),
                    }),
                }
            }
        }
    };
}

string_enum! {
    #[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
    pub enum QuestionShell {
        MultipleChoice => "multiple_choice",
        StandaloneCalculation => "standalone_calculation",
        #[default]
        Multipart => "multipart",
        MultipleCase => "multiple_case",
        Lifecycle => "lifecycle",
        Comprehensive => "comprehensive",
        MemoResearch => "memo_research",
    }
}

string_enum! {
    #[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
    pub enum VariationStyle {
        #[default]
        Core => "core",
        NumberVariant => "number_variant",
        AlternateAngle => "alternate_angle",
        Counterfactual => "counterfactual",
        Diagnostic => "diagnostic",
        LongPath => "long_path",
        IndependentCases => "independent_cases",
        StaffDraft => "staff_draft",
    }
}

string_enum! {
    /// Pedagogical formats are independent of the response editor primitive.
    #[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
    pub enum QuestionFormat {
        SingleNumber => "single_number",
        FormulaSetup => "formula_setup",
        InitialJournalEntry => "initial_journal_entry",
        AdjustingJournalEntry => "adjusting_journal_entry",
        CorrectingJournalEntry => "correcting_journal_entry",
        ClosingReversingEntry => "closing_reversing_entry",
        SettlementEntry => "settlement_entry",
        EntryOrNoEntry => "entry_or_no_entry",
        MultiPeriodSchedule => "multi_period_schedule",
        Rollforward => "rollforward",
        TAccount => "t_account",
        Backsolve => "backsolve",
        WorksheetTrialBalance => "worksheet_trial_balance",
        FullStatement => "full_statement",
        PartialStatement => "partial_statement",
        PresentationClassificationGrid => "presentation_classification_grid",
        EffectMatrix => "effect_matrix",
        IncludeExcludeTable => "include_exclude_table",
        DisclosureDrafting => "disclosure_drafting",
        ReconciliationProof => "reconciliation_proof",
        ErrorCorrection => "error_correction",
        CorrectVersusIncorrect => "correct_versus_incorrect",
        AlternativeMethodComparison => "alternative_method_comparison",
        SensitivityChangedFact => "sensitivity_changed_fact",
        ThresholdCriteriaTest => "threshold_criteria_test",
        RankingSequentialInclusion => "ranking_sequential_inclusion",
        OrderingTimeline => "ordering_timeline",
        RatioAnalysis => "ratio_analysis",
        #[default]
        ShortExplanation => "short_explanation",
        ClaimEvaluation => "claim_evaluation",
        TrueFalseCorrection => "true_false_correction",
        MatchingMappingSorting => "matching_mapping_sorting",
        CodificationResearch => "codification_research",
        AisSourceDocumentFlow => "ais_source_document_flow",
        MultipleChoice => "multiple_choice",
    }
}

string_enum! {
    /// Twelve response primitives compose to cover every pedagogical format.
    #[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
    pub enum ResponseKind {
        SingleChoice => "single_choice",
        MultipleChoice => "multiple_choice",
        Number => "number",
        Formula => "formula",
        ShortText => "short_text",
        #[default]
        LongText => "long_text",
        Journal => "journal",
        Table => "table",
        Matching => "matching",
        Ordering => "ordering",
        TrueFalse => "true_false",
        NoEntry => "no_entry",
    }
}

impl ResponseKind {
    pub const fn default_format(self) -> QuestionFormat {
        match self {
            Self::SingleChoice | Self::MultipleChoice => QuestionFormat::MultipleChoice,
            Self::Number => QuestionFormat::SingleNumber,
            Self::Formula => QuestionFormat::FormulaSetup,
            Self::ShortText | Self::LongText => QuestionFormat::ShortExplanation,
            Self::Journal => QuestionFormat::InitialJournalEntry,
            Self::Table => QuestionFormat::MultiPeriodSchedule,
            Self::Matching => QuestionFormat::MatchingMappingSorting,
            Self::Ordering => QuestionFormat::OrderingTimeline,
            Self::TrueFalse => QuestionFormat::TrueFalseCorrection,
            Self::NoEntry => QuestionFormat::EntryOrNoEntry,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuestionOption {
    pub id: String,
    pub text: String,
}

impl QuestionOption {
    pub fn new(id: impl Into<String>, text: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            text: text.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct ExpectedAnswer {
    pub scalar: String,
    pub selections: Vec<String>,
    pub rows: Vec<Vec<String>>,
    pub pairs: BTreeMap<String, String>,
    pub order: Vec<String>,
    pub accepted: Vec<String>,
    pub tolerance: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct QuestionPart {
    pub id: String,
    pub kind: ResponseKind,
    pub format: QuestionFormat,
    pub points: f64,
    pub prompt_markdown: String,
    pub options: Vec<QuestionOption>,
    pub columns: Vec<String>,
    pub items: Vec<QuestionOption>,
    pub targets: Vec<QuestionOption>,
    pub expected: ExpectedAnswer,
    pub rubric_markdown: String,
    pub settings: BTreeMap<String, String>,
}

impl Default for QuestionPart {
    fn default() -> Self {
        Self {
            id: String::new(),
            kind: ResponseKind::LongText,
            format: QuestionFormat::ShortExplanation,
            points: 1.0,
            prompt_markdown: String::new(),
            options: Vec::new(),
            columns: Vec::new(),
            items: Vec::new(),
            targets: Vec::new(),
            expected: ExpectedAnswer::default(),
            rubric_markdown: String::new(),
            settings: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AccountingQuestion {
    pub id: String,
    pub title: String,
    pub shell: QuestionShell,
    pub variation: VariationStyle,
    pub formats: Vec<QuestionFormat>,
    pub scenario_markdown: String,
    pub parts: Vec<QuestionPart>,
    pub tags: Vec<String>,
    pub source_name: String,
}

impl Default for AccountingQuestion {
    fn default() -> Self {
        Self {
            id: String::new(),
            title: "Untitled Question".to_owned(),
            shell: QuestionShell::default(),
            variation: VariationStyle::default(),
            formats: Vec::new(),
            scenario_markdown: String::new(),
            parts: Vec::new(),
            tags: Vec::new(),
            source_name: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct QuestionPack {
    pub version: u32,
    pub title: String,
    pub questions: Vec<AccountingQuestion>,
}

impl Default for QuestionPack {
    fn default() -> Self {
        Self {
            version: 1,
            title: "Imported Markdown".to_owned(),
            questions: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct StudentAnswer {
    pub scalar: String,
    pub selections: Vec<String>,
    pub rows: Vec<Vec<String>>,
    pub pairs: BTreeMap<String, String>,
    pub order: Vec<String>,
    pub notes: String,
}

impl StudentAnswer {
    pub fn is_blank(&self) -> bool {
        self.scalar.trim().is_empty()
            && self.selections.is_empty()
            && self
                .rows
                .iter()
                .all(|row| row.iter().all(|cell| cell.trim().is_empty()))
            && self.pairs.is_empty()
            && self.order.is_empty()
            && self.notes.trim().is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct AttemptRecord {
    /// Stable locally generated identifier. Stored as text to remain implementation-neutral.
    pub id: String,
    pub question_id: String,
    pub answers: BTreeMap<String, StudentAnswer>,
    /// Part identifiers explicitly submitted by the student.
    ///
    /// Older saved attempts predate this field, so it must deserialize to an
    /// empty set instead of treating merely entered answers as submitted.
    #[serde(default)]
    pub checked_part_ids: BTreeSet<String>,
    pub self_reviews: BTreeMap<String, bool>,
    pub updated_at_unix_ms: u64,
}
