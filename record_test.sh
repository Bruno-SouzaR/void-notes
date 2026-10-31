#!/usr/bin/env bash
set -euo pipefail

DURATION="${1:-4}"
TEMP_WAV="/tmp/void_test_input.wav"

cd "$(dirname "$0")"

echo "============================================================"
echo "  void-notes — Teste Rápido de Áudio e Precisão do Whisper"
echo "============================================================"
echo "  Duração da gravação: ${DURATION} segundos"
echo "  Modelo: models/ggml-base-q5_1.bin (PT-BR quantizado)"
echo ""

echo "Preparando gravação..."
sleep 0.5
echo "🎙️  FALE NO MICROFONE AGORA... (${DURATION} segundos)"

pw-record --rate 16000 --channels 1 --format s16 "$TEMP_WAV" &
PID=$!
sleep "$DURATION"
kill -TERM "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "✓ Gravação concluída. Transcrevendo áudio com whisper.cpp..."
echo ""

START_TIME=$(date +%s%N)
RAW_OUTPUT=$(./bin/whisper-cli -m ./models/ggml-base-q5_1.bin -l pt -t 2 -nt "$TEMP_WAV" 2>/dev/null)
END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

rm -f "$TEMP_WAV"

# Clean out any bracketed tags or status lines
CLEAN_TEXT=$(echo "$RAW_OUTPUT" | grep -v '^\[' | tr '\n' ' ' | sed 's/^[ \t]*//;s/[ \t]*$//')

echo "============================================================"
echo "  RESULTADO DO TESTE DE PRECISÃO"
echo "============================================================"
if [ -n "$CLEAN_TEXT" ]; then
    echo "  Texto Transcrito:"
    echo "    \"$CLEAN_TEXT\""
    echo ""
    echo "  Métricas:"
    echo "    - Tempo de Gravação:   ${DURATION}s"
    echo "    - Tempo de Inferência: ${ELAPSED_MS}ms"
else
    echo "  Texto Transcrito Bruto:"
    echo "    \"$RAW_OUTPUT\""
fi
echo "============================================================"
