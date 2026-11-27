mod support;

use std::fs;
use support::{AudioGenerator, TestHarness};
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;

/// Regression Test: UndoWindow 8-second revocation.
///
/// Proves that calling revoke_latest_directive marks the note as soft-deleted
/// in SQLite and automatically removes its line from the daily Markdown file.
#[test]
fn test_regression_undo_window_revokes_from_db_and_markdown() {
    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response("void comprar cafe amarga");

    let (service, _temp, _db_path, notes_dir) = TestHarness::create_service(
        Box::new(mock_kws),
        Box::new(mock_stt),
        FeedbackProfile::Normal,
    );

    // 1. Record directive
    let speech = AudioGenerator::speech_burst(30, 180.0, 0.25);
    service.process_audio_chunk(&speech, 30).unwrap(); // Trigger KWS
    for _ in 0..70 {
        service.process_audio_chunk(&speech, 30).unwrap(); // 2.1s speech
    }
    let silence = AudioGenerator::silence(30);
    for _ in 0..50 {
        service.process_audio_chunk(&silence, 30).unwrap(); // 1.5s endpoint
    }

    // Verify created
    assert_eq!(service.list_today_notes().unwrap().len(), 1);
    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let md_path = notes_dir.join(format!("{}.md", today_str));
    assert!(fs::read_to_string(&md_path)
        .unwrap()
        .contains("Comprar cafe amarga."));

    // 2. Execute UndoWindow revocation
    let (revoked_note, actions) = service.revoke_latest_directive().unwrap();
    let revoked = revoked_note.expect("Expected note to be returned on revocation");
    assert_eq!(revoked.content, "Comprar cafe amarga.");
    assert!(!actions.is_empty());

    // 3. Verify SQLite no longer lists it as active
    assert_eq!(service.list_today_notes().unwrap().len(), 0);

    // 4. Verify Markdown file mirror no longer contains the line
    let md_content = fs::read_to_string(&md_path).unwrap();
    assert!(
        !md_content.contains("Comprar cafe amarga."),
        "Markdown mirror must expunge revoked directive!"
    );
}
