# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Docker image (`harbor.cyverse.org/vice/mesa-cli`) that runs a browser terminal (ttyd → tmux → bash) as a CyVerse VICE app for the MESA project. There is no application code, test suite, or linter: the deliverable is the image, and "the build" means `docker buildx build`. Everything that ships lives under `bash/` (the Docker build context); `docs/` holds the splash-screen HTML mockup and `credential-security-assessment.md`; nothing in `docs/` ships in the image.

## Build commands

Run from the repo root. The build context is `bash/`, not the repo root.

```bash
# arm64 (native on Apple Silicon)
docker buildx build --platform linux/arm64 -t harbor.cyverse.org/vice/mesa-cli:arm64 --load bash/

# amd64 (cloud target, tagged :latest)
docker buildx build --platform linux/amd64 -t harbor.cyverse.org/vice/mesa-cli:latest --load bash/

# or via the Makefile (defaults: platform=linux/amd64, tag=latest)
make -C bash build platform=linux/arm64 tag=arm64
make -C bash push tag=arm64

# smoke test
docker run --rm -p 7681:7681 harbor.cyverse.org/vice/mesa-cli:arm64   # open http://localhost:7681
```

Building amd64 on Apple Silicon needs `docker run --privileged --rm tonistiigi/binfmt:latest --install amd64` first, and the emulated conda solve takes ~40 min. Prefer CI for amd64.

CI (`.github/workflows/harbor.yml`) builds on push to `main`, weekly (Sunday 00:00 UTC), and on manual dispatch, using a native runner per arch: amd64 → `:latest`, arm64 → `:arm64`. `bash/.dockerignore` drops `*.md`, `.github`, and `.git` from the context.

Local builds need the Docker daemon running (`colima start` on this Mac).

## Updating tool versions

Most downloaded tools are pinned by `ARG`s at the top of `bash/Dockerfile`: Go, tini, ttyd, GCM, DuckDB, `ant`, Claude Code, Codex, `ccr`, the filesystem MCP server, OpenCode, Goose. To update, bump the defaults (check `npm view <pkg> version` and the GitHub releases API) and rebuild; `--build-arg NAME=ver` overrides one for a single build. Every one of these `ARG`s is consumed above the `mamba env create` layer, so a bump re-runs the conda solve; moving conda to the top of the jovyan stage would fix that for the npm/OpenCode/Goose installs and is a pending follow-up. Not pinned: Antigravity (`agy`) and GoCommands (no installer pin option), the AWS CLI zip, Node.js (NodeSource `setup_22.x`), and the base image tag `:latest`. Keep `DUCKDB_VERSION` identical for the CLI and the pip wheel in `/opt/mesa`: the DuckLake extension cache under `~/.duckdb/extensions` is keyed by version and platform, and the pre-install step at build time only serves both if they match.

## Dockerfile layering (keep this invariant)

The `mamba env create` step for `environment.yml` is the expensive layer. Every config, script, and asset `COPY` sits **after** it, so edits to the splash, prompt, `entry.sh`, or any `configs/*` rebuild in seconds. Do not move package installs below the config COPYs, and do not move config COPYs above the conda layer. All version `ARG`s are consumed above the conda layer, so a version bump re-solves conda; see "Updating tool versions".

Other Dockerfile gotchas that have bitten before (each is commented inline):
- The base image sets `HOME=/home/jovyan` even for root; keep Go build caches in `/tmp` or they land root-owned in jovyan's home.
- `COPY --chown` does not chown parent dirs it auto-creates, hence the trailing `chown -R 1000:100` on `~/.config`, `~/.codex`, `~/.gemini`.
- `/usr/local/bin/mesa-mcp` is a shim (`configs/mesa-mcp-shim.sh`), not the venv symlink. The symlink must be `rm`'d before the COPY because COPY writes *through* a symlink to its target.
- `mesa-mcp`/`mesa-ducklake` need Python ≥3.11, so they live in their own venv at `/opt/mesa`; the `geospatial` conda env pins 3.10.
- The `ant` tarball is verified against the release's SHA-256 checksums file before install; the binary is located with `find` rather than a hard-coded path inside the archive.
- Arch-specific downloads key off buildx's `TARGETARCH` (amd64/arm64) and translate to each upstream's naming (x86_64/aarch64, x64/arm64).

## Runtime flow

`entry.sh` (ENTRYPOINT) runs once per container: writes `~/.irods/irods_environment.json` from `$IPLANT_USER`, copies `.gitconfig`/`.aws`/`.ssh` from the user's mounted Data Store home (`/data-store/iplant/home/$IPLANT_USER`), s3fs-mounts any buckets declared in `~/.aws/config` under `/osn/<bucket>`, then execs `tini -- ttyd -W tmux new -A -s ttyd bash`. Interactive shells then source `/etc/profile.d/mesa-prompt.sh` and run `/etc/motd` (the `01-custom` splash) via `~/.bashrc`.

Two user-facing helpers are installed to `/usr/local/bin` from `configs/`:
- `cyverse-login` writes `~/.irods/` credentials (via python-irodsclient in `/opt/mesa`) and verifies them. GoCommands, the local `mesa`/`irods` MCP servers, and the agents all read those files.
- `aiverde-setup` validates an AI Verde key against `/v1/models` and writes `~/.config/aiverde/env` (sourced from `~/.bashrc`). It picks the Claude Code path based on whether the course exposes `anthropic/*` models (native env vars vs. `ccr`).

The splash checks for `~/.irods/.irodsA` and `~/.config/aiverde/env` to decide which hints to show, so those paths are contracts between the scripts.

## MCP server registration across the five agent CLIs

Each agent gets the same four servers (`irods`, `mesa`, `formation`, `filesystem`) from a config file in `bash/configs/`, copied to the CLI's expected location. The `filesystem` server runs from the globally installed `mcp-server-filesystem` binary in `~/.npm-global/bin` (pinned at build time), never via `npx -y`, so agents don't fetch code from npm at runtime.

| CLI | Config file | Destination |
| --- | --- | --- |
| Claude Code | `claude.json` | `~/.claude.json` |
| Codex | `codex-config.toml` | `~/.codex/config.toml` |
| OpenCode | `opencode.json` | `~/.config/opencode/opencode.json` |
| Antigravity | `antigravity-mcp_config.json` | `~/.gemini/config/mcp_config.json` |
| Goose | `goose-config.yaml` | `~/.config/goose/config.yaml` |

When changing a server (URL, env var, args), update all five. Intentional differences, documented in the configs and README:
- `irods` is the hosted public HTTP endpoint (`mcp-public.cyverse.ai`) for Claude Code, OpenCode, and Goose, but the local `irods-mcp-server` Go binary for Codex and Antigravity. Only Claude Code also registers `irods-auth` (the authenticated endpoint with the pre-registered `mcp-client` OAuth client); OpenCode would silently stay anonymous against it.
- `formation` is a hosted OAuth remote MCP everywhere; no local binary is built.
- Codex is deliberately not wired to AI Verde (no Responses API on AI Verde); only OpenCode, Goose, and Claude Code (via `ccr`) are.

Never set `MESA_MCP_*` variables to an empty string anywhere (entry.sh, configs, Dockerfile ENV). `mesa-mcp` coerces empty to `None`, fails config validation, and the server dies before the stdio handshake. The shim strips empty ones defensively, but don't rely on it.

## Splash screen and prompt

`01-custom` is a hand-written ANSI truecolor port of `docs/mesa-terminal.html`; `mesa-prompt.sh`, `aiverde-setup.sh`, and `cyverse-login.sh` reuse the same palette (cyan `45;212;191`, green `74;222;128`, orange `212;113;42`, muted `74;98;114`). Change colors in the mockup first, then propagate. The splash is 68 columns wide (`W=68`).

## Security posture

All agents run as `jovyan` with passwordless `sudo` and share one home directory, so every credential a user brings in (`~/.irods`, `~/.aws`, `~/.ssh`, `~/.config/aiverde/env`, each agent's own tokens) is readable by every agent. `docs/credential-security-assessment.md` inventories this and ranks the fixes; read it before touching `entry.sh`, `aiverde-setup.sh`, `cyverse-login.sh`, or the sudoers line. Do not add new `export`s of secrets to `~/.bashrc` or new unconditional dotfile copies in `entry.sh`.

## Things that are duplicated on purpose

`entry.sh` and `osn-mount.sh` both parse `~/.aws/config` and build s3fs options. `entry.sh` is the boot-time automatic mount; `osn-mount.sh` is the user-invoked manual tool. A change to mount options usually belongs in both.
