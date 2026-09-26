#!/usr/bin/env python3
"""Build-time helper: register the local Ollama server with the MESA agent CLIs.

Shared file: keep identical in the five idss-mesa GPU image repos.

    patch-agent-configs.py --opencode ~/.config/opencode/opencode.json \
                           --codex ~/.codex/config.toml

* OpenCode: adds an 'ollama' provider (OpenAI-compatible, http://127.0.0.1:11434/v1)
  next to the existing 'aiverde' provider. The default model is unchanged.
* Codex: sets oss_provider = "ollama" so `codex --oss` uses the local server.

Idempotent; paths that do not exist are skipped.
"""
import argparse
import json
import os

CONTEXT = 32768
MODELS = {
    "qwen3.5:9b": "Qwen3.5 9B (local GPU)",
    "gpt-oss:20b": "gpt-oss 20B (local GPU)",
    "gemma4:12b": "Gemma 4 12B (local GPU)",
    "qwen3:4b": "Qwen3 4B (local GPU)",
}


def patch_opencode(path):
    with open(path) as f:
        cfg = json.load(f)
    provider = cfg.setdefault("provider", {})
    provider.setdefault("ollama", {
        "npm": "@ai-sdk/openai-compatible",
        "name": "Ollama (local GPU)",
        "options": {"baseURL": "http://127.0.0.1:11434/v1"},
        "models": {
            name: {"name": label, "limit": {"context": CONTEXT, "output": 8192}}
            for name, label in MODELS.items()
        },
    })
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")


def patch_codex(path):
    with open(path) as f:
        text = f.read()
    if "oss_provider" in text:
        return
    # Top-level keys must precede the first [table] header.
    line = ('# `codex --oss` uses the local Ollama server (MESA GPU image; see ollama-setup)\n'
            'oss_provider = "ollama"\n\n')
    lines = text.splitlines(keepends=True)
    idx = next((i for i, l in enumerate(lines) if l.lstrip().startswith("[")), len(lines))
    lines.insert(idx, line)
    with open(path, "w") as f:
        f.write("".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--opencode", action="append", default=[])
    ap.add_argument("--codex", action="append", default=[])
    args = ap.parse_args()
    for p in args.opencode:
        if os.path.exists(p):
            patch_opencode(p)
            print(f"opencode: ollama provider -> {p}")
    for p in args.codex:
        if os.path.exists(p):
            patch_codex(p)
            print(f"codex: oss_provider=ollama -> {p}")


if __name__ == "__main__":
    main()
