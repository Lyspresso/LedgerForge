//! A small, deterministic spreadsheet evaluator for answer grids.
//!
//! Formulas are deliberately kept as the raw persisted cell text. Evaluation is
//! side-effect free, bounded, and produces ordinary spreadsheet-style errors
//! instead of panicking on malformed input, invalid references, or cycles.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

const MAX_FORMULA_BYTES: usize = 16_384;
const MAX_TOKENS: usize = 4_096;
const MAX_PARSE_DEPTH: usize = 128;
const MAX_EVAL_DEPTH: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpreadsheetErrorKind {
    Value,
    Reference,
    DivisionByZero,
    Cycle,
}

impl SpreadsheetErrorKind {
    pub const fn code(self) -> &'static str {
        match self {
            Self::Value => "#VALUE!",
            Self::Reference => "#REF!",
            Self::DivisionByZero => "#DIV/0!",
            Self::Cycle => "#CYCLE!",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpreadsheetError {
    pub kind: SpreadsheetErrorKind,
    pub detail: String,
}

impl SpreadsheetError {
    fn new(kind: SpreadsheetErrorKind, detail: impl Into<String>) -> Self {
        Self {
            kind,
            detail: detail.into(),
        }
    }

    fn value(detail: impl Into<String>) -> Self {
        Self::new(SpreadsheetErrorKind::Value, detail)
    }

    fn reference(detail: impl Into<String>) -> Self {
        Self::new(SpreadsheetErrorKind::Reference, detail)
    }

    fn division_by_zero(detail: impl Into<String>) -> Self {
        Self::new(SpreadsheetErrorKind::DivisionByZero, detail)
    }

    fn cycle(detail: impl Into<String>) -> Self {
        Self::new(SpreadsheetErrorKind::Cycle, detail)
    }
}

impl fmt::Display for SpreadsheetError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.detail.is_empty() {
            formatter.write_str(self.kind.code())
        } else {
            write!(formatter, "{} {}", self.kind.code(), self.detail)
        }
    }
}

impl std::error::Error for SpreadsheetError {}

#[derive(Debug, Clone, PartialEq)]
pub enum CellValue {
    Blank,
    Number(f64),
    Text(String),
    Boolean(bool),
    Error(SpreadsheetError),
}

impl CellValue {
    pub fn display_text(&self) -> String {
        match self {
            Self::Blank => String::new(),
            Self::Number(number) => format_number(*number),
            Self::Text(text) => text.clone(),
            Self::Boolean(value) => {
                if *value {
                    "TRUE".to_owned()
                } else {
                    "FALSE".to_owned()
                }
            }
            Self::Error(error) => error.kind.code().to_owned(),
        }
    }

    pub const fn error(&self) -> Option<&SpreadsheetError> {
        match self {
            Self::Error(error) => Some(error),
            _ => None,
        }
    }
}

/// Evaluate every stored cell while preserving the ragged shape of `rows`.
pub fn evaluate_grid(rows: &[Vec<String>]) -> Vec<Vec<CellValue>> {
    let mut evaluator = GridEvaluator::new(rows);
    rows.iter()
        .enumerate()
        .map(|(row, cells)| {
            (0..cells.len())
                .map(|column| evaluator.evaluate_cell(row, column))
                .collect()
        })
        .collect()
}

/// Return evaluated display strings for deterministic grading.
pub fn evaluated_rows(rows: &[Vec<String>]) -> Vec<Vec<String>> {
    evaluate_grid(rows)
        .into_iter()
        .map(|row| row.into_iter().map(|value| value.display_text()).collect())
        .collect()
}

/// Evaluate a self-contained standalone formula. Cell references intentionally
/// remain grid-scoped and therefore return a reference or cycle error here.
pub fn evaluate_formula(formula: &str) -> CellValue {
    evaluate_grid(&[vec![formula.to_owned()]])
        .into_iter()
        .next()
        .and_then(|row| row.into_iter().next())
        .unwrap_or(CellValue::Blank)
}

#[derive(Debug)]
struct GridEvaluator<'a> {
    rows: &'a [Vec<String>],
    column_count: usize,
    cache: BTreeMap<(usize, usize), CellValue>,
    visiting: BTreeSet<(usize, usize)>,
}

impl<'a> GridEvaluator<'a> {
    fn new(rows: &'a [Vec<String>]) -> Self {
        Self {
            rows,
            column_count: rows.iter().map(Vec::len).max().unwrap_or(0),
            cache: BTreeMap::new(),
            visiting: BTreeSet::new(),
        }
    }

    fn evaluate_cell(&mut self, row: usize, column: usize) -> CellValue {
        self.evaluate_cell_at(row, column, 0)
    }

    fn evaluate_cell_at(&mut self, row: usize, column: usize, depth: usize) -> CellValue {
        if depth > MAX_EVAL_DEPTH {
            return CellValue::Error(SpreadsheetError::value(
                "cell dependency chain is too deeply nested",
            ));
        }
        if row >= self.rows.len() || column >= self.column_count {
            return CellValue::Error(SpreadsheetError::reference(format!(
                "cell {} is outside the grid",
                cell_name(row, column)
            )));
        }
        if let Some(value) = self.cache.get(&(row, column)) {
            return value.clone();
        }
        if !self.visiting.insert((row, column)) {
            return CellValue::Error(SpreadsheetError::cycle(format!(
                "{} depends on itself",
                cell_name(row, column)
            )));
        }

        let raw = self
            .rows
            .get(row)
            .and_then(|cells| cells.get(column))
            .cloned()
            .unwrap_or_default();
        let value = self.evaluate_raw(&raw, depth + 1);
        self.visiting.remove(&(row, column));
        self.cache.insert((row, column), value.clone());
        value
    }

    fn evaluate_raw(&mut self, raw: &str, depth: usize) -> CellValue {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return CellValue::Blank;
        }
        let Some(formula) = trimmed.strip_prefix('=') else {
            return parse_literal_number(trimmed)
                .map_or_else(|| CellValue::Text(trimmed.to_owned()), CellValue::Number);
        };
        match parse_formula(formula).and_then(|expression| self.evaluate(&expression, depth)) {
            Ok(value) => value,
            Err(error) => CellValue::Error(error),
        }
    }

    fn evaluate(&mut self, expression: &Expr, depth: usize) -> Result<CellValue, SpreadsheetError> {
        if depth > MAX_EVAL_DEPTH {
            return Err(SpreadsheetError::value(
                "formula evaluation is too deeply nested",
            ));
        }
        let next_depth = depth + 1;
        match expression {
            Expr::Number(number) => Ok(CellValue::Number(*number)),
            Expr::Text(text) => Ok(CellValue::Text(text.clone())),
            Expr::Boolean(value) => Ok(CellValue::Boolean(*value)),
            Expr::Cell(reference) => {
                Ok(self.evaluate_cell_at(reference.row, reference.column, next_depth))
            }
            Expr::Range(_, _) => Err(SpreadsheetError::value(
                "a range cannot be used as a single value",
            )),
            Expr::Unary(operator, expression) => {
                let number = self.numeric(expression, next_depth)?;
                finite_number(match operator {
                    UnaryOperator::Plus => number,
                    UnaryOperator::Minus => -number,
                    UnaryOperator::Percent => number / 100.0,
                })
                .map(CellValue::Number)
            }
            Expr::Binary(left, operator, right) => {
                self.evaluate_binary(left, *operator, right, next_depth)
            }
            Expr::Function(name, arguments) => self.evaluate_function(name, arguments, next_depth),
        }
    }

    fn evaluate_binary(
        &mut self,
        left: &Expr,
        operator: BinaryOperator,
        right: &Expr,
        depth: usize,
    ) -> Result<CellValue, SpreadsheetError> {
        if operator.is_comparison() {
            let left = self.evaluate(left, depth)?;
            let right = self.evaluate(right, depth)?;
            return compare_values(&left, operator, &right).map(CellValue::Boolean);
        }

        let left = self.numeric(left, depth)?;
        let right = self.numeric(right, depth)?;
        let result = match operator {
            BinaryOperator::Add => left + right,
            BinaryOperator::Subtract => left - right,
            BinaryOperator::Multiply => left * right,
            BinaryOperator::Divide => {
                if right == 0.0 {
                    return Err(SpreadsheetError::division_by_zero(
                        "a formula divided by zero",
                    ));
                }
                left / right
            }
            BinaryOperator::Power => left.powf(right),
            BinaryOperator::Equal
            | BinaryOperator::NotEqual
            | BinaryOperator::Less
            | BinaryOperator::LessOrEqual
            | BinaryOperator::Greater
            | BinaryOperator::GreaterOrEqual => {
                return Err(SpreadsheetError::value("invalid arithmetic operator"));
            }
        };
        finite_number(result).map(CellValue::Number)
    }

    fn evaluate_function(
        &mut self,
        name: &str,
        arguments: &[Expr],
        depth: usize,
    ) -> Result<CellValue, SpreadsheetError> {
        let name = name.to_ascii_uppercase();
        if name == "IF" {
            if !(2..=3).contains(&arguments.len()) {
                return Err(argument_count("IF", "two or three"));
            }
            let condition = self.evaluate(&arguments[0], depth)?;
            let chosen = if truthy(&condition)? {
                &arguments[1]
            } else if let Some(otherwise) = arguments.get(2) {
                otherwise
            } else {
                return Ok(CellValue::Boolean(false));
            };
            return self.evaluate(chosen, depth);
        }

        match name.as_str() {
            "SUM" | "AVERAGE" | "MIN" | "MAX" => {
                let numbers = self.aggregate_numbers(arguments, depth)?;
                let result = match name.as_str() {
                    "SUM" => numbers.iter().sum(),
                    "AVERAGE" => {
                        if numbers.is_empty() {
                            return Err(SpreadsheetError::division_by_zero(
                                "AVERAGE has no numeric cells",
                            ));
                        }
                        numbers.iter().sum::<f64>() / numbers.len() as f64
                    }
                    "MIN" => numbers.into_iter().reduce(f64::min).unwrap_or(0.0),
                    "MAX" => numbers.into_iter().reduce(f64::max).unwrap_or(0.0),
                    _ => {
                        return Err(SpreadsheetError::value("invalid aggregate function"));
                    }
                };
                finite_number(result).map(CellValue::Number)
            }
            "ROUND" => {
                require_argument_range("ROUND", arguments, 1, 2)?;
                let number = self.numeric(&arguments[0], depth)?;
                let digits = if let Some(expression) = arguments.get(1) {
                    self.numeric(expression, depth)?.round() as i32
                } else {
                    0
                }
                .clamp(-308, 308);
                let factor = 10_f64.powi(digits.abs());
                let result = if digits >= 0 {
                    (number * factor).round() / factor
                } else {
                    (number / factor).round() * factor
                };
                finite_number(result).map(CellValue::Number)
            }
            "ABS" => {
                require_argument_count("ABS", arguments, 1)?;
                finite_number(self.numeric(&arguments[0], depth)?.abs()).map(CellValue::Number)
            }
            "PV" => {
                require_argument_range("PV", arguments, 3, 5)?;
                let values = self.numeric_arguments(arguments, depth)?;
                finance_pv(&values).map(CellValue::Number)
            }
            "FV" => {
                require_argument_range("FV", arguments, 3, 5)?;
                let values = self.numeric_arguments(arguments, depth)?;
                finance_fv(&values).map(CellValue::Number)
            }
            "PMT" => {
                require_argument_range("PMT", arguments, 3, 5)?;
                let values = self.numeric_arguments(arguments, depth)?;
                finance_pmt(&values).map(CellValue::Number)
            }
            "NPV" => {
                if arguments.len() < 2 {
                    return Err(argument_count("NPV", "at least two"));
                }
                let rate = self.numeric(&arguments[0], depth)?;
                let cash_flows = self.aggregate_numbers(&arguments[1..], depth)?;
                finance_npv(rate, &cash_flows).map(CellValue::Number)
            }
            _ => Err(SpreadsheetError::value(format!(
                "unknown function '{name}'"
            ))),
        }
    }

    fn numeric_arguments(
        &mut self,
        expressions: &[Expr],
        depth: usize,
    ) -> Result<Vec<f64>, SpreadsheetError> {
        expressions
            .iter()
            .map(|expression| self.numeric(expression, depth))
            .collect()
    }

    fn numeric(&mut self, expression: &Expr, depth: usize) -> Result<f64, SpreadsheetError> {
        let value = self.evaluate(expression, depth)?;
        numeric_value(&value)
    }

    fn aggregate_numbers(
        &mut self,
        expressions: &[Expr],
        depth: usize,
    ) -> Result<Vec<f64>, SpreadsheetError> {
        let mut result = Vec::new();
        for expression in expressions {
            match expression {
                Expr::Range(start, end) => {
                    let (first_row, last_row) = sorted_pair(start.row, end.row);
                    let (first_column, last_column) = sorted_pair(start.column, end.column);
                    if last_row >= self.rows.len() || last_column >= self.column_count {
                        return Err(SpreadsheetError::reference(format!(
                            "range {}:{} is outside the grid",
                            start.name, end.name
                        )));
                    }
                    let cell_count = last_row
                        .saturating_sub(first_row)
                        .saturating_add(1)
                        .saturating_mul(last_column.saturating_sub(first_column).saturating_add(1));
                    if cell_count > 1_000_000 {
                        return Err(SpreadsheetError::value("range contains too many cells"));
                    }
                    for row in first_row..=last_row {
                        for column in first_column..=last_column {
                            match self.evaluate_cell_at(row, column, depth + 1) {
                                CellValue::Number(number) => result.push(number),
                                CellValue::Blank | CellValue::Text(_) | CellValue::Boolean(_) => {}
                                CellValue::Error(error) => return Err(error),
                            }
                        }
                    }
                }
                _ => match self.evaluate(expression, depth)? {
                    CellValue::Number(number) => result.push(number),
                    CellValue::Blank => result.push(0.0),
                    CellValue::Boolean(value) => result.push(if value { 1.0 } else { 0.0 }),
                    CellValue::Text(text) => {
                        let Some(number) = parse_literal_number(&text) else {
                            return Err(SpreadsheetError::value(
                                "a function argument is not numeric",
                            ));
                        };
                        result.push(number);
                    }
                    CellValue::Error(error) => return Err(error),
                },
            }
        }
        Ok(result)
    }
}

fn numeric_value(value: &CellValue) -> Result<f64, SpreadsheetError> {
    match value {
        CellValue::Number(number) => Ok(*number),
        CellValue::Blank => Ok(0.0),
        CellValue::Boolean(value) => Ok(if *value { 1.0 } else { 0.0 }),
        CellValue::Text(text) => parse_literal_number(text)
            .ok_or_else(|| SpreadsheetError::value("a referenced cell is not numeric")),
        CellValue::Error(error) => Err(error.clone()),
    }
}

fn truthy(value: &CellValue) -> Result<bool, SpreadsheetError> {
    match value {
        CellValue::Blank => Ok(false),
        CellValue::Number(number) => Ok(*number != 0.0),
        CellValue::Boolean(value) => Ok(*value),
        CellValue::Text(text) if text.eq_ignore_ascii_case("true") => Ok(true),
        CellValue::Text(text) if text.eq_ignore_ascii_case("false") => Ok(false),
        CellValue::Text(text) => parse_literal_number(text)
            .map(|number| number != 0.0)
            .ok_or_else(|| SpreadsheetError::value("IF condition is not logical or numeric")),
        CellValue::Error(error) => Err(error.clone()),
    }
}

fn compare_values(
    left: &CellValue,
    operator: BinaryOperator,
    right: &CellValue,
) -> Result<bool, SpreadsheetError> {
    if let CellValue::Error(error) = left {
        return Err(error.clone());
    }
    if let CellValue::Error(error) = right {
        return Err(error.clone());
    }
    let numeric = numeric_value(left).ok().zip(numeric_value(right).ok());
    let ordering = numeric.map_or_else(
        || {
            left.display_text()
                .to_ascii_lowercase()
                .partial_cmp(&right.display_text().to_ascii_lowercase())
        },
        |(left, right)| left.partial_cmp(&right),
    );
    let Some(ordering) = ordering else {
        return Err(SpreadsheetError::value("values could not be compared"));
    };
    Ok(match operator {
        BinaryOperator::Equal => ordering.is_eq(),
        BinaryOperator::NotEqual => !ordering.is_eq(),
        BinaryOperator::Less => ordering.is_lt(),
        BinaryOperator::LessOrEqual => !ordering.is_gt(),
        BinaryOperator::Greater => ordering.is_gt(),
        BinaryOperator::GreaterOrEqual => !ordering.is_lt(),
        _ => return Err(SpreadsheetError::value("invalid comparison operator")),
    })
}

fn finance_pv(values: &[f64]) -> Result<f64, SpreadsheetError> {
    let [rate, periods, payment, rest @ ..] = values else {
        return Err(argument_count("PV", "three to five"));
    };
    let future = rest.first().copied().unwrap_or(0.0);
    let timing = rest.get(1).copied().unwrap_or(0.0);
    let result = if *rate == 0.0 {
        -(payment * periods + future)
    } else {
        let factor = (1.0 + rate).powf(*periods);
        if factor == 0.0 {
            return Err(SpreadsheetError::division_by_zero(
                "PV discount factor is zero",
            ));
        }
        -(payment * (1.0 + rate * timing) * (factor - 1.0) / (rate * factor) + future / factor)
    };
    finite_number(result)
}

fn finance_fv(values: &[f64]) -> Result<f64, SpreadsheetError> {
    let [rate, periods, payment, rest @ ..] = values else {
        return Err(argument_count("FV", "three to five"));
    };
    let present = rest.first().copied().unwrap_or(0.0);
    let timing = rest.get(1).copied().unwrap_or(0.0);
    let result = if *rate == 0.0 {
        -(present + payment * periods)
    } else {
        let factor = (1.0 + rate).powf(*periods);
        -(present * factor + payment * (1.0 + rate * timing) * (factor - 1.0) / rate)
    };
    finite_number(result)
}

fn finance_pmt(values: &[f64]) -> Result<f64, SpreadsheetError> {
    let [rate, periods, present, rest @ ..] = values else {
        return Err(argument_count("PMT", "three to five"));
    };
    if *periods == 0.0 {
        return Err(SpreadsheetError::division_by_zero("PMT periods are zero"));
    }
    let future = rest.first().copied().unwrap_or(0.0);
    let timing = rest.get(1).copied().unwrap_or(0.0);
    let result = if *rate == 0.0 {
        -(present + future) / periods
    } else {
        let factor = (1.0 + rate).powf(*periods);
        let denominator = (1.0 + rate * timing) * (factor - 1.0) / rate;
        if denominator == 0.0 {
            return Err(SpreadsheetError::division_by_zero(
                "PMT denominator is zero",
            ));
        }
        -(present * factor + future) / denominator
    };
    finite_number(result)
}

fn finance_npv(rate: f64, cash_flows: &[f64]) -> Result<f64, SpreadsheetError> {
    let base = 1.0 + rate;
    if base == 0.0 {
        return Err(SpreadsheetError::division_by_zero(
            "NPV discount rate makes the denominator zero",
        ));
    }
    let mut result = 0.0;
    for (index, cash_flow) in cash_flows.iter().enumerate() {
        result += cash_flow / base.powi((index + 1) as i32);
    }
    finite_number(result)
}

fn finite_number(number: f64) -> Result<f64, SpreadsheetError> {
    if number.is_finite() {
        Ok(number)
    } else {
        Err(SpreadsheetError::value("numeric result is not finite"))
    }
}

fn require_argument_count(
    name: &str,
    arguments: &[Expr],
    expected: usize,
) -> Result<(), SpreadsheetError> {
    if arguments.len() == expected {
        Ok(())
    } else {
        Err(argument_count(name, &expected.to_string()))
    }
}

fn require_argument_range(
    name: &str,
    arguments: &[Expr],
    minimum: usize,
    maximum: usize,
) -> Result<(), SpreadsheetError> {
    if (minimum..=maximum).contains(&arguments.len()) {
        Ok(())
    } else {
        Err(argument_count(name, &format!("{minimum} to {maximum}")))
    }
}

fn argument_count(name: &str, expected: &str) -> SpreadsheetError {
    SpreadsheetError::value(format!("{name} expects {expected} arguments"))
}

fn sorted_pair(left: usize, right: usize) -> (usize, usize) {
    if left <= right {
        (left, right)
    } else {
        (right, left)
    }
}

fn cell_name(row: usize, column: usize) -> String {
    let mut number = column.saturating_add(1);
    let mut letters = Vec::new();
    while number > 0 {
        let remainder = (number - 1) % 26;
        letters.push((b'A' + remainder as u8) as char);
        number = (number - 1) / 26;
    }
    letters.reverse();
    format!(
        "{}{row_number}",
        letters.into_iter().collect::<String>(),
        row_number = row + 1
    )
}

fn format_number(number: f64) -> String {
    let number = if number.abs() < 0.000_000_000_05 {
        0.0
    } else {
        number
    };
    if number.fract().abs() < 0.000_000_000_05 {
        format!("{number:.0}")
    } else {
        let mut formatted = format!("{number:.10}");
        while formatted.ends_with('0') {
            formatted.pop();
        }
        if formatted.ends_with('.') {
            formatted.pop();
        }
        formatted
    }
}

fn parse_literal_number(input: &str) -> Option<f64> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return None;
    }
    let (without_percent, percentage) = trimmed
        .strip_suffix('%')
        .map_or((trimmed, false), |value| (value.trim_end(), true));
    if without_percent.contains('%') {
        return None;
    }
    let negative_parentheses = without_percent.starts_with('(') && without_percent.ends_with(')');
    let without_parentheses = if negative_parentheses {
        without_percent.strip_prefix('(')?.strip_suffix(')')?.trim()
    } else {
        if without_percent.contains(['(', ')']) {
            return None;
        }
        without_percent
    };
    let without_currency = without_parentheses
        .strip_prefix('$')
        .unwrap_or(without_parentheses)
        .trim();
    if without_currency.contains('$') {
        return None;
    }
    let cleaned = without_currency.replace(',', "");
    let number = cleaned.trim().parse::<f64>().ok()?;
    if !number.is_finite() {
        return None;
    }
    let signed = if negative_parentheses {
        -number.abs()
    } else {
        number
    };
    Some(if percentage { signed / 100.0 } else { signed })
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Number(f64),
    Identifier(String),
    Text(String),
    Plus,
    Minus,
    Star,
    Slash,
    Caret,
    Percent,
    LeftParenthesis,
    RightParenthesis,
    Comma,
    Colon,
    Equal,
    NotEqual,
    Less,
    LessOrEqual,
    Greater,
    GreaterOrEqual,
}

fn tokenize(formula: &str) -> Result<Vec<Token>, SpreadsheetError> {
    if formula.len() > MAX_FORMULA_BYTES {
        return Err(SpreadsheetError::value("formula is too long"));
    }
    let characters: Vec<char> = formula.chars().collect();
    let mut tokens = Vec::new();
    let mut index = 0;
    while index < characters.len() {
        let character = characters[index];
        if character.is_whitespace() {
            index += 1;
            continue;
        }
        let token = match character {
            '+' => {
                index += 1;
                Token::Plus
            }
            '-' => {
                index += 1;
                Token::Minus
            }
            '*' => {
                index += 1;
                Token::Star
            }
            '/' => {
                index += 1;
                Token::Slash
            }
            '^' => {
                index += 1;
                Token::Caret
            }
            '%' => {
                index += 1;
                Token::Percent
            }
            '(' => {
                index += 1;
                Token::LeftParenthesis
            }
            ')' => {
                index += 1;
                Token::RightParenthesis
            }
            ',' | ';' => {
                index += 1;
                Token::Comma
            }
            ':' => {
                index += 1;
                Token::Colon
            }
            '=' => {
                index += 1;
                Token::Equal
            }
            '<' => {
                index += 1;
                if characters.get(index) == Some(&'=') {
                    index += 1;
                    Token::LessOrEqual
                } else if characters.get(index) == Some(&'>') {
                    index += 1;
                    Token::NotEqual
                } else {
                    Token::Less
                }
            }
            '>' => {
                index += 1;
                if characters.get(index) == Some(&'=') {
                    index += 1;
                    Token::GreaterOrEqual
                } else {
                    Token::Greater
                }
            }
            '!' if characters.get(index + 1) == Some(&'=') => {
                index += 2;
                Token::NotEqual
            }
            '"' => {
                index += 1;
                let mut text = String::new();
                let mut closed = false;
                while index < characters.len() {
                    if characters[index] == '"' {
                        if characters.get(index + 1) == Some(&'"') {
                            text.push('"');
                            index += 2;
                        } else {
                            index += 1;
                            closed = true;
                            break;
                        }
                    } else {
                        text.push(characters[index]);
                        index += 1;
                    }
                }
                if !closed {
                    return Err(SpreadsheetError::value("text literal is not closed"));
                }
                Token::Text(text)
            }
            character if character.is_ascii_digit() || character == '.' => {
                let start = index;
                let mut seen_exponent = false;
                index += 1;
                while let Some(next) = characters.get(index) {
                    if next.is_ascii_digit() || *next == '.' {
                        index += 1;
                    } else if (*next == 'e' || *next == 'E') && !seen_exponent {
                        seen_exponent = true;
                        index += 1;
                        if matches!(characters.get(index), Some('+' | '-')) {
                            index += 1;
                        }
                    } else {
                        break;
                    }
                }
                let text: String = characters[start..index].iter().collect();
                let number = text
                    .parse::<f64>()
                    .ok()
                    .filter(|value| value.is_finite())
                    .ok_or_else(|| SpreadsheetError::value(format!("invalid number '{text}'")))?;
                Token::Number(number)
            }
            character
                if character.is_ascii_alphabetic() || character == '_' || character == '$' =>
            {
                let start = index;
                index += 1;
                while characters.get(index).is_some_and(|next| {
                    next.is_ascii_alphanumeric() || matches!(next, '_' | '.' | '$')
                }) {
                    index += 1;
                }
                Token::Identifier(characters[start..index].iter().collect())
            }
            _ => {
                return Err(SpreadsheetError::value(format!(
                    "unexpected character '{character}'"
                )));
            }
        };
        tokens.push(token);
        if tokens.len() > MAX_TOKENS {
            return Err(SpreadsheetError::value("formula has too many tokens"));
        }
    }
    Ok(tokens)
}

#[derive(Debug, Clone, PartialEq)]
enum Expr {
    Number(f64),
    Text(String),
    Boolean(bool),
    Cell(CellReference),
    Range(CellReference, CellReference),
    Unary(UnaryOperator, Box<Expr>),
    Binary(Box<Expr>, BinaryOperator, Box<Expr>),
    Function(String, Vec<Expr>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CellReference {
    row: usize,
    column: usize,
    name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum UnaryOperator {
    Plus,
    Minus,
    Percent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinaryOperator {
    Add,
    Subtract,
    Multiply,
    Divide,
    Power,
    Equal,
    NotEqual,
    Less,
    LessOrEqual,
    Greater,
    GreaterOrEqual,
}

impl BinaryOperator {
    const fn is_comparison(self) -> bool {
        matches!(
            self,
            Self::Equal
                | Self::NotEqual
                | Self::Less
                | Self::LessOrEqual
                | Self::Greater
                | Self::GreaterOrEqual
        )
    }
}

fn parse_formula(formula: &str) -> Result<Expr, SpreadsheetError> {
    let tokens = tokenize(formula)?;
    if tokens.is_empty() {
        return Err(SpreadsheetError::value("formula is empty"));
    }
    let mut parser = FormulaParser {
        tokens,
        position: 0,
        depth: 0,
    };
    let expression = parser.parse_comparison()?;
    if parser.position != parser.tokens.len() {
        return Err(SpreadsheetError::value("formula contains trailing input"));
    }
    Ok(expression)
}

#[derive(Debug)]
struct FormulaParser {
    tokens: Vec<Token>,
    position: usize,
    depth: usize,
}

impl FormulaParser {
    fn parse_comparison(&mut self) -> Result<Expr, SpreadsheetError> {
        let mut expression = self.parse_additive()?;
        while let Some(operator) = self.comparison_operator() {
            self.position += 1;
            let right = self.parse_additive()?;
            expression = Expr::Binary(Box::new(expression), operator, Box::new(right));
        }
        Ok(expression)
    }

    fn parse_additive(&mut self) -> Result<Expr, SpreadsheetError> {
        let mut expression = self.parse_multiplicative()?;
        loop {
            let operator = match self.peek() {
                Some(Token::Plus) => BinaryOperator::Add,
                Some(Token::Minus) => BinaryOperator::Subtract,
                _ => break,
            };
            self.position += 1;
            let right = self.parse_multiplicative()?;
            expression = Expr::Binary(Box::new(expression), operator, Box::new(right));
        }
        Ok(expression)
    }

    fn parse_multiplicative(&mut self) -> Result<Expr, SpreadsheetError> {
        let mut expression = self.parse_unary()?;
        loop {
            let operator = match self.peek() {
                Some(Token::Star) => BinaryOperator::Multiply,
                Some(Token::Slash) => BinaryOperator::Divide,
                _ => break,
            };
            self.position += 1;
            let right = self.parse_unary()?;
            expression = Expr::Binary(Box::new(expression), operator, Box::new(right));
        }
        Ok(expression)
    }

    fn parse_unary(&mut self) -> Result<Expr, SpreadsheetError> {
        let operator = match self.peek() {
            Some(Token::Plus) => Some(UnaryOperator::Plus),
            Some(Token::Minus) => Some(UnaryOperator::Minus),
            _ => None,
        };
        if let Some(operator) = operator {
            self.position += 1;
            self.enter_nested()?;
            let expression = self.parse_unary();
            self.leave_nested();
            let expression = expression?;
            Ok(Expr::Unary(operator, Box::new(expression)))
        } else {
            self.parse_power()
        }
    }

    fn parse_power(&mut self) -> Result<Expr, SpreadsheetError> {
        let expression = self.parse_postfix()?;
        if matches!(self.peek(), Some(Token::Caret)) {
            self.position += 1;
            self.enter_nested()?;
            let right = self.parse_unary();
            self.leave_nested();
            let right = right?;
            Ok(Expr::Binary(
                Box::new(expression),
                BinaryOperator::Power,
                Box::new(right),
            ))
        } else {
            Ok(expression)
        }
    }

    fn parse_postfix(&mut self) -> Result<Expr, SpreadsheetError> {
        let mut expression = self.parse_primary()?;
        while matches!(self.peek(), Some(Token::Percent)) {
            self.position += 1;
            expression = Expr::Unary(UnaryOperator::Percent, Box::new(expression));
        }
        Ok(expression)
    }

    fn parse_primary(&mut self) -> Result<Expr, SpreadsheetError> {
        let token = self
            .tokens
            .get(self.position)
            .cloned()
            .ok_or_else(|| SpreadsheetError::value("formula ended unexpectedly"))?;
        self.position += 1;
        match token {
            Token::Number(number) => Ok(Expr::Number(number)),
            Token::Text(text) => Ok(Expr::Text(text)),
            Token::Identifier(identifier) => self.parse_identifier(identifier),
            Token::LeftParenthesis => {
                self.enter_nested()?;
                let expression = self.parse_comparison();
                self.leave_nested();
                let expression = expression?;
                self.expect_right_parenthesis()?;
                Ok(expression)
            }
            _ => Err(SpreadsheetError::value(
                "expected a value or cell reference",
            )),
        }
    }

    fn parse_identifier(&mut self, identifier: String) -> Result<Expr, SpreadsheetError> {
        if matches!(self.peek(), Some(Token::LeftParenthesis)) {
            self.position += 1;
            self.enter_nested()?;
            let arguments = self.parse_arguments();
            self.leave_nested();
            return arguments.map(|arguments| Expr::Function(identifier, arguments));
        }
        if identifier.eq_ignore_ascii_case("TRUE") {
            return Ok(Expr::Boolean(true));
        }
        if identifier.eq_ignore_ascii_case("FALSE") {
            return Ok(Expr::Boolean(false));
        }
        let start = parse_cell_reference(&identifier)
            .ok_or_else(|| SpreadsheetError::value(format!("unknown name '{identifier}'")))?;
        if matches!(self.peek(), Some(Token::Colon)) {
            self.position += 1;
            let Some(Token::Identifier(end)) = self.tokens.get(self.position).cloned() else {
                return Err(SpreadsheetError::reference(
                    "range is missing its ending cell",
                ));
            };
            self.position += 1;
            let end = parse_cell_reference(&end)
                .ok_or_else(|| SpreadsheetError::reference("range ending cell is invalid"))?;
            Ok(Expr::Range(start, end))
        } else {
            Ok(Expr::Cell(start))
        }
    }

    fn parse_arguments(&mut self) -> Result<Vec<Expr>, SpreadsheetError> {
        let mut arguments = Vec::new();
        if matches!(self.peek(), Some(Token::RightParenthesis)) {
            self.position += 1;
            return Ok(arguments);
        }
        loop {
            arguments.push(self.parse_comparison()?);
            match self.peek() {
                Some(Token::Comma) => self.position += 1,
                Some(Token::RightParenthesis) => {
                    self.position += 1;
                    break;
                }
                _ => {
                    return Err(SpreadsheetError::value(
                        "function arguments must be separated by commas",
                    ));
                }
            }
        }
        Ok(arguments)
    }

    fn comparison_operator(&self) -> Option<BinaryOperator> {
        match self.peek()? {
            Token::Equal => Some(BinaryOperator::Equal),
            Token::NotEqual => Some(BinaryOperator::NotEqual),
            Token::Less => Some(BinaryOperator::Less),
            Token::LessOrEqual => Some(BinaryOperator::LessOrEqual),
            Token::Greater => Some(BinaryOperator::Greater),
            Token::GreaterOrEqual => Some(BinaryOperator::GreaterOrEqual),
            _ => None,
        }
    }

    fn expect_right_parenthesis(&mut self) -> Result<(), SpreadsheetError> {
        if matches!(self.peek(), Some(Token::RightParenthesis)) {
            self.position += 1;
            Ok(())
        } else {
            Err(SpreadsheetError::value("missing closing parenthesis"))
        }
    }

    fn enter_nested(&mut self) -> Result<(), SpreadsheetError> {
        self.depth += 1;
        if self.depth > MAX_PARSE_DEPTH {
            self.depth -= 1;
            Err(SpreadsheetError::value("formula is too deeply nested"))
        } else {
            Ok(())
        }
    }

    fn leave_nested(&mut self) {
        self.depth = self.depth.saturating_sub(1);
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }
}

fn parse_cell_reference(value: &str) -> Option<CellReference> {
    let normalized = value.replace('$', "").to_ascii_uppercase();
    let split = normalized
        .char_indices()
        .find(|(_, character)| character.is_ascii_digit())
        .map(|(index, _)| index)?;
    let (letters, digits) = normalized.split_at(split);
    if letters.is_empty()
        || digits.is_empty()
        || !letters
            .chars()
            .all(|character| character.is_ascii_alphabetic())
        || !digits.chars().all(|character| character.is_ascii_digit())
    {
        return None;
    }
    let mut column = 0_usize;
    for character in letters.chars() {
        let value = (character as u8 - b'A' + 1) as usize;
        column = column.checked_mul(26)?.checked_add(value)?;
    }
    let row = digits.parse::<usize>().ok()?;
    if row == 0 || column == 0 {
        return None;
    }
    Some(CellReference {
        row: row - 1,
        column: column - 1,
        name: normalized,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(rows: &[&[&str]]) -> Vec<Vec<CellValue>> {
        let owned = rows
            .iter()
            .map(|row| row.iter().map(|cell| (*cell).to_owned()).collect())
            .collect::<Vec<Vec<String>>>();
        evaluate_grid(&owned)
    }

    fn number(value: &CellValue) -> f64 {
        match value {
            CellValue::Number(number) => *number,
            other => panic!("expected a number, got {other:?}"),
        }
    }

    #[test]
    fn arithmetic_references_ranges_and_core_functions_evaluate() {
        let evaluated = values(&[
            &["10", "20", "=A1+B1*2", "=2^3^2"],
            &[
                "=SUM(A1:B1)",
                "=AVERAGE(A1:B1)",
                "=MIN(A1:B1)",
                "=MAX(A1:B1)",
            ],
            &[
                "=ROUND(10/3,2)",
                "=ABS(-12)",
                "=IF(A1>5,99,1/0)",
                "=sum(A1:B1)",
            ],
        ]);
        assert_eq!(number(&evaluated[0][2]), 50.0);
        assert_eq!(number(&evaluated[0][3]), 512.0);
        assert_eq!(number(&evaluated[1][0]), 30.0);
        assert_eq!(number(&evaluated[1][1]), 15.0);
        assert_eq!(number(&evaluated[1][2]), 10.0);
        assert_eq!(number(&evaluated[1][3]), 20.0);
        assert_eq!(number(&evaluated[2][0]), 3.33);
        assert_eq!(number(&evaluated[2][1]), 12.0);
        assert_eq!(number(&evaluated[2][2]), 99.0);
        assert_eq!(number(&evaluated[2][3]), 30.0);
    }

    #[test]
    fn references_division_cycles_and_parse_failures_return_visible_errors() {
        let evaluated = values(&[
            &["=Z99", "=1/0", "=D1", "=C1"],
            &["=SUM(", "=UNKNOWN(1)", "=C2+1", ""],
        ]);
        assert_eq!(
            evaluated[0][0].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Reference)
        );
        assert_eq!(
            evaluated[0][1].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::DivisionByZero)
        );
        assert_eq!(
            evaluated[0][2].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Cycle)
        );
        assert_eq!(
            evaluated[1][0].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Value)
        );
        assert_eq!(
            evaluated[1][1].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Value)
        );
        assert_eq!(
            evaluated[1][2].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Cycle)
        );
    }

    #[test]
    fn percentage_cells_and_pathologically_nested_formulas_are_safe() {
        let evaluated = values(&[&["8%", "=A1*100"]]);
        assert!((number(&evaluated[0][0]) - 0.08).abs() < f64::EPSILON);
        assert!((number(&evaluated[0][1]) - 8.0).abs() < f64::EPSILON);

        let nested_unary = format!("={}1", "-".repeat(MAX_PARSE_DEPTH + 1));
        assert!(matches!(
            evaluate_formula(&nested_unary),
            CellValue::Error(SpreadsheetError {
                kind: SpreadsheetErrorKind::Value,
                ..
            })
        ));
    }

    #[test]
    fn financial_functions_match_standard_sign_conventions() {
        let evaluated = values(&[&[
            "=PV(0.1,2,0,121)",
            "=FV(0.1,2,0,-100)",
            "=PMT(0.1,2,100)",
            "=NPV(0.1,110,121)",
        ]]);
        assert!((number(&evaluated[0][0]) + 100.0).abs() < 1e-9);
        assert!((number(&evaluated[0][1]) - 121.0).abs() < 1e-9);
        assert!((number(&evaluated[0][2]) + 57.619_047_619).abs() < 1e-8);
        assert!((number(&evaluated[0][3]) - 200.0).abs() < 1e-9);
        let percent_pv = evaluate_formula("=PV(8%,5,0,10000)");
        assert!((number(&percent_pv) + 6_805.831_970_337_529).abs() < 1e-9);
    }

    #[test]
    fn evaluated_rows_leave_raw_formulas_untouched() {
        let rows = vec![vec!["7".to_owned(), "=A1*6".to_owned()]];
        assert_eq!(
            evaluated_rows(&rows),
            [vec!["7".to_owned(), "42".to_owned()]]
        );
        assert_eq!(rows[0][1], "=A1*6");
    }

    #[test]
    fn very_deep_cell_dependency_chains_fail_safely() {
        let mut row = (0..300)
            .map(|column| format!("={}", cell_name(0, column + 1)))
            .collect::<Vec<_>>();
        if let Some(last) = row.last_mut() {
            *last = "1".to_owned();
        }
        let evaluated = evaluate_grid(&[row]);
        assert_eq!(
            evaluated[0][0].error().map(|error| error.kind),
            Some(SpreadsheetErrorKind::Value)
        );
    }
}
