/// Configuration parameters for the Tier 0 acoustic energy gate.
#[derive(Debug, Clone)]
pub struct EnergyGateConfig {
    /// Minimum RMS threshold to consider potential speech activity.
    pub min_energy_threshold: f32,
    /// Multiplier above the estimated noise floor required to trigger speech presence.
    pub snr_multiplier: f32,
    /// Exponential moving average factor for updating the background noise floor (0.0 to 1.0).
    pub noise_floor_alpha: f32,
    /// Maximum zero-crossing rate ratio typical for human speech.
    pub max_zcr_threshold: f32,
}

impl Default for EnergyGateConfig {
    fn default() -> Self {
        Self {
            min_energy_threshold: 0.005, // -46 dBFS approx
            snr_multiplier: 1.8,         // Signal must be 1.8x estimated background noise
            noise_floor_alpha: 0.05,     // Slow adaptation to ambient room changes
            max_zcr_threshold: 0.45, // Human voice typically stays below 0.45 zero crossings per sample
        }
    }
}

/// Tier 0 Energy Gate: Ultra-low-power pre-filter preventing neural KWS execution during silence.
///
/// Operates in sub-microsecond time with zero heap allocations.
#[derive(Debug, Clone)]
pub struct EnergyGate {
    config: EnergyGateConfig,
    noise_floor: f32,
    speech_frame_count: usize,
}

impl EnergyGate {
    /// Creates a new EnergyGate with the provided configuration.
    pub fn new(config: EnergyGateConfig) -> Self {
        let initial_noise = config.min_energy_threshold;
        Self {
            config,
            noise_floor: initial_noise,
            speech_frame_count: 0,
        }
    }

    /// Creates an EnergyGate with default tuned parameters.
    pub fn with_defaults() -> Self {
        Self::new(EnergyGateConfig::default())
    }

    /// Returns the current estimated background noise floor RMS.
    pub fn noise_floor(&self) -> f32 {
        self.noise_floor
    }

    /// Calculates the Root Mean Square (RMS) amplitude of an audio frame.
    pub fn calculate_rms(frame: &[f32]) -> f32 {
        if frame.is_empty() {
            return 0.0;
        }
        let sum_sq: f32 = frame.iter().map(|&s| s * s).sum();
        (sum_sq / frame.len() as f32).sqrt()
    }

    /// Calculates the zero-crossing rate (ZCR) of an audio frame.
    pub fn calculate_zcr(frame: &[f32]) -> f32 {
        if frame.len() < 2 {
            return 0.0;
        }
        let mut crossings = 0;
        for i in 1..frame.len() {
            if (frame[i] >= 0.0 && frame[i - 1] < 0.0) || (frame[i] < 0.0 && frame[i - 1] >= 0.0) {
                crossings += 1;
            }
        }
        crossings as f32 / (frame.len() - 1) as f32
    }

    /// Analyzes an incoming audio chunk (e.g., 10-80ms) and determines if speech energy is present.
    pub fn is_speech(&mut self, frame: &[f32]) -> bool {
        let rms = Self::calculate_rms(frame);
        let zcr = Self::calculate_zcr(frame);

        let is_above_min = rms >= self.config.min_energy_threshold;
        let is_above_noise = rms >= (self.noise_floor * self.config.snr_multiplier);
        let is_valid_zcr = zcr <= self.config.max_zcr_threshold;

        let speech_detected = is_above_min && is_above_noise && is_valid_zcr;

        if speech_detected {
            self.speech_frame_count += 1;
        } else {
            self.speech_frame_count = 0;
            // Adaptively update noise floor during quiet periods
            self.noise_floor = (self.config.noise_floor_alpha * rms)
                + ((1.0 - self.config.noise_floor_alpha) * self.noise_floor);

            // Clamp noise floor to prevent it from decaying to absolute zero
            self.noise_floor = self.noise_floor.max(self.config.min_energy_threshold * 0.5);
        }

        speech_detected
    }

    /// Resets the internal noise floor estimator.
    pub fn reset(&mut self) {
        self.noise_floor = self.config.min_energy_threshold;
        self.speech_frame_count = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_silence_detection() {
        let mut gate = EnergyGate::with_defaults();
        let silence = vec![0.0f32; 480]; // 30ms at 16kHz
        assert!(!gate.is_speech(&silence));
    }

    #[test]
    fn test_low_noise_floor_adaptation() {
        let mut gate = EnergyGate::with_defaults();
        // Low ambient noise (~0.002 RMS) below min_energy_threshold (0.005)
        let low_noise: Vec<f32> = (0..480)
            .map(|i| if i % 2 == 0 { 0.002 } else { -0.002 })
            .collect();
        assert!(!gate.is_speech(&low_noise));
    }

    #[test]
    fn test_speech_burst_detection() {
        let mut gate = EnergyGate::with_defaults();
        // Speech transient: high amplitude (0.2 RMS) and voice-like frequency
        let speech: Vec<f32> = (0..480).map(|i| 0.2 * (i as f32 * 0.05).sin()).collect();
        assert!(gate.is_speech(&speech));
    }

    #[test]
    fn test_extreme_high_frequency_noise_rejection() {
        let mut gate = EnergyGate::with_defaults();
        // High frequency static noise: alternating every sample -> ZCR = 1.0 (exceeds max_zcr_threshold)
        let high_freq_noise: Vec<f32> = (0..480)
            .map(|i| if i % 2 == 0 { 0.1 } else { -0.1 })
            .collect();
        assert!(!gate.is_speech(&high_freq_noise));
    }
}
