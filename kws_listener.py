#!/usr/bin/env python3
import os
import sys
import subprocess
import array
import time
import sherpa_onnx

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
    print("  void-notes — Listener 24/7 com PipeWire Direto")
    print("============================================================")
    print("  Palavra de ativação: 'Hey Void' ou 'Void'")
    print("  Entrada de áudio:    pw-record (PipeWire nativo)")
    print("  Aguardando chamada... Fale 'Hey Void' no microfone.")
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

    # Spawn pw-record streaming raw 16kHz s16le PCM to stdout
    pw_proc = subprocess.Popen(
        ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )

    stream = kws.create_stream()
    chunk_bytes = 3200 # 100ms chunk at 16kHz 16-bit mono

    try:
        while True:
            raw = pw_proc.stdout.read(chunk_bytes)
            if not raw or len(raw) < 2:
                time.sleep(0.01)
                continue

            i16_arr = array.array('h', raw)
            f32_samples = [x / 32768.0 for x in i16_arr]
            stream.accept_waveform(16000, f32_samples)

            while kws.is_ready(stream):
                kws.decode_stream(stream)
                result = kws.get_result(stream)
                if result:
                    now_str = time.strftime("%H:%M:%S")
                    print(f"\n⚡ [{now_str}] WakeWord Detectado: '{result}'!", flush=True)

                    # Play chime
                    subprocess.Popen(["pw-play", "sounds/chime_wake.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.Popen(["notify-send", "-t", "2000", "V.O.I.D. — Ouvindo", "Diga sua anotação..."], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    # Record directive for 5s
                    directive_wav = "/tmp/void_wake_directive.wav"
                    print("🎙️ Gravando fala por 5s...", flush=True)
                    rec = subprocess.Popen(
                        ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", directive_wav],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    time.sleep(5.0)
                    rec.terminate()
                    rec.wait()

                    # Transcribe with whisper small q5_1
                    print("⚙️ Transcrevendo áudio com whisper (small-q5_1)...", flush=True)
                    whisper_cmd = [
                        "./bin/whisper-cli",
                        "-m", "models/ggml-small-q5_1.bin",
                        "-l", "pt",
                        "-t", "2",
                        "-nt",
                        "-ac", "320",
                        "--prompt", "Anotações diárias em português brasileiro, fala natural e rápida.",
                        directive_wav,
                    ]
                    whisper_res = subprocess.run(whisper_cmd, capture_output=True, text=True)
                    try:
                        os.remove(directive_wav)
                    except OSError:
                        pass

                    raw_text = whisper_res.stdout.strip()
                    clean_lines = [l.strip() for l in raw_text.splitlines() if l.strip() and not l.strip().startswith('[')]
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

                        print(f"✓ [{now_str}] Nota salva: \"{clean_text}\"\n", flush=True)
                        subprocess.Popen(["pw-play", "sounds/chime_complete.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.Popen(["notify-send", "-t", "3500", "V.O.I.D. — Nota Salva", clean_text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        print("⚠️ Nenhuma fala audível detectada após o wake word.\n", flush=True)

                    # Reset stream after handling
                    kws.reset_stream(stream)
                    print("Aguardando próxima chamada por 'Hey Void'...", flush=True)

    except KeyboardInterrupt:
        print("\nEncerrando listener...", flush=True)
    finally:
        pw_proc.terminate()
        pw_proc.wait()

if __name__ == "__main__":
    main()
