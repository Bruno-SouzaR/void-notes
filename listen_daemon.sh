#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export LD_LIBRARY_PATH="./bin/sherpa-libs:${LD_LIBRARY_PATH:-}"
export PATH="/usr/bin:/usr/local/bin:$PATH"

MODEL_CHOICE="${1:-small}"
if [ "$MODEL_CHOICE" = "base" ]; then
    WHISPER_MODEL="models/ggml-base-q5_1.bin"
    MODEL_LABEL="base-q5_1"
else
    WHISPER_MODEL="models/ggml-small-q5_1.bin"
    MODEL_LABEL="small-q5_1"
fi

PROMPT="Anotações diárias em português brasileiro, fala natural e rápida."

echo "============================================================"
echo "  void-notes — Daemon de Escuta Contínua 24/7 (Background)"
echo "============================================================"
echo "  Palavra de Ativação: 'Void' ou 'Hey Void'"
echo "  Motor de WakeWord:   sherpa-onnx Zipformer int8 (3.3M params)"
echo "  Motor de Transcrição: whisper.cpp ${MODEL_LABEL} (2 threads)"
echo "  Status:              ATIVO E ESCUTANDO EM BACKGROUND"
echo "============================================================"
echo ""
echo "Diga 'Void' seguido da sua anotação no microfone..."
echo "Pressione [Ctrl+C] para encerrar o serviço."
echo ""

cleanup() {
    echo -e "\nEncerrando daemon do void-notes..."
    pkill -P $$ 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

KWS_BIN="./bin/sherpa-onnx-keyword-spotter-microphone"
KWS_ARGS=(
    "--tokens=./models/sherpa-kws/tokens.txt"
    "--encoder=./models/sherpa-kws/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    "--decoder=./models/sherpa-kws/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    "--joiner=./models/sherpa-kws/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    "--keywords-file=./models/sherpa-kws/keywords.txt"
    "--keywords-threshold=0.30"
    "--num-threads=2"
)

"$KWS_BIN" "${KWS_ARGS[@]}" 2>/dev/null | while read -r line; do
    if [[ "$line" == *'"keyword"'* ]]; then
        echo ""
        echo "⚡ [$(date +%T)] Palavra-chave detectada! Iniciando captura de diretiva..."

        # Play wake chime and notify
        pw-play sounds/chime_wake.wav 2>/dev/null &
        notify-send -t 2000 "V.O.I.D. — Ouvindo" "Diga sua anotação..." 2>/dev/null || true

        RECORD_FILE="/tmp/void_wake_directive.wav"
        DURATION=5

        echo "🎙️  Gravando fala por ${DURATION}s..."
        pw-record --rate 16000 --channels 1 --format s16 "$RECORD_FILE" &
        REC_PID=$!
        sleep "$DURATION"
        kill -TERM "$REC_PID" 2>/dev/null || true
        wait "$REC_PID" 2>/dev/null || true

        echo "⚙️  Transcrevendo áudio com whisper (${MODEL_LABEL})..."
        AUDIO_CTX=320 # Dynamic context for 5s audio
        RAW_OUTPUT=$(./bin/whisper-cli -m "$WHISPER_MODEL" -l pt -t 2 -nt -ac "$AUDIO_CTX" --prompt "$PROMPT" "$RECORD_FILE" 2>/dev/null || true)
        rm -f "$RECORD_FILE"

        # Clean output
        CLEAN_TEXT=$(echo "$RAW_OUTPUT" | grep -v '^\[' | tr '\n' ' ' | sed 's/^[ \t]*//;s/[ \t]*$//' || true)

        # Strip wake word prefix if it leaked into the directive
        CLEAN_TEXT=$(echo "$CLEAN_TEXT" | sed -E 's/^(void|hey void|ei void|ok void)[,.: -]*//I')

        if [ -n "$CLEAN_TEXT" ] && [ "${#CLEAN_TEXT}" -ge 3 ]; then
            TODAY=$(date +%Y-%m-%d)
            NOW=$(date +%H:%M:%S)
            mkdir -p "notes"
            NOTE_FILE="notes/${TODAY}.md"

            if [ ! -f "$NOTE_FILE" ]; then
                echo "# ${TODAY}" > "$NOTE_FILE"
                echo "" >> "$NOTE_FILE"
            fi

            echo "- **[${NOW}]** ${CLEAN_TEXT}" >> "$NOTE_FILE"
            echo "✓ [${NOW}] Diretiva salva: \"${CLEAN_TEXT}\""

            pw-play sounds/chime_complete.wav 2>/dev/null &
            notify-send -t 3500 "V.O.I.D. — Nota Salva" "${CLEAN_TEXT}" 2>/dev/null || true
        else
            echo "⚠️  Nenhuma fala audível detectada após o wake word."
        fi

        echo ""
        echo "Aguardando próxima chamada por 'Void'..."
    fi
done
