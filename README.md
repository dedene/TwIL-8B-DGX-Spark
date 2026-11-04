# TwIL-8B on a single DGX Spark (llama.cpp, Docker Compose)

Serve [TwIL-8B](https://huggingface.co/webAI-Official/TwIL-8B) on one NVIDIA DGX Spark with stock llama.cpp. One command downloads a pinned GGUF and starts an OpenAI-compatible API with reasoning and tool calls.

TwIL-8B is an 8.8B dense reasoning model from webAI, fine-tuned from IBM's Granite 4.2 8B for math, code and instruction following, with a 131K context window. It comes in two variants that differ in how long they reason: `balanced` (the default) and `verbose`. This recipe serves `balanced` at Q4_K_M, the only GGUF of that variant.

The model card says tool use and agentic tasks were neither trained nor evaluated, and that it is not a general assistant.

**Hardware:** DGX Spark (GB10, sm_121, aarch64), driver 580, CUDA 13, Docker with the NVIDIA Container Toolkit and Compose v2. About 6 GB free disk. With the full 131K context the server takes about 26 GB of the Spark's memory.

## Quickstart

```bash
git clone https://github.com/dedene/TwIL-8B-DGX-Spark.git
cd TwIL-8B-DGX-Spark
docker compose up -d --wait     # download 5.35 GB (first run only), load, wait until healthy
tools/check.py                  # model id, thinking off/on, tool calls and round trip, streaming, Dutch
docker compose down
```

The download checks its sha256; `up --wait` returns once `/health` answers.

The API is at `http://<spark-ip>:8888/v1`, model `twil-8b`. llama-server answers whatever model id a client sends.

```bash
curl http://<spark-ip>:8888/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "twil-8b",
  "messages": [{"role": "user", "content": "Write a Python function that merges overlapping intervals."}],
  "chat_template_kwargs": {"enable_thinking": false}
}'
```

Thinking is on by default, and the card evaluates the model only that way. The reasoning comes back in `message.reasoning_content`, and `max_tokens` counts it, so leave room: the card uses 32,768. `"chat_template_kwargs": {"enable_thinking": false}` turns it off for a request, and `"reasoning_effort": "low"` in the same object shortens it. The server samples with the card's temperature 1.0 and top_p 0.95.

## How it is put together

- **`compose.yaml`:** `download` fetches the pinned GGUF and checks it, then `twil` serves. A healthcheck hits `/health`.
- **`tools/download.sh`:** curl of the pinned Hugging Face revision, resumable, sha256 checked.
- **`tools/serve.sh`:** `llama-server` with all layers on the GPU, flash attention, `--jinja` for the chat template and tool calls, and one KV pool shared by all slots (`--kv-unified`), so one long agent session can use more than its share of `CONTEXT`.
- **`tools/check.py`:** functional checks, plus `--needle N` for a long-context recall test.
- The image is the official arm64 CUDA 13 build of llama.cpp (b12098), pinned by digest. There is no Dockerfile.

## Configuration

Copy `.env.example` to `.env` and uncomment what you want to change, then `docker compose up -d --wait` again.

| Variable | Default | |
|---|---|---|
| `VARIANT` | `balanced` | `balanced` or `verbose`. |
| `QUANT` | `Q4_K_M` | `balanced` ships as `Q4_K_M` only; `verbose` also as `Q8_0` and `F16`. |
| `SPEC` | `none` | `ngram` or `none`. Both lossless. |
| `CONTEXT` | 131072 | Context llama-server allocates (the native window). Slots share it. |
| `PARALLEL` | 1 | Server slots, for concurrent requests. spark-bench-kit wants 4. |
| `UBATCH` | 2048 | Prefill micro-batch. |
| `TEMP`, `TOP_P`, `TOP_K`, `MIN_P` | 1.0, 0.95, 0, 0 | Server defaults; a request can override them. |
| `PORT`, `HOST`, `SERVED_NAME` | 8888, 0.0.0.0, twil-8b | |
| `API_KEY` | empty | Bearer token, when set. |
| `RESTART` | `no` | `unless-stopped` to come back after a reboot. Only one recipe on a port should set it. |
| `MODEL_DIR` | `~/.cache/twil-8b` | Where the GGUF lives. |
| `LLAMA_CPP_IMAGE`, `MODEL_REVISION` | pinned | Re-run `tools/check.py` after a bump. |

## Notes

- Port 8888 clashes with any other recipe that uses it; stop that one first. `PORT=8889` runs next to it.
- The API is open on the LAN unless you set `API_KEY`.
- The GGUFs were not part of webAI's evaluation, and the card expects small deviations, most likely at Q4_K_M.

## Credits

- [webAI](https://huggingface.co/webAI-Official) for TwIL-8B and its GGUFs. The weights are not in this repository.
- [IBM](https://huggingface.co/ibm-granite/granite-4.2-8b) for Granite 4.2 8B, the base model (Apache 2.0).
- The shape of this repository follows [Underdog-Saluki-27B-DGX-Spark](https://github.com/dedene/Underdog-Saluki-27B-DGX-Spark): one Compose project, pinned downloads, and a small check.

## License

MIT, see [LICENSE](LICENSE). The model weights are under the [webAI Non-Commercial License 1.0](https://huggingface.co/webAI-Official/TwIL-8B/blob/main/LICENSE.md): non-commercial research and education only.
