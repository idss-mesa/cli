#!/usr/bin/env bash
# ollama-setup — run the MESA agent CLIs on a local model served by Ollama on
# this container's GPU. The GPU counterpart of `aiverde-setup`: no API key,
# nothing leaves the pod.
# Shared file: keep identical in the five idss-mesa GPU image repos.
set -euo pipefail

DEFAULT_MODEL=qwen3.5:9b
model="${1:-${OLLAMA_DEFAULT_MODEL:-$DEFAULT_MODEL}}"

c_cyan=$'\e[38;2;45;212;191m'; c_green=$'\e[38;2;74;222;128m'
c_orange=$'\e[38;2;212;113;42m'; c_muted=$'\e[38;2;74;98;114m'; c_off=$'\e[0m'
say()  { printf '%s%s%s\n' "$c_cyan" "$1" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_orange" "$1" "$c_off"; }
note() { printf '%s%s%s\n' "$c_muted" "$1" "$c_off"; }
cmd()  { printf '  %s%s%s\n' "$c_green" "$1" "$c_off"; }

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
    cat <<EOF
Usage: ollama-setup [MODEL]

Starts the local Ollama server (if needed), pulls MODEL (default $DEFAULT_MODEL)
and registers it with OpenCode. Then prints how to point Claude Code, Codex and
OpenCode (and Goose, where installed) at it.

Models that fit one 16 GB GPU (A16 / T4):
  qwen3.5:9b    default: coding agents, tool calling, vision, long context
  gpt-oss:20b   larger; Codex's default --oss model (keep context <= 64k)
  gemma4:12b    chat + vision
  qwen3:4b      small and fast
Models are stored in ${OLLAMA_MODELS:-~/.ollama/models} (container-local; they
are gone when the analysis ends). Larger models (qwen3-coder:30b, ...) do not
fit in 16 GB and spill to the CPU.
EOF
    exit 0
fi

mesa-ollama-start >/dev/null
if ! ollama --version >/dev/null 2>&1 || ! curl -fsS -m 3 "http://${OLLAMA_HOST:-127.0.0.1:11434}/api/version" >/dev/null; then
    warn "The Ollama server is not answering; see /tmp/ollama-$(id -u).log"
    exit 1
fi
if ! nvidia-smi -L >/dev/null 2>&1; then
    warn "No NVIDIA GPU visible: Ollama will run on the CPU (slow). Launch the DE app with a GPU."
fi

say "Pulling $model (first time only; several GB) ..."
ollama pull "$model"

# Register the model with OpenCode's pre-configured 'ollama' provider.
oc="$HOME/.config/opencode/opencode.json"
if [ -f "$oc" ]; then
    python3 - "$oc" "$model" "${OLLAMA_CONTEXT_LENGTH:-32768}" <<'EOF' && note "OpenCode: added ollama/$model to $oc"
import json, sys
path, model, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path) as f:
    cfg = json.load(f)
prov = cfg.setdefault("provider", {}).setdefault("ollama", {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Ollama (local GPU)",
    "options": {"baseURL": "http://127.0.0.1:11434/v1"},
    "models": {},
})
models = prov.setdefault("models", {})
if model in models:
    sys.exit(1)
models[model] = {"name": f"{model} (local)", "limit": {"context": ctx, "output": 8192}}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
EOF
fi

ctx="${OLLAMA_CONTEXT_LENGTH:-32768}"
echo
say "Local model ready: $model  (context ${ctx} tokens; server http://${OLLAMA_HOST:-127.0.0.1:11434})"
echo
say "Claude Code"
cmd "ollama launch claude --model $model"
note "  (or: ANTHROPIC_BASE_URL=http://127.0.0.1:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY= claude --model $model)"
say "Codex (needs a model with reliable tool calls; gpt-oss:20b is Codex's default)"
cmd "codex --oss --local-provider ollama -m $model"
say "OpenCode"
cmd "opencode -m ollama/$model"
if command -v goose >/dev/null 2>&1; then
    say "Goose"
    cmd "GOOSE_PROVIDER=ollama GOOSE_MODEL=$model OLLAMA_HOST=http://127.0.0.1:11434 goose session"
fi
say "Python / R / curl (OpenAI-compatible API)"
cmd "http://127.0.0.1:11434/v1   (model \"$model\", any API key)"
echo
note "Ollama keeps a model on the GPU for ${OLLAMA_KEEP_ALIVE:-5m} after its last request;"
note "'ollama stop $model' frees the GPU memory immediately for PyTorch/R jobs."
