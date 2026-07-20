#!/usr/bin/env bash
# aiverde-setup — connect this MESA cloud shell to CyVerse AI Verde LLMs.
#
# AI Verde issues a *per-user* API key that each VICE user obtains by logging
# in with their own institutional identity (CILogon) at
#   https://chat.cyverse.ai  →  Course → API Key tab
# so the key is NEVER baked into this image. This helper captures the key at
# runtime, validates it, and wires it into the pre-installed agent CLIs
# (Codex, OpenCode, and — where supported — Claude Code).
#
# The key is written only to ~/.config/aiverde/env (chmod 600) in this
# ephemeral container home; it is never committed or pushed anywhere.
set -euo pipefail

BASE="${LLM_URL:-https://llm-api.cyverse.ai}"
V1="${BASE%/}/v1"
CFG_DIR="$HOME/.config/aiverde"
ENV_FILE="$CFG_DIR/env"

c_cyan=$'\e[38;2;45;212;191m'; c_green=$'\e[38;2;74;222;128m'
c_orange=$'\e[38;2;212;113;42m'; c_muted=$'\e[38;2;74;98;114m'; c_off=$'\e[0m'

say()  { printf '%s%s%s\n' "$c_cyan" "$1" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_orange" "$1" "$c_off"; }
note() { printf '%s%s%s\n' "$c_muted" "$1" "$c_off"; }

KEY="${1:-${LLM_API_KEY:-}}"
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
Usage: aiverde-setup [API_KEY]

Connect this shell to CyVerse AI Verde. With no argument you are prompted for
your key. Get your key at https://chat.cyverse.ai (Course → API Key tab).

Reads:  LLM_API_KEY / LLM_URL (optional overrides)
Writes: $ENV_FILE (chmod 600) and sources it from ~/.bashrc
EOF
  exit 0
fi

if [ -z "$KEY" ]; then
  say "CyVerse AI Verde setup"
  note "Log in at https://chat.cyverse.ai with your institutional identity,"
  note "open your Course → API Key tab, and copy the key."
  printf '%sPaste your AI Verde API key:%s ' "$c_green" "$c_off"
  read -rs KEY; echo
fi
[ -z "$KEY" ] && { warn "No key entered; aborting."; exit 1; }

# --- validate the key against the models endpoint -------------------------
say "Validating key against $V1/models ..."
resp="$(curl -fsS -L "$V1/models" -H "Authorization: Bearer $KEY" \
        -H 'Content-Type: application/json' 2>/dev/null)" || {
  warn "Could not authenticate to AI Verde. Check the key and try again."
  exit 1
}

models="$(printf '%s' "$resp" | python3 -c \
  'import sys,json; print("\n".join(m["id"] for m in json.load(sys.stdin).get("data",[])))' \
  2>/dev/null || true)"
[ -z "$models" ] && { warn "Authenticated, but no models are visible for this key."; }

say "Available models:"
printf '%s\n' "$models" | sed 's/^/  - /'

# first non-anthropic model is a sensible default for the OpenAI-compatible CLIs
default_model="$(printf '%s\n' "$models" | grep -v '^anthropic/' | head -1 || true)"
[ -z "$default_model" ] && default_model="$(printf '%s\n' "$models" | head -1)"
has_anthropic="$(printf '%s\n' "$models" | grep -c '^anthropic/' || true)"

# --- persist the key (per-user, 600) --------------------------------------
mkdir -p "$CFG_DIR"; chmod 700 "$CFG_DIR"
umask 177
cat > "$ENV_FILE" <<EOF
# CyVerse AI Verde — written by aiverde-setup on first run. chmod 600.
# Delete this file (or rerun aiverde-setup) to change your key.
export LLM_URL="$BASE"
export LLM_API_KEY="$KEY"
# OpenAI-compatible aliases so plain OpenAI SDK code and tools work too
export OPENAI_BASE_URL="$V1"
export OPENAI_API_KEY="$KEY"
export AIVERDE_DEFAULT_MODEL="$default_model"
EOF
chmod 600 "$ENV_FILE"
umask 022

# make every future interactive shell load it
bashrc="$HOME/.bashrc"
srcline='[ -f "$HOME/.config/aiverde/env" ] && . "$HOME/.config/aiverde/env"'
grep -qF "$srcline" "$bashrc" 2>/dev/null || printf '\n# CyVerse AI Verde\n%s\n' "$srcline" >> "$bashrc"

# load into the current shell's parent is not possible from a child process,
# so tell the user to source it (or just open a new shell).
say "Saved to $ENV_FILE (readable only by you)."

# --- Claude Code: pick the documented path for this course ----------------
if [ "${has_anthropic:-0}" -gt 0 ]; then
  # Course serves Anthropic models directly — Claude Code needs only env vars.
  anthropic_model="$(printf '%s\n' "$models" | grep '^anthropic/' | head -1)"
  cat >> "$ENV_FILE" <<EOF
# Claude Code (course has Anthropic models): native Anthropic endpoint
export ANTHROPIC_BASE_URL="$BASE"
export ANTHROPIC_API_KEY="$KEY"
export ANTHROPIC_MODEL="$anthropic_model"
EOF
  say "Claude Code: wired to $anthropic_model — just run 'claude'."
else
  warn "Claude Code: this course exposes no Anthropic models, so Claude Code"
  warn "cannot use AI Verde directly. Use Claude Code Router instead:"
  note "  ccr code        # first run prompts for provider/key/url/model"
  note "  Provider URL:  $V1/chat/completions"
  note "  Your key and models are shown above."
fi

echo
say "Codex:    codex        (provider 'aiverde', model $default_model)"
say "OpenCode: opencode     (provider 'aiverde')"
echo
warn "Run 'source ~/.config/aiverde/env' now, or open a new terminal, to load your key."
