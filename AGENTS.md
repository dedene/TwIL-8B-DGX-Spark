# AGENTS.md

Serve TwIL-8B (8.79B dense Granite 4.2 fine-tune, official GGUF, balanced Q4_K_M, 5.35 GB) on one DGX Spark with stock
llama.cpp via Docker Compose.

## Layout
- `compose.yaml`: `download` (one-shot curl of the pinned revision, sha256 checked) -> `twil` (llama-server, healthcheck).
  Knobs are `${VAR:-default}` plus `tools/serve.sh`. `.env.example` documents them.
- `tools/download.sh`, `tools/serve.sh`: fetch and launch. The image is the official arm64 CUDA 13 build, so there is no
  Dockerfile. `tools/check.py`: functional checks, stdlib only.
- `VARIANT` + `QUANT` pick the GGUF in both `download.sh` and `serve.sh`: `TwIL-8B-<QUANT>-<VARIANT>.gguf`. balanced only
  ships as Q4_K_M.

## Spark
- `ssh zenjoy@10.0.0.158`, checkout at `~/Development/TwIL-8B-DGX-Spark`, weights in `~/.cache/twil-8b`.
- GB10, sm_121, aarch64, 128 GB unified, driver 580, CUDA 13, Compose v5.
- :8888 is the daily model for Hermes (Qwen3.8 Flash Next on TensorFold or Saluki). Stop it first, or use `PORT=8889`: the
  model fits next to either one with a smaller `CONTEXT`.

## Verify
- `docker compose config --quiet`, `shellcheck tools/*.sh`, `python3 -m py_compile tools/*.py`
- `docker compose up -d --wait`, then `tools/check.py` (all ok).

## Pins
- `ghcr.io/ggml-org/llama.cpp:server-cuda13` at index digest
  `sha256:71f26c2ef2f336418cd42d617db8e479a738a0b9283e327add00e4de633cccfd`. llama.cpp build 12098, commit `149f5641b`.
- Weights `webAI-Official/TwIL-8B@58d49f0d9909e62f9c2fb09e99fc5c76f3f2d630`. File sha256 values are in `tools/download.sh`.

## Model facts
- `GraniteForCausalLM`, 40 layers, hidden size 4096, 32 attention heads, 8 KV heads, vocabulary 100,352, context 131,072.
- The chat template thinks by default: the generation prompt ends in `<think>\n`. `chat_template_kwargs.enable_thinking:
  false` makes it `<think></think>`. `reasoning_effort: "low"` also goes through `chat_template_kwargs`.
- Tool calls use the XML form `<tool_call><function=name><parameter=key>value</parameter></function></tool_call>`.
  llama.cpp parses it with `--jinja`, also after reasoning.
- Card sampling: temperature 1.0, top_p 0.95. Balanced and verbose share architecture, tokenizer and template.
- The card evaluates with thinking on only, and says tool use and agentic tasks were not evaluated or trained.

## Constraints
- Stock llama.cpp; no fork and no Dockerfile.
- Weights are under the webAI Non-Commercial License 1.0 (non-commercial research and education only). Keep that in the
  README, and don't point paid work at this model.
- Never `hf cache prune` on the Spark.
- Credits: write our own scripts.
