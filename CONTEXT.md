# void-notes Domain Context

The core domain model for `void-notes`, defining the ubiquitous language governing voice capture, directive transcription, persistence, and feedback.

## Language

### Directives & Persistence

**Directive**:
The spoken thought, instruction, or task uttered by the user intended for interpretation and preservation.
_Avoid_: Command, prompt, speech snippet, utterance

**DirectiveNote**:
The canonical, immutable, timestamped record generated from an interpreted Directive, identified by a client-generated UUID v4.
_Avoid_: Note, memo, reminder, transcription entry, record

**UndoWindow**:
The bounded 8-second time horizon immediately following DirectiveNote persistence during which the record may be revoked and expunged via voice command or physical gesture.
_Avoid_: Grace period, cancel timeout, rollback window, delete buffer

### Acoustic Capture & States

**WakeWord**:
The specific acoustic phonetic signature (`"Void"` or `"Hey Void"`) that primes the assistant into active listening.
_Avoid_: Hotword, keyphrase, invocation tag, trigger phrase

**AcousticWindow**:
The bounded rolling in-memory buffer that continuously caches audio samples to detect wake words and preserve speech headers without disk I/O.
_Avoid_: Audio chunk, sound cache, recording buffer, audio stream

**Endpoint**:
The acoustic boundary marking the definitive cessation of user speech following a Directive, determined by prolonged silence.
_Avoid_: Stop condition, cut point, timeout marker, speech boundary

### Interaction & Operational Modes

**FeedbackProfile**:
The behavioral configuration governing sensory feedback emitted by the assistant upon WakeWord recognition and Directive persistence (`Normal` vs. `SilentMeeting`).
_Avoid_: Sound mode, ring profile, quiet state, volume level

**PriorityOverride**:
The manual hardware gesture or keyboard shortcut that forces immediate Directive capture even when continuous WakeWord listening is suspended due to active calls or meetings.
_Avoid_: Manual bypass, force record, panic button, shortcut trigger
