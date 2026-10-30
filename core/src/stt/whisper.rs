use std::path::{Path, PathBuf};
use crate::Result;

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
