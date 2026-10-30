use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Synchronization status for Local-First replication.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncStatus {
    Pending,
    Synced,
}

impl SyncStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            SyncStatus::Pending => "pending",
            SyncStatus::Synced => "synced",
        }
    }
}

impl TryFrom<&str> for SyncStatus {
    type Error = String;

    fn try_from(s: &str) -> std::result::Result<Self, Self::Error> {
        match s {
            "pending" => Ok(SyncStatus::Pending),
            "synced" => Ok(SyncStatus::Synced),
            other => Err(format!("Unknown sync status: {}", other)),
        }
    }
}

/// Canonical, immutable domain record generated from an interpreted Directive.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DirectiveNote {
    pub id: String,
    pub content: String,
    pub raw_transcription: String,
    pub audio_duration_ms: u32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub sync_status: SyncStatus,
}

impl DirectiveNote {
    /// Creates a new DirectiveNote with a fresh client-generated UUID v4.
    pub fn new(content: impl Into<String>, raw_transcription: impl Into<String>, audio_duration_ms: u32) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4().to_string(),
            content: content.into(),
            raw_transcription: raw_transcription.into(),
            audio_duration_ms,
            created_at: now,
            updated_at: now,
            deleted_at: None,
            sync_status: SyncStatus::Pending,
        }
    }

    /// Checks whether the note has been soft-deleted.
    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }
}
