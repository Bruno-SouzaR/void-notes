#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export LD_LIBRARY_PATH="./bin/sherpa-libs:${LD_LIBRARY_PATH:-}"
export PATH="/usr/bin:/usr/local/bin:$PATH"

DIAG_WAV="/tmp/void_diag.wav"

echo "============================================================"
echo "  void-notes — Diagnóstico Completo de Microfone e WakeWord"
echo "============================================================"
echo "Este teste gravará 4 segundos do seu microfone para analisarmos"
echo "o volume real, os fonemas detectados e por que o KWS não ativou."
echo ""
echo "Instrução: Pressione ENTER e diga: 'Hey Void' (ou 'Void') no microfone."
read -p "Pressione [ENTER] para iniciar: "

echo ""
echo "🎙️  FALE AGORA: 'Hey Void' ou 'Void'... (4 segundos)"
pw-record --rate 16000 --channels 1 --format s16 "$DIAG_WAV" &
PID=$!
sleep 4
kill -TERM "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "✓ Gravação concluída. Analisando sinal de áudio..."
echo ""

python3 - <<EOF
import wave, array, math, os, subprocess, sherpa_onnx

wav_path = "$DIAG_WAV"
with wave.open(wav_path, "rb") as w:
    raw = w.readframes(w.getnframes())
    samples = [x / 32768.0 for x in array.array("h", raw)]
    duration_s = len(samples) / 16000.0
    rms = math.sqrt(sum(s*s for s in samples) / len(samples))
    max_peak = max(abs(s) for s in samples)
    non_zeros = sum(1 for s in samples if s != 0.0)

print(f"[1. Nível de Sinal do Microfone]")
print(f"    - Duração gravada:    {duration_s:.2f}s ({len(samples)} amostras)")
print(f"    - Nível RMS:          {rms:.6f}")
print(f"    - Pico Máximo:        {max_peak:.6f}")
print(f"    - Amostras Não-Zero:  {non_zeros} / {len(samples)}")

if non_zeros == 0 or max_peak < 0.005:
    print("\n⚠️  PROBLEMA IDENTIFICADO: O microfone enviou SILÊNCIO QUASE TOTAL.")
    print("    Verifique se o microfone está no mudo físico ou se o ganho está zerado.")
else:
    print("    ✓ Sinal de áudio audível detectado no microfone.")

# 2. Whisper Transcription
print(f"\n[2. O que o Whisper ouve nesse áudio]")
whisper_cmd = [
    "./bin/whisper-cli",
    "-m", "models/ggml-small-q5_1.bin",
    "-l", "pt",
    "-t", "2",
    "-nt",
    "-ac", "256",
    wav_path
]
res = subprocess.run(whisper_cmd, capture_output=True, text=True)
clean_lines = [l.strip() for l in res.stdout.splitlines() if l.strip() and not l.strip().startswith("[") and not l.strip().startswith("whisper_") and not l.strip().startswith("main:")]
transcription = " ".join(clean_lines)
print(f"    - Transcrição Whisper: \"{transcription}\"")

# 3. Sherpa KWS Tokens & Prediction
print(f"\n[3. O que o Sherpa-ONNX KWS analisa nesse áudio]")
kws = sherpa_onnx.KeywordSpotter(
    tokens="models/sherpa-kws/tokens.txt",
    encoder="models/sherpa-kws/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    decoder="models/sherpa-kws/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    joiner="models/sherpa-kws/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    keywords_file="models/sherpa-kws/keywords.txt",
    keywords_threshold=0.15,
    keywords_score=2.5,
    num_threads=2,
)

stream = kws.create_stream()
stream.accept_waveform(16000, samples + [0.0]*8000)

detected_keywords = []
all_tokens = []
while kws.is_ready(stream):
    kws.decode_stream(stream)
    r = kws.get_result(stream)
    toks = kws.tokens(stream)
    if toks:
        all_tokens.extend(toks)
    if r:
        detected_keywords.append(r)

print(f"    - Tokens fonéticos previstos: {list(dict.fromkeys(all_tokens))}")
print(f"    - Palavras-chave disparadas:  {detected_keywords}")

if not detected_keywords:
    print("\n⚠️  O KWS não disparou.")
    print("    Abaixo analisamos os fonemas previstos vs os tokens em keywords.txt.")
else:
    print("\n✓ O KWS disparou com sucesso para este áudio!")
EOF

rm -f "$DIAG_WAV"
echo "============================================================"
