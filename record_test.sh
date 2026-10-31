#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:$PATH"
DURATION="${1:-5}"
MODEL_CHOICE="${2:-base}"
TEMP_WAV="/tmp/void_test_input.wav"

cd "$(dirname "$0")"

if [ "$MODEL_CHOICE" = "small" ]; then
    MODEL_PATH="models/ggml-small-q5_1.bin"
    MODEL_LABEL="small-q5_1 (244M params, alta fidelidade para fala rápida)"
else
    MODEL_PATH="models/ggml-base-q5_1.bin"
    MODEL_LABEL="base-q5_1 (74M params, ultra-leve)"
fi

PROMPT="Anotações diárias em português brasileiro, fala natural e rápida."

echo "============================================================"
echo "  void-notes — Teste de Precisão do Whisper em Português"
echo "============================================================"
echo "  Duração:  ${DURATION} segundos"
echo "  Modelo:   ${MODEL_LABEL}"
echo "  Prompt:   \"${PROMPT}\""
echo ""

echo "Preparando gravação..."
sleep 0.5
echo "🎙️  FALE NO MICROFONE AGORA... (${DURATION} segundos no seu ritmo normal)"

pw-record --rate 16000 --channels 1 --format s16 "$TEMP_WAV" &
PID=$!
sleep "$DURATION"
kill -TERM "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "✓ Gravação concluída. Transcrevendo áudio com whisper.cpp..."
echo ""

START_TIME=$(date +%s%N)
RAW_OUTPUT=$(./bin/whisper-cli -m "$MODEL_PATH" -l pt -t 2 -nt --prompt "$PROMPT" "$TEMP_WAV" 2>/dev/null)
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
    echo "    - Modelo Usado:        ${MODEL_CHOICE}"
    echo "    - Tempo de Gravação:   ${DURATION}s"
    echo "    - Tempo de Inferência: ${ELAPSED_MS}ms"

    TODAY=$(date +%Y-%m-%d)
    NOW=$(date +%H:%M:%S)
    mkdir -p "notes"
    NOTE_FILE="notes/${TODAY}.md"

    if [ ! -f "$NOTE_FILE" ]; then
        echo "# ${TODAY}" > "$NOTE_FILE"
        echo "" >> "$NOTE_FILE"
    fi

    echo "- **[${NOW}]** ${CLEAN_TEXT}" >> "$NOTE_FILE"
    echo ""
    echo "  ✓ Nota espelhada com sucesso em ${NOTE_FILE}"
else
    echo "  Texto Transcrito Bruto:"
    echo "    \"$RAW_OUTPUT\""
fi
echo "============================================================"
