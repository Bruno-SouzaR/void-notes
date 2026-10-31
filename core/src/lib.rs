//! void-notes Core Engine
//!
//! High-efficiency native runtime for hands-free voice note-taking and directive execution.

pub mod audio;
pub mod bridge;
pub mod db;
pub mod feedback;
pub mod kws;
pub mod models;
pub mod service;
pub mod storage;
pub mod stt;

pub use service::VoidService;

/// Core error types for the void-notes engine.
#[derive(thiserror::Error, Debug)]
pub enum VoidError {
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Domain error: {0}")]
    Domain(String),
}

pub type Result<T, E = VoidError> = std::result::Result<T, E>;
