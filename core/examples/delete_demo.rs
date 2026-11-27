//! Demonstrates the delete path end to end: a note disappears from SQLite and from its daily
//! Markdown file through the same `VoidService::delete_note` the desktop app calls.
//!
//! ```bash
//! cargo run --example delete_demo
//! ```
use std::fs;
use void_notes_core::db::DirectiveNoteRepository;
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::models::DirectiveNote;
use void_notes_core::storage::MarkdownMirror;
use void_notes_core::{Result, VoidService};

fn main() -> Result<()> {
    let root = std::env::temp_dir().join("void-delete-demo");
    let _ = fs::remove_dir_all(&root);
    let notes_dir = root.join("notes");
    fs::create_dir_all(&notes_dir).expect("notes dir");
    let db_path = root.join("notes.db");

    let service = VoidService::new(&db_path, &notes_dir, FeedbackProfile::Normal)?;
    let conn = rusqlite::Connection::open(&db_path).expect("second connection");

    let notes = [
        DirectiveNote::new("Revisar o PR do ingest.", "raw", 900),
        DirectiveNote::new("Escrever o teste do endpointing.", "raw", 800),
        DirectiveNote::new("Atualizar o README.", "raw", 700),
    ];
    for note in &notes {
        DirectiveNoteRepository::create(&conn, note)?;
        MarkdownMirror::new(&notes_dir).append_note(note)?;
    }

    let date = notes[0].created_at.format("%Y-%m-%d").to_string();
    let path = notes_dir.join(format!("{date}.md"));

    println!("3 notas criadas\n");
    println!("{}", fs::read_to_string(&path).unwrap_or_default());

    let target = &notes[1];
    println!(">>> delete_note({})", &target.id[..8]);
    let removed = service.delete_note(&target.id)?;
    println!("    retorno: {removed}");
    println!("    notas ativas: {}\n", service.list_today_notes()?.len());

    println!("{}", fs::read_to_string(&path).unwrap_or_default());

    println!(">>> delete_note no mesmo id outra vez");
    println!("    retorno: {}", service.delete_note(&target.id)?);

    Ok(())
}
