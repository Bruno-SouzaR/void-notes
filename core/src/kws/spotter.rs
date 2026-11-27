/// Represents a confirmed WakeWord detection event.
#[derive(Debug, Clone, PartialEq)]
pub struct WakeWordDetection {
    pub name: String,
    pub confidence: f32,
    pub timestamp_ms: u64,
}

/// Configuration for the Keyword Spotting (KWS) detector.
#[derive(Debug, Clone)]
pub struct KwsConfig {
    /// Target wake word to detect (e.g. "Void" or "Hey Void").
    pub wake_word: String,
    /// Minimum confidence threshold (0.0 to 1.0). Default: 0.55.
    pub threshold: f32,
    /// Refractory cooldown period in milliseconds to suppress rapid re-triggers. Default: 1500ms.
    pub refractory_window_ms: u64,
}

impl Default for KwsConfig {
    fn default() -> Self {
        Self {
            wake_word: "Void".to_string(),
            threshold: 0.55,
            refractory_window_ms: 1500,
        }
    }
}

/// Trait defining the contract for wake word spotters.
pub trait WakeWordDetector: Send + Sync {
    /// Feeds incoming 16 kHz f32 samples and checks for wake word activation.
    fn process_samples(&mut self, samples: &[f32]) -> Option<WakeWordDetection>;
    /// Resets internal acoustic state.
    fn reset(&mut self);
}

/// Mock wake word detector for offline unit tests and continuous integration.
#[derive(Debug, Clone)]
pub struct MockWakeWordDetector {
    config: KwsConfig,
    should_trigger: bool,
    last_trigger_time_ms: Option<u64>,
    current_time_ms: u64,
}

impl MockWakeWordDetector {
    pub fn new(config: KwsConfig) -> Self {
        Self {
            config,
            should_trigger: false,
            last_trigger_time_ms: None,
            current_time_ms: 0,
        }
    }

    /// Arms the mock detector to fire on the next sample chunk.
    pub fn arm_trigger(&mut self) {
        self.should_trigger = true;
    }

    /// Advances simulated clock time.
    pub fn advance_time(&mut self, delta_ms: u64) {
        self.current_time_ms += delta_ms;
    }
}

impl WakeWordDetector for MockWakeWordDetector {
    fn process_samples(&mut self, samples: &[f32]) -> Option<WakeWordDetection> {
        // Calculate duration of the incoming chunk in ms
        let duration_ms = (samples.len() as f64 / 16.0) as u64;
        self.current_time_ms += duration_ms;

        if !self.should_trigger {
            return None;
        }

        // Check refractory window
        if let Some(last) = self.last_trigger_time_ms {
            if self.current_time_ms - last < self.config.refractory_window_ms {
                return None;
            }
        }

        self.should_trigger = false;
        self.last_trigger_time_ms = Some(self.current_time_ms);

        Some(WakeWordDetection {
            name: self.config.wake_word.clone(),
            confidence: 0.92,
            timestamp_ms: self.current_time_ms,
        })
    }

    fn reset(&mut self) {
        self.should_trigger = false;
        self.last_trigger_time_ms = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mock_wake_word_trigger_and_refractory_cooldown() {
        let mut detector = MockWakeWordDetector::new(KwsConfig::default());
        let dummy_chunk = vec![0.1f32; 1280]; // 80ms at 16kHz

        // Not armed -> returns None
        assert_eq!(detector.process_samples(&dummy_chunk), None);

        // Arm trigger -> returns WakeWordDetection
        detector.arm_trigger();
        let detection = detector
            .process_samples(&dummy_chunk)
            .expect("expected detection");
        assert_eq!(detection.name, "Void");
        assert!(detection.confidence >= 0.55);

        // Immediately arming again without advancing time -> suppressed by refractory window
        detector.arm_trigger();
        assert_eq!(detector.process_samples(&dummy_chunk), None);

        // Advance simulated time past refractory window (1500ms)
        detector.advance_time(1600);
        detector.arm_trigger();
        let second_detection = detector
            .process_samples(&dummy_chunk)
            .expect("expected second detection");
        assert_eq!(second_detection.name, "Void");
    }
}
