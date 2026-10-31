mod support;

use support::AudioGenerator;
use void_notes_core::audio::{EnergyGate, EnergyGateConfig};

#[test]
fn test_energy_gate_silence_rejection() {
    let mut gate = EnergyGate::with_defaults();
    let silence = AudioGenerator::silence(30); // 30ms frame
    assert!(!gate.is_speech(&silence));
}

#[test]
fn test_energy_gate_ambient_noise_learning() {
    let mut gate = EnergyGate::with_defaults();
    let ambient = AudioGenerator::ambient_noise(30, 0.003); // Low background hum

    // Over multiple frames, noise floor must adapt and consistently classify as non-speech
    for _ in 0..20 {
        assert!(!gate.is_speech(&ambient));
    }
    assert!(gate.noise_floor() > 0.0);
}

#[test]
fn test_energy_gate_voice_transient_trigger() {
    let mut gate = EnergyGate::with_defaults();
    let speech = AudioGenerator::speech_burst(30, 180.0, 0.25); // Vowel at 180 Hz
    assert!(gate.is_speech(&speech));
}

#[test]
fn test_energy_gate_rejects_high_zcr_static_noise() {
    let mut gate = EnergyGate::with_defaults();
    // High-frequency static alternating sign every sample (ZCR = 1.0)
    let static_hiss = AudioGenerator::high_frequency_noise(30, 0.15);
    assert!(!gate.is_speech(&static_hiss));
}

#[test]
fn test_energy_gate_custom_snr_tuning() {
    let config = EnergyGateConfig {
        min_energy_threshold: 0.01,
        snr_multiplier: 3.0, // High SNR requirement
        noise_floor_alpha: 0.1,
        max_zcr_threshold: 0.45,
    };
    let mut gate = EnergyGate::new(config);

    // Weak speech (amplitude 0.015) fails 3.0x SNR multiplier test
    let weak_signal = AudioGenerator::speech_burst(30, 200.0, 0.015);
    assert!(!gate.is_speech(&weak_signal));

    // Strong speech (amplitude 0.3) passes
    let strong_signal = AudioGenerator::speech_burst(30, 200.0, 0.3);
    assert!(gate.is_speech(&strong_signal));
}
