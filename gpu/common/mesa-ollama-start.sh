#!/usr/bin/env bash
# mesa-ollama-start — start a local `ollama serve` in the background.
# Shared file: keep identical in the five idss-mesa GPU image repos.
#
#   mesa-ollama-start            start if needed, wait up to 30 s for the API
#   mesa-ollama-start --no-wait  start if needed and return immediately
#
# Idempotent (exits 0 when a server already answers on $OLLAMA_HOST) and never
# fails the caller: the IDE must start even if Ollama cannot. The server binds
# to loopback only (OLLAMA_HOST=127.0.0.1:11434): the Ollama API has no auth
# and a pod IP is reachable from inside the cluster. Models go to
# $OLLAMA_MODELS (default ~/.ollama/models, local disk; never the iRODS
# ~/data-store FUSE mount). CUDA forward-compat is handled by the `ollama`
# wrapper (see /etc/profile.d/mesa-gpu-env.sh).
set -u
: "${OLLAMA_HOST:=127.0.0.1:11434}"
: "${OLLAMA_MODELS:=$HOME/.ollama/models}"
: "${OLLAMA_LOG:=/tmp/ollama-$(id -u).log}"
export OLLAMA_HOST OLLAMA_MODELS

wait=1
[ "${1:-}" = --no-wait ] && wait=0

api="http://${OLLAMA_HOST#http://}/api/version"
up() { curl -fsS -m 2 "$api" >/dev/null 2>&1; }

if up; then
    echo "ollama already running on ${OLLAMA_HOST}"
    exit 0
fi

mkdir -p "$OLLAMA_MODELS" 2>/dev/null || true
setsid nohup ollama serve >>"$OLLAMA_LOG" 2>&1 < /dev/null &

[ "$wait" = 0 ] && exit 0
for _ in $(seq 1 60); do
    if up; then
        echo "ollama up on ${OLLAMA_HOST} (log: $OLLAMA_LOG)"
        exit 0
    fi
    sleep 0.5
done
echo "ollama did not answer within 30 s; see $OLLAMA_LOG" >&2
exit 0
