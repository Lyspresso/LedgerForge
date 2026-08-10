//! Application-level state for the desktop study workspace.
//!
//! This layer deliberately contains no `egui` types, so library filtering,
//! import replacement, first-launch seeding, attempts, and progress are easy to
//! verify without opening a window.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::{
    AccountingQuestion, AppState, AttemptGrade, AttemptRecord, GradeStatus, ImportWarning,
    JsonStateStore, QuestionFormat, QuestionShell, StoredQuestionPack, StudentAnswer,
    current_unix_ms, grade_question, parse_markdown,
};

pub const APP_IDENTIFIER: &str = "com.openai.ledgerforge";
pub const BUILT_IN_SAMPLE_NAME: &str = "ALL_FORMATS_SAMPLE.md";
pub const BUILT_IN_SAMPLE: &str = include_str!("../../Samples/ALL_FORMATS_SAMPLE.md");
const AUTOSAVE_DELAY: Duration = Duration::from_millis(650);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QuestionProgress {
    NotStarted,
    InProgress,
    Complete,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LibraryQuestion {
    pub pack_id: String,
    pub pack_title: String,
    pub question_id: String,
    pub title: String,
    pub shell: QuestionShell,
    pub formats: Vec<QuestionFormat>,
    pub tags: Vec<String>,
    pub progress: QuestionProgress,
    pub answered_parts: usize,
    pub mastered_parts: usize,
    pub total_parts: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportSummary {
    pub source_name: String,
    pub question_count: usize,
    pub replaced_existing_pack: bool,
    pub warnings: Vec<ImportWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct LibraryCacheKey {
    revision: u64,
    pack_filter: Option<String>,
    search: String,
    format_filter: Option<QuestionFormat>,
    shell_filter: Option<QuestionShell>,
}

#[derive(Debug)]
pub struct StudioModel {
    pub state: AppState,
    pub selected_pack_id: Option<String>,
    pub selected_question_id: Option<String>,
    pub library_pack_filter: Option<String>,
    pub search: String,
    pub format_filter: Option<QuestionFormat>,
    pub shell_filter: Option<QuestionShell>,
    pub last_import: Option<ImportSummary>,
    pub last_error: Option<String>,
    pub last_saved_at: Option<Instant>,
    store: JsonStateStore,
    dirty_since: Option<Instant>,
    attempt_index: BTreeMap<String, String>,
    progress_cache: RefCell<BTreeMap<String, (usize, usize)>>,
    library_revision: u64,
    library_cache_key: Option<LibraryCacheKey>,
    library_cache: Arc<[LibraryQuestion]>,
}

impl StudioModel {
    pub fn load_standard() -> Self {
        match JsonStateStore::standard_macos(APP_IDENTIFIER) {
            Ok(store) => Self::load(store),
            Err(error) => {
                let fallback = JsonStateStore::new(
                    std::env::temp_dir().join("ledgerforge-fallback-state.json"),
                );
                let mut model = Self::from_state(fallback, AppState::default());
                model.last_error = Some(error.to_string());
                model
            }
        }
    }

    pub fn load(store: JsonStateStore) -> Self {
        match store.load_with_recovery() {
            Ok(loaded) => {
                let recovered = loaded.recovered_from_backup;
                let mut model = Self::from_state(store, loaded.state);
                if recovered {
                    model.last_error = Some(
                        "The primary saved state was unavailable or corrupt. LedgerForge recovered the last atomic backup and will repair the primary file on the next save."
                            .to_owned(),
                    );
                    model.mark_dirty();
                }
                model
            }
            Err(error) => {
                let mut model = Self::from_state(store, AppState::default());
                model.last_error = Some(format!(
                    "Saved study state could not be opened. A clean workspace was loaded: {error}"
                ));
                model
            }
        }
    }

    pub fn from_state(store: JsonStateStore, state: AppState) -> Self {
        let selected_pack_id = state.preferences.last_pack_id.clone();
        let selected_question_id = state.preferences.last_question_id.clone();
        let mut model = Self {
            state,
            selected_pack_id,
            selected_question_id,
            library_pack_filter: None,
            search: String::new(),
            format_filter: None,
            shell_filter: None,
            last_import: None,
            last_error: None,
            last_saved_at: None,
            store,
            dirty_since: None,
            attempt_index: BTreeMap::new(),
            progress_cache: RefCell::new(BTreeMap::new()),
            library_revision: 0,
            library_cache_key: None,
            library_cache: Arc::from([]),
        };
        model.rebuild_attempt_index();
        if model.migrate_unscoped_attempts() {
            model.rebuild_attempt_index();
            model.mark_dirty();
        }
        if model.state.schema_version < crate::CURRENT_SCHEMA_VERSION {
            model.state.schema_version = crate::CURRENT_SCHEMA_VERSION;
            model.mark_dirty();
        }
        if model.state.packs.is_empty()
            && let Err(error) = model.seed_built_in_sample()
        {
            model.last_error = Some(error);
        }
        model.repair_selection();
        model
    }

    fn seed_built_in_sample(&mut self) -> Result<(), String> {
        let result = parse_markdown(BUILT_IN_SAMPLE, BUILT_IN_SAMPLE_NAME)
            .map_err(|error| format!("The built-in practice pack is invalid: {error}"))?;
        let stored = StoredQuestionPack::imported(result.pack, None);
        self.selected_pack_id = Some(stored.id.clone());
        self.selected_question_id = stored
            .pack
            .questions
            .first()
            .map(|question| question.id.clone());
        self.state.preferences.last_pack_id = self.selected_pack_id.clone();
        self.state.preferences.last_question_id = self.selected_question_id.clone();
        self.state.upsert_pack(stored);
        self.invalidate_library();
        self.mark_dirty();
        // First launch should be durable even if the user closes immediately.
        self.save_now()
    }

    pub fn import_path(&mut self, path: &Path) -> Result<ImportSummary, String> {
        let canonical_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        let markdown = std::fs::read_to_string(&canonical_path)
            .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
        let source_name = canonical_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("Imported Markdown.md");
        self.import_markdown(&markdown, source_name, Some(canonical_path.clone()))
    }

    pub fn import_markdown(
        &mut self,
        markdown: &str,
        source_name: &str,
        source_path: Option<PathBuf>,
    ) -> Result<ImportSummary, String> {
        let result = parse_markdown(markdown, source_name)
            .map_err(|error| format!("{source_name} could not be imported: {error}"))?;
        let question_count = result.pack.questions.len();
        if question_count == 0 {
            return Err(format!(
                "{source_name} did not contain any recognizable questions."
            ));
        }

        let existing_index = source_path.as_ref().and_then(|path| {
            self.state.packs.iter().position(|pack| {
                pack.source_path
                    .as_ref()
                    .is_some_and(|existing| same_source_path(existing, path))
            })
        });
        let replaced_existing_pack = existing_index.is_some();
        let mut stored = StoredQuestionPack::imported(result.pack, source_path);
        if let Some(index) = existing_index {
            stored.id.clone_from(&self.state.packs[index].id);
            self.state.packs[index] = stored.clone();
        } else {
            self.state.upsert_pack(stored.clone());
        }

        self.selected_pack_id = Some(stored.id.clone());
        self.selected_question_id = stored
            .pack
            .questions
            .first()
            .map(|question| question.id.clone());
        self.library_pack_filter = Some(stored.id.clone());
        self.state.preferences.last_pack_id = self.selected_pack_id.clone();
        self.state.preferences.last_question_id = self.selected_question_id.clone();
        self.progress_cache.borrow_mut().clear();
        self.invalidate_library();
        self.mark_dirty();

        let summary = ImportSummary {
            source_name: source_name.to_owned(),
            question_count,
            replaced_existing_pack,
            warnings: result.warnings,
        };
        self.last_import = Some(summary.clone());
        self.last_error = None;
        Ok(summary)
    }

    pub fn pack_choices(&self) -> Vec<(String, String, usize)> {
        self.state
            .packs
            .iter()
            .map(|pack| {
                (
                    pack.id.clone(),
                    pack.pack.title.clone(),
                    pack.pack.questions.len(),
                )
            })
            .collect()
    }

    pub fn filtered_questions(&mut self) -> Arc<[LibraryQuestion]> {
        let key = LibraryCacheKey {
            revision: self.library_revision,
            pack_filter: self.library_pack_filter.clone(),
            search: self.search.trim().to_ascii_lowercase(),
            format_filter: self.format_filter,
            shell_filter: self.shell_filter,
        };
        if self.library_cache_key.as_ref() != Some(&key) {
            self.library_cache = self.build_filtered_questions(&key.search).into();
            self.library_cache_key = Some(key);
        }
        Arc::clone(&self.library_cache)
    }

    fn build_filtered_questions(&self, query: &str) -> Vec<LibraryQuestion> {
        self.state
            .packs
            .iter()
            .filter(|pack| {
                self.library_pack_filter
                    .as_ref()
                    .is_none_or(|filter| filter == &pack.id)
            })
            .flat_map(|pack| {
                pack.pack.questions.iter().filter_map(|question| {
                    if self
                        .format_filter
                        .is_some_and(|format| !question.formats.contains(&format))
                        || self
                            .shell_filter
                            .is_some_and(|shell| question.shell != shell)
                        || !query.is_empty()
                            && !question_matches_query(question, &pack.pack.title, query)
                    {
                        return None;
                    }
                    let (answered_parts, mastered_parts) =
                        self.question_progress(&pack.id, question);
                    let total_parts = question.parts.len();
                    let progress = if answered_parts == 0 {
                        QuestionProgress::NotStarted
                    } else if total_parts > 0 && mastered_parts == total_parts {
                        QuestionProgress::Complete
                    } else {
                        QuestionProgress::InProgress
                    };
                    Some(LibraryQuestion {
                        pack_id: pack.id.clone(),
                        pack_title: pack.pack.title.clone(),
                        question_id: question.id.clone(),
                        title: question.title.clone(),
                        shell: question.shell,
                        formats: question.formats.clone(),
                        tags: question.tags.clone(),
                        progress,
                        answered_parts,
                        mastered_parts,
                        total_parts,
                    })
                })
            })
            .collect()
    }

    pub fn selected_question(&self) -> Option<AccountingQuestion> {
        let pack_id = self.selected_pack_id.as_ref()?;
        let question_id = self.selected_question_id.as_ref()?;
        self.state
            .packs
            .iter()
            .find(|pack| &pack.id == pack_id)?
            .pack
            .questions
            .iter()
            .find(|question| &question.id == question_id)
            .cloned()
    }

    pub fn select_question(&mut self, pack_id: &str, question_id: &str) {
        let exists = self.state.packs.iter().any(|pack| {
            pack.id == pack_id
                && pack
                    .pack
                    .questions
                    .iter()
                    .any(|question| question.id == question_id)
        });
        if !exists {
            return;
        }
        self.selected_pack_id = Some(pack_id.to_owned());
        self.selected_question_id = Some(question_id.to_owned());
        self.state.preferences.last_pack_id = self.selected_pack_id.clone();
        self.state.preferences.last_question_id = self.selected_question_id.clone();
        self.mark_dirty();
    }

    pub fn attempt_for(&self, pack_id: &str, question_id: &str) -> Option<&AttemptRecord> {
        let scoped_id = scoped_question_id(pack_id, question_id);
        let attempt_id = self.attempt_index.get(&scoped_id)?;
        self.state.attempts.get(attempt_id)
    }

    pub fn attempt_for_mut(&mut self, pack_id: &str, question_id: &str) -> &mut AttemptRecord {
        let scoped_id = scoped_question_id(pack_id, question_id);
        if let Some(id) = self.attempt_index.get(&scoped_id).cloned() {
            return self
                .state
                .attempts
                .entry(id.clone())
                .or_insert_with(|| AttemptRecord {
                    id,
                    question_id: scoped_id,
                    ..AttemptRecord::default()
                });
        }
        let id = crate::new_local_id("attempt");
        let attempt = AttemptRecord {
            id: id.clone(),
            question_id: scoped_id.clone(),
            updated_at_unix_ms: current_unix_ms(),
            ..AttemptRecord::default()
        };
        self.attempt_index.insert(scoped_id, id.clone());
        self.state.attempts.entry(id).or_insert(attempt)
    }

    pub fn answer_mut(
        &mut self,
        pack_id: &str,
        question_id: &str,
        part_id: &str,
    ) -> &mut StudentAnswer {
        self.attempt_for_mut(pack_id, question_id)
            .answers
            .entry(part_id.to_owned())
            .or_default()
    }

    /// Whether a part has enough student input to be explicitly submitted.
    /// This is the shared guard used by card, toolbar, inspector, and keyboard
    /// submission paths.
    pub fn can_check_part(&self, pack_id: &str, question_id: &str, part_id: &str) -> bool {
        self.attempt_for(pack_id, question_id)
            .and_then(|attempt| attempt.answers.get(part_id))
            .is_some_and(|answer| !answer.is_blank())
    }

    pub fn is_part_checked(&self, pack_id: &str, question_id: &str, part_id: &str) -> bool {
        self.attempt_for(pack_id, question_id)
            .is_some_and(|attempt| attempt.checked_part_ids.contains(part_id))
    }

    /// Persist or clear the explicit submitted state for a part.
    ///
    /// Submitting a blank answer is rejected. Clearing submission also removes
    /// any self-review for that response so an edit cannot retain stale mastery.
    /// The return value reports whether the requested state was accepted.
    pub fn set_part_checked(
        &mut self,
        pack_id: &str,
        question_id: &str,
        part_id: &str,
        checked: bool,
    ) -> bool {
        if checked && !self.can_check_part(pack_id, question_id, part_id) {
            return false;
        }

        let changed = if checked {
            self.attempt_for_mut(pack_id, question_id)
                .checked_part_ids
                .insert(part_id.to_owned())
        } else {
            let scoped_id = scoped_question_id(pack_id, question_id);
            self.attempt_index
                .get(&scoped_id)
                .and_then(|attempt_id| self.state.attempts.get_mut(attempt_id))
                .is_some_and(|attempt| {
                    let removed_check = attempt.checked_part_ids.remove(part_id);
                    let removed_review = attempt.self_reviews.remove(part_id).is_some();
                    removed_check || removed_review
                })
        };

        if changed {
            self.attempt_for_mut(pack_id, question_id)
                .updated_at_unix_ms = current_unix_ms();
            self.progress_cache
                .borrow_mut()
                .remove(&scoped_question_id(pack_id, question_id));
            self.invalidate_library();
            self.mark_dirty();
        }
        true
    }

    pub fn touch_attempt(&mut self, pack_id: &str, question_id: &str) {
        self.attempt_for_mut(pack_id, question_id)
            .updated_at_unix_ms = current_unix_ms();
        self.progress_cache
            .borrow_mut()
            .remove(&scoped_question_id(pack_id, question_id));
        self.invalidate_library();
        self.mark_dirty();
    }

    pub fn set_self_review(
        &mut self,
        pack_id: &str,
        question_id: &str,
        part_id: &str,
        reviewed: bool,
    ) {
        let attempt = self.attempt_for_mut(pack_id, question_id);
        attempt.self_reviews.insert(part_id.to_owned(), reviewed);
        attempt.updated_at_unix_ms = current_unix_ms();
        self.progress_cache
            .borrow_mut()
            .remove(&scoped_question_id(pack_id, question_id));
        self.invalidate_library();
        self.mark_dirty();
    }

    pub fn grade_for(&self, pack_id: &str, question: &AccountingQuestion) -> AttemptGrade {
        let empty = AttemptRecord {
            question_id: scoped_question_id(pack_id, &question.id),
            ..AttemptRecord::default()
        };
        grade_question(
            question,
            self.attempt_for(pack_id, &question.id).unwrap_or(&empty),
        )
    }

    pub fn question_progress(
        &self,
        pack_id: &str,
        question: &AccountingQuestion,
    ) -> (usize, usize) {
        let scope = scoped_question_id(pack_id, &question.id);
        if let Some(progress) = self.progress_cache.borrow().get(&scope).copied() {
            return progress;
        }
        let Some(attempt) = self.attempt_for(pack_id, &question.id) else {
            self.progress_cache.borrow_mut().insert(scope, (0, 0));
            return (0, 0);
        };
        let answered = question
            .parts
            .iter()
            .filter(|part| {
                attempt
                    .answers
                    .get(&part.id)
                    .is_some_and(|answer| !answer.is_blank())
            })
            .count();
        let grade = grade_question(question, attempt);
        let mastered = grade
            .parts
            .iter()
            .filter(|part| {
                attempt.checked_part_ids.contains(&part.part_id)
                    && part.result.status == GradeStatus::Correct
            })
            .count();
        let progress = (answered, mastered);
        self.progress_cache.borrow_mut().insert(scope, progress);
        progress
    }

    pub fn is_dirty(&self) -> bool {
        self.dirty_since.is_some()
    }

    pub fn save_if_due(&mut self) {
        if self.state.preferences.autosave_answers
            && self
                .dirty_since
                .is_some_and(|dirty_since| dirty_since.elapsed() >= AUTOSAVE_DELAY)
        {
            let _ = self.save_now();
        }
    }

    pub fn save_now(&mut self) -> Result<(), String> {
        match self.store.save(&self.state) {
            Ok(()) => {
                self.dirty_since = None;
                self.last_saved_at = Some(Instant::now());
                self.last_error = None;
                Ok(())
            }
            Err(error) => {
                let message = format!("Study progress could not be saved: {error}");
                self.last_error = Some(message.clone());
                Err(message)
            }
        }
    }

    pub fn set_autosave(&mut self, enabled: bool) {
        self.state.preferences.autosave_answers = enabled;
        self.mark_dirty();
    }

    pub fn set_reveal_after_check(&mut self, enabled: bool) {
        self.state.preferences.show_answer_after_check = enabled;
        self.mark_dirty();
    }

    fn mark_dirty(&mut self) {
        self.dirty_since = Some(Instant::now());
    }

    fn invalidate_library(&mut self) {
        self.library_revision = self.library_revision.wrapping_add(1);
        self.library_cache_key = None;
    }

    fn rebuild_attempt_index(&mut self) {
        let mut index: BTreeMap<String, (u64, String)> = BTreeMap::new();
        for (map_id, attempt) in &self.state.attempts {
            let candidate = (attempt.updated_at_unix_ms, map_id.clone());
            let replace = index
                .get(&attempt.question_id)
                .is_none_or(|existing| candidate >= *existing);
            if replace {
                index.insert(attempt.question_id.clone(), candidate);
            }
        }
        self.attempt_index = index
            .into_iter()
            .map(|(scope, (_, attempt_id))| (scope, attempt_id))
            .collect();
    }

    /// Upgrade development-era attempts that stored only a raw question id.
    /// A colliding attempt is assigned to one pack and is never exposed to all
    /// packs that happen to reuse the same Markdown question id.
    fn migrate_unscoped_attempts(&mut self) -> bool {
        let preferred_pack = self.state.preferences.last_pack_id.clone();
        let scopes = self
            .state
            .packs
            .iter()
            .flat_map(|pack| {
                pack.pack.questions.iter().map(|question| {
                    (
                        pack.id.clone(),
                        question.id.clone(),
                        scoped_question_id(&pack.id, &question.id),
                    )
                })
            })
            .collect::<Vec<_>>();
        let mut migrated = false;
        for attempt in self.state.attempts.values_mut() {
            if scopes
                .iter()
                .any(|(_, _, scoped)| scoped == &attempt.question_id)
            {
                continue;
            }
            let candidates = scopes
                .iter()
                .filter(|(_, question_id, _)| question_id == &attempt.question_id)
                .collect::<Vec<_>>();
            let selected = preferred_pack
                .as_ref()
                .and_then(|pack_id| {
                    candidates
                        .iter()
                        .find(|(candidate_pack, _, _)| candidate_pack == pack_id)
                        .copied()
                })
                .or_else(|| candidates.first().copied());
            if let Some((_, _, scoped)) = selected {
                attempt.question_id.clone_from(scoped);
                migrated = true;
            }
        }
        migrated
    }

    fn repair_selection(&mut self) {
        let valid = self
            .selected_pack_id
            .as_ref()
            .zip(self.selected_question_id.as_ref())
            .is_some_and(|(pack_id, question_id)| {
                self.state.packs.iter().any(|pack| {
                    &pack.id == pack_id
                        && pack
                            .pack
                            .questions
                            .iter()
                            .any(|question| &question.id == question_id)
                })
            });
        if valid {
            return;
        }
        let first = self.state.packs.first().and_then(|pack| {
            pack.pack
                .questions
                .first()
                .map(|question| (pack.id.clone(), question.id.clone()))
        });
        if let Some((pack_id, question_id)) = first {
            self.selected_pack_id = Some(pack_id.clone());
            self.selected_question_id = Some(question_id.clone());
            self.state.preferences.last_pack_id = Some(pack_id);
            self.state.preferences.last_question_id = Some(question_id);
        }
    }
}

/// Rust persistence scopes attempt identity by pack, because independent
/// Markdown banks are allowed to reuse a stable question id.
pub fn scoped_question_id(pack_id: &str, question_id: &str) -> String {
    format!("{pack_id}::{question_id}")
}

fn same_source_path(left: &Path, right: &Path) -> bool {
    if left == right {
        return true;
    }
    left.canonicalize()
        .ok()
        .zip(right.canonicalize().ok())
        .is_some_and(|(left, right)| left == right)
}

fn question_matches_query(question: &AccountingQuestion, pack_title: &str, query: &str) -> bool {
    question.title.to_ascii_lowercase().contains(query)
        || question.id.to_ascii_lowercase().contains(query)
        || question
            .scenario_markdown
            .to_ascii_lowercase()
            .contains(query)
        || pack_title.to_ascii_lowercase().contains(query)
        || question
            .tags
            .iter()
            .any(|tag| tag.to_ascii_lowercase().contains(query))
        || question
            .formats
            .iter()
            .any(|format| format.as_str().contains(query))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{QuestionPack, QuestionPart, ResponseKind, new_local_id};

    fn test_store(name: &str) -> JsonStateStore {
        JsonStateStore::new(std::env::temp_dir().join(format!(
            "ledgerforge-studio-{}-{name}/state.json",
            new_local_id("test")
        )))
    }

    fn number_question_model(name: &str) -> (StudioModel, String, AccountingQuestion) {
        let mut model = StudioModel::load(test_store(name));
        let markdown = r#"
:::question id=submission-test
# Submission Test
:::part id=amount kind=number points=3
### Prompt
Enter 42.
### Answer
42
:::endpart
:::endquestion
"#;
        model
            .import_markdown(markdown, "submission-test.md", None)
            .unwrap();
        let pack_id = model.selected_pack_id.clone().unwrap();
        let question = model.selected_question().unwrap();
        (model, pack_id, question)
    }

    #[test]
    fn clean_first_launch_seeds_every_format_and_response_kind() {
        let model = StudioModel::load(test_store("seed"));
        assert_eq!(model.state.packs.len(), 1);
        let questions = &model.state.packs[0].pack.questions;
        assert_eq!(questions.len(), QuestionFormat::ALL.len());
        for format in QuestionFormat::ALL {
            assert!(
                questions
                    .iter()
                    .any(|question| question.formats.contains(format)),
                "missing format {format}"
            );
        }
        for kind in ResponseKind::ALL {
            assert!(
                questions
                    .iter()
                    .flat_map(|question| &question.parts)
                    .any(|part| part.kind == *kind),
                "missing response kind {kind}"
            );
        }
    }

    #[test]
    fn search_and_format_filters_compose() {
        let mut model = StudioModel::load(test_store("filter"));
        model.search = "cash".to_owned();
        model.format_filter = Some(QuestionFormat::ReconciliationProof);
        let matches = model.filtered_questions();
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].question_id, "fmt-20-reconciliation");
    }

    #[test]
    fn blank_answers_cannot_be_checked_and_edits_clear_review_state() {
        let (mut model, pack_id, question) = number_question_model("blank-check");
        let question_id = &question.id;
        let part_id = &question.parts[0].id;

        assert!(!model.can_check_part(&pack_id, question_id, part_id));
        assert!(!model.set_part_checked(&pack_id, question_id, part_id, true));
        assert!(!model.is_part_checked(&pack_id, question_id, part_id));

        model.answer_mut(&pack_id, question_id, part_id).scalar = "   ".to_owned();
        model.touch_attempt(&pack_id, question_id);
        assert!(!model.set_part_checked(&pack_id, question_id, part_id, true));

        model.answer_mut(&pack_id, question_id, part_id).scalar = "42".to_owned();
        model.touch_attempt(&pack_id, question_id);
        assert!(model.can_check_part(&pack_id, question_id, part_id));
        assert!(model.set_part_checked(&pack_id, question_id, part_id, true));
        model.set_self_review(&pack_id, question_id, part_id, true);

        model.answer_mut(&pack_id, question_id, part_id).scalar = "41".to_owned();
        assert!(model.set_part_checked(&pack_id, question_id, part_id, false));
        model.touch_attempt(&pack_id, question_id);
        let attempt = model.attempt_for(&pack_id, question_id).unwrap();
        assert!(!attempt.checked_part_ids.contains(part_id));
        assert!(!attempt.self_reviews.contains_key(part_id));
    }

    #[test]
    fn correct_unsubmitted_answers_do_not_count_as_mastered() {
        let (mut model, pack_id, question) = number_question_model("mastered-check");
        let question_id = &question.id;
        let part_id = &question.parts[0].id;
        model.answer_mut(&pack_id, question_id, part_id).scalar = "42".to_owned();
        model.touch_attempt(&pack_id, question_id);

        assert_eq!(model.question_progress(&pack_id, &question), (1, 0));
        let before = model
            .filtered_questions()
            .iter()
            .find(|item| item.question_id == *question_id)
            .unwrap()
            .clone();
        assert_eq!(before.mastered_parts, 0);
        assert_eq!(before.progress, QuestionProgress::InProgress);

        assert!(model.set_part_checked(&pack_id, question_id, part_id, true));
        assert_eq!(model.question_progress(&pack_id, &question), (1, 1));
        let after = model
            .filtered_questions()
            .iter()
            .find(|item| item.question_id == *question_id)
            .unwrap()
            .clone();
        assert_eq!(after.mastered_parts, 1);
        assert_eq!(after.progress, QuestionProgress::Complete);
    }

    #[test]
    fn checked_parts_survive_save_and_relaunch() {
        let store = test_store("checked-relaunch");
        let mut model = StudioModel::load(store.clone());
        let markdown = r#"
:::question id=persisted-submission
# Persisted Submission
:::part id=amount kind=number
### Prompt
Enter 42.
### Answer
42
:::endpart
:::endquestion
"#;
        model
            .import_markdown(markdown, "persisted-submission.md", None)
            .unwrap();
        let pack_id = model.selected_pack_id.clone().unwrap();
        model
            .answer_mut(&pack_id, "persisted-submission", "amount")
            .scalar = "42".to_owned();
        model.touch_attempt(&pack_id, "persisted-submission");
        assert!(model.set_part_checked(&pack_id, "persisted-submission", "amount", true));
        model.save_now().unwrap();

        let reloaded = StudioModel::load(store);
        assert!(reloaded.is_part_checked(&pack_id, "persisted-submission", "amount"));
        let question = reloaded.selected_question().unwrap();
        assert_eq!(reloaded.question_progress(&pack_id, &question), (1, 1));
    }

    #[test]
    fn zero_result_filters_preserve_selection_and_saved_answers() {
        let (mut model, pack_id, question) = number_question_model("zero-filter");
        model.answer_mut(&pack_id, &question.id, "amount").scalar = "42".to_owned();
        model.touch_attempt(&pack_id, &question.id);
        let selected_before = (
            model.selected_pack_id.clone(),
            model.selected_question_id.clone(),
        );

        model.search = "no question can match this exact filter".to_owned();
        assert!(model.filtered_questions().is_empty());
        assert_eq!(
            (
                model.selected_pack_id.clone(),
                model.selected_question_id.clone()
            ),
            selected_before
        );
        assert_eq!(
            model.attempt_for(&pack_id, &question.id).unwrap().answers["amount"].scalar,
            "42"
        );

        model.search.clear();
        assert!(
            model
                .filtered_questions()
                .iter()
                .any(|item| { item.pack_id == pack_id && item.question_id == question.id })
        );
        assert_eq!(
            model.attempt_for(&pack_id, &question.id).unwrap().answers["amount"].scalar,
            "42"
        );
    }

    #[test]
    fn reimporting_the_same_source_replaces_its_pack() {
        let mut model = StudioModel::load(test_store("replace"));
        let path = PathBuf::from("/tmp/replace-me.md");
        let markdown = r#"
:::question id=replace-1
# Replacement
:::part id=a kind=number
### Prompt
Enter one.
### Answer
1
:::endpart
:::endquestion
"#;
        model
            .import_markdown(markdown, "replace-me.md", Some(path.clone()))
            .unwrap();
        let pack_id = model.selected_pack_id.clone().unwrap();
        model.answer_mut(&pack_id, "replace-1", "a").scalar = "1".to_owned();
        model.touch_attempt(&pack_id, "replace-1");
        let pack_count = model.state.packs.len();
        let summary = model
            .import_markdown(markdown, "replace-me.md", Some(path))
            .unwrap();
        assert!(summary.replaced_existing_pack);
        assert_eq!(model.state.packs.len(), pack_count);
        assert_eq!(model.selected_pack_id.as_deref(), Some(pack_id.as_str()));
        assert_eq!(
            model
                .attempt_for(&pack_id, "replace-1")
                .and_then(|attempt| attempt.answers.get("a"))
                .map(|answer| answer.scalar.as_str()),
            Some("1")
        );
    }

    #[test]
    fn duplicate_question_ids_in_separate_packs_never_share_answers() {
        let mut model = StudioModel::load(test_store("pack-scope"));
        let markdown = r#"
:::question id=shared-id
# Shared-looking question
:::part id=a kind=number
### Prompt
Enter one.
### Answer
1
:::endpart
:::endquestion
"#;
        model
            .import_markdown(markdown, "bank-a.md", Some(PathBuf::from("/tmp/bank-a.md")))
            .unwrap();
        let first_pack = model.selected_pack_id.clone().unwrap();
        model
            .import_markdown(markdown, "bank-b.md", Some(PathBuf::from("/tmp/bank-b.md")))
            .unwrap();
        let second_pack = model.selected_pack_id.clone().unwrap();

        model.answer_mut(&first_pack, "shared-id", "a").scalar = "111".to_owned();
        model.touch_attempt(&first_pack, "shared-id");

        assert_eq!(
            model.attempt_for(&first_pack, "shared-id").unwrap().answers["a"].scalar,
            "111"
        );
        assert!(model.attempt_for(&second_pack, "shared-id").is_none());
    }

    #[test]
    fn large_library_results_are_cached_between_frames() {
        let questions = (0..3_088)
            .map(|index| AccountingQuestion {
                id: format!("large-{index:04}"),
                title: format!("Accounting question {index}"),
                formats: vec![QuestionFormat::ShortExplanation],
                parts: vec![QuestionPart {
                    id: "response".to_owned(),
                    ..QuestionPart::default()
                }],
                ..AccountingQuestion::default()
            })
            .collect();
        let state = AppState {
            packs: vec![StoredQuestionPack {
                id: "large-pack".to_owned(),
                pack: QuestionPack {
                    title: "Large bank".to_owned(),
                    questions,
                    ..QuestionPack::default()
                },
                ..StoredQuestionPack::default()
            }],
            ..AppState::default()
        };
        let mut model = StudioModel::from_state(test_store("large-cache"), state);
        let first = model.filtered_questions();
        assert_eq!(first.len(), 3_088);
        let second = model.filtered_questions();
        assert!(Arc::ptr_eq(&first, &second));

        model.search = "question 3087".to_owned();
        let filtered = model.filtered_questions();
        assert_eq!(filtered.len(), 1);
        assert!(!Arc::ptr_eq(&first, &filtered));
    }
}
