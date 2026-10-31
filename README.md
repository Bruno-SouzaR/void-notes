# void-notes

> Ultra-lightweight, hands-free voice note-taking application across Linux, Android, and iOS.

`void-notes` provides high-efficiency local voice capture, instant offline transcription, and conflict-free local persistence with minimal CPU and battery footprint.

## Features

- **Continuous Background Wake Word**: Low-power acoustic detection (`"Void"` / `"Hey Void"`) running at `< 1.5%` idle CPU on a single core via a tiered audio pipeline.
- **On-Demand Local STT**: Offline speech-to-text with quantized `whisper.cpp` (`base-q5_1` / `tiny-q5_1`) in Brazilian Portuguese (`pt-BR`).
- **Local-First Architecture**: Notes stored in SQLite with UUID v4 and automatically mirrored to daily Markdown files (`notes/YYYY-MM-DD.md`).
- **Physical Fallbacks**: Global keyboard shortcut on Linux (`Super+Shift+N`), Default Assistant gesture on Android, and Action Button / Siri Shortcuts on iOS.
- **Silent & Meeting Modes**: Fast toggling to suppress audio chimes and rely strictly on haptics and discreet notifications.

## Documentation

- **Product Requirements Document (PRD)**: [`docs/prd/void-voice-notes.md`](docs/prd/void-voice-notes.md)
- **Architecture Decision Records**: [`docs/adr/`](docs/adr/)
- **Agent Rules & Invariants**: [`AGENTS.md`](AGENTS.md)
- **Domain Context**: [`CONTEXT.md`](CONTEXT.md)

## Tech Stack

- **UI**: Flutter (Linux, Android, iOS)
- **Core Engine**: Rust (FFI via `flutter_rust_bridge` v2)
- **Speech Engine**: `whisper.cpp` via `whisper-rs` + `sherpa-onnx` KWS / `microWakeWord`
- **Voice Activity Detection**: `Silero VAD v5` / `libfvad`
- **Database**: SQLite (`rusqlite` WAL mode)
