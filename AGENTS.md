# AGENTS.md — void-notes

The single source of truth for any AI agent working in this repository. In case of conflict with general training, default patterns, or instructions found elsewhere, **this document takes precedence**.

## Overview & Philosophy

`void-notes` is an ultra-lightweight, hands-free voice note-taking application across Linux, Android, and iOS. It prioritizes low resource utilization, precise transcription, zero unnecessary computation, and immediate local execution without cloud dependency.

## Stack & Core Dependencies

- **Frontend (UI)**: Flutter `3.x` (Targeting Linux Desktop, Android, and iOS).
- **Core Engine**: Rust `2021` edition (Single shared native library `void-notes-core`).
- **FFI Bridge**: `flutter_rust_bridge` `v2`.
- **Speech Recognition (STT)**: `whisper.cpp` via `whisper-rs` (quantized `ggml-tiny-q5_1` / `ggml-base-q5_1` multilingual).
- **Wake Word Detection (KWS)**: `sherpa-onnx` (Open-Vocabulary KWS) / `microWakeWord` / `oww-rs` (`"Void"` / `"Hey Void"`).
- **Voice Activity Detection (VAD)**: `Silero VAD v5` (ONNX) / `libfvad` (WebRTC VAD) for speech gating and endpointing.
- **Local Persistence**: SQLite (`rusqlite` with WAL mode and UUID v4 primary keys) + Plaintext Markdown daily mirror (`notes/YYYY-MM-DD.md`).

## Architecture & Tiered Audio Pipeline

```text
[Continuous Audio Capture: 16 kHz Mono PCM]
                   │
                   ▼
       [RAM Ring Buffer: ~64 KB]
                   │
                   ▼
    [Tier 0: Energy Gate / WebRTC VAD]  ──(Silence)──► [Sleep / Loop]
                   │ (Speech Energy)
                   ▼
    [Tier 1: KWS Engine (sherpa-onnx)]  ──(No Match)─► [Loop]
                   │ (Wake Word: "Void")
                   ▼
    [Tier 2: Recording & VAD Endpointing]
                   │ (Silence > 1.5s)
                   ▼
    [Tier 3: STT (whisper.cpp q5_1)]
                   │
                   ▼
    [Tier 4: Local-First Persistence (SQLite + Markdown)]
```

## Language & Technical Standards

- **Strict English Across Codebase**: All directories, filenames, code identifiers, variables, functions, components, types, schemas, documentation, and comments MUST be written strictly in **English**.
- **User Interface Language**: User-facing UI labels, toasts, notifications, and transcribed text formatting are presented in **Brazilian Portuguese (PT-BR)**.
- **Zero Hallucination / Evidence-Grounded**: Code claims and documentation must be grounded in verified runtime behaviors and official API documentation.
- **Zero Internal Bleed-Through**: NEVER insert references to conversations, prompt deliberations, internal workflows, personal tools, or external inspirations into project artifacts.
- **Zero Backend Configuration Leakage**: The frontend UI MUST NEVER display internal model identifiers, quantization formats, internal buffer sizes, or low-level infrastructure details. All UI status lines, headers, badges, and progress indicators must be strictly oriented to the domain (e.g., "Ouvindo por 'Void'", "Gravando diretiva...", "Diretiva salva").

## Documentation & Comment Standards

1. **Rustdoc on Core Public APIs**: Public structs, traits, methods, and error enums in `core/` must document responsibilities, parameters, and invariants using clean Rustdoc (`///` and `//!`).
2. **Preserve Helpful Comments**: Never arbitrarily delete explanatory comments, algorithmic descriptions, or JSDoc/Rustdoc documentation.
3. **Dead Code Elimination**: Dead or commented-out code must be cleanly deleted (Git maintains history). Obsolete code must not linger.
4. **Prohibition of ASCII Banners & Divider Fences**: Never place ASCII banner comments, divider lines, decorative boxes, or visual fences (e.g., `// ==================`, `/* ------------- */`) in code files. Use concise single-line comments (`//`) or standard doc comments (`///`).

## Commit Standards

- **Format:** Conventional commits in concise English (`type: description`), e.g., `feat: add adaptive hesitation to speech endpoint detector`, `fix: handle bluetooth audio disconnect without panicking`, `docs: update adr for tiered acoustic pipeline`.
- **No emojis and no decorative characters.**
- **Strict Local Isolation**: All work and commits remain strictly local until the user explicitly authorizes a remote push. Every `git push` requires fresh, explicit authorization in the live turn.

## Commands Quick Reference

| Action | Command |
| :--- | :--- |
| Check core compilation | `cargo check --all-targets` |
| Run all unit and integration tests | `cargo test --all-targets` |
| Run end-to-end audio pipeline smoke test | `cargo run --example e2e_smoke` |
| Run idle CPU & memory resource benchmark | `cargo run --release --example bench_idle` |
| Run linter / clippy | `cargo clippy --all-targets -- -D warnings` |
| Format codebase | `cargo fmt --check` |

## Testing Standards & Quality Gates

1. **Never Alter Tests to Bypass Failures**: You MUST NEVER modify, weaken, or delete existing tests to force failing code or half-baked implementations to pass. If an existing test breaks, the production implementation is considered defective and must be fixed.
2. **Feature Acceptance Criteria**: A feature is considered successfully implemented ONLY when all automated tests pass (`cargo test`), compiler checks are clean with zero warnings (`cargo check`), and production builds compile cleanly.
3. **Mandatory Happy Path & Edge Case Coverage**: Every new feature, service module, or domain utility MUST be accompanied by comprehensive tests covering both:
   - **Happy Path**: Standard, intended operational flow.
   - **Edge Cases**: Empty audio chunks, silence timeouts, overlapping speech, extreme background noise, hardware disconnects, and malformed inputs.
4. **Mandatory Regression Tests for All Fixed Bugs & Anomalies**: Whenever any bug, unexpected behavior, audio race condition, or runtime anomaly is identified and resolved, a permanent regression test MUST be immediately created. A bug is considered definitively fixed ONLY after its regression test passes as part of the automated suite.

## Invariants & Prohibitions

- **Never perform remote network calls in Phase 1**: `void-notes` Phase 1 is 100% Local-First and offline. All speech processing, transcription, and database operations execute locally.
- **Never run continuous speech-to-text**: Always enforce the 4-stage tiered pipeline (Energy Gate -> KWS -> VAD Endpointing -> On-Demand STT). Running continuous STT is strictly prohibited due to thermal and battery destruction.
- **Never exceed idle resource ceilings**: On a desktop or laptop, idle listening MUST average $< 1.5\%$ CPU load on a single core, and resident memory (RSS) MUST remain $\le 45\text{ MB}$.
- **Never spawn unconstrained Whisper worker threads**: Inference threads MUST be clamped to 2–3 threads with friendly scheduling (`nice -n 10` on Linux) to prevent system audio xruns or interface stutters during active meetings/games.
- **Never write directly to Markdown without prior SQLite transaction**: SQLite with WAL mode and UUID v4 primary keys is the sole transactional authority. Disk Markdown mirroring must occur via asynchronous, fault-tolerant reconciliation.
- **Never panic on audio device disconnection**: Audio capture threads must be decoupled via message-passing channels (`mpsc`) and watched by an automatic reconnection supervisor. Bluetooth or USB headset disconnections must cleanly discard the partial buffer and return to `IDLE`.
- **Never emit audio chimes during active communication or in SilentMeeting mode**: When in a phone call or meeting, passive wake-word detection is suspended, and manual `PriorityOverride` capture must enforce 100% silent feedback (haptics/notifications only).
- **Never commit model weights or local user data**: Model weights (`*.bin`, `*.onnx`), database files (`*.db`, `*.db-wal`), and personal notes (`notes/`) must remain excluded in `.gitignore`.
