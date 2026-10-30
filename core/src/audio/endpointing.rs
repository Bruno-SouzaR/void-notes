/// Current state of the speech endpointing detector.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointState {
    /// Idle, awaiting WakeWord or manual shortcut activation.
    Idle,
    /// Actively capturing user speech following an activation.
    Capturing,
    /// Speech has paused, counting silence cooldown duration.
    SilenceCooldown,
    /// Definitive speech cessation reached (ready for Whisper transcription).
    Completed,
    /// Session cancelled (timeout with no speech or explicit cancellation).
    Cancelled,
}

/// Output event returned after processing each audio frame.
#[derive(Debug, Clone, PartialEq)]
pub enum EndpointResult {
    /// Still recording, more audio needed.
    Continuing,
    /// Directive speech concluded; returns the complete audio vector in 16 kHz f32.
    DirectiveComplete(Vec<f32>),
    /// Session discarded (e.g. initial silence timeout or voice cancel).
    SessionCancelled,
}

/// Tuning parameters for the endpoint detector.
#[derive(Debug, Clone)]
pub struct EndpointConfig {
    /// Silence required to mark end of speech (in milliseconds). Default: 1500ms.
    pub standard_silence_ms: u32,
    /// Extended silence allowed when the initial directive is short (< 2.0s). Default: 2200ms.
    pub adaptive_hesitation_ms: u32,
    /// Maximum silence allowed immediately after wake word before auto-aborting. Default: 3500ms.
    pub initial_silence_timeout_ms: u32,
    /// Maximum total recording limit before forced completion. Default: 60,000ms (1 min).
    pub max_duration_ms: u32,
}

impl Default for EndpointConfig {
    fn default() -> Self {
        Self {
            standard_silence_ms: 1500,
            adaptive_hesitation_ms: 2200,
            initial_silence_timeout_ms: 3500,
            max_duration_ms: 60_000,
        }
    }
}

/// State machine tracking speech bursts and silence to determine exact Directive boundaries.
#[derive(Debug, Clone)]
pub struct SpeechEndpointDetector {
    config: EndpointConfig,
    state: EndpointState,
    audio_buffer: Vec<f32>,
    total_duration_ms: u32,
    speech_duration_ms: u32,
    trailing_silence_ms: u32,
    has_detected_any_speech: bool,
}

impl SpeechEndpointDetector {
    /// Creates a new detector with the given configuration.
    pub fn new(config: EndpointConfig) -> Self {
        Self {
            config,
            state: EndpointState::Idle,
            audio_buffer: Vec::new(),
            total_duration_ms: 0,
            speech_duration_ms: 0,
            trailing_silence_ms: 0,
            has_detected_any_speech: false,
        }
    }

    /// Creates a detector with default tuned parameters.
    pub fn with_defaults() -> Self {
        Self::new(EndpointConfig::default())
    }

    /// Starts a new recording session (triggered by WakeWord or PriorityOverride).
    pub fn start_session(&mut self) {
        self.state = EndpointState::Capturing;
        self.audio_buffer.clear();
        self.total_duration_ms = 0;
        self.speech_duration_ms = 0;
        self.trailing_silence_ms = 0;
        self.has_detected_any_speech = false;
    }

    /// Current operational state.
    pub fn state(&self) -> EndpointState {
        self.state
    }

    /// Manually cancels the active session (e.g. user said "cancela" or aborted).
    pub fn cancel(&mut self) {
        self.state = EndpointState::Cancelled;
        self.audio_buffer.clear();
    }

    /// Processes an audio frame along with its VAD speech probability flag.
    pub fn process_frame(
        &mut self,
        is_speech: bool,
        frame_duration_ms: u32,
        samples: &[f32],
    ) -> EndpointResult {
        if self.state == EndpointState::Idle
            || self.state == EndpointState::Completed
            || self.state == EndpointState::Cancelled
        {
            return EndpointResult::Continuing;
        }

        self.audio_buffer.extend_from_slice(samples);
        self.total_duration_ms += frame_duration_ms;

        // Check maximum safety duration cap
        if self.total_duration_ms >= self.config.max_duration_ms {
            self.state = EndpointState::Completed;
            return EndpointResult::DirectiveComplete(std::mem::take(&mut self.audio_buffer));
        }

        if is_speech {
            self.has_detected_any_speech = true;
            self.speech_duration_ms += frame_duration_ms;
            self.trailing_silence_ms = 0;
            self.state = EndpointState::Capturing;
            EndpointResult::Continuing
        } else {
            self.trailing_silence_ms += frame_duration_ms;

            // Edge Case: If no speech was ever detected and initial silence timeout expires -> Abort session
            if !self.has_detected_any_speech
                && self.trailing_silence_ms >= self.config.initial_silence_timeout_ms
            {
                self.state = EndpointState::Cancelled;
                self.audio_buffer.clear();
                return EndpointResult::SessionCancelled;
            }

            // If we had speech previously, determine if silence reached the threshold
            if self.has_detected_any_speech {
                self.state = EndpointState::SilenceCooldown;

                // Adaptive hesitation: short thoughts (< 2.0s) get more leeway to pause
                let silence_limit = if self.speech_duration_ms < 2000 {
                    self.config.adaptive_hesitation_ms
                } else {
                    self.config.standard_silence_ms
                };

                if self.trailing_silence_ms >= silence_limit {
                    self.state = EndpointState::Completed;
                    return EndpointResult::DirectiveComplete(std::mem::take(&mut self.audio_buffer));
                }
            }

            EndpointResult::Continuing
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nominal_speech_and_endpoint() {
        let mut detector = SpeechEndpointDetector::with_defaults();
        detector.start_session();

        let dummy_chunk = vec![0.1f32; 480]; // 30ms

        // 1. User speaks for 2.4s (80 frames of 30ms)
        for _ in 0..80 {
            let res = detector.process_frame(true, 30, &dummy_chunk);
            assert_eq!(res, EndpointResult::Continuing);
        }
        assert_eq!(detector.state(), EndpointState::Capturing);

        // 2. User stops speaking. Trailing silence accumulates.
        // Standard silence is 1500ms -> 50 frames of 30ms
        for _ in 0..49 {
            let res = detector.process_frame(false, 30, &dummy_chunk);
            assert_eq!(res, EndpointResult::Continuing);
            assert_eq!(detector.state(), EndpointState::SilenceCooldown);
        }

        // 50th silence frame hits 1500ms
        let final_res = detector.process_frame(false, 30, &dummy_chunk);
        assert_eq!(detector.state(), EndpointState::Completed);

        match final_res {
            EndpointResult::DirectiveComplete(audio) => {
                // Total frames: 80 speech + 50 silence = 130 frames * 480 samples = 62,400 samples
                assert_eq!(audio.len(), 130 * 480);
            }
            _ => panic!("Expected DirectiveComplete"),
        }
    }

    #[test]
    fn test_initial_silence_timeout_cancels() {
        let mut detector = SpeechEndpointDetector::with_defaults();
        detector.start_session();

        let dummy_chunk = vec![0.0f32; 480]; // 30ms silence

        // 3500ms / 30ms = ~117 frames of silence with zero speech detected
        for _ in 0..116 {
            let res = detector.process_frame(false, 30, &dummy_chunk);
            assert_eq!(res, EndpointResult::Continuing);
        }

        // 117th frame triggers timeout cancel
        let final_res = detector.process_frame(false, 30, &dummy_chunk);
        assert_eq!(detector.state(), EndpointState::Cancelled);
        assert_eq!(final_res, EndpointResult::SessionCancelled);
    }

    #[test]
    fn test_adaptive_hesitation_allows_pause() {
        let mut detector = SpeechEndpointDetector::with_defaults();
        detector.start_session();

        let dummy_chunk = vec![0.1f32; 480]; // 30ms

        // Short initial speech: 600ms (20 frames)
        for _ in 0..20 {
            detector.process_frame(true, 30, &dummy_chunk);
        }

        // User hesitates for 1800ms (60 frames of 30ms)
        // Standard threshold is 1500ms, but adaptive hesitation allows 2200ms
        for _ in 0..60 {
            let res = detector.process_frame(false, 30, &dummy_chunk);
            assert_eq!(res, EndpointResult::Continuing);
        }

        // User resumes speaking!
        let resume_res = detector.process_frame(true, 30, &dummy_chunk);
        assert_eq!(resume_res, EndpointResult::Continuing);
        assert_eq!(detector.state(), EndpointState::Capturing);
    }
}
