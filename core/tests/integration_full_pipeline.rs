mod support;

use std::fs;
use support::{AudioGenerator, TestHarness};
use void_notes_core::feedback::{FeedbackAction, FeedbackProfile};
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;

#[test]
fn test_integration_full_audio_pipeline_to_markdown() {
    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response("void comprar cafe e enviar relatorio");

    let (service, _temp, _db_path, notes_dir) = TestHarness::create_service(
        Box::new(mock_kws),
        Box::new(mock_stt),
        FeedbackProfile::Normal,
    );

    // 1. Stream 10 frames of background silence (Tier 0 Energy Gate keeps system idle)
    let silence = AudioGenerator::silence(30);
    for _ in 0..10 {
        let (note, actions) = service.process_audio_chunk(&silence, 30).unwrap();
        assert!(note.is_none());
        assert!(actions.is_empty());
    }

    // 2. Stream speech chunk containing wake word ("Void")
    let speech = AudioGenerator::speech_burst(30, 180.0, 0.25);
    let (note, actions) = service.process_audio_chunk(&speech, 30).unwrap();
    assert!(note.is_none());
    assert!(actions.contains(&FeedbackAction::PlayAudioChime("chime_wake.wav")));

    // 3. User speaks for 2.1 seconds (70 frames)
    for _ in 0..70 {
        service.process_audio_chunk(&speech, 30).unwrap();
    }

    // 4. User stops speaking; trailing silence streams for 1.5s (50 frames of 30ms)
    let mut completed_note = None;
    for _ in 0..50 {
        let (maybe_note, actions) = service.process_audio_chunk(&silence, 30).unwrap();
        if maybe_note.is_some() {
            completed_note = maybe_note;
            assert!(actions.contains(&FeedbackAction::PlayAudioChime("chime_complete.wav")));
            break;
        }
    }

    // 5. Verify DirectiveNote
    let note = completed_note.expect("Expected completed directive note!");
    assert_eq!(note.content, "Comprar cafe e enviar relatorio.");

    // 6. Verify SQLite persistence
    let today_notes = service.list_today_notes().unwrap();
    assert_eq!(today_notes.len(), 1);
    assert_eq!(today_notes[0].id, note.id);

    // 7. Verify Markdown mirror file
    let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let md_path = notes_dir.join(format!("{}.md", today_str));
    assert!(md_path.exists());
    let md_content = fs::read_to_string(&md_path).unwrap();
    assert!(md_content.contains("Comprar cafe e enviar relatorio."));
}
