mod support;

use support::{AudioGenerator, TestHarness};
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;

/// Regression Test for AC-3 Invariant: Anti-Ghost Note.
///
/// Proves that an accidental WakeWord activation followed immediately by silence
/// strictly aborts without writing ghost notes to SQLite or Markdown.
#[test]
fn test_regression_anti_ghost_note_creates_zero_records() {
    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response("Ghost note should not appear");

    let (service, _temp, _db_path, notes_dir) = TestHarness::create_service(
        Box::new(mock_kws),
        Box::new(mock_stt),
        FeedbackProfile::Normal,
    );

    // 1. Trigger WakeWord
    let speech = AudioGenerator::speech_burst(30, 180.0, 0.2);
    let (note_trigger, _) = service.process_audio_chunk(&speech, 30).unwrap();
    assert!(note_trigger.is_none());

    // 2. Room goes dead silent for 3.6s (> initial_silence_timeout_ms = 3500ms)
    // 3600ms / 30ms = 120 frames
    let silence = AudioGenerator::silence(30);
    for _ in 0..120 {
        let (maybe_note, _) = service.process_audio_chunk(&silence, 30).unwrap();
        assert!(maybe_note.is_none(), "Ghost note was prematurely produced!");
    }

    // 3. Assert zero notes exist in SQLite
    let today_notes = service.list_today_notes().unwrap();
    assert_eq!(
        today_notes.len(),
        0,
        "AC-3 Violation: SQLite must contain 0 records after silence timeout!"
    );

    // 4. Assert no Markdown files exist
    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let md_path = notes_dir.join(format!("{}.md", today_str));
    assert!(
        !md_path.exists(),
        "AC-3 Violation: Markdown mirror must not exist for ghost activations!"
    );
}
