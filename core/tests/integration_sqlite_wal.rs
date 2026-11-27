mod support;

use rusqlite::Connection;
use std::sync::Arc;
use std::thread;
use tempfile::tempdir;
use void_notes_core::db::{initialize_schema, DirectiveNoteRepository};
use void_notes_core::models::DirectiveNote;

#[test]
fn test_integration_sqlite_wal_concurrent_readers_and_writers() {
    let temp = tempdir().expect("tempdir failed");
    let db_path = temp.path().join("wal_test.db");

    // Initialize primary connection with WAL mode
    {
        let conn = Connection::open(&db_path).unwrap();
        initialize_schema(&conn).unwrap();
    }

    let db_path = Arc::new(db_path);
    let mut handles = Vec::new();

    // Spawn 4 concurrent writer threads
    for t_idx in 0..4 {
        let path = Arc::clone(&db_path);
        let handle = thread::spawn(move || {
            let conn = Connection::open(&*path).unwrap();
            for i in 0..25 {
                let note = DirectiveNote::new(
                    format!("Note from thread {} iter {}", t_idx, i),
                    "raw transcription",
                    1000,
                );
                DirectiveNoteRepository::create(&conn, &note).unwrap();
            }
        });
        handles.push(handle);
    }

    // Spawn 2 concurrent reader threads
    for _ in 0..2 {
        let path = Arc::clone(&db_path);
        let handle = thread::spawn(move || {
            let conn = Connection::open(&*path).unwrap();
            for _ in 0..20 {
                let _ = DirectiveNoteRepository::list_active(&conn, 50).unwrap();
                thread::yield_now();
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().unwrap();
    }

    // Total written notes must be 4 threads * 25 = 100 notes with zero locks or corruption
    let conn = Connection::open(&*db_path).unwrap();
    let total_notes = DirectiveNoteRepository::list_active(&conn, 200).unwrap();
    assert_eq!(total_notes.len(), 100);
}
