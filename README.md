# V.O.I.D. — VOID Only Interprets Directives

> An advanced computational assistant inspired by the classic cadence of a digital butler, characterized by an existentialist, minimalist, and technical posture.

V.O.I.D. prioritizes silent attentiveness, precise interpretation of directives, zero unnecessary computation, and immediate local execution.

## Phase 1: Multiplatform Voice Notes Assistant

Phase 1 provides an ultra-lightweight, hands-free voice note-taking system across **Linux**, **Android**, and **iOS**:

- **Continuous Background Wake Word**: Low-power acoustic detection (`"Void"` / `"Hey Void"`) running at `< 1.5%` idle CPU on a single core via a tiered audio pipeline.
- **On-Demand Local STT**: Offline speech-to-text with quantized `whisper.cpp` (`base-q5_1` / `tiny-q5_1`) in Brazilian Portuguese (`pt-BR`).
- **Local-First Architecture**: Notes stored in SQLite with UUID v4 and automatically mirrored to daily Markdown files (`notes/YYYY-MM-DD.md`).
- **Physical Fallbacks**: Global keyboard shortcut on Linux (`Super+Shift+N`), Default Assistant gesture on Android, and Action Button / Siri Shortcuts on iOS.

## Documentation

- **Product Requirements Document (PRD)**: [`docs/prd/void-voice-notes.md`](docs/prd/void-voice-notes.md)
- **Agent Rules & Invariants**: [`AGENTS.md`](AGENTS.md)

## Tech Stack

- **UI**: Flutter (Linux, Android, iOS)
- **Core Engine**: Rust (FFI via `flutter_rust_bridge` v2)
- **Speech Engine**: `whisper.cpp` via `whisper-rs` + `sherpa-onnx` KWS / `microWakeWord`
- **Voice Activity Detection**: `Silero VAD v5` / `libfvad`
- **Database**: SQLite (`rusqlite` WAL mode)
