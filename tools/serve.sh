#!/usr/bin/env bash
# llama-server arguments for TwIL-8B. Sampling defaults follow the model card (temperature 1.0, top_p 0.95); a
# request can override them. Extra arguments from compose are appended.
set -euo pipefail

file="TwIL-8B-${QUANT:-Q4_K_M}-${VARIANT:-balanced}.gguf"
args=(
  --model "/models/${file}"
  --alias "${SERVED_NAME:-twil-8b}"
  --host "${HOST:-0.0.0.0}"
  --port "${PORT:-8888}"
  --jinja
  --reasoning-format deepseek
  --n-gpu-layers all
  --flash-attn on
  --ctx-size "${CONTEXT:-131072}"
  --parallel "${PARALLEL:-1}"
  --kv-unified
  --ubatch-size "${UBATCH:-2048}"
  --temp "${TEMP:-1.0}"
  --top-p "${TOP_P:-0.95}"
  --top-k "${TOP_K:-0}"
  --min-p "${MIN_P:-0}"
)
# Speculative decoding is lossless: the model checks every drafted token. ngram-mod drafts text the reply repeats
# from the prompt or earlier turns.
case ${SPEC:-none} in
  ngram) args+=(--spec-type ngram-mod) ;;
  none) ;;
  *) echo "SPEC must be ngram or none (got ${SPEC})" >&2; exit 1 ;;
esac
[[ -n ${API_KEY:-} ]] && args+=(--api-key "${API_KEY}")

# The image sets LLAMA_ARG_HOST and LLAMA_ARG_PORT, and we pass both ourselves.
unset LLAMA_ARG_HOST LLAMA_ARG_PORT
exec /app/llama-server "${args[@]}" "$@"
