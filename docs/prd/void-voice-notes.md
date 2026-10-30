---
title: V.O.I.D. — Multiplatform Voice Notes Assistant (Phase 1)
type: product
status: ready-for-planning
created_at: 2026-10-30
target_audience: internal
---

# PRD — V.O.I.D. (VOID Only Interprets Directives)

## 1. Overview & Problem Statement

### 1.1 Concept & Vision
**V.O.I.D.** (*VOID Only Interprets Directives*) is an advanced computational assistant inspired by the classic cadence of a digital butler (akin to J.A.R.V.I.S.), designed with an existentialist, minimalist, and technical posture. Rather than operating as a chatty, cloud-reliant corporate assistant, V.O.I.D. prioritizes silent attentiveness, precise interpretation of directives, zero unnecessary computation, and immediate local execution.

The long-term vision scales V.O.I.D. into an agentic personal workstation assistant. However, to guarantee an unshakable technical foundation, **Phase 1** focuses strictly on high-performance, hands-free voice note-taking with zero friction across everyday devices.

### 1.2 Problem Statement
Capturing transient thoughts, tasks, and ideas during deep work or movement currently suffers from excessive friction:
1. **Context Fragmentation**: Unlocking a device, locating an app, typing, and formatting breaks mental flow.
2. **Resource Inefficiency**: Existing voice assistants and continuous transcription models (such as unoptimized Whisper streams) consume unsustainable CPU cycles (often 100% across multiple cores) and rapidly drain mobile battery.
3. **Cloud & Latency Dependency**: Most mobile assistants require persistent internet connectivity, transmitting private room audio to third-party cloud servers.
4. **Platform Lock-in**: Note-taking solutions are rarely cohesive across Linux desktop, Android, and iOS while respecting local file ownership (Markdown).

### 1.3 Solution & Scope
V.O.I.D. Phase 1 provides an ultra-lightweight, multiplatform (Android, iOS, Linux) background service and user interface that:
- Listens continuously for the native wake word (`"Void"` / `"Hey Void"`) using sub-2% CPU via a tiered audio pipeline.
- Automatically detects speech boundaries via Voice Activity Detection (VAD) endpointing.
- Transcribes the speech burst locally via quantized `whisper.cpp` (`tiny-q5_1` / `base-q5_1`) in Brazilian Portuguese (`pt-BR`).
- Cleans and formats the note, storing it in a Local-First SQLite database and mirroring it into daily Markdown files (`notes/YYYY-MM-DD.md`).
- Operates 100% offline with zero server requirements, structured with sync primitives (UUID v4, ISO timestamps, soft deletes) to facilitate future cloud sync.

---

## 2. Project Context & Constraints

### 2.1 Multiplatform Hardware & OS Constraints
- **Linux (Desktop)**:
  - Audio capture via PipeWire / PulseAudio / ALSA.
  - Background execution via a native `systemd` user service (`void-daemon.service`).
  - Near-zero idle resource ceiling: `< 1.5%` CPU of one core, `< 45 MB` idle RAM.
- **Android**:
  - Implements an official Android `VoiceInteractionService` and `HotwordDetectionService` (Default Assistant integration).
  - Uses `microWakeWord` / quantized ONNX models with energy gating (WebRTC VAD) to eliminate idle battery drain (< 2% battery consumption per 24 hours).
  - Fallback foreground service with persistent status notification for non-default configurations.
- **iOS (Apple Restrictions)**:
  - iOS strictly prohibits third-party continuous background microphone recording when suspended/locked.
  - Native integration paths:
    1. Siri Shortcuts / App Intents integration (`"Hey Siri, Void"` or custom command).
    2. Action Button (iPhone 15 Pro / 16) and Back Tap (AssistiveTouch) physical activation.
    3. Lock screen widget and Control Center toggle.

### 2.2 Tech Stack Baseline
- **Application UI**: Flutter (single unified codebase targeting Android, iOS, and Linux desktop).
- **Core Engine**: Pure Rust library compiled for all targets, interfaced via `flutter_rust_bridge` (v2).
- **Wake Word Engine**: `sherpa-onnx` (Open-Vocabulary KWS) / `microWakeWord` / `oww-rs` (`"Void"` / `"Hey Void"`).
- **Speech-to-Text Engine**: `whisper.cpp` via `whisper-rs` (quantized `ggml-base-q5_1` or `ggml-tiny-q5_1` multilingual).
- **VAD Engine**: `Silero VAD v5` (ONNX) or `libfvad` (WebRTC VAD) for speech gating and endpointing.
- **Database**: Local SQLite with Write-Ahead Logging (`WAL` mode) and UUID v4 primary keys.
- **File System**: Plaintext Markdown daily logs (`notes/YYYY-MM-DD.md`).

---

## 3. User Stories

- **US-1 (Hands-free Voice Directive)**: As a user with hands occupied, I want to say `"Void, [directive]"` so that my thought is accurately transcribed and saved without touching my device.
- **US-2 (Physical / Desktop Hotkey Fallback)**: As a user in a loud environment or working on my keyboard, I want to press a global shortcut (`Super+Shift+N` on Linux, long-press power on Android, or Action Button on iOS) to immediately start dictating a note without speaking the wake word.
- **US-3 (Contextual Feedback Profile)**: As a user frequently in meetings or quiet spaces, I want to toggle between "Normal" (auditory chime + haptics) and "Meeting/Silent" (haptics + desktop notification only) modes so that the assistant never disrupts my environment.
- **US-4 (Local-First Note Access & Journaling)**: As a user of tools like Obsidian or Neovim, I want my voice directives mirrored into daily Markdown files on my local filesystem so that my data remains sovereign and easily readable outside the app.
- **US-5 (Sync-Ready Architecture)**: As a multi-device user, I want notes created on mobile or desktop to be stored with conflict-free identifiers and change metadata so that cross-device account synchronization can be layered on without schema redesign.

---

## 4. Non-Goals (Out of Scope for Phase 1)

1. **Active Cloud Synchronization & Remote Server**: Phase 1 is strictly **100% Local-First and offline**. No remote synchronization servers, user registration, or cloud databases (e.g., Supabase or custom APIs) will be deployed in this milestone. Sync traits and database schemas are prepared, but network syncing is deferred to Phase 2.
2. **Conversational Agent / LLM Synthesis / Text-to-Speech (TTS)**: V.O.I.D. will not generate voice replies or execute complex multi-turn LLM reasoning in Phase 1. It acts strictly as an ultra-efficient listener, transcriber, and note persistent layer.
3. **Speaker Diarization & Biometric Voice Identification**: V.O.I.D. will not attempt to distinguish between multiple speakers in Phase 1. It triggers on the configured wake word regardless of the speaker's biometric voiceprint.
4. **Rich-Text / WYSIWYG Note Editing**: The application interface will provide a clean, read-only list and detail inspector for captured directives, but will not implement an inline markdown rich-text editor (plain text viewing and raw filesystem editing suffice).

---

## 5. System Flows & Edge Cases

### Flow 1: Wake Word Activation & Voice Dictation
- **Actor**: User.
- **Happy Path**:
  1. System sits in low-power idle listening state (`Tier 0/1`).
  2. User speaks: *"Void, comprar café torrado e enviar o relatório financeiro"*.
  3. KWS engine spots `"Void"` with confidence score $\ge 0.55$.
  4. State shifts from `IDLE` to `RECORDING`.
  5. If configured in Normal Mode, system plays a subtle, crisp 150ms activation chime and emits a short haptic pulse.
  6. Incoming 16 kHz PCM audio stream is buffered into a memory ring buffer.
  7. Silero VAD monitors incoming frames; after 1.5 seconds of continuous silence following the speech, the system triggers `ENDPOINT_REACHED`.
  8. Audio buffer is passed to `whisper.cpp` (`base-q5_1`, Portuguese).
  9. Transcribed text is parsed: the trigger phrase (`"Void"`) is stripped, first letter capitalized, and punctuation applied.
  10. Note is persisted in local SQLite with UUID v4 and appended to `notes/YYYY-MM-DD.md`.
  11. System plays a confirmation chime (or haptic pulse) and returns to `IDLE`.
- **Empty State**:
  - User speaks the wake word *"Void"*, but remains silent afterwards.
  - VAD detects no speech within 4.0 seconds after activation.
  - System aborts recording, emits a double-short haptic pulse, discards the audio buffer, and returns to `IDLE` without creating an empty database record.
- **Error & Edge Cases**:
  - *Audio Hardware Busy / Permission Revoked*: System logs error, emits a failure haptic pattern, and displays a non-blocking toast/desktop notification.
  - *False Positive Wake Word*: Audio is captured, but Whisper produces no intelligible tokens or hallucinations (e.g. repeated whitespace/fillers). Length check ($< 3$ characters) filters the entry and suppresses persistence.

### Flow 2: Manual / Physical Trigger Fallback
- **Actor**: User.
- **Happy Path**:
  1. User presses global shortcut (`Super+Shift+N` on Linux, long-presses Power button / gesture on Android, or presses Action Button on iOS).
  2. System bypasses KWS and transitions directly to `RECORDING`.
  3. Haptic pulse / visual indicator activates.
  4. User speaks the directive.
  5. VAD silence endpointing triggers completion (or user presses the shortcut a second time to force stop).
  6. Audio is transcribed and saved to SQLite and Markdown.
- **Empty State**:
  - Shortcut is pressed, but no speech is detected for 5.0 seconds. Recording times out and auto-cancels.
- **Error & Edge Cases**:
  - Shortcut pressed while another transcription is currently running. New input is queued or rejected with a busy haptic feedback.

### Flow 3: Note Review & Markdown Mirroring
- **Actor**: User opening the Flutter app.
- **Happy Path**:
  1. User opens the V.O.I.D. app on Linux, Android, or iOS.
  2. App loads notes ordered by `created_at DESC` from the local SQLite store.
  3. User can filter by date (today, past 7 days, all).
  4. Each entry displays: Timestamp (e.g., `14:32`), transcribed text, and audio duration (e.g., `4.2s`).
  5. Concurrently, the user can inspect the filesystem at `notes/YYYY-MM-DD.md` (via Obsidian or text editor) and see the exact same entries formatted as clean markdown lists with timestamps.
- **Empty State**:
  - First-time launch or no notes recorded for the day. App displays a minimalist aesthetic empty state: *"No directives recorded today. V.O.I.D. is listening for 'Void'..."*
- **Error & Edge Cases**:
  - *Markdown File Locked or Inaccessible*: SQLite write succeeds, and an event is queued in an internal retry buffer to reconcile the `.md` file once the filesystem lock is released.

### Flow 4: Meeting / Silent Mode Configuration
- **Actor**: User.
- **Happy Path**:
  1. User opens settings or clicks the system tray icon / quick settings tile.
  2. User toggles `Silent / Meeting Mode` to `ON`.
  3. All subsequent wake word activations and note completions suppress audio chimes.
  4. Feedback is routed exclusively through subtle haptic vibrations (mobile) or silent desktop notifications (Linux).
- **Empty State**: N/A (binary toggle).
- **Error & Edge Cases**: Device has no haptic motor (e.g. standard Linux desktop without gamepad/vibration). System falls back to a discrete system tray icon pulse or silent desktop notification.

---

## 6. Acceptance Criteria (BDD)

### AC-1: Hands-free Wake Word Detection & Persistence
- **Given** V.O.I.D. is running in background and the device is idle,
- **When** the user clearly speaks *"Void, lembrar de revisar o PR amanhã às dez horas"*,
- **Then** the KWS engine MUST trigger within 300ms of the word "Void",
- **And** the audio following the wake word MUST be recorded until 1.5s of silence is detected,
- **And** `whisper.cpp` MUST transcribe the audio in $\le 1.5\text{s}$ on CPU,
- **And** the database MUST insert a row with `content = "Lembrar de revisar o PR amanhã às dez horas."`,
- **And** the file `notes/<today>.md` MUST contain `- **[HH:MM:SS]** Lembrar de revisar o PR amanhã às dez horas.`.

### AC-2: Idle Resource Ceiling on Linux Desktop
- **Given** V.O.I.D. daemon is running in the background listening to the default PipeWire microphone source,
- **When** the room is quiet or contains constant non-speech background ambient noise,
- **Then** the process CPU utilization MUST average $< 1.5\%$ of a single core over a 10-minute sampling window,
- **And** the resident set size (RSS) memory footprint MUST remain $\le 45\text{ MB}$.

### AC-3: Silence Cancellation (Anti-Ghost Note)
- **Given** the wake word *"Void"* was triggered accidentally by ambient television or conversational noise,
- **When** no human speech is detected by the VAD during the 3.0 seconds following the trigger,
- **Then** the session MUST abort automatically,
- **And** NO record MUST be added to SQLite or the Markdown file,
- **And** the memory buffer MUST be cleared.

### AC-4: Shortcut Bypass
- **Given** the user is typing on their Linux workstation with V.O.I.D. active,
- **When** the user presses `Super+Shift+N`,
- **Then** the system MUST transition immediately to `RECORDING` without requiring the wake word `"Void"`,
- **And** transcribe and persist the note upon speech termination.

### AC-5: Silent Mode Compliance
- **Given** the user has toggled `Silent / Meeting Mode = true`,
- **When** a note is triggered, recorded, and persisted,
- **Then** the system MUST NOT emit any audio chimes through system speakers or headphones,
- **And** MUST provide feedback exclusively via haptic vibration (on mobile) or discrete notification (on desktop).

---

## 7. High-Level Architecture & Tech Stack

### 7.1 Architecture Diagram

```
+-------------------------------------------------------------+
|                      FLUTTER UI LAYER                       |
|   (Android App / iOS App / Linux Desktop App & System Tray) |
+-------------------------------------------------------------+
                              |
                    [flutter_rust_bridge v2]
                              |
+-------------------------------------------------------------+
|                       RUST CORE ENGINE                      |
|                                                             |
|  [Audio Capture Subsystem]                                  |
|   - cpal (Linux) / Oboe & AAudio (Android) / CoreAudio (iOS)|
|   - 16 kHz Mono PCM Circular Ring Buffer (~64 KB RAM)       |
|                                                             |
|  [Tiered Acoustic Pipeline]                                 |
|   - Tier 0: WebRTC VAD (energy gate, ~0.1% CPU)             |
|   - Tier 1: sherpa-onnx KWS / microWakeWord ("Void")        |
|   - Tier 2: Silero VAD v5 (Speech Endpointing, silence >1.5s|
|   - Tier 3: whisper-rs / whisper.cpp (Quantized q5_1 ASR)   |
|                                                             |
|  [Data & Persistence Layer]                                 |
|   - SQLite local store (rusqlite, WAL mode, UUID v4)        |
|   - Markdown Mirror Engine (appends to notes/YYYY-MM-DD.md) |
|   - Sync Engine Trait (LocalNoOp implementation for v1)     |
+-------------------------------------------------------------+
```

### 7.2 Confirmed Database Schema (`notes`)

```sql
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY NOT NULL,              -- UUID v4 generated on client
    content TEXT NOT NULL,                     -- Cleaned & formatted transcribed directive
    raw_transcription TEXT NOT NULL,           -- Unmodified whisper output
    audio_duration_ms INTEGER NOT NULL,        -- Duration of the voice snippet in milliseconds
    created_at TEXT NOT NULL,                  -- ISO8601 UTC timestamp (e.g. 2026-10-30T14:32:00Z)
    updated_at TEXT NOT NULL,                  -- ISO8601 UTC timestamp
    deleted_at TEXT,                           -- NULL if active, ISO8601 UTC timestamp if soft-deleted
    sync_status TEXT DEFAULT 'pending'         -- 'pending' | 'synced' (ready for Phase 2)
);

CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_sync_status ON notes(sync_status);
```

### 7.3 Sync Trait Contract (Future-Proofing for Phase 2)

```rust
#[async_trait::async_trait]
pub trait SyncProvider: Send + Sync {
    async fn push_pending_notes(&self, notes: &[Note]) -> Result<(), SyncError>;
    async fn pull_notes_since(&self, timestamp: &str) -> Result<Vec<Note>, SyncError>;
}
```

*In Phase 1, `LocalOnlySyncProvider` implements this trait as an offline no-op, ensuring zero network overhead while guaranteeing zero refactoring when cloud sync (BaaS Supabase or Self-hosted API) is integrated in Phase 2.*
