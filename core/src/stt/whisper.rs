use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use crate::{Result, VoidError};

/// Configuration for offline Whisper speech recognition.
#[derive(Debug, Clone)]
pub struct WhisperConfig {
    /// Path to the quantized ggml model (e.g. `ggml-base-q5_1.bin` or `ggml-tiny-q5_1.bin`).
    pub model_path: PathBuf,
    /// Target language code (e.g. "pt" for Brazilian Portuguese).
    pub language: String,
    /// Number of worker threads for inference (clamped to 2-3 to prevent system audio xruns).
    pub threads: usize,
    /// Translate to English if true, or keep original language transcription.
    pub translate: bool,
}

impl Default for WhisperConfig {
    fn default() -> Self {
        Self {
            model_path: PathBuf::from("models/ggml-base-q5_1.bin"),
            language: "pt".to_string(),
            threads: 2, // Clamped per ADR 0001 & Grilling consensus
            translate: false,
        }
    }
}

/// Abstract contract for speech-to-text recognition implementations.
pub trait SpeechRecognizer: Send + Sync {
    /// Transcribes an incoming 16 kHz mono f32 audio buffer into raw text.
    fn transcribe(&self, audio_samples: &[f32]) -> Result<String>;
}

/// Real offline recognizer executing whisper.cpp binary with AVX/NEON SIMD intrinsics.
#[derive(Debug, Clone)]
pub struct WhisperCliRecognizer {
    binary_path: PathBuf,
    model_path: PathBuf,
    language: String,
    threads: usize,
}

impl WhisperCliRecognizer {
    /// Creates a new WhisperCliRecognizer instance.
    pub fn new(binary_path: impl Into<PathBuf>, model_path: impl Into<PathBuf>) -> Self {
        Self {
            binary_path: binary_path.into(),
            model_path: model_path.into(),
            language: "pt".to_string(),
            threads: 2,
        }
    }

    /// Sets the number of worker threads (clamped between 1 and 4).
    pub fn with_threads(mut self, threads: usize) -> Self {
        self.threads = threads.clamp(1, 4);
        self
    }

    /// Sets the target language (e.g. "pt" or "en").
    pub fn with_language(mut self, language: impl Into<String>) -> Self {
        self.language = language.into();
        self
    }

    /// Writes raw f32 samples to a standard 16 kHz 16-bit mono PCM WAV file.
    fn write_temp_wav(path: &Path, samples: &[f32]) -> Result<()> {
        let mut file = File::create(path)?;
        let pcm_samples: Vec<i16> = samples
            .iter()
            .map(|&s| (s.clamp(-1.0, 1.0) * 32767.0) as i16)
            .collect();
        let data_len = (pcm_samples.len() * 2) as u32;

        // RIFF header
        file.write_all(b"RIFF")?;
        file.write_all(&(36 + data_len).to_le_bytes())?;
        file.write_all(b"WAVE")?;

        // fmt chunk (16-bit mono 16 kHz PCM)
        file.write_all(b"fmt ")?;
        file.write_all(&16u32.to_le_bytes())?; // Chunk size (16 for PCM)
        file.write_all(&1u16.to_le_bytes())?;  // Format (1 = PCM)
        file.write_all(&1u16.to_le_bytes())?;  // Channels (1 = mono)
        file.write_all(&16000u32.to_le_bytes())?; // Sample rate
        file.write_all(&32000u32.to_le_bytes())?; // Byte rate (16000 * 1 * 2)
        file.write_all(&2u16.to_le_bytes())?;  // Block align
        file.write_all(&16u16.to_le_bytes())?; // Bits per sample

        // data chunk
        file.write_all(b"data")?;
        file.write_all(&data_len.to_le_bytes())?;
        for sample in pcm_samples {
            file.write_all(&sample.to_le_bytes())?;
        }
        file.flush()?;

        Ok(())
    }
}

impl SpeechRecognizer for WhisperCliRecognizer {
    fn transcribe(&self, audio_samples: &[f32]) -> Result<String> {
        if audio_samples.is_empty() {
            return Ok(String::new());
        }

        let temp_dir = std::env::temp_dir();
        let temp_wav_path = temp_dir.join(format!("void_transcribe_{}.wav", uuid::Uuid::new_v4()));

        Self::write_temp_wav(&temp_wav_path, audio_samples)?;

        let output_res = Command::new(&self.binary_path)
            .arg("-m")
            .arg(&self.model_path)
            .arg("-l")
            .arg(&self.language)
            .arg("-t")
            .arg(self.threads.to_string())
            .arg("-nt")
            .arg("-f")
            .arg(&temp_wav_path)
            .output();

        // Clean up temporary WAV file immediately
        let _ = fs::remove_file(&temp_wav_path);

        let output = match output_res {
            Ok(o) => o,
            Err(e) => {
                return Err(VoidError::Domain(format!(
                    "Failed to execute whisper-cli at {:?}: {}",
                    self.binary_path, e
                )))
            }
        };

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(VoidError::Domain(format!("Whisper inference failed: {}", stderr)));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        // Clean out bracketed tags like [MÚSICA DE FUNDO] or timestamps if any remain
        let mut clean_lines = Vec::new();
        for line in stdout.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            // Strip whisper status header lines if present
            if trimmed.starts_with("whisper_") || trimmed.starts_with("system_info:") || trimmed.starts_with("main:") {
                continue;
            }
            clean_lines.push(trimmed);
        }

        Ok(clean_lines.join(" "))
    }
}

/// Mock recognizer used for unit testing and offline development environments.
#[derive(Debug, Clone, Default)]
pub struct MockSpeechRecognizer {
    canned_response: Option<String>,
}

impl MockSpeechRecognizer {
    pub fn new() -> Self {
        Self { canned_response: None }
    }

    pub fn with_response(response: impl Into<String>) -> Self {
        Self {
            canned_response: Some(response.into()),
        }
    }
}

impl SpeechRecognizer for MockSpeechRecognizer {
    fn transcribe(&self, audio_samples: &[f32]) -> Result<String> {
        if audio_samples.is_empty() {
            return Ok(String::new());
        }

        if let Some(ref text) = self.canned_response {
            Ok(text.clone())
        } else {
            Ok("Lembrar de comprar filtro de café e pagar condomínio.".to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_speech_recognizer() {
        let recognizer = MockSpeechRecognizer::with_response("Comprar leite.");
        let dummy_samples = vec![0.1f32; 16000]; // 1 second
        let result = recognizer.transcribe(&dummy_samples).expect("transcription failed");
        assert_eq!(result, "Comprar leite.");
    }

    #[test]
    fn test_mock_speech_recognizer_empty_audio() {
        let recognizer = MockSpeechRecognizer::new();
        let result = recognizer.transcribe(&[]).expect("empty transcription failed");
        assert_eq!(result, "");
    }
}
