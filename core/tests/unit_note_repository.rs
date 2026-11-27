mod support;

use support::TestHarness;
use uuid::Uuid;
use void_notes_core::db::DirectiveNoteRepository;
use void_notes_core::models::DirectiveNote;

#[test]
fn test_repository_uuid_validation_and_uniqueness() {
    let conn = TestHarness::in_memory_connection();

    let note1 = DirectiveNote::new("Nota 1", "raw 1", 1000);
    let note2 = DirectiveNote::new("Nota 2", "raw 2", 1500);

    assert_ne!(note1.id, note2.id);
    assert!(Uuid::parse_str(&note1.id).is_ok());
    assert!(Uuid::parse_str(&note2.id).is_ok());

    DirectiveNoteRepository::create(&conn, &note1).expect("create note1 failed");
    DirectiveNoteRepository::create(&conn, &note2).expect("create note2 failed");

    let fetched1 = DirectiveNoteRepository::get_by_id(&conn, &note1.id)
        .expect("get note1 failed")
        .expect("note1 not found");
    assert_eq!(fetched1.content, "Nota 1");
    assert_eq!(fetched1.audio_duration_ms, 1000);
}

#[test]
fn test_repository_soft_delete_preserves_audit_trail() {
    let conn = TestHarness::in_memory_connection();

    let note = DirectiveNote::new("Nota para arquivar", "raw", 2000);
    DirectiveNoteRepository::create(&conn, &note).expect("create failed");

    // Initially active
    assert_eq!(
        DirectiveNoteRepository::list_active(&conn, 10)
            .unwrap()
            .len(),
        1
    );

    // Soft delete
    let deleted = DirectiveNoteRepository::soft_delete(&conn, &note.id).expect("delete failed");
    assert!(deleted);

    // Must be hidden from active list
    assert_eq!(
        DirectiveNoteRepository::list_active(&conn, 10)
            .unwrap()
            .len(),
        0
    );

    // Must still exist in database with deleted_at timestamp
    let raw_record = DirectiveNoteRepository::get_by_id(&conn, &note.id)
        .expect("get failed")
        .expect("record missing");
    assert!(raw_record.is_deleted());
    assert!(raw_record.deleted_at.is_some());
}

#[test]
fn test_repository_date_filtering() {
    let conn = TestHarness::in_memory_connection();

    let note = DirectiveNote::new("Nota de hoje", "raw", 2500);
    DirectiveNoteRepository::create(&conn, &note).expect("create failed");

    let today_prefix = note.created_at.format("%Y-%m-%d").to_string();
    let today_notes =
        DirectiveNoteRepository::list_by_date(&conn, &today_prefix).expect("query failed");
    assert_eq!(today_notes.len(), 1);

    // Unrelated date returns empty
    let past_notes =
        DirectiveNoteRepository::list_by_date(&conn, "1999-01-01").expect("query failed");
    assert_eq!(past_notes.len(), 0);
}
