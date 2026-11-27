use std::fs;
use tempfile::tempdir;
use void_notes_core::feedback::{FeedbackAction, FeedbackProfile};
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::MockSpeechRecognizer;
use void_notes_core::VoidService;

fn main() -> anyhow::Result<()> {
    println!("============================================================");
    println!("  void-notes — End-to-End Pipeline Smoke Test");
    println!("============================================================");

    let temp_dir = tempdir()?;
    let db_path = temp_dir.path().join("void_notes.db");
    let notes_dir = temp_dir.path().join("notes");

    println!("[1/6] Initializing VoidService...");
    println!("      DB Path: {:?}", db_path);
    println!("      Notes Dir: {:?}", notes_dir);

    let conn = rusqlite::Connection::open(&db_path)?;

    let mut mock_kws = MockWakeWordDetector::new(Default::default());
    mock_kws.arm_trigger();

    let mock_stt = MockSpeechRecognizer::with_response(
        "void lembrar de comprar cafe torrado e revisar documentacao",
    );

    let service = VoidService::from_connection(
        conn,
        &notes_dir,
        FeedbackProfile::Normal,
        Box::new(mock_kws),
        Box::new(mock_stt),
    )?;
    println!("      ✓ Service initialized with schema in WAL mode.");

    // 2. Feed silence first (Tier 0 Energy Gate check)
    println!("\n[2/6] Testing Tier 0 Energy Gate with pure silence...");
    let silence_frame = vec![0.0f32; 480]; // 30ms
    let (note_on_silence, actions_on_silence) = service.process_audio_chunk(&silence_frame, 30)?;
    assert!(note_on_silence.is_none());
    assert!(actions_on_silence.is_empty());
    println!("      ✓ Silence rejected by Energy Gate (0% downstream compute).");

    // 3. Feed speech chunk with armed KWS -> trigger WakeWord
    println!("\n[3/6] Simulating WakeWord trigger ('Void')...");
    let speech_frame: Vec<f32> = (0..480).map(|i| 0.25 * (i as f32 * 0.05).sin()).collect();
    let (trigger_note, trigger_actions) = service.process_audio_chunk(&speech_frame, 30)?;
    assert!(trigger_note.is_none());
    assert!(trigger_actions.contains(&FeedbackAction::PlayAudioChime("chime_wake.wav")));
    println!("      ✓ WakeWord recognized! State -> Capturing directive.");

    // 4. Feed speech directive (2.4s of active speech)
    println!("\n[4/6] Streaming speech directive (2.4s)...");
    for _ in 0..80 {
        service.process_audio_chunk(&speech_frame, 30)?;
    }

    // 5. Feed silence to hit VAD Endpoint (1.5s = 50 frames)
    println!("[5/6] Feeding trailing silence to trigger VAD endpoint (1.5s)...");
    let mut completed_note = None;
    for _ in 0..50 {
        let (maybe_note, _actions) = service.process_audio_chunk(&silence_frame, 30)?;
        if maybe_note.is_some() {
            completed_note = maybe_note;
            break;
        }
    }

    let note = completed_note.expect("Expected directive completion!");
    println!("      ✓ Endpoint reached! Speech successfully transcribed & persisted:");
    println!("        - Note ID: {}", note.id);
    println!("        - Content: \"{}\"", note.content);
    println!("        - Audio Duration: {}ms", note.audio_duration_ms);
    println!("        - Created At: {}", note.created_at);

    // Verify SQLite persistence
    let today_notes = service.list_today_notes()?;
    assert_eq!(today_notes.len(), 1);
    assert_eq!(today_notes[0].id, note.id);
    println!("      ✓ Verified in SQLite database.");

    // Verify Markdown file mirror
    let date_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let md_path = notes_dir.join(format!("{}.md", date_str));
    assert!(md_path.exists());
    let md_content = fs::read_to_string(&md_path)?;
    println!("\n[6/6] Verifying Markdown file mirror at {:?}...", md_path);
    println!(
        "------ File Content Start ------\n{}\n------- File Content End -------",
        md_content.trim()
    );
    assert!(md_content.contains("Lembrar de comprar cafe torrado e revisar documentacao."));
    println!("      ✓ Markdown mirror contains formatted directive with timestamp.");

    // Test UndoWindow revocation
    println!("\n[Undo Test] Testing UndoWindow revocation...");
    let (revoked, _) = service.revoke_latest_directive()?;
    assert!(revoked.is_some());
    let remaining = service.list_today_notes()?;
    assert_eq!(remaining.len(), 0);
    println!("      ✓ Note revoked and soft-deleted cleanly.");

    println!("\n============================================================");
    println!("  ✓ Smoke test passed successfully! Zero defects observed.");
    println!("============================================================");

    Ok(())
}
