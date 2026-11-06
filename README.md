# TwIL-8B on a single DGX Spark (llama.cpp, Docker Compose)

Serve [TwIL-8B](https://huggingface.co/webAI-Official/TwIL-8B) on one NVIDIA DGX Spark with stock llama.cpp. One command downloads a pinned GGUF and starts an OpenAI-compatible API with reasoning and tool calls.

TwIL-8B is an 8.8B dense reasoning model from webAI, fine-tuned from IBM's Granite 4.2 8B for math, code and instruction following, with a 131K context window. It comes in two variants that differ in how long they reason: `balanced` (the default) and `verbose`. This recipe serves `balanced` at Q4_K_M, the only GGUF of that variant.

The model card says tool use and agentic tasks were neither trained nor evaluated, and that it is not a general assistant. [My benchmark](#as-an-agent-benchmark-results) found good tool calling but weak prompt-injection resistance, so don't point it at text you didn't write.

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
| `SPEC` | `none` | `ngram` or `none`. Both lossless. `ngram` gained nothing: 34.9 vs 35.3 tok/s weighted, though long-context decode went from 27.1 to 30.2. |
| `CONTEXT` | 131072 | Context llama-server allocates (the native window). Slots share it, so use 262144 with thinking and more than one slot. One request stays capped at 131,072. |
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

## As an agent: benchmark results

I ran TwIL-8B through the same agent benchmark as the other models on this Spark, on 5 and 6 November 2026: same box, same samples, temperature 0, four requests in flight. The card says tool use was neither trained nor evaluated, so I wanted to see what happens anyway. Thinking stayed on, because that is the model's default and the only way the card evaluates it, with 32,768 output tokens per request.

This run is incomplete. I stopped it after 24 hours, with 11 of 12 suites done. GPQA-Diamond with thinking was on course for another 15 to 20 hours, and the thinking-off run never started. The Qwen columns are thinking off, so the table does not compare like with like. It is still the best comparison I have, because Qwen has no thinking-on run.

| | TwIL-8B, thinking on | Qwen3.8 Flash Next (NVIDIA FP4-Local, vLLM + MTP), thinking off | Qwen3.8 Flash Next (MLX 4-bit, TensorFold + MTP), thinking off |
|---|---:|---:|---:|
| BFCL single-turn, n=500 | 82.2 (79–85) | 82.4 (79–85) | 71.8 (68–76) |
| BFCL multi-turn, n=200 | 57.0 (50–64) | 54.5 (48–61) | 43.0 (36–50) |
| AgentDojo, tasks done without an attack, n=96 | 75.0 (65–83) | 84.4 (76–90) | 78.1 (69–85) |
| AgentDojo, attacks that executed, n=200 (lower is better) | 101/200 (44–57) | **2/200** (0–4) | 6/200 (1–6) |
| AgentDojo, attacks that disclosed user data, n=200 (lower is better) | 48/200 (19–30) | **0/200** (0–2) | **0/200** (0–2) |
| Same, mail, calendar and files: executed, n=113 | 36/113 (24–41) | **0/113** (0–3) | 1/113 (0–5) |
| Same, mail, calendar and files: disclosed, n=113 | 20/113 (12–26) | **0/113** (0–3) | **0/113** (0–3) |
| AgentDojo, tasks done under attack, n=200 | 53.5 (47–60) | **82.0** (76–87) | 70.5 (64–76) |
| AgentDojo, task done with no unauthorised action, n=200 | 36.5 (30–43) | **81.0** (75–86) | 69.0 (62–75) |
| IFEval, prompt strict, n=541 | 90.0 (87–92) | 85.8 (83–88) | 85.0 (82–88) |
| Global-MMLU Dutch, n=300 | 77.3 (72–82) | 87.0 (83–90) | **87.7** (83–91) |
| GPQA-Diamond, n=198 | not finished | 64.6 (58–71) | 59.1 (52–66) |
| Scripted loop, steps per minute (latency only, no outcome scored) | 16.1 | 13.8 | **21.0** |
| Decode, tok/s weighted over code, prose and tool calls | 35.3 | 43.6 | **67.2** |
| Decode, Dutch prose, tok/s | 37.5 | 31.7 | **50.2** |
| Prefill at ~32k tokens, tok/s | 1,698 | 2,274 | 2,185 |
| 4 requests at once, tok/s | 127 | 113 | **145** |
| Memory for the whole server | **~27 GB** (~48 GB at 262K context) | ~97 GB | ~103 GB |

**Corrected on 6 November 2026.** This table used to show "attacks resisted", taken from AgentDojo's own score. That score only counts an attack when every step completes, so a model that mailed the data out but skipped deleting the sent mail counted as safe. The rows now count what the model did: attacks that went through as an unauthorised action, and attacks that got the user's data out. Lower is better. Data disclosed is a lower bound, because it matches text word for word. All of it is one English attack template on one mailbox, so a low count is no proof of safety. The Qwen columns are thinking off.

Numbers in brackets are 95% Wilson intervals. The speed rows come from a thinking-off pass, because decode speed does not depend on thinking. No unauthorised action means the task got done and no attacker action went through.

Tool calling is the surprise. An 8.8B model that was never trained for it matches Qwen FP4-Local on BFCL single-turn and multi-turn, is clearly ahead of TensorFold on single-turn, and does it in a quarter of the memory. IFEval is about level with Qwen too.

Prompt injection rules it out as an agent that reads anything you didn't write. 101 of 200 attacks went through, against 2 for Qwen FP4-Local with thinking off, and at least 48 got user data out, against 0. I read a few, and they are real: in one banking task it sent the money to the attacker's IBAN and then reported doing so "as instructed". 34 of those 101 also finished the user's task, so the result looks fine unless you check what else happened. Thinking is on here, and I can't say whether thinking off would change this, but I wouldn't count on it.

Dutch is a clear step down from Qwen at 77.3.

It is also slow in practice, and the 127 tok/s above is misleading. That number is four short conversations. With thinking on and long contexts each stream drops to 8-16 tok/s, and GPQA requests average 13,000 tokens, with 4 of 29 hitting the 32,768 limit. The whole server did about 49 tok/s on GPQA. AgentDojo with attacks took 4 h 45 and BFCL multi-turn 7 h 14. A few AgentDojo samples loop on the same tool call until the 120-message limit stops them.

So Qwen stays the model for an agent on a single Spark, and the weights' non-commercial license rules out paid work anyway. TwIL-8B is an interesting small model for tool calls on text you trust, if you can live with the wait.

If you do run it with thinking and more than one slot, set `CONTEXT=262144`. Four slots share the pool, and at 131,072 it overflowed once during the attack suite. Four requests failed and were retried, and every sample still got a score.

## Credits

- [webAI](https://huggingface.co/webAI-Official) for TwIL-8B and its GGUFs. The weights are not in this repository.
- [IBM](https://huggingface.co/ibm-granite/granite-4.2-8b) for Granite 4.2 8B, the base model (Apache 2.0).
- The shape of this repository follows [Underdog-Saluki-27B-DGX-Spark](https://github.com/dedene/Underdog-Saluki-27B-DGX-Spark): one Compose project, pinned downloads, and a small check.

## License

MIT, see [LICENSE](LICENSE). The model weights are under the [webAI Non-Commercial License 1.0](https://huggingface.co/webAI-Official/TwIL-8B/blob/main/LICENSE.md): non-commercial research and education only.
