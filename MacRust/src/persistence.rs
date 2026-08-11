use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::domain::{AttemptRecord, QuestionPack};

pub const CURRENT_SCHEMA_VERSION: u32 = 1;
static ID_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct StoredQuestionPack {
    pub id: String,
    pub source_path: Option<PathBuf>,
    pub imported_at_unix_ms: u64,
    pub pack: QuestionPack,
}

impl StoredQuestionPack {
    pub fn imported(pack: QuestionPack, source_path: Option<PathBuf>) -> Self {
        Self {
            id: new_local_id("pack"),
            source_path,
            imported_at_unix_ms: current_unix_ms(),
            pack,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AppPreferences {
    pub last_pack_id: Option<String>,
    pub last_question_id: Option<String>,
    pub autosave_answers: bool,
    pub show_answer_after_check: bool,
}

impl Default for AppPreferences {
    fn default() -> Self {
        Self {
            last_pack_id: None,
            last_question_id: None,
            autosave_answers: true,
            show_answer_after_check: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct AppState {
    pub schema_version: u32,
    /// Imported packs are immutable and shared so an autosave snapshot never
    /// copies a multi-megabyte question bank on the UI thread.
    pub packs: Vec<Arc<StoredQuestionPack>>,
    /// Attempts are keyed by their stable attempt id for deterministic serialization.
    pub attempts: BTreeMap<String, AttemptRecord>,
    pub preferences: AppPreferences,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            packs: Vec::new(),
            attempts: BTreeMap::new(),
            preferences: AppPreferences::default(),
        }
    }
}

impl AppState {
    pub fn upsert_pack(&mut self, stored_pack: StoredQuestionPack) {
        if let Some(existing) = self.packs.iter_mut().find(|pack| pack.id == stored_pack.id) {
            *existing = Arc::new(stored_pack);
        } else {
            self.packs.push(Arc::new(stored_pack));
        }
    }

    pub fn upsert_attempt(&mut self, attempt: AttemptRecord) {
        self.attempts.insert(attempt.id.clone(), attempt);
    }

    pub fn new_attempt(&mut self, question_id: impl Into<String>) -> &mut AttemptRecord {
        let id = new_local_id("attempt");
        let attempt = AttemptRecord {
            id: id.clone(),
            question_id: question_id.into(),
            answers: BTreeMap::new(),
            checked_part_ids: BTreeSet::new(),
            self_reviews: BTreeMap::new(),
            updated_at_unix_ms: current_unix_ms(),
        };
        self.attempts.entry(id).or_insert(attempt)
    }
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("could not locate the user's home folder")]
    HomeDirectoryUnavailable,
    #[error("could not read or write application state at {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("application state at {path} is not valid JSON: {source}")]
    Decode {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("could not encode application state: {0}")]
    Encode(#[from] serde_json::Error),
    #[error("state schema {found} is newer than the supported schema {supported}")]
    UnsupportedSchema { found: u32, supported: u32 },
}

#[derive(Debug, Clone)]
pub struct JsonStateStore {
    path: PathBuf,
    primary_verified: Arc<AtomicBool>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LoadedAppState {
    pub state: AppState,
    pub recovered_from_backup: bool,
}

impl JsonStateStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self {
            path: path.into(),
            primary_verified: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn standard_macos(app_identifier: &str) -> Result<Self, StoreError> {
        let home = std::env::var_os("HOME").ok_or(StoreError::HomeDirectoryUnavailable)?;
        Ok(Self::new(
            PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join(app_identifier)
                .join("state.json"),
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Copy a prior installation's state into this store only when this store
    /// has no primary or recovery file. The legacy files remain untouched so
    /// an identifier migration is reversible.
    pub fn migrate_if_missing_from(&self, legacy: &Self) -> Result<bool, StoreError> {
        if self.path.exists() || backup_path_for(&self.path).exists() {
            return Ok(false);
        }
        if !legacy.path.exists() && !backup_path_for(&legacy.path).exists() {
            return Ok(false);
        }

        let loaded = legacy.load_with_recovery()?;
        self.save(&loaded.state)?;
        Ok(true)
    }

    /// A missing state file means a clean first launch, not an error.
    pub fn load(&self) -> Result<AppState, StoreError> {
        self.load_with_recovery().map(|loaded| loaded.state)
    }

    /// Load the primary state, falling back to the last atomically written
    /// backup when the primary JSON is missing or corrupt. A newer schema is
    /// never silently replaced with an older backup.
    pub fn load_with_recovery(&self) -> Result<LoadedAppState, StoreError> {
        match load_state_file(&self.path) {
            Ok(Some(state)) => {
                self.primary_verified.store(true, Ordering::Relaxed);
                Ok(LoadedAppState {
                    state,
                    recovered_from_backup: false,
                })
            }
            Ok(None) => self.load_backup_or_default(),
            Err(primary_error @ StoreError::Decode { .. }) => {
                match load_state_file(&backup_path_for(&self.path)) {
                    Ok(Some(state)) => {
                        self.primary_verified.store(false, Ordering::Relaxed);
                        Ok(LoadedAppState {
                            state,
                            recovered_from_backup: true,
                        })
                    }
                    Ok(None) | Err(_) => Err(primary_error),
                }
            }
            Err(error) => Err(error),
        }
    }

    /// Save through a sibling temporary file, then atomically replace the prior state.
    pub fn save(&self, state: &AppState) -> Result<(), StoreError> {
        let bytes = serde_json::to_vec(state)?;
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent).map_err(|source| StoreError::Io {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        let backup_path = backup_path_for(&self.path);
        let primary_verified = self.primary_verified.load(Ordering::Relaxed) && self.path.exists();
        if primary_verified {
            replace_with_hard_link(&self.path, &backup_path)?;
        }
        write_atomic(&self.path, &bytes)?;
        self.primary_verified.store(true, Ordering::Relaxed);
        if !primary_verified && !backup_path.exists() {
            // A first save gets a recoverable twin. If the current primary was
            // corrupt and a good backup already exists, preserve that backup.
            // Use a separate inode here so an in-place external overwrite of
            // the primary cannot corrupt both copies at once.
            write_atomic(&backup_path, &bytes)?;
        }
        Ok(())
    }

    fn load_backup_or_default(&self) -> Result<LoadedAppState, StoreError> {
        match load_state_file(&backup_path_for(&self.path)) {
            Ok(Some(state)) => {
                self.primary_verified.store(false, Ordering::Relaxed);
                Ok(LoadedAppState {
                    state,
                    recovered_from_backup: true,
                })
            }
            Ok(None) => {
                self.primary_verified.store(false, Ordering::Relaxed);
                Ok(LoadedAppState {
                    state: AppState::default(),
                    recovered_from_backup: false,
                })
            }
            Err(error) => Err(error),
        }
    }
}

impl PartialEq for JsonStateStore {
    fn eq(&self, other: &Self) -> bool {
        self.path == other.path
    }
}

impl Eq for JsonStateStore {}

fn temporary_path_for(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("state.json");
    path.with_file_name(format!(".{file_name}.{}.tmp", new_local_id("write")))
}

fn backup_path_for(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("state.json");
    path.with_file_name(format!(".{file_name}.backup"))
}

fn load_state_file(path: &Path) -> Result<Option<AppState>, StoreError> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(source) => {
            return Err(StoreError::Io {
                path: path.to_path_buf(),
                source,
            });
        }
    };
    decode_state(&bytes, path).map(Some)
}

fn decode_state(bytes: &[u8], path: &Path) -> Result<AppState, StoreError> {
    let state: AppState = serde_json::from_slice(bytes).map_err(|source| StoreError::Decode {
        path: path.to_path_buf(),
        source,
    })?;
    if state.schema_version > CURRENT_SCHEMA_VERSION {
        return Err(StoreError::UnsupportedSchema {
            found: state.schema_version,
            supported: CURRENT_SCHEMA_VERSION,
        });
    }
    Ok(state)
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), StoreError> {
    let temporary_path = temporary_path_for(path);
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary_path)
            .map_err(|source| StoreError::Io {
                path: temporary_path.clone(),
                source,
            })?;
        file.write_all(bytes).map_err(|source| StoreError::Io {
            path: temporary_path.clone(),
            source,
        })?;
        file.sync_all().map_err(|source| StoreError::Io {
            path: temporary_path.clone(),
            source,
        })?;
        fs::rename(&temporary_path, path).map_err(|source| StoreError::Io {
            path: path.to_path_buf(),
            source,
        })?;
        sync_parent(path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    result
}

fn replace_with_hard_link(source: &Path, destination: &Path) -> Result<(), StoreError> {
    let temporary_path = temporary_path_for(destination);
    let result = (|| {
        fs::hard_link(source, &temporary_path).map_err(|source| StoreError::Io {
            path: temporary_path.clone(),
            source,
        })?;
        fs::rename(&temporary_path, destination).map_err(|source| StoreError::Io {
            path: destination.to_path_buf(),
            source,
        })?;
        sync_parent(destination)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    result
}

fn sync_parent(path: &Path) -> Result<(), StoreError> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|source| StoreError::Io {
            path: parent.to_path_buf(),
            source,
        })
}

pub fn current_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

pub fn new_local_id(prefix: &str) -> String {
    let sequence = ID_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!(
        "{prefix}-{}-{}-{sequence}",
        std::process::id(),
        current_unix_ms()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temporary_test_store(test_name: &str) -> JsonStateStore {
        JsonStateStore::new(std::env::temp_dir().join(format!(
            "accounting-question-studio-{}-{test_name}/state.json",
            new_local_id("test")
        )))
    }

    #[test]
    fn missing_file_loads_clean_state_and_can_migrate_legacy_state() {
        let store = temporary_test_store("missing");
        assert_eq!(store.load().unwrap(), AppState::default());

        let root = std::env::temp_dir().join(format!(
            "ledgerforge-identifier-migration-{}",
            new_local_id("test")
        ));
        let legacy = JsonStateStore::new(root.join("legacy/state.json"));
        let current = JsonStateStore::new(root.join("current/state.json"));
        let mut legacy_state = AppState::default();
        legacy_state.preferences.last_question_id = Some("kept-progress".to_owned());
        legacy.save(&legacy_state).unwrap();

        assert!(current.migrate_if_missing_from(&legacy).unwrap());
        assert_eq!(current.load().unwrap(), legacy_state);
        assert_eq!(legacy.load().unwrap(), legacy_state);
        assert!(legacy.path().exists());

        let mut current_state = legacy_state.clone();
        current_state.preferences.last_question_id = Some("current-wins".to_owned());
        current.save(&current_state).unwrap();
        assert!(!current.migrate_if_missing_from(&legacy).unwrap());
        assert_eq!(current.load().unwrap(), current_state);

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn state_round_trips_through_versioned_json() {
        let store = temporary_test_store("roundtrip");
        let mut state = AppState::default();
        state
            .new_attempt("question-1")
            .checked_part_ids
            .insert("part-a".to_owned());
        store.save(&state).unwrap();
        assert_eq!(store.load().unwrap(), state);
        let parent = store.path().parent().unwrap();
        let _ = fs::remove_dir_all(parent);
    }

    #[test]
    fn legacy_nonempty_pack_json_remains_wire_compatible_with_shared_packs() {
        let legacy_json = r#"{
            "schemaVersion": 1,
            "packs": [{
                "id": "legacy-pack",
                "sourcePath": null,
                "importedAtUnixMs": 1,
                "pack": {
                    "version": 1,
                    "title": "Legacy Pack",
                    "questions": [{
                        "id": "legacy-question",
                        "title": "Legacy Question",
                        "parts": []
                    }]
                }
            }],
            "attempts": {},
            "preferences": {
                "lastPackId": "legacy-pack",
                "lastQuestionId": "legacy-question",
                "autosaveAnswers": true,
                "showAnswerAfterCheck": false
            }
        }"#;

        let state: AppState = serde_json::from_str(legacy_json).unwrap();
        assert_eq!(state.packs.len(), 1);
        assert_eq!(state.packs[0].id, "legacy-pack");
        assert_eq!(state.packs[0].pack.questions[0].id, "legacy-question");

        let encoded = serde_json::to_value(&state).unwrap();
        let stored_pack = &encoded["packs"][0];
        assert!(stored_pack.is_object());
        assert_eq!(stored_pack["id"], "legacy-pack");
        assert_eq!(stored_pack["pack"]["title"], "Legacy Pack");
    }

    #[test]
    fn legacy_attempt_without_checked_parts_migrates_to_unsubmitted() {
        let legacy_json = r#"{
            "id": "legacy-attempt",
            "questionId": "pack::question",
            "answers": {"part-a": {"scalar": "42"}},
            "selfReviews": {"part-a": true},
            "updatedAtUnixMs": 1
        }"#;
        let attempt: AttemptRecord = serde_json::from_str(legacy_json).unwrap();
        assert!(attempt.checked_part_ids.is_empty());
        assert_eq!(attempt.answers["part-a"].scalar, "42");
        assert_eq!(attempt.self_reviews.get("part-a"), Some(&true));
    }

    #[test]
    fn future_schema_is_rejected() {
        let store = temporary_test_store("schema");
        let state = AppState {
            schema_version: CURRENT_SCHEMA_VERSION + 1,
            ..AppState::default()
        };
        store.save(&state).unwrap();
        assert!(matches!(
            store.load(),
            Err(StoreError::UnsupportedSchema { .. })
        ));
        let parent = store.path().parent().unwrap();
        let _ = fs::remove_dir_all(parent);
    }

    #[test]
    fn corrupt_primary_recovers_the_last_atomic_backup() {
        let store = temporary_test_store("recovery");
        let mut first = AppState::default();
        first.preferences.last_question_id = Some("first".to_owned());
        store.save(&first).unwrap();

        let mut second = first.clone();
        second.preferences.last_question_id = Some("second".to_owned());
        store.save(&second).unwrap();
        fs::write(store.path(), b"{not valid json").unwrap();

        let loaded = store.load_with_recovery().unwrap();
        assert!(loaded.recovered_from_backup);
        assert_eq!(loaded.state, first);
        let parent = store.path().parent().unwrap();
        let _ = fs::remove_dir_all(parent);
    }

    #[test]
    fn repeated_saves_serialize_the_primary_state_deterministically() {
        let store = temporary_test_store("deterministic");
        let mut state = AppState::default();
        state.new_attempt("pack::question");
        store.save(&state).unwrap();
        let first = fs::read(store.path()).unwrap();
        store.save(&state).unwrap();
        let second = fs::read(store.path()).unwrap();
        assert_eq!(first, second);
        let parent = store.path().parent().unwrap();
        let _ = fs::remove_dir_all(parent);
    }
}
