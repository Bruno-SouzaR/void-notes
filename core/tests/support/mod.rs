#![allow(dead_code)]
use rusqlite::Connection;
use std::f32::consts::PI;
use std::path::PathBuf;
use tempfile::{tempdir, TempDir};
use void_notes_core::audio::SAMPLE_RATE;
use void_notes_core::db::initialize_schema;
use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::kws::WakeWordDetector;
use void_notes_core::stt::SpeechRecognizer;
use void_notes_core::VoidService;

/// Utility for generating synthetic acoustic test vectors.
pub struct AudioGenerator;

impl AudioGenerator {
    /// Generates pure digital silence (0.0).
    pub fn silence(duration_ms: u32) -> Vec<f32> {
        let sample_count = (duration_ms as f32 * (SAMPLE_RATE as f32 / 1000.0)) as usize;
        vec![0.0f32; sample_count]
    }

    /// Generates stationary ambient noise below the energy gate threshold.
    pub fn ambient_noise(duration_ms: u32, amplitude: f32) -> Vec<f32> {
        let sample_count = (duration_ms as f32 * (SAMPLE_RATE as f32 / 1000.0)) as usize;
        (0..sample_count)
            .map(|i| if i % 2 == 0 { amplitude } else { -amplitude })
            .collect()
    }

    /// Generates synthetic voice-like harmonic waveforms.
    pub fn speech_burst(duration_ms: u32, fundamental_hz: f32, amplitude: f32) -> Vec<f32> {
        let sample_count = (duration_ms as f32 * (SAMPLE_RATE as f32 / 1000.0)) as usize;
        let mut samples = Vec::with_capacity(sample_count);

        for i in 0..sample_count {
            let t = i as f32 / SAMPLE_RATE as f32;
            // Harmonic sum simulating human vowel acoustics (F0 + F1 + F2)
            let s1 = (2.0 * PI * fundamental_hz * t).sin();
            let s2 = 0.5 * (2.0 * PI * (fundamental_hz * 2.0) * t).sin();
            let s3 = 0.25 * (2.0 * PI * (fundamental_hz * 3.0) * t).sin();
            samples.push(amplitude * (s1 + s2 + s3));
        }

        samples
    }

    /// Generates high-frequency noise with maximum zero-crossing rate (for ZCR rejection tests).
    pub fn high_frequency_noise(duration_ms: u32, amplitude: f32) -> Vec<f32> {
        let sample_count = (duration_ms as f32 * (SAMPLE_RATE as f32 / 1000.0)) as usize;
        (0..sample_count)
            .map(|i| if i % 2 == 0 { amplitude } else { -amplitude })
            .collect()
    }
}

/// Helper harness creating isolated temporary test environments.
pub struct TestHarness;

impl TestHarness {
    /// Opens an in-memory SQLite connection with WAL schema pre-initialized.
    pub fn in_memory_connection() -> Connection {
        let conn = Connection::open_in_memory().expect("failed to open memory db");
        initialize_schema(&conn).expect("failed to initialize schema");
        conn
    }

    /// Creates an isolated VoidService with dedicated temporary directory and database file.
    pub fn create_service(
        kws: Box<dyn WakeWordDetector>,
        stt: Box<dyn SpeechRecognizer>,
        profile: FeedbackProfile,
    ) -> (VoidService, TempDir, PathBuf, PathBuf) {
        let temp = tempdir().expect("failed to create tempdir");
        let db_path = temp.path().join("test_void.db");
        let notes_dir = temp.path().join("notes");

        let conn = Connection::open(&db_path).expect("failed to open test db");
        let service = VoidService::from_connection(conn, &notes_dir, profile, kws, stt)
            .expect("failed to create service");

        (service, temp, db_path, notes_dir)
    }
}
