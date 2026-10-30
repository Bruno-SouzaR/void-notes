use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use crate::models::DirectiveNote;
use crate::Result;

/// Asynchronous, fault-tolerant reconciler for mirroring SQLite DirectiveNotes into daily Markdown files.
#[derive(Debug, Clone)]
pub struct MarkdownMirror {
    base_dir: PathBuf,
}

impl MarkdownMirror {
    /// Creates a mirror pointing to the specified directory (e.g. `notes/`).
    pub fn new(base_dir: impl Into<PathBuf>) -> Self {
        Self {
            base_dir: base_dir.into(),
        }
    }

    /// Returns the base directory for notes.
    pub fn base_dir(&self) -> &Path {
        &self.base_dir
    }

    /// Appends a new DirectiveNote to its corresponding daily file (`YYYY-MM-DD.md`).
    pub fn append_note(&self, note: &DirectiveNote) -> Result<PathBuf> {
        fs::create_dir_all(&self.base_dir)?;

        let date_str = note.created_at.format("%Y-%m-%d").to_string();
        let file_path = self.base_dir.join(format!("{}.md", date_str));

        let file_exists = file_path.exists();
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&file_path)?;

        // If newly created, initialize with daily header
        if !file_exists {
            writeln!(file, "# {}\n", date_str)?;
        }

        let time_str = note.created_at.format("%H:%M:%S").to_string();
        writeln!(file, "- **[{}]** {}", time_str, note.content)?;

        Ok(file_path)
    }

    /// Reconciles an entire day's active notes from SQLite into the daily file.
    ///
    /// Rewrites the file cleanly to reflect soft-deletions (e.g. after UndoWindow revocation).
    pub fn reconcile_day(&self, date_str: &str, active_notes: &[DirectiveNote]) -> Result<PathBuf> {
        fs::create_dir_all(&self.base_dir)?;
        let file_path = self.base_dir.join(format!("{}.md", date_str));

        let mut content = format!("# {}\n\n", date_str);
        for note in active_notes {
            if !note.is_deleted() {
                let time_str = note.created_at.format("%H:%M:%S").to_string();
                content.push_str(&format!("- **[{}]** {}\n", time_str, note.content));
            }
        }

        // Write atomically via temporary file rename to prevent editor conflicts
        let temp_path = self.base_dir.join(format!(".{}.tmp", date_str));
        fs::write(&temp_path, content)?;
        fs::rename(&temp_path, &file_path)?;

        Ok(file_path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_append_note_creates_and_formats_markdown() {
        let temp = tempdir().expect("tempdir failed");
        let mirror = MarkdownMirror::new(temp.path());

        let note = DirectiveNote::new("Comprar café torrado.", "void comprar cafe torrado", 2400);
        let path = mirror.append_note(&note).expect("append failed");

        assert!(path.exists());
        let content = fs::read_to_string(&path).expect("read failed");
        assert!(content.contains(&note.created_at.format("%Y-%m-%d").to_string()));
        assert!(content.contains("Comprar café torrado."));
        assert!(content.contains(&note.created_at.format("%H:%M:%S").to_string()));
    }

    #[test]
    fn test_reconcile_day_excludes_soft_deleted_notes() {
        let temp = tempdir().expect("tempdir failed");
        let mirror = MarkdownMirror::new(temp.path());

        let note1 = DirectiveNote::new("Nota 1 ativa", "nota 1", 1000);
        let mut note2 = DirectiveNote::new("Nota 2 cancelada", "nota 2", 1200);
        note2.deleted_at = Some(chrono::Utc::now());

        let date_str = note1.created_at.format("%Y-%m-%d").to_string();
        let path = mirror.reconcile_day(&date_str, &[note1, note2]).expect("reconcile failed");

        let content = fs::read_to_string(&path).expect("read failed");
        assert!(content.contains("Nota 1 ativa"));
        assert!(!content.contains("Nota 2 cancelada"));
    }
}
