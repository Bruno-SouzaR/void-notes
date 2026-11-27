use crate::models::{DirectiveNote, SyncStatus};
use crate::{Result, VoidError};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Row};

pub struct DirectiveNoteRepository;

impl DirectiveNoteRepository {
    /// Inserts a new DirectiveNote into the database.
    pub fn create(conn: &Connection, note: &DirectiveNote) -> Result<()> {
        conn.execute(
            r#"
            INSERT INTO notes (
                id, content, raw_transcription, audio_duration_ms,
                created_at, updated_at, deleted_at, sync_status
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
            params![
                note.id,
                note.content,
                note.raw_transcription,
                note.audio_duration_ms,
                note.created_at.to_rfc3339(),
                note.updated_at.to_rfc3339(),
                note.deleted_at.map(|d| d.to_rfc3339()),
                note.sync_status.as_str(),
            ],
        )?;
        Ok(())
    }

    /// Retrieves an active or deleted note by ID.
    pub fn get_by_id(conn: &Connection, id: &str) -> Result<Option<DirectiveNote>> {
        let mut stmt = conn.prepare(
            r#"
            SELECT id, content, raw_transcription, audio_duration_ms,
                   created_at, updated_at, deleted_at, sync_status
            FROM notes
            WHERE id = ?1
            "#,
        )?;

        let mut rows = stmt.query(params![id])?;
        if let Some(row) = rows.next()? {
            Ok(Some(Self::map_row(row)?))
        } else {
            Ok(None)
        }
    }

    /// Lists active (non-deleted) notes ordered by created_at descending.
    pub fn list_active(conn: &Connection, limit: usize) -> Result<Vec<DirectiveNote>> {
        let mut stmt = conn.prepare(
            r#"
            SELECT id, content, raw_transcription, audio_duration_ms,
                   created_at, updated_at, deleted_at, sync_status
            FROM notes
            WHERE deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?1
            "#,
        )?;

        let note_iter = stmt.query_map(params![limit as i64], Self::map_row)?;
        let mut notes = Vec::new();
        for note in note_iter {
            notes.push(note?);
        }
        Ok(notes)
    }

    /// Lists active notes for a given UTC date prefix (e.g., "2026-10-30").
    pub fn list_by_date(conn: &Connection, date_prefix: &str) -> Result<Vec<DirectiveNote>> {
        let pattern = format!("{}%", date_prefix);
        let mut stmt = conn.prepare(
            r#"
            SELECT id, content, raw_transcription, audio_duration_ms,
                   created_at, updated_at, deleted_at, sync_status
            FROM notes
            WHERE deleted_at IS NULL AND created_at LIKE ?1
            ORDER BY created_at ASC
            "#,
        )?;

        let note_iter = stmt.query_map(params![pattern], Self::map_row)?;
        let mut notes = Vec::new();
        for note in note_iter {
            notes.push(note?);
        }
        Ok(notes)
    }

    /// Retrieves the most recently created active note (for the UndoWindow).
    pub fn get_latest_active(conn: &Connection) -> Result<Option<DirectiveNote>> {
        let mut stmt = conn.prepare(
            r#"
            SELECT id, content, raw_transcription, audio_duration_ms,
                   created_at, updated_at, deleted_at, sync_status
            FROM notes
            WHERE deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT 1
            "#,
        )?;

        let mut rows = stmt.query([])?;
        if let Some(row) = rows.next()? {
            Ok(Some(Self::map_row(row)?))
        } else {
            Ok(None)
        }
    }

    /// Soft-deletes a note by setting its deleted_at timestamp.
    pub fn soft_delete(conn: &Connection, id: &str) -> Result<bool> {
        let now = Utc::now().to_rfc3339();
        let rows_affected = conn.execute(
            r#"
            UPDATE notes
            SET deleted_at = ?1, updated_at = ?1, sync_status = 'pending'
            WHERE id = ?2 AND deleted_at IS NULL
            "#,
            params![now, id],
        )?;
        Ok(rows_affected > 0)
    }

    /// Maps a SQLite row to a DirectiveNote domain struct.
    fn map_row(row: &Row) -> rusqlite::Result<DirectiveNote> {
        let id: String = row.get(0)?;
        let content: String = row.get(1)?;
        let raw_transcription: String = row.get(2)?;
        let audio_duration_ms: u32 = row.get(3)?;
        let created_at_str: String = row.get(4)?;
        let updated_at_str: String = row.get(5)?;
        let deleted_at_str: Option<String> = row.get(6)?;
        let sync_status_str: String = row.get(7)?;

        let created_at = DateTime::parse_from_rfc3339(&created_at_str)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|e| {
                rusqlite::Error::FromSqlConversionFailure(
                    4,
                    rusqlite::types::Type::Text,
                    Box::new(e),
                )
            })?;

        let updated_at = DateTime::parse_from_rfc3339(&updated_at_str)
            .map(|dt| dt.with_timezone(&Utc))
            .map_err(|e| {
                rusqlite::Error::FromSqlConversionFailure(
                    5,
                    rusqlite::types::Type::Text,
                    Box::new(e),
                )
            })?;

        let deleted_at = match &deleted_at_str {
            Some(s) => Some(
                DateTime::parse_from_rfc3339(s)
                    .map(|dt| dt.with_timezone(&Utc))
                    .map_err(|e| {
                        rusqlite::Error::FromSqlConversionFailure(
                            6,
                            rusqlite::types::Type::Text,
                            Box::new(e),
                        )
                    })?,
            ),
            None => None,
        };

        let sync_status = SyncStatus::try_from(sync_status_str.as_str()).map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(
                7,
                rusqlite::types::Type::Text,
                Box::new(VoidError::Domain(e)),
            )
        })?;

        Ok(DirectiveNote {
            id,
            content,
            raw_transcription,
            audio_duration_ms,
            created_at,
            updated_at,
            deleted_at,
            sync_status,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::schema::initialize_schema;

    #[test]
    fn test_note_lifecycle_crud() {
        let conn = Connection::open_in_memory().expect("failed to open memory db");
        initialize_schema(&conn).expect("failed to init schema");

        let note = DirectiveNote::new(
            "Lembrar de comprar pão",
            "void lembrar de comprar pao",
            3200,
        );
        let note_id = note.id.clone();

        // 1. Create
        DirectiveNoteRepository::create(&conn, &note).expect("create failed");

        // 2. Read by ID
        let fetched = DirectiveNoteRepository::get_by_id(&conn, &note_id)
            .expect("fetch failed")
            .expect("note not found");
        assert_eq!(fetched.content, "Lembrar de comprar pão");
        assert_eq!(fetched.audio_duration_ms, 3200);
        assert!(!fetched.is_deleted());

        // 3. List active
        let active = DirectiveNoteRepository::list_active(&conn, 10).expect("list failed");
        assert_eq!(active.len(), 1);
        assert_eq!(active[0].id, note_id);

        // 4. Latest active (UndoWindow check)
        let latest = DirectiveNoteRepository::get_latest_active(&conn)
            .expect("get latest failed")
            .expect("latest note missing");
        assert_eq!(latest.id, note_id);

        // 5. Soft Delete
        let deleted = DirectiveNoteRepository::soft_delete(&conn, &note_id).expect("delete failed");
        assert!(deleted);

        // 6. Verify deleted note is hidden from list_active
        let active_after_delete =
            DirectiveNoteRepository::list_active(&conn, 10).expect("list failed");
        assert_eq!(active_after_delete.len(), 0);

        // 7. Verify note still exists with deleted_at populated
        let fetched_after_delete = DirectiveNoteRepository::get_by_id(&conn, &note_id)
            .expect("fetch failed")
            .expect("note should still exist");
        assert!(fetched_after_delete.is_deleted());
    }
}
