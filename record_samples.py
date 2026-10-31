#!/usr/bin/env python3
import os
import sys
import subprocess
import time
import wave

def record_snippet(duration_s=2.0):
    """Records duration_s of raw 16kHz s16le PCM from PipeWire."""
    proc = subprocess.Popen(
        ["pw-record", "--raw", "--rate", "16000", "--channels", "1", "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    n_bytes = int(duration_s * 16000 * 2)
    raw = bytearray()
    while len(raw) < n_bytes:
        chunk = proc.stdout.read(min(3200, n_bytes - len(raw)))
        if not chunk:
            break
        raw.extend(chunk)
    proc.terminate()
    proc.wait()
    # Ensure exact 32000 samples (64000 bytes)
    if len(raw) < n_bytes:
        raw.extend(b'\x00' * (n_bytes - len(raw)))
    elif len(raw) > n_bytes:
        raw = raw[:n_bytes]
    return bytes(raw)

def write_wav(filename, raw_pcm, sample_rate=16000):
    with wave.open(filename, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(raw_pcm)

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(base_dir)

    pos_dir = os.path.join(base_dir, "dataset/positive")
    neg_dir = os.path.join(base_dir, "dataset/negative")
    os.makedirs(pos_dir, exist_ok=True)
    os.makedirs(neg_dir, exist_ok=True)

    target_count = 25

    print("============================================================")
    print("  void-notes — Coletor de Voz para Treinamento de 'VOID'")
    print("============================================================")
    print(f"Vamos gravar {target_count} amostras da palavra 'VOID' da sua própria voz.")
    print("Cada gravação dura 2.0 segundos.")
    print("\nOrientações de entonação para um modelo robusto:")
    print("  - Amostras 01 a 05: Fale 'VOID' em tom de conversa normal")
    print("  - Amostras 06 a 10: Fale 'VOID' rápido e natural")
    print("  - Amostras 11 a 15: Fale 'VOID' mais baixo / quase sussurrado")
    print("  - Amostras 16 a 20: Fale 'VOID' um pouco mais distante do microfone")
    print("  - Amostras 21 a 25: Fale 'VOID' firme e com mais energia")
    print("============================================================\n")

    for i in range(1, target_count + 1):
        guidance = ""
        if i <= 5:
            guidance = "(Tom normal)"
        elif i <= 10:
            guidance = "(Rápido)"
        elif i <= 15:
            guidance = "(Mais baixo/sussurrado)"
        elif i <= 20:
            guidance = "(Mais longe do microfone)"
        else:
            guidance = "(Firme/enfático)"

        input(f"[{i:02d}/{target_count}] Pressione [ENTER] e fale 'VOID'... {guidance} ")
        print("  🔴 GRAVANDO (2.0s)... ", end="", flush=True)
        raw = record_snippet(2.0)
        print("✓ Capturado!")

        wav_path = os.path.join(pos_dir, f"void_{i:02d}.wav")
        write_wav(wav_path, raw)
        time.sleep(0.2)

    print("\n============================================================")
    print("  [Etapa Final: Amostra Negativa de Ruído Ambiente]")
    print("============================================================")
    print("Agora vamos gravar 10 segundos de ruído ambiente e silêncio da sua sala.")
    print("Fique em silêncio ou digite no teclado normalmente.")
    input("Pressione [ENTER] para iniciar os 10s de ruído ambiente: ")
    print("  🔴 Gravando ruído ambiente (10s)... ", end="", flush=True)
    ambient_raw = record_snippet(10.0)
    print("✓ Capturado!")

    write_wav(os.path.join(neg_dir, "ambient_room.wav"), ambient_raw)

    print("\n============================================================")
    print(f"  ✓ {target_count} amostras de 'VOID' salvas em '{pos_dir}'!")
    print(f"  ✓ Ruído ambiente salvo em '{neg_dir}'!")
    print("  Pronto para treinar! Execute: ./train_custom_void.py")
    print("============================================================\n")

if __name__ == "__main__":
    main()
