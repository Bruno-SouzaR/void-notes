mod support;

use support::{AudioGenerator, TestHarness};
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;

/// Regression Test: Adaptive Hesitation on short thoughts.
///
/// Proves that when user speaks briefly (< 2.0s) and pauses for 1.8s (exceeding standard
/// 1.5s silence limit, but below 2.2s adaptive threshold), the recording is NOT truncated.
#[test]
fn test_regression_adaptive_hesitation_preserves_paused_speech() {
    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response("void lembrar... comprar pao");

    let (service, _temp, _db_path, _notes_dir) = TestHarness::create_service(
        Box::new(mock_kws),
        Box::new(mock_stt),
        FeedbackProfile::Normal,
    );

    let speech = AudioGenerator::speech_burst(30, 180.0, 0.25);
    let silence = AudioGenerator::silence(30);

    // 1. Trigger WakeWord
    service.process_audio_chunk(&speech, 30).unwrap();

    // 2. User speaks briefly: 600ms (20 frames)
    for _ in 0..20 {
        service.process_audio_chunk(&speech, 30).unwrap();
    }

    // 3. User pauses to think for 1.8 seconds (60 frames of 30ms)
    // Standard limit is 1500ms, but adaptive hesitation extends to 2200ms
    for _ in 0..60 {
        let (maybe_note, _) = service.process_audio_chunk(&silence, 30).unwrap();
        assert!(
            maybe_note.is_none(),
            "Regression Violation: Session prematurely cut during legitimate 1.8s pause!"
        );
    }

    // 4. User resumes speaking for 1.2s (40 frames)
    for _ in 0..40 {
        service.process_audio_chunk(&speech, 30).unwrap();
    }

    // 5. Final definitive silence (exceeding adaptive hesitation 2200ms: 75 frames * 30ms = 2250ms)
    let mut completed_note = None;
    for _ in 0..75 {
        let (maybe_note, _) = service.process_audio_chunk(&silence, 30).unwrap();
        if maybe_note.is_some() {
            completed_note = maybe_note;
            break;
        }
    }

    assert!(
        completed_note.is_some(),
        "Expected note to complete successfully after resumption!"
    );
}
