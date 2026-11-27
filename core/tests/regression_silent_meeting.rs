mod support;

use support::{AudioGenerator, TestHarness};
use void_notes_core::feedback::{FeedbackAction, FeedbackProfile};
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;

/// Regression Test for AC-5 Invariant: Silent Meeting Mode Compliance.
///
/// Proves that when SilentMeeting is active, the engine STRICTLY NEVER emits
/// any PlayAudioChime actions across any phase of directive lifecycle.
#[test]
fn test_regression_silent_meeting_mode_never_emits_audio_chimes() {
    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response("void anotação confidencial em reunião");

    let (service, _temp, _db_path, _notes_dir) = TestHarness::create_service(
        Box::new(mock_kws),
        Box::new(mock_stt),
        FeedbackProfile::SilentMeeting, // Enforcing SilentMeeting
    );

    let speech = AudioGenerator::speech_burst(30, 180.0, 0.25);
    let silence = AudioGenerator::silence(30);

    // 1. Trigger WakeWord
    let (_, trigger_actions) = service.process_audio_chunk(&speech, 30).unwrap();
    for action in &trigger_actions {
        if let FeedbackAction::PlayAudioChime(chime) = action {
            panic!(
                "AC-5 Invariant Violation: Chime '{}' emitted during WakeWord in SilentMeeting!",
                chime
            );
        }
    }

    // 2. Stream speech
    for _ in 0..60 {
        service.process_audio_chunk(&speech, 30).unwrap();
    }

    // 3. Complete via endpointing
    let mut completion_actions = Vec::new();
    for _ in 0..50 {
        let (maybe_note, actions) = service.process_audio_chunk(&silence, 30).unwrap();
        if maybe_note.is_some() {
            completion_actions = actions;
            break;
        }
    }

    for action in &completion_actions {
        if let FeedbackAction::PlayAudioChime(chime) = action {
            panic!("AC-5 Invariant Violation: Chime '{}' emitted on DirectiveComplete in SilentMeeting!", chime);
        }
    }

    // 4. Revoke directive
    let (_, revoke_actions) = service.revoke_latest_directive().unwrap();
    for action in &revoke_actions {
        if let FeedbackAction::PlayAudioChime(chime) = action {
            panic!("AC-5 Invariant Violation: Chime '{}' emitted on DirectiveRevoked in SilentMeeting!", chime);
        }
    }
}
