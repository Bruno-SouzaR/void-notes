#!/usr/bin/env python3
import warnings
warnings.filterwarnings('ignore')
import os
import sys
import subprocess
import array
import time
import math
import fcntl
import numpy as np
import openwakeword

def calc_rms(samples):
    if len(samples) == 0:
        return 0.0
    if isinstance(samples, np.ndarray):
        return float(np.sqrt(np.mean(samples ** 2)))
    return math.sqrt(sum(s * s for s in samples) / len(samples))

def write_wav(filename, samples, sample_rate=16000):
    import wave, struct
    with wave.open(filename, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        raw = bytearray()
        for s in samples:
            val = int(max(-1.0, min(1.0, s)) * 32767.0)
            raw.extend(struct.pack('<h', val))
        w.writeframes(raw)

def flush_pipe(pipe):
    """Flushes any accumulated audio frames from the OS pipe buffer."""
    fd = pipe.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    try:
        while True:
            chunk = pipe.read(65536)
            if not chunk:
                break
    except (BlockingIOError, IOError):
        pass
    finally:
        fcntl.fcntl(fd, fcntl.F_SETFL, fl)

def render_meter(rms, is_speech, silence_ms, duration_s):
    bars = int(min(1.0, rms * 30.0) * 12)
    bar_str = "█" * bars + "░" * (12 - bars)
    state_str = "FALA" if is_speech else f"Silêncio {silence_ms}ms/1500ms"
    return f"\r  🎙️ [{bar_str}] {duration_s:4.1f}s | {state_str:<24}"

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(base_dir)

    model_path = os.path.join(base_dir, "models/void_custom.onnx")
    if not os.path.exists(model_path):
        print(f"Erro: Modelo customizado não encontrado em '{model_path}'.")
        print("Grave as amostras com './record_samples.py' e treine com './train_custom_void.py'.")
        sys.exit(1)

    print("============================================================")
    print("  void-notes — Listener com Modelo Customizado 'VOID'")
    print("============================================================")
    print("  Modelo Ativo:        models/void_custom.onnx (Treinado na sua voz)")
    print("  Palavra de Ativação: 'VOID' (palavra única)")
    print("  Entrada de Áudio:    pw-record --raw (PipeWire nativo)")
    print("  Aguardando chamada... Diga 'VOID' no microfone.")
    print("============================================================\n")

    oww_model = openwakeword.Model(
        wakeword_model_paths=[model_path],
    )

    pw_proc = subprocess.Popen(
        ["pw-record", "--raw", "--rate", "16000", "--channels", "1", "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )

    # 80ms chunks = 1280 samples = 2560 bytes (openWakeWord standard)
    chunk_samples = 1280
    chunk_bytes = chunk_samples * 2
    noise_floor = 0.005

    try:
        while True:
            raw = pw_proc.stdout.read(chunk_bytes)
            if not raw or len(raw) < chunk_bytes:
                time.sleep(0.01)
                continue

            i16_arr = np.frombuffer(raw, dtype=np.int16)
            f32_samples = i16_arr.astype(np.float32) / 32768.0

            chunk_rms = calc_rms(f32_samples)
            if chunk_rms < noise_floor * 1.5:
                noise_floor = (0.05 * chunk_rms) + (0.95 * noise_floor)
                noise_floor = max(0.003, noise_floor)

            # Predict with custom model
            predictions = oww_model.predict(i16_arr)
            prob = predictions.get("void_custom", 0.0)

            # Live passive meter (always visible so user sees mic status and confidence)
            bars = int(min(1.0, chunk_rms * 30.0) * 10)
            bar_str = "█" * bars + "░" * (10 - bars)
            sys.stdout.write(f"\r  [●] Ouvindo: [{bar_str}] RMS: {chunk_rms:.4f} | 'VOID': {prob*100:5.1f}%  ")
            sys.stdout.flush()

            if prob >= 0.40:
                now_str = time.strftime("%H:%M:%S")
                print(f"\n\n⚡ [{now_str}] WakeWord 'VOID' Detectado (Confiança: {prob*100:.1f}%)!", flush=True)

                # 1. Play wake chime immediately
                subprocess.run(["pw-play", "sounds/chime_wake.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                subprocess.Popen(["notify-send", "-t", "2000", "V.O.I.D. — Ouvindo", "Diga sua anotação..."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                flush_pipe(pw_proc.stdout)

                # 2. Dynamic Recording Loop
                print("  🎙️ Gravando... (fale no seu ritmo normal, corte automático no silêncio):", flush=True)
                directive_samples = []
                speech_detected = False
                silence_duration_ms = 0
                total_duration_ms = 0

                speech_threshold = max(0.008, noise_floor * 1.8)
                rec_chunk_bytes = 1600 # 50ms chunks

                while True:
                    rec_raw = pw_proc.stdout.read(rec_chunk_bytes)
                    if not rec_raw or len(rec_raw) < rec_chunk_bytes:
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

                    sys.stdout.write(render_meter(rms, rms >= speech_threshold, silence_duration_ms, total_duration_ms / 1000.0))
                    sys.stdout.flush()

                    if speech_detected and silence_duration_ms >= 1500:
                        sys.stdout.write(f"\n  ✓ Fim da fala detectado ({total_duration_ms/1000.0:.1}s gravados)\n")
                        sys.stdout.flush()
                        break

                    if not speech_detected and silence_duration_ms >= 4000:
                        sys.stdout.write("\n  ⚠️ Nenhuma fala detectada após ativação (sessão cancelada).\n")
                        sys.stdout.flush()
                        break

                    if total_duration_ms >= 45000:
                        sys.stdout.write("\n  ✓ Limite máximo de gravação atingido (45s)\n")
                        sys.stdout.flush()
                        break

                # 3. Transcribe if speech was captured
                if speech_detected and len(directive_samples) >= 16000:
                    directive_wav = "/tmp/void_dynamic_directive.wav"
                    write_wav(directive_wav, directive_samples, 16000)

                    print("  ⚙️ Transcrevendo com Whisper small-q5_1...", flush=True)
                    duration_s = len(directive_samples) / 16000.0
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

                    for prefix in ["void", "hey void", "ei void", "ok void"]:
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

                        print(f"  ✓ [{now_str}] Nota salva ({inf_time:.2}s): \"{clean_text}\"", flush=True)
                        subprocess.Popen(["pw-play", "sounds/chime_complete.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.Popen(["notify-send", "-t", "3500", "V.O.I.D. — Nota Salva", clean_text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        print("  ⚠️ Nenhuma fala audível compreendida.", flush=True)

                flush_pipe(pw_proc.stdout)
                oww_model.reset()
                print("\nPronto! Aguardando próxima chamada ('VOID')...\n", flush=True)

    except KeyboardInterrupt:
        print("\nEncerrando listener...", flush=True)
    finally:
        pw_proc.terminate()
        pw_proc.wait()

if __name__ == "__main__":
    main()
