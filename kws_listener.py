#!/usr/bin/env python3
import os
import sys
import subprocess
import array
import time
import math
import sherpa_onnx

def calc_rms(samples):
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))

def write_wav(filename, samples, sample_rate=16000):
    import wave, struct
    with wave.open(filename, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        # Convert f32 [-1.0, 1.0] to int16
        raw = bytearray()
        for s in samples:
            val = int(max(-1.0, min(1.0, s)) * 32767.0)
            raw.extend(struct.pack('<h', val))
        w.writeframes(raw)

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(base_dir)

    model_dir = os.path.join(base_dir, "models/sherpa-kws")
    tokens = os.path.join(model_dir, "tokens.txt")
    encoder = os.path.join(model_dir, "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx")
    decoder = os.path.join(model_dir, "decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx")
    joiner = os.path.join(model_dir, "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx")
    keywords = os.path.join(model_dir, "keywords.txt")

    print("============================================================")
    print("  void-notes — Listener Contínuo com Gravação Dinâmica (VAD)")
    print("============================================================")
    print("  Palavra de ativação: 'Hey Void'")
    print("  Gravação:            Dinâmica (corta quando você para de falar)")
    print("  Aguardando chamada... Diga 'Hey Void' no microfone.")
    print("============================================================")

    kws = sherpa_onnx.KeywordSpotter(
        tokens=tokens,
        encoder=encoder,
        decoder=decoder,
        joiner=joiner,
        keywords_file=keywords,
        keywords_threshold=0.25,
        keywords_score=2.0,
        num_threads=2,
    )

    # Spawn continuous 16kHz s16le PCM stream from PipeWire
    pw_proc = subprocess.Popen(
        ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )

    stream = kws.create_stream()
    # 50ms chunks = 800 samples = 1600 bytes
    chunk_samples_count = 800
    chunk_bytes = chunk_samples_count * 2

    # Noise floor baseline
    noise_floor = 0.005

    try:
        while True:
            raw = pw_proc.stdout.read(chunk_bytes)
            if not raw or len(raw) < chunk_bytes:
                time.sleep(0.01)
                continue

            i16_arr = array.array('h', raw)
            f32_chunk = [x / 32768.0 for x in i16_arr]

            # Feed to KWS stream
            stream.accept_waveform(16000, f32_chunk)

            while kws.is_ready(stream):
                kws.decode_stream(stream)
                result = kws.get_result(stream)
                if result:
                    now_str = time.strftime("%H:%M:%S")
                    print(f"\n⚡ [{now_str}] WakeWord Detectado: '{result}'!", flush=True)

                    # 1. Play wake chime immediately in foreground so it sounds BEFORE recording speech
                    print("🔔 Tocando sinal de ativação...", flush=True)
                    subprocess.run(["pw-play", "sounds/chime_wake.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.Popen(["notify-send", "-t", "2000", "V.O.I.D. — Ouvindo", "Fale sua anotação..."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    # 2. Dynamic Recording Loop
                    print("🎙️ Ouvindo... (fale no seu ritmo normal, corte automático no silêncio)", flush=True)
                    directive_samples = []
                    speech_detected = False
                    silence_duration_ms = 0
                    total_duration_ms = 0

                    speech_threshold = max(0.007, noise_floor * 2.0)

                    while True:
                        rec_raw = pw_proc.stdout.read(chunk_bytes)
                        if not rec_raw or len(rec_raw) < chunk_bytes:
                            time.sleep(0.01)
                            continue

                        rec_i16 = array.array('h', rec_raw)
                        rec_f32 = [x / 32768.0 for x in rec_i16]
                        directive_samples.extend(rec_f32)

                        total_duration_ms += 50
                        rms = calc_rms(rec_f32)

                        if rms >= speech_threshold:
                            speech_detected = True
                            silence_duration_ms = 0
                        else:
                            silence_duration_ms += 50

                        # Endpointing condition: user spoke and then paused for > 1500ms
                        if speech_detected and silence_duration_ms >= 1500:
                            print(f"      ✓ Fim da fala detectado ({total_duration_ms/1000.0:.1}s gravados)", flush=True)
                            break

                        # Anti-ghost note: no speech at all within 4.0s of wake word
                        if not speech_detected and silence_duration_ms >= 4000:
                            print("      ⚠️ Nenhuma fala detectada após ativação (sessão abortada).", flush=True)
                            break

                        # Safety cap at 45 seconds
                        if total_duration_ms >= 45000:
                            print("      ✓ Limite máximo de gravação atingido (45s)", flush=True)
                            break

                    # 3. Transcribe if speech was captured
                    if speech_detected and len(directive_samples) >= 16000:
                        directive_wav = "/tmp/void_dynamic_directive.wav"
                        write_wav(directive_wav, directive_samples, 16000)

                        print("⚙️ Transcrevendo áudio com whisper (small-q5_1)...", flush=True)
                        duration_s = len(directive_samples) / 16000.0
                        # Dynamic audio context: duration_ms / 20 + 64 headroom, aligned to 64
                        duration_ms = int(duration_s * 1000)
                        raw_frames = (duration_ms + 19) // 20
                        with_headroom = raw_frames + 64
                        audio_ctx = ((with_headroom + 63) // 64) * 64
                        audio_ctx = max(128, min(1500, audio_ctx))

                        whisper_cmd = [
                            "./bin/whisper-cli",
                            "-m", "models/ggml-small-q5_1.bin",
                            "-l", "pt",
                            "-t", "2",
                            "-nt",
                            "-ac", str(audio_ctx),
                            "--prompt", "Anotações diárias em português brasileiro, fala natural e rápida.",
                            directive_wav,
                        ]
                        start_inf = time.time()
                        whisper_res = subprocess.run(whisper_cmd, capture_output=True, text=True)
                        inf_time = time.time() - start_inf

                        try:
                            os.remove(directive_wav)
                        except OSError:
                            pass

                        raw_text = whisper_res.stdout.strip()
                        clean_lines = [l.strip() for l in raw_text.splitlines() if l.strip() and not l.strip().startswith('[') and not l.strip().startswith('whisper_') and not l.strip().startswith('main:')]
                        clean_text = " ".join(clean_lines)

                        # Strip wake word if leaked
                        for prefix in ["hey void", "void", "ei void", "ok void"]:
                            if clean_text.lower().startswith(prefix):
                                clean_text = clean_text[len(prefix):].lstrip(" ,.:-")

                        if len(clean_text) >= 3:
                            today_str = time.strftime("%Y-%m-%d")
                            os.makedirs("notes", exist_ok=True)
                            note_path = os.path.join("notes", f"{today_str}.md")
                            first_time = not os.path.exists(note_path)

                            with open(note_path, "a", encoding="utf-8") as f:
                                if first_time:
                                    f.write(f"# {today_str}\n\n")
                                f.write(f"- **[{now_str}]** {clean_text}\n")

                            print(f"✓ [{now_str}] Nota salva ({inf_time:.2}s): \"{clean_text}\"\n", flush=True)

                            # Play completion chime and notify
                            subprocess.Popen(["pw-play", "sounds/chime_complete.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            subprocess.Popen(["notify-send", "-t", "3500", "V.O.I.D. — Nota Salva", clean_text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        else:
                            print("⚠️ Nenhuma fala audível compreendida.\n", flush=True)

                    # Reset stream and flush buffer
                    kws.reset_stream(stream)
                    print("Aguardando próxima chamada por 'Hey Void'...\n", flush=True)

    except KeyboardInterrupt:
        print("\nEncerrando listener...", flush=True)
    finally:
        pw_proc.terminate()
        pw_proc.wait()

if __name__ == "__main__":
    main()
