# MESA CLI — CyVerse VICE Cloud Shell

A browser-based terminal ([ttyd](https://github.com/tsl0922/ttyd) + `bash` inside `tmux`) for the **MESA** project, built to run as a [CyVerse Discovery Environment (VICE)](https://cyverse.org/discovery-environment) app. It bundles the MESA data-science stack, four AI coding-agent CLIs wired to CyVerse [AI Verde](https://aiverde-docs.cyverse.ai/) LLMs, MESA [MCP](https://modelcontextprotocol.io/) servers, and CyVerse Data Store tooling.

![platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-blue) ![registry](https://img.shields.io/badge/registry-harbor.cyverse.org%2Fvice%2Fmesa--cli-0a7bbb)

## What's inside

| Category | Tools |
| --- | --- |
| **AI agent CLIs** | Claude Code (`claude`), OpenAI Codex (`codex`), OpenCode (`opencode`), Antigravity (`agy`), Claude Code Router (`ccr`) |
| **MCP servers** | `irods` (CyVerse Data Store), `mesa` ([mesa-mcp](https://github.com/idss-mesa/mesa-mcp) + [mesa-ducklake](https://github.com/idss-mesa/mesa-ducklake)), `formation` ([formation-mcp](https://github.com/idss-mesa/formation-mcp), CyVerse DE), `filesystem` — pre-registered for every agent CLI |
| **AI Verde** | `aiverde-setup` helper wires OpenCode + Claude Code (via `ccr`) to `https://llm-api.cyverse.ai` |
| **CyVerse data** | GoCommands (`gocmd`), iRODS config, `s3fs`/OSN mounts (`osn-mount.sh`), AWS CLI |
| **Dev** | GitHub CLI (`gh`), Git Credential Manager, Go 1.25, Node.js 22 |
| **Science** | `geospatial` conda env (GDAL, PDAL, GeoPandas, NumPy/SciPy, …), MiniConda/Mamba |

Base image: `quay.io/jupyter/minimal-notebook` (Ubuntu 24.04, user `jovyan`). Terminal on port **7681**; working dir `/home/jovyan/data-store`.

## Run it

```bash
docker run --rm -p 7681:7681 harbor.cyverse.org/vice/mesa-cli:latest
```

Then open <http://localhost:7681>. `:latest` is `linux/amd64` (cloud servers); `:arm64` is the native Apple Silicon build.

## Sign in to CyVerse

```bash
cyverse-login          # your CyVerse username + password
```

Writes the standard iRODS credential files (`~/.irods/`) so GoCommands, the `mesa`
and `formation` MCP servers, and the agents all act as **you** — with write/own
access to your home and shared collections. Without it you get anonymous, public
read-only access.

For the hosted CyVerse Data Store MCP, Claude Code and OpenCode register **two**
servers: `irods` points at the anonymous
[public endpoint](https://mcp-public.cyverse.ai/mcp) (public data under
`/iplant/home/shared`, no sign-in) and works out of the box; `irods-auth` points
at the [authenticated endpoint](https://mcp.cyverse.ai/mcp), which uses CyVerse's
pre-registered OAuth client (`mcp-client`) to skip the Keycloak
dynamic-registration step that otherwise fails with a "Trusted Hosts" error.

In **Claude Code**, sign in to `irods-auth` once per session to reach your private
home collection:

```bash
claude mcp login irods-auth --no-browser   # opens a kc.cyverse.org URL; paste the redirect back
```

**OpenCode** connects to both endpoints anonymously — because `mcp.cyverse.ai`
answers unauthenticated requests, OpenCode never triggers the interactive login,
so `irods-auth` stays anonymous there. For private-collection access under
OpenCode (and for Codex/Antigravity), rely on `cyverse-login`: the bundled
**local** `mesa`/iRODS MCP servers and `gocmd` read your `~/.irods` credentials
directly (no OAuth) and act as you. Restart an agent after logging in so its MCP
servers pick up the credentials.

## Connect AI Verde LLMs

Each user authenticates with their **own** institutional identity — no API key is baked into the image. Inside the terminal:

```bash
aiverde-setup          # paste your key from chat.cyverse.ai → Course → API Key
```

It validates the key against `/v1/models`, lists your models, and writes `~/.config/aiverde/env` (chmod 600). Then:

- **OpenCode** — uses the `aiverde` provider directly.
- **Claude Code** — uses `ccr` for non-Anthropic models (`ccr code`), or the native `ANTHROPIC_BASE_URL` env path if your course serves Anthropic models.
- **Codex** — *not* wired to AI Verde: Codex dropped Chat Completions support and AI Verde does not serve the Responses API. It runs on its own OpenAI auth.

## Build

The build context is `bash/`. Multi-arch via buildx `TARGETARCH`:

```bash
# arm64 (native on Apple Silicon)
docker buildx build --platform linux/arm64 -t harbor.cyverse.org/vice/mesa-cli:arm64 --load bash/

# amd64 (cloud target)
docker buildx build --platform linux/amd64 -t harbor.cyverse.org/vice/mesa-cli:latest --load bash/
```

> **Building amd64 on Apple Silicon:** the emulated `mamba env create` step fails with `cannot allocate memory` unless you first install the newer QEMU:
> ```bash
> docker run --privileged --rm tonistiigi/binfmt:latest --install amd64
> ```
> The emulated conda solve then succeeds but is slow (~40 min). Prefer a native x86 host or CI for amd64. The Dockerfile copies all config/asset files *after* the conda layer, so editing configs rebuilds in seconds without re-solving conda.

## Layout

```
bash/
  Dockerfile          multi-arch image definition
  entry.sh            container entrypoint (iRODS config, S3 mounts, launches ttyd+tmux)
  01-custom           MESA ANSI splash screen (/etc/motd)
  mesa-prompt.sh      shell prompt (/etc/profile.d)
  environment.yml     geospatial conda env
  osn-mount.sh        s3fs mounts for OSN/S3 buckets
  configs/            agent-CLI configs + aiverde-setup helper
docs/
  mesa-terminal.html  splash-screen design mockup
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/)
- MESA org: <https://github.com/idss-mesa>
