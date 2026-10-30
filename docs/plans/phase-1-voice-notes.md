# Implementation Plan — V.O.I.D. Phase 1: Multiplatform Voice Notes

**Goal:** Build the foundational, ultra-lightweight, hands-free voice note-taking assistant (V.O.I.D.) across Linux, Android, and iOS using a shared Rust core, Flutter UI, tiered audio pipeline, local SQLite, and daily Markdown mirroring.

---

## Architecture & Dependency Flow

```text
[Phase 1: Foundation]
  │── Setup Rust toolchain & Cargo workspace
  │── SQLite schema & LocalNote repository (UUID v4, WAL mode)
  ▼
[Phase 2: Audio Pipeline & VAD]
  │── Circular ring buffer (16 kHz 16-bit PCM mono)
  │── WebRTC VAD (Tier 0 energy gate)
  │── Silero VAD (Tier 2 speech endpointing: silence > 1.5s)
  ▼
[Phase 3: Recognition & KWS]
  │── whisper.cpp integration via whisper-rs (quantized q5_1 PT-BR)
  │── Text sanitization & formatting pipeline
  │── sherpa-onnx / microWakeWord KWS integration ("Void")
  ▼
[Phase 4: Persistence & Feedback]
  │── Markdown daily file mirror (notes/YYYY-MM-DD.md)
  │── FeedbackMode controller (Normal Chime vs. Silent/Meeting)
  ▼
[Phase 5: UI & Platform Integration]
  │── Flutter app scaffold & flutter_rust_bridge v2 bindings
  │── Note list / detail view & state stream
  │── Global hotkey listener (Super+Shift+N) & desktop tray
  ▼
[Phase 6: Verification & Benchmarks]
  │── TDD test suites (audio buffer, VAD state machine, DB)
  │── End-to-end smoke test
  │── Resource audit (<1.5% CPU idle, <45MB RAM)
```

---

## Detailed Task Breakdown

### Phase 1: Foundation & Tooling Setup
- **Task: Setup Rust workspace and dependencies**
  - **# Target:** `Cargo.toml`, `core/Cargo.toml`, `core/src/lib.rs`.
  - **# Change:** Create root workspace manifest with `core` member. Add `rusqlite` (bundled), `uuid`, `chrono`, `anyhow`, `thiserror`, and `tokio`.
  - **# Acceptance:** `cargo check` compiles cleanly with zero warnings.
- **Task: Initialize SQLite schema and migrations**
  - **# Target:** `core/src/db/schema.rs`, `core/src/db/mod.rs`.
  - **# Change:** Create `notes` table schema with UUID v4 primary key, UTC timestamps, `deleted_at`, and `sync_status`. Enable WAL mode.
  - **# Acceptance:** Unit test connects to in-memory/temp SQLite, creates schema, and confirms table indices.
- **Task: Implement LocalNote repository with CRUD**
  - **# Target:** `core/src/db/repo.rs`, `core/src/models/note.rs`.
  - **# Change:** Implement `create_note`, `list_notes_by_date`, `get_note`, and `soft_delete_note`.
  - **# Acceptance:** CRUD unit test verifies creation, retrieval, and soft delete with 100% assertions passing.

### Phase 2: Audio Pipeline & VAD
- **Task: Implement circular audio ring buffer**
  - **# Target:** `core/src/audio/ring_buffer.rs`.
  - **# Change:** Implement fixed-capacity ring buffer holding 3.0s of 16 kHz mono f32/i16 audio (~96 KB).
  - **# Acceptance:** Unit test verifies sliding window write/read without heap reallocations.
- **Task: Integrate WebRTC VAD energy gate**
  - **# Target:** `core/src/audio/energy_gate.rs`.
  - **# Change:** Implement Tier 0 speech energy/zero-crossing detector to suppress downstream inference on silence.
  - **# Acceptance:** Synthetic silence and noise test vectors accurately trigger or bypass the gate.
- **Task: Implement Silero VAD speech endpointing**
  - **# Target:** `core/src/audio/endpointing.rs`.
  - **# Change:** Implement state machine: `IDLE` -> `RECORDING` -> `ENDPOINT_REACHED` when silence exceeds 1.5s.
  - **# Acceptance:** State machine test confirms transitions on simulated speech and silence sequences.

### Phase 3: Recognition & KWS
- **Task: Integrate whisper.cpp with quantized PT-BR model**
  - **# Target:** `core/src/stt/whisper.rs`.
  - **# Change:** Wrap `whisper-rs` with thread-safe inference runner. Support `ggml-tiny-q5_1` and `ggml-base-q5_1`.
  - **# Acceptance:** Transcription smoke test passes a 16kHz WAV sample and returns Portuguese text.
- **Task: Implement text cleanup and formatting pipeline**
  - **# Target:** `core/src/stt/formatter.rs`.
  - **# Change:** Strip wake word prefixes (`"Void"`, `"Hey Void"`), trim whitespace, capitalize first letter, and ensure ending punctuation.
  - **# Acceptance:** Unit test verifies formatted variants (`"void comprar cafe"` -> `"Comprar café."`).
- **Task: Integrate sherpa-onnx KWS engine for Void**
  - **# Target:** `core/src/kws/spotter.rs`.
  - **# Change:** Integrate `sherpa-onnx` keyword spotter configured with `"Void"` / `"Hey Void"` keywords.
  - **# Acceptance:** Synthetic audio sample of "Void" triggers detection with confidence $> 0.55$.

### Phase 4: Persistence & Feedback
- **Task: Implement Markdown daily file mirror engine**
  - **# Target:** `core/src/storage/markdown_mirror.rs`.
  - **# Change:** Append formatted notes to `notes/YYYY-MM-DD.md` with timestamp badges `[HH:MM:SS]`.
  - **# Acceptance:** Integration test asserts file existence and valid markdown list format after note creation.
- **Task: Implement FeedbackMode controller**
  - **# Target:** `core/src/feedback/mod.rs`.
  - **# Change:** Manage audio chime playback (Normal mode) and haptic/notification signals (Silent/Meeting mode).
  - **# Acceptance:** Unit test confirms audio suppression when `silent_mode = true`.

### Phase 5: UI & Platform Integration
- **Task: Initialize Flutter app shell with bridge bindings**
  - **# Target:** `apps/mobile_desktop/`, `bridge/`.
  - **# Change:** Scaffold Flutter application and configure `flutter_rust_bridge` code generation.
  - **# Acceptance:** App compiles and executes a ping-pong call to the Rust core.
- **Task: Wire Rust core state stream into Flutter UI**
  - **# Target:** `apps/mobile_desktop/lib/screens/notes_screen.dart`.
  - **# Change:** Stream note updates, listening states (`Idle`, `Listening`, `Transcribing`), and history list.
  - **# Acceptance:** UI reflects state changes and renders persisted notes.
- **Task: Implement system tray and global hotkey listener**
  - **# Target:** `apps/mobile_desktop/lib/platform/tray_hotkey.dart`.
  - **# Change:** Register `Super+Shift+N` on Linux and tray icon for quick toggles.
  - **# Acceptance:** Pressing shortcut triggers `RECORDING` state.

### Phase 6: Verification & Quality Gates
- **Task: Run automated unit and integration test suite**
  - **# Target:** Full repository.
  - **# Change:** Execute `cargo test` across all core modules and Flutter widget tests.
  - **# Acceptance:** 100% green tests with zero regressions.
- **Task: Perform end-to-end audio pipeline smoke test**
  - **# Target:** E2E smoke script.
  - **# Change:** Exercise microphone input -> wake word -> VAD endpoint -> whisper transcription -> SQLite -> Markdown.
  - **# Acceptance:** Spoken directive creates database row and matching line in `notes/YYYY-MM-DD.md`.
- **Task: Verify idle memory and CPU benchmarks meet ceilings**
  - **# Target:** Benchmark telemetry report.
  - **# Change:** Measure process CPU and RSS memory over 5 minutes of idle listening.
  - **# Acceptance:** CPU $< 1.5\%$ of 1 core, RSS $\le 45\text{ MB}$.
