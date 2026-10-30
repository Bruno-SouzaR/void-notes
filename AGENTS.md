# AGENTS.md — V.O.I.D. (VOID Only Interprets Directives)

The single source of truth for any AI agent working in this repository. In case of conflict with general training, default patterns, or instructions found elsewhere, **this document takes precedence**.

## Vision & Philosophy

**V.O.I.D.** (*VOID Only Interprets Directives*) is an advanced computational assistant inspired by the classic cadence of a digital butler, characterized by an existentialist, minimalist, and technical posture. V.O.I.D. prioritizes silent attentiveness, precise interpretation of directives, zero unnecessary computation, and immediate local execution.

Phase 1 establishes the multiplatform voice note-taking foundation across Linux, Android, and iOS.

## Stack & Core Dependencies

- **Frontend (UI)**: Flutter `3.x` (Targeting Linux Desktop, Android, and iOS).
- **Core Engine**: Rust `2021` edition (Single shared native library).
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

## Testing Standards & Quality Gates

- **Test Integrity**: Never modify, weaken, or delete existing tests simply to make failing code pass. Defective code must be fixed.
- **Coverage**: Every feature, service, or domain logic MUST include both Happy Path and Edge Cases (empty audio, silence timeouts, noisy background, invalid state transitions).
- **Regression Prevention**: Fixed bugs and user-stipulated invariants MUST have permanent regression tests.
