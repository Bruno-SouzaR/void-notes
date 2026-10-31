use std::path::PathBuf;
use std::sync::OnceLock;
use parking_lot::Mutex;

use crate::feedback::FeedbackProfile;
use crate::models::DirectiveNote;
use crate::service::VoidService;
use crate::{Result, VoidError};

static GLOBAL_SERVICE: OnceLock<Mutex<VoidService>> = OnceLock::new();

/// Initializes the global void-notes singleton engine from Flutter.
pub fn init_engine(db_path: String, notes_dir: String, silent_mode: bool) -> Result<()> {
    let profile = if silent_mode {
        FeedbackProfile::SilentMeeting
    } else {
        FeedbackProfile::Normal
    };

    let service = VoidService::new(
        &PathBuf::from(db_path),
        &PathBuf::from(notes_dir),
        profile,
    )?;

    if GLOBAL_SERVICE.get().is_some() {
        return Err(VoidError::Domain("void-notes engine is already initialized".to_string()));
    }

    let _ = GLOBAL_SERVICE.set(Mutex::new(service));
    Ok(())
}

/// Helper to get the global service reference.
fn get_service() -> Result<&'static Mutex<VoidService>> {
    GLOBAL_SERVICE
        .get()
        .ok_or_else(|| VoidError::Domain("void-notes engine not initialized".to_string()))
}

/// Triggers manual recording bypass (hotkey / action button).
pub fn trigger_priority_override() -> Result<Vec<String>> {
    let service = get_service()?.lock();
    let actions = service.trigger_priority_override();
    let action_names = actions.iter().map(|a| format!("{:?}", a)).collect();
    Ok(action_names)
}

/// Cancels active speech capture.
pub fn cancel_active_session() -> Result<()> {
    let service = get_service()?.lock();
    service.cancel_active_session();
    Ok(())
}

/// Feeds an audio chunk from the platform microphone stream.
pub fn process_audio_chunk(samples: Vec<f32>, duration_ms: u32) -> Result<Option<DirectiveNote>> {
    let service = get_service()?.lock();
    let (note, _actions) = service.process_audio_chunk(&samples, duration_ms)?;
    Ok(note)
}

/// Reverses the latest captured directive within the UndoWindow.
pub fn revoke_latest_directive() -> Result<Option<DirectiveNote>> {
    let service = get_service()?.lock();
    let (note, _actions) = service.revoke_latest_directive()?;
    Ok(note)
}

/// Lists today's active directives.
pub fn list_today_notes() -> Result<Vec<DirectiveNote>> {
    let service = get_service()?.lock();
    service.list_today_notes()
}

/// Toggles between Normal and SilentMeeting feedback profiles.
pub fn set_silent_mode(enabled: bool) -> Result<()> {
    let service = get_service()?.lock();
    let profile = if enabled {
        FeedbackProfile::SilentMeeting
    } else {
        FeedbackProfile::Normal
    };
    service.set_feedback_profile(profile);
    Ok(())
}
