use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};
use tempfile::tempdir;
use void_notes_core::db::DirectiveNoteRepository;
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::models::DirectiveNote;
use void_notes_core::storage::MarkdownMirror;
use void_notes_core::VoidService;

/// Builds a service over a temp database with one mirrored note already captured.
fn service_with_note() -> (tempfile::TempDir, VoidService, DirectiveNote, PathBuf) {
    let temp = tempdir().expect("tempdir failed");
    let db_path = temp.path().join("notes.db");
    let notes_dir = temp.path().join("notes");
    fs::create_dir_all(&notes_dir).expect("notes dir");

    let service = VoidService::new(&db_path, &notes_dir, FeedbackProfile::Normal).expect("service");

    let note = DirectiveNote::new("Comprar café.", "raw", 900);
    let conn = Connection::open(&db_path).expect("second connection");
    DirectiveNoteRepository::create(&conn, &note).expect("insert note");
    MarkdownMirror::new(&notes_dir)
        .append_note(&note)
        .expect("append to mirror");

    (temp, service, note, notes_dir)
}

fn daily_file(notes_dir: &Path, note: &DirectiveNote) -> String {
    let date_str = note.created_at.format("%Y-%m-%d").to_string();
    fs::read_to_string(notes_dir.join(format!("{date_str}.md"))).expect("daily file")
}

#[test]
fn deleting_a_note_hides_it_and_rewrites_the_daily_file() {
    let (_temp, service, note, notes_dir) = service_with_note();
    assert_eq!(service.list_today_notes().unwrap().len(), 1);
    assert!(daily_file(&notes_dir, &note).contains("Comprar café."));

    assert!(
        service.delete_note(&note.id).unwrap(),
        "delete should succeed"
    );

    assert!(
        service.list_today_notes().unwrap().is_empty(),
        "a deleted note must not be listed"
    );
    assert!(
        !daily_file(&notes_dir, &note).contains("Comprar café."),
        "the mirror must drop the deleted note"
    );
}

#[test]
fn deleting_twice_is_a_no_op() {
    let (_temp, service, note, _notes_dir) = service_with_note();
    assert!(service.delete_note(&note.id).unwrap());
    assert!(
        !service.delete_note(&note.id).unwrap(),
        "a second delete must report false instead of failing"
    );
}

#[test]
fn deleting_an_unknown_id_reports_false() {
    let (_temp, service, _note, _notes_dir) = service_with_note();
    assert!(!service.delete_note("does-not-exist").unwrap());
}
