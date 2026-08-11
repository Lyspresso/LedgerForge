//! Shared domain, import, grading, and persistence engine for the Rust macOS app.
//!
//! Markdown is the cross-app interchange format. Persisted Rust application state is
//! versioned JSON so migrations can be added without changing imported question packs.

pub mod domain;
pub mod grading;
pub mod markdown;
pub mod persistence;
pub mod spreadsheet;
pub mod studio;
pub mod title;

pub use domain::*;
pub use grading::*;
pub use markdown::*;
pub use persistence::*;
pub use spreadsheet::*;
pub use studio::*;
pub use title::*;
