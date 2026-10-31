use std::fs;
use tempfile::tempdir;
use void_notes_core::models::DirectiveNote;
use void_notes_core::storage::MarkdownMirror;

#[test]
fn test_integration_markdown_atomic_mirror_and_reconciliation() {
    let temp = tempdir().expect("tempdir failed");
    let mirror = MarkdownMirror::new(temp.path());

    let note1 = DirectiveNote::new("Comprar café.", "raw 1", 1000);
    let note2 = DirectiveNote::new("Pagar boleto.", "raw 2", 1500);
    let note3 = DirectiveNote::new("Revisar PR.", "raw 3", 2000);

    mirror.append_note(&note1).unwrap();
    mirror.append_note(&note2).unwrap();
    let md_path = mirror.append_note(&note3).unwrap();

    let content_initial = fs::read_to_string(&md_path).unwrap();
    assert!(content_initial.contains("Comprar café."));
    assert!(content_initial.contains("Pagar boleto."));
    assert!(content_initial.contains("Revisar PR."));

    // Simulate soft-deletion of note2
    let mut soft_deleted_note2 = note2.clone();
    soft_deleted_note2.deleted_at = Some(chrono::Utc::now());

    let active_list = vec![note1, soft_deleted_note2, note3];
    let date_str = chrono::Utc::now().format("%Y-%m-%d").to_string();

    mirror.reconcile_day(&date_str, &active_list).unwrap();

    let content_after = fs::read_to_string(&md_path).unwrap();
    assert!(content_after.contains("Comprar café."));
    assert!(!content_after.contains("Pagar boleto.")); // Successfully pruned
    assert!(content_after.contains("Revisar PR."));
}
