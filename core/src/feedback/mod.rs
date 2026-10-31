use serde::{Deserialize, Serialize};

/// Behavioral profile for sensory cues.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackProfile {
    /// Plays auditory chimes and emits haptic pulses.
    Normal,
    /// Completely mutes all audio chimes, relying exclusively on haptics and silent notifications.
    SilentMeeting,
}

/// Types of haptic vibration patterns.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HapticPattern {
    /// Crisp single tap for trigger activation.
    LightTap,
    /// Double confirmation tap for completed directive save.
    DoubleConfirmation,
    /// Triple pulse for rejection or error.
    RejectionPulse,
}

/// Concrete actions emitted by the feedback controller to be rendered by platform layers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FeedbackAction {
    /// Play an audio chime sound by asset identifier (e.g. "chime_activation.wav").
    PlayAudioChime(&'static str),
    /// Trigger device haptic vibration motor.
    TriggerHaptic(HapticPattern),
    /// Show a system desktop or push notification.
    EmitNotification {
        title: String,
        body: String,
    },
}

/// Domain events triggering feedback.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedbackEvent {
    WakeWordDetected,
    DirectiveCompleted,
    DirectiveRevoked,
    MicrophoneError,
}

/// Controller deciding which sensory actions to execute based on the active FeedbackProfile.
#[derive(Debug, Clone)]
pub struct FeedbackController {
    profile: FeedbackProfile,
}

impl FeedbackController {
    /// Creates a new controller with the specified profile.
    pub fn new(profile: FeedbackProfile) -> Self {
        Self { profile }
    }

    /// Sets the active profile (e.g. toggled to SilentMeeting in a conference).
    pub fn set_profile(&mut self, profile: FeedbackProfile) {
        self.profile = profile;
    }

    /// Returns the current active profile.
    pub fn profile(&self) -> FeedbackProfile {
        self.profile
    }

    /// Determines the exact list of actions to dispatch for a given event.
    pub fn resolve_feedback(&self, event: FeedbackEvent) -> Vec<FeedbackAction> {
        let mut actions = Vec::new();

        match event {
            FeedbackEvent::WakeWordDetected => {
                if self.profile == FeedbackProfile::Normal {
                    actions.push(FeedbackAction::PlayAudioChime("chime_wake.wav"));
                }
                actions.push(FeedbackAction::TriggerHaptic(HapticPattern::LightTap));
            }
            FeedbackEvent::DirectiveCompleted => {
                if self.profile == FeedbackProfile::Normal {
                    actions.push(FeedbackAction::PlayAudioChime("chime_complete.wav"));
                }
                actions.push(FeedbackAction::TriggerHaptic(HapticPattern::DoubleConfirmation));
            }
            FeedbackEvent::DirectiveRevoked => {
                if self.profile == FeedbackProfile::Normal {
                    actions.push(FeedbackAction::PlayAudioChime("chime_cancel.wav"));
                }
                actions.push(FeedbackAction::TriggerHaptic(HapticPattern::LightTap));
            }
            FeedbackEvent::MicrophoneError => {
                actions.push(FeedbackAction::TriggerHaptic(HapticPattern::RejectionPulse));
                actions.push(FeedbackAction::EmitNotification {
                    title: "void-notes — Erro de Microfone".to_string(),
                    body: "Acesso ao microfone indisponível ou bloqueado.".to_string(),
                });
            }
        }

        actions
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normal_profile_includes_audio_and_haptic() {
        let controller = FeedbackController::new(FeedbackProfile::Normal);
        let actions = controller.resolve_feedback(FeedbackEvent::WakeWordDetected);

        assert!(actions.contains(&FeedbackAction::PlayAudioChime("chime_wake.wav")));
        assert!(actions.contains(&FeedbackAction::TriggerHaptic(HapticPattern::LightTap)));
    }

    #[test]
    fn test_silent_meeting_profile_suppresses_audio() {
        let controller = FeedbackController::new(FeedbackProfile::SilentMeeting);
        let actions = controller.resolve_feedback(FeedbackEvent::WakeWordDetected);

        // Crucial test: Audio chimes MUST be completely absent in SilentMeeting
        for action in &actions {
            if let FeedbackAction::PlayAudioChime(_) = action {
                panic!("SilentMeeting profile must NEVER emit audio chimes!");
            }
        }
        assert!(actions.contains(&FeedbackAction::TriggerHaptic(HapticPattern::LightTap)));
    }

    #[test]
    fn test_error_feedback_emits_rejection_and_notification() {
        let controller = FeedbackController::new(FeedbackProfile::SilentMeeting);
        let actions = controller.resolve_feedback(FeedbackEvent::MicrophoneError);

        assert!(actions.contains(&FeedbackAction::TriggerHaptic(HapticPattern::RejectionPulse)));
        let has_notif = actions.iter().any(|a| matches!(a, FeedbackAction::EmitNotification { .. }));
        assert!(has_notif);
    }
}
