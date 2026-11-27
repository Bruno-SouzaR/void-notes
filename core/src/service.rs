use parking_lot::Mutex;
use rusqlite::Connection;
use std::path::Path;
use std::sync::Arc;

use crate::audio::{AudioRingBuffer, EndpointResult, EnergyGate, SpeechEndpointDetector};
use crate::db::{initialize_schema, DirectiveNoteRepository};
use crate::feedback::{FeedbackAction, FeedbackController, FeedbackEvent, FeedbackProfile};
use crate::kws::{MockWakeWordDetector, WakeWordDetector};
use crate::models::DirectiveNote;
use crate::storage::MarkdownMirror;
use crate::stt::{DirectiveFormatter, MockSpeechRecognizer, SpeechRecognizer};
use crate::Result;

/// High-level orchestration engine for the void-notes service.
pub struct VoidService {
    conn: Arc<Mutex<Connection>>,
    mirror: MarkdownMirror,
    energy_gate: Arc<Mutex<EnergyGate>>,
    kws: Arc<Mutex<Box<dyn WakeWordDetector>>>,
    endpoint_detector: Arc<Mutex<SpeechEndpointDetector>>,
    recognizer: Arc<Box<dyn SpeechRecognizer>>,
    feedback: Arc<Mutex<FeedbackController>>,
    ring_buffer: Arc<Mutex<AudioRingBuffer>>,
    is_active_session: Arc<Mutex<bool>>,
}

impl VoidService {
    /// Initializes a new VoidService with an open SQLite connection and storage directory.
    pub fn new(
        db_path: &Path,
        notes_dir: &Path,
        feedback_profile: FeedbackProfile,
    ) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        initialize_schema(&conn)?;

        Self::from_connection(
            conn,
            notes_dir,
            feedback_profile,
            Box::new(MockWakeWordDetector::new(Default::default())),
            Box::new(MockSpeechRecognizer::new()),
        )
    }

    /// Initializes a service from an existing connection (useful for in-memory testing).
    pub fn from_connection(
        conn: Connection,
        notes_dir: &Path,
        feedback_profile: FeedbackProfile,
        kws: Box<dyn WakeWordDetector>,
        recognizer: Box<dyn SpeechRecognizer>,
    ) -> Result<Self> {
        initialize_schema(&conn)?;

        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            mirror: MarkdownMirror::new(notes_dir),
            energy_gate: Arc::new(Mutex::new(EnergyGate::with_defaults())),
            kws: Arc::new(Mutex::new(kws)),
            endpoint_detector: Arc::new(Mutex::new(SpeechEndpointDetector::with_defaults())),
            recognizer: Arc::new(recognizer),
            feedback: Arc::new(Mutex::new(FeedbackController::new(feedback_profile))),
            ring_buffer: Arc::new(Mutex::new(AudioRingBuffer::with_duration_seconds(3.0))),
            is_active_session: Arc::new(Mutex::new(false)),
        })
    }

    /// Triggers an immediate PriorityOverride recording session (for hotkeys / meeting mode).
    pub fn trigger_priority_override(&self) -> Vec<FeedbackAction> {
        let mut session = self.is_active_session.lock();
        *session = true;

        let mut detector = self.endpoint_detector.lock();
        detector.start_session();

        let feedback = self.feedback.lock();
        feedback.resolve_feedback(FeedbackEvent::WakeWordDetected)
    }

    /// Cancels the current ongoing directive recording session.
    pub fn cancel_active_session(&self) {
        let mut session = self.is_active_session.lock();
        *session = false;

        let mut detector = self.endpoint_detector.lock();
        detector.cancel();
    }

    /// Ingests an incoming audio chunk (16 kHz f32 samples) through the tiered acoustic pipeline.
    ///
    /// Returns any DirectiveNote created as well as sensory feedback actions to trigger.
    pub fn process_audio_chunk(
        &self,
        samples: &[f32],
        chunk_duration_ms: u32,
    ) -> Result<(Option<DirectiveNote>, Vec<FeedbackAction>)> {
        let mut actions = Vec::new();

        // 1. Always update sliding ring buffer
        {
            let mut rb = self.ring_buffer.lock();
            rb.push_samples(samples);
        }

        let is_session_active = *self.is_active_session.lock();

        if !is_session_active {
            // Tier 0: Check Energy Gate first before neural KWS
            let is_speech = self.energy_gate.lock().is_speech(samples);
            if !is_speech {
                return Ok((None, actions));
            }

            // Tier 1: Check Wake Word Spotter
            let detection = self.kws.lock().process_samples(samples);
            if detection.is_some() {
                // WakeWord detected! Activate session
                let mut session = self.is_active_session.lock();
                *session = true;

                let mut detector = self.endpoint_detector.lock();
                detector.start_session();

                let feedback = self.feedback.lock();
                actions.extend(feedback.resolve_feedback(FeedbackEvent::WakeWordDetected));
            }
            return Ok((None, actions));
        }

        // Active session: Tier 2 Endpointing
        let is_speech = self.energy_gate.lock().is_speech(samples);
        let endpoint_res =
            self.endpoint_detector
                .lock()
                .process_frame(is_speech, chunk_duration_ms, samples);

        match endpoint_res {
            EndpointResult::Continuing => Ok((None, actions)),
            EndpointResult::SessionCancelled => {
                let mut session = self.is_active_session.lock();
                *session = false;
                Ok((None, actions))
            }
            EndpointResult::DirectiveComplete(captured_audio) => {
                let mut session = self.is_active_session.lock();
                *session = false;

                // Tier 3: Speech-to-Text via Recognizer
                let raw_text = self.recognizer.transcribe(&captured_audio)?;
                let duration_ms = (captured_audio.len() as f32 / 16.0) as u32;

                // Clean and format directive
                if let Some(cleaned_content) = DirectiveFormatter::format(&raw_text) {
                    let note = DirectiveNote::new(cleaned_content, raw_text, duration_ms);

                    // Tier 4: Persist in SQLite
                    {
                        let conn = self.conn.lock();
                        DirectiveNoteRepository::create(&conn, &note)?;
                    }

                    // Mirror into daily Markdown file
                    self.mirror.append_note(&note)?;

                    // Emitting completion feedback
                    let feedback = self.feedback.lock();
                    actions.extend(feedback.resolve_feedback(FeedbackEvent::DirectiveCompleted));

                    Ok((Some(note), actions))
                } else {
                    Ok((None, actions))
                }
            }
        }
    }

    /// Revokes and soft-deletes the most recently created directive within the UndoWindow.
    pub fn revoke_latest_directive(&self) -> Result<(Option<DirectiveNote>, Vec<FeedbackAction>)> {
        let conn = self.conn.lock();
        let latest = DirectiveNoteRepository::get_latest_active(&conn)?;

        if let Some(note) = latest {
            // Soft-delete in SQLite
            DirectiveNoteRepository::soft_delete(&conn, &note.id)?;

            // Reconcile today's Markdown file
            let date_str = note.created_at.format("%Y-%m-%d").to_string();
            let remaining_active = DirectiveNoteRepository::list_by_date(&conn, &date_str)?;
            self.mirror.reconcile_day(&date_str, &remaining_active)?;

            let feedback = self.feedback.lock();
            let actions = feedback.resolve_feedback(FeedbackEvent::DirectiveRevoked);

            Ok((Some(note), actions))
        } else {
            Ok((None, Vec::new()))
        }
    }

    /// Lists today's active directives.
    pub fn list_today_notes(&self) -> Result<Vec<DirectiveNote>> {
        let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let conn = self.conn.lock();
        DirectiveNoteRepository::list_by_date(&conn, &today)
    }

    /// Updates the sensory feedback profile (Normal vs. SilentMeeting).
    pub fn set_feedback_profile(&self, profile: FeedbackProfile) {
        let mut feedback = self.feedback.lock();
        feedback.set_profile(profile);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::feedback::HapticPattern;
    use tempfile::tempdir;

    #[test]
    fn test_void_service_end_to_end_flow() {
        let temp = tempdir().expect("tempdir failed");
        let conn = Connection::open_in_memory().expect("in memory db failed");

        let mut mock_kws = MockWakeWordDetector::new(Default::default());
        mock_kws.arm_trigger();

        let mock_stt = MockSpeechRecognizer::with_response("void comprar pao e cafe");

        let service = VoidService::from_connection(
            conn,
            temp.path(),
            FeedbackProfile::Normal,
            Box::new(mock_kws),
            Box::new(mock_stt),
        )
        .expect("service init failed");

        let speech_chunk: Vec<f32> = (0..480).map(|i| 0.2 * (i as f32 * 0.05).sin()).collect(); // 30ms speech

        // 1. Process chunk with armed KWS -> triggers WakeWord
        let (note1, actions1) = service
            .process_audio_chunk(&speech_chunk, 30)
            .expect("chunk process failed");
        assert!(note1.is_none());
        assert!(actions1.contains(&FeedbackAction::PlayAudioChime("chime_wake.wav")));

        // 2. Feed speech frames (80 frames = 2.4s)
        for _ in 0..80 {
            service
                .process_audio_chunk(&speech_chunk, 30)
                .expect("speech frame failed");
        }

        // 3. Feed silence frames until endpointing completion (50 frames = 1500ms)
        let silence_chunk = vec![0.0f32; 480];
        let mut completed_note = None;
        let mut completed_actions = Vec::new();

        for _ in 0..50 {
            let (maybe_note, actions) = service
                .process_audio_chunk(&silence_chunk, 30)
                .expect("silence frame failed");
            if maybe_note.is_some() {
                completed_note = maybe_note;
                completed_actions = actions;
                break;
            }
        }

        // Verify DirectiveNote was created and formatted cleanly
        let note = completed_note.expect("expected completed note");
        assert_eq!(note.content, "Comprar pao e cafe.");
        assert!(completed_actions.contains(&FeedbackAction::PlayAudioChime("chime_complete.wav")));

        // 4. Verify note is persisted in SQLite
        let today_notes = service.list_today_notes().expect("list failed");
        assert_eq!(today_notes.len(), 1);
        assert_eq!(today_notes[0].id, note.id);

        // 5. Verify Markdown file was written
        let date_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let md_file = temp.path().join(format!("{}.md", date_str));
        assert!(md_file.exists());
        let md_content = std::fs::read_to_string(&md_file).expect("read md failed");
        assert!(md_content.contains("Comprar pao e cafe."));

        // 6. Test UndoWindow: Revoke the directive
        let (revoked, revoke_actions) = service.revoke_latest_directive().expect("revoke failed");
        assert!(revoked.is_some());
        assert!(revoke_actions.contains(&FeedbackAction::TriggerHaptic(HapticPattern::LightTap)));

        // Verify list is now empty and MD file has removed it
        let active_after_revoke = service.list_today_notes().expect("list failed");
        assert_eq!(active_after_revoke.len(), 0);
        let updated_md = std::fs::read_to_string(&md_file).expect("read md failed");
        assert!(!updated_md.contains("Comprar pao e cafe."));
    }
}
