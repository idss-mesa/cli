# MESA CLI — CyVerse VICE Cloud Shell

A browser-based terminal ([ttyd](https://github.com/tsl0922/ttyd) + `bash` inside `tmux`) for the **MESA** project, built to run as a [CyVerse Discovery Environment (VICE)](https://cyverse.org/discovery-environment) app. It bundles the MESA data-science stack, five AI coding-agent CLIs wired to CyVerse [AI Verde](https://aiverde-docs.cyverse.ai/) LLMs, MESA [MCP](https://modelcontextprotocol.io/) servers, and CyVerse Data Store tooling.

![platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%7C%20linux%2Farm64-blue) ![registry](https://img.shields.io/badge/registry-harbor.cyverse.org%2Fvice%2Fmesa--cli-0a7bbb)

## What's inside

| Category | Tools |
| --- | --- |
| **AI agent CLIs** | Claude Code (`claude`), OpenAI Codex (`codex`), OpenCode (`opencode`), Goose (`goose`), Antigravity (`agy`), Claude Code Router (`ccr`) |
| **MCP servers** | `irods` (CyVerse Data Store), `mesa` ([mesa-mcp](https://github.com/idss-mesa/mesa-mcp) + [mesa-ducklake](https://github.com/idss-mesa/mesa-ducklake), pinned to `v0.2.0` on DuckDB 2.0: catalog files it creates cannot be opened by DuckDB 1.x), `formation` ([formation-mcp](https://github.com/idss-mesa/formation-mcp), CyVerse DE), `filesystem` — pre-registered for every agent CLI |
| **DuckDB** | DuckDB 2.0.0: `duckdb` CLI and `import duckdb` in the conda base Python. Not in the `geospatial` env (Python 3.10; DuckDB 2.0's Python client needs ≥ 3.11), so use the CLI or base Python there. Same major as `mesa`, so it opens the catalogs mesa-ducklake writes |
| **AI Verde** | `aiverde-setup` helper wires OpenCode, Goose + Claude Code (via `ccr`) to `https://llm-api.cyverse.ai` |
| **CyVerse data** | GoCommands (`gocmd`), iRODS config, `s3fs`/OSN mounts (`osn-mount.sh`), AWS CLI |
| **Dev** | GitHub CLI (`gh`), Git Credential Manager, Go 1.25, Node.js 22 |
| **Science** | `geospatial` conda env (GDAL, PDAL, GeoPandas, NumPy/SciPy, …), MiniConda/Mamba |

Base image: `quay.io/jupyter/minimal-notebook` (Ubuntu 24.04, user `jovyan`). Terminal on port **7681**; working dir `/home/jovyan/data-store`.

## Run it

```bash
docker run --rm -p 7681:7681 harbor.cyverse.org/vice/mesa-cli:latest
```

Then open <http://localhost:7681>. `:latest` is `linux/amd64` (cloud servers); `:arm64` is the native Apple Silicon build.

## DE tool settings

These live in the Discovery Environment, not in this repo, and must match the image. Change them only together with the Dockerfile.

| Setting | Value |
| --- | --- |
| DE app | **MESA Cloud Shell** (`34050904-86f9-11f1-beaf-008cfa5ae3e1`) |
| DE tool (version `1.1.0`) | `mesa-cli` (`2e106bb0-86f9-11f1-a992-008cfa5ae3e1`) |
| Image | `harbor.cyverse.org/vice/mesa-cli:latest` |
| Type | interactive |
| Network mode | `bridge` (Terrain's default `none` gives an analysis that runs but never serves) |
| Skip /tmp mount | `true` |
| VICE proxy | `interactive_apps` = cas-proxy (`discoenv/cas-proxy`) |
| Container port | **7681** (ttyd) |
| Working directory | `/home/jovyan/data-store` (the Data Store CSI mount point) |
| UID | 1000 |
| PIDs limit | 1024 |
| Entrypoint override | none (the image's own startup script does the MESA per-user setup) |
| Max CPU | 32 cores |
| Memory limit | 128 GiB |

## Sign in to CyVerse

```bash
cyverse-login          # your CyVerse username + password
```

Writes the standard iRODS credential files (`~/.irods/`) so GoCommands, the `mesa`
and `formation` MCP servers, and the agents all act as **you** — with write/own
access to your home and shared collections. Without it you get anonymous, public
read-only access.

For the hosted CyVerse Data Store MCP, **Claude Code** registers **two** servers:
`irods` points at the anonymous
[public endpoint](https://mcp-public.cyverse.ai/mcp) (public data under
`/iplant/home/shared`, no sign-in) and works out of the box; `irods-auth` points
at the [authenticated endpoint](https://mcp.cyverse.ai/mcp), which uses CyVerse's
pre-registered OAuth client (`mcp-client`) to skip the Keycloak
dynamic-registration step that otherwise fails with a "Trusted Hosts" error. Sign
in to `irods-auth` once per session to reach your private home collection:

```bash
claude mcp login irods-auth --no-browser   # opens a kc.cyverse.org URL; paste the redirect back
```

**OpenCode** registers only the anonymous public `irods` server: because
`mcp.cyverse.ai` answers unauthenticated requests, OpenCode never triggers the
interactive login, so a hosted authenticated entry would stay anonymous anyway.
For private-collection access under OpenCode (and for Codex/Antigravity), rely on
`cyverse-login`: the bundled **local** `mesa`/iRODS MCP servers and `gocmd` read
your `~/.irods` credentials directly (no OAuth) and act as you. Restart an agent
after logging in so its MCP servers pick up the credentials.

## Connect AI Verde LLMs

Each user authenticates with their **own** institutional identity — no API key is baked into the image. Inside the terminal:

```bash
aiverde-setup          # paste your key from chat.cyverse.ai → Course → API Key
```

It validates the key against `/v1/models`, lists your models, and writes `~/.config/aiverde/env` (chmod 600). Then:

- **OpenCode** — uses the `aiverde` provider directly.
- **Goose** — uses the `openai` provider pointed at AI Verde (`goose`).
- **Claude Code** — uses `ccr` for non-Anthropic models (`ccr code`), or the native `ANTHROPIC_BASE_URL` env path if your course serves Anthropic models.
- **Codex** — *not* wired to AI Verde: Codex dropped Chat Completions support and AI Verde does not serve the Responses API. It runs on its own OpenAI auth.

## GPU variant (`:gpu`)

`harbor.cyverse.org/vice/mesa-cli:gpu` is this image plus an NVIDIA GPU layer ([`gpu/Dockerfile`](gpu/Dockerfile) builds `FROM` `:latest`, `linux/amd64` only), for the DE's GPU nodes (NVIDIA A16, 16 GB). Everything above works the same; the layer adds:

| Category | Tools |
| --- | --- |
| **PyTorch** | `torch` 2.14 + `torchvision` 0.29, CUDA 12.6 build, in the conda **base** env (Python 3.13) — the terminal's default `python` |
| **ML** | `transformers`, `accelerate`, `huggingface_hub` (`hf` CLI) |
| **Local LLMs** | [Ollama](https://ollama.com) 0.34.4, started in the background on `127.0.0.1:11434`; `ollama-setup`; `ollama` Python client. OpenCode gets an `ollama` provider, Codex `oss_provider = "ollama"` |
| **GPU tools** | `mesa-gpu-check`, `nvtop`, `nvitop`; `gcc` so `torch.compile` (Triton) works |
| **CUDA** | `cuda-compat-13-4` forward-compat driver (used only on pre-R580 hosts, see below). No NVIDIA driver is baked in (the container runtime injects the host's), and an apt pin keeps it that way |

The GPU image is about **17.7 GB** uncompressed (CPU `:latest`: 7.8 GB). Most of the difference is PyTorch plus its CUDA 12 wheels (6.8 GB) and Ollama (2.2 GB); the forward-compat driver adds 0.5 GB.

### Run it locally

Needs an NVIDIA GPU with its driver and [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/):

```bash
docker run --rm --gpus all -p 127.0.0.1:7681:7681 harbor.cyverse.org/vice/mesa-cli:gpu     # or: make run-gpu
```

Then open <http://localhost:7681>. The port is bound to loopback because outside VICE the terminal is unauthenticated (on VICE the cas-proxy does the login) and `jovyan` has passwordless `sudo`. For a remote GPU server, tunnel instead of publishing the port: `ssh -L 7681:127.0.0.1:7681 <gpu-host>`. The landing screen shows the GPU, the driver and whether Ollama is running.

### PyTorch in the terminal

The terminal (ttyd → tmux → interactive, non-login `bash`) activates the conda **base** env, so `python` and `pip` are `/opt/conda/bin/python` with CUDA PyTorch:

```bash
python -c 'import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))'
```

`conda activate geospatial` and login shells switch to the geospatial env (Python 3.10, **no** torch). Login shells are `bash -l` **and every new tmux window or pane** (`Ctrl-b c`, `Ctrl-b %`, `Ctrl-b "`), because tmux starts them as login shells and `~/.bash_profile` activates `geospatial`; only the terminal's first window is on base. Check with `which python`. Get back with `conda activate base`, or call `/opt/conda/bin/python` directly (e.g. `#!/opt/conda/bin/python` in scripts). To add packages without swapping torch for PyPI's CUDA 13 build:

```bash
pip install -c /etc/mesa/torch-constraints.txt --extra-index-url https://download.pytorch.org/whl/cu126 <package>
```

### Local LLMs (Ollama)

The agents can run on a local model on the GPU, with no API key:

```bash
ollama-setup                  # pulls qwen3.5:9b (default) and prints the commands below
ollama-setup gpt-oss:20b      # or another model; ollama-setup --help lists the ones that fit
```

| Agent | Command |
| --- | --- |
| Claude Code | `ollama launch claude --model qwen3.5:9b` |
| Codex | `codex --oss --local-provider ollama -m qwen3.5:9b` |
| OpenCode | `opencode -m ollama/qwen3.5:9b` |
| Goose | `GOOSE_PROVIDER=ollama GOOSE_MODEL=qwen3.5:9b OLLAMA_HOST=http://127.0.0.1:11434 goose session` |
| Python / curl | OpenAI-compatible API at `http://127.0.0.1:11434/v1` |

One 16 GB GPU fits `qwen3.5:9b`, `gemma4:12b`, `qwen3:4b` and `gpt-oss:20b` (keep its context ≤ 64k); 30B+ models spill to the CPU. The context defaults to 32k tokens (`OLLAMA_CONTEXT_LENGTH`). Models go to `~/.ollama/models` (container disk; gone when the analysis ends — not the Data Store). Ollama keeps a model on the GPU for 5 min after its last request; `ollama stop <model>` frees the memory for PyTorch. The server listens on loopback only; `MESA_OLLAMA_AUTOSTART=0` skips starting it (see [switches](#cuda-and-driver-compatibility)).

### Check the GPU

```bash
mesa-gpu-check            # driver, libcuda, CUDA forward-compat, PyTorch (matmul + cuDNN), Ollama
mesa-gpu-check --ollama   # also pulls qwen3:0.6b (~0.5 GB) and confirms it runs 100% on the GPU
```

It exits non-zero with `no NVIDIA GPU in this container` when the app was launched without a GPU.

### CUDA and driver compatibility

- **PyTorch** (cu126) runs on any driver ≥ R525 — T4, A16, A100 — with nothing extra.
- **Ollama 0.34.4** needs R550+ for its CUDA 12 runner and R580+ for CUDA 13; other CUDA 13 software needs R580+. On pre-R580 drivers (e.g. R535), `/etc/profile.d/mesa-gpu-env.sh` (run by the entrypoint, again by `ollama serve`, and from `/etc/bash.bashrc` for `docker exec`/`kubectl exec` shells) puts NVIDIA's forward-compat driver `$MESA_CUDA_COMPAT_DIR` (`/usr/local/cuda-13.4/compat`) first on `LD_LIBRARY_PATH` — only when the host's CUDA API is < 13 **and** `cuInit` succeeds with it (data-center GPUs only). R580+ hosts are left alone. `MESA_DISABLE_CUDA_COMPAT=1` opts out.
- **Switches are read at container start.** `MESA_OLLAMA_AUTOSTART` and `MESA_DISABLE_CUDA_COMPAT` are read by the entrypoint before the terminal starts, so exporting them in a shell or a `~/.env`-style file changes nothing. On VICE set them as environment variables of the DE app; locally `docker run -e MESA_OLLAMA_AUTOSTART=0 ...`.
- **No driver packages.** `/etc/apt/preferences.d/mesa-no-nvidia-driver` pins `nvidia-driver-*`, `libnvidia-*`, `nvidia-utils-*`, `cuda-drivers` and friends to priority -1, so `sudo apt install` cannot pull a driver userspace that would shadow the injected host driver (`nvidia-smi`: *Driver/library version mismatch*). CUDA toolkit packages (`cuda-toolkit-12-x`, `cuda-nvcc-12-x`) still install. To install a driver package on purpose, `sudo rm` that file first.
- The image sets `NVIDIA_DRIVER_CAPABILITIES=compute,utility` and deliberately not `NVIDIA_VISIBLE_DEVICES` (the DE's device plugin / `docker --gpus` set it).

### Build & publish from a GPU server

`docker build` never uses the GPU, so the image is the same on any x86_64 host with Docker + buildx and ~40 GB free disk; only `make test-gpu` needs an NVIDIA GPU (driver + nvidia-container-toolkit). On a GPU build host (e.g. the A100 server):

```bash
git clone https://github.com/idss-mesa/cli.git && cd cli
docker login harbor.cyverse.org
make pull-base build-gpu test-gpu push-gpu      # GPU=<n> make test-gpu tests on GPU n (default 0; GPU=all)
```

- `pull-base` fetches the published CPU `:latest` the layer builds on, and `build-gpu` prints that base's digest (note it in the push message). `:latest` is rebuilt weekly (Sunday 00:00 UTC) and on pushes to `main` (except ones touching only `gpu/`, `harbor-gpu.yml`, `README.md`, `.gitignore` or the root `Makefile`); to build on one specific CPU image run `make build-gpu base_image=harbor.cyverse.org/vice/mesa-cli@sha256:<digest>`. `make build build-gpu` layers on a fresh local CPU build instead.
- `test-gpu` ([`gpu/test-gpu.sh`](gpu/test-gpu.sh), ~4 min) checks the host driver is injected and none is baked in (and, given network for `apt-get update`, that the apt pin refuses driver packages; SKIP without), starts the image like VICE (`--user 1000`) until ttyd answers (and Docker reports it healthy), runs `mesa-gpu-check --ollama`, opens a real ttyd terminal to check `python`/torch/`torch.compile` and `bash -l`, checks a `docker exec ... bash -i` shell gets the same forward-compat env and `nvitop`, and repeats without a GPU. It must pass before `push-gpu`.
- Version pins are build args in `gpu/Dockerfile` (`TORCH_INDEX_URL`, `TORCH_VERSION`, `TORCHVISION_VERSION`, `OLLAMA_VERSION`/`OLLAMA_SHA256`, `CUDA_COMPAT_VERSION`). `CUDA_COMPAT_VERSION` (13.4) is the single compat pin: it sets both the `cuda-compat-13-4` package and `MESA_CUDA_COMPAT_DIR` (`/usr/local/cuda-13.4/compat`), and the build fails if that directory has no `libcuda.so.1`. Each pin is declared just above the first `RUN` that uses it, and cuda-compat and Ollama are installed after the PyTorch layers, so bumping `CUDA_COMPAT_VERSION` or `OLLAMA_*` does not rebuild or re-push the ~7 GB torch layer. Move `TORCH_INDEX_URL` to `.../cu130` once every DE GPU node runs R580+.
- CI alternative: **Actions → harbor-gpu → Run workflow** ([`.github/workflows/harbor-gpu.yml`](.github/workflows/harbor-gpu.yml); manual only, pins the CPU base by digest, builds and pushes without GPU tests). This repo has no `security.yml` (no hadolint/Trivy CI).

### DE tool settings (GPU)

The DE app is a copy of the CPU app pointing at a separate GPU tool. [`gpu/de-tool.json`](gpu/de-tool.json) is the tool-import body for `POST /terrain/admin/tools` (admin only: `container_devices` and a memory limit above 16 GiB are refused on the private tools API; replace `<email>`).

| Setting | Value |
| --- | --- |
| DE app | **MESA Cloud Shell (GPU)** (`6ac0f7c4-ba88-11f1-a02a-008cfa5ae3e1`, private) |
| DE tool (version `1.1.0`) | `mesa-cli-gpu` (`2b026a00-ba88-11f1-82ec-008cfa5ae3e1`) |
| Image | `harbor.cyverse.org/vice/mesa-cli:gpu` |
| Type | interactive |
| Container port | **7681** |
| Working directory | `/home/jovyan/data-store` |
| UID | 1000 |
| GPUs | `min_gpus` = `max_gpus` = **1** (with `min_gpus` unset, the launch default of 0 gives no GPU) |
| GPU models | `NVIDIA-A16` |
| `/dev/shm` | 4 GiB (device `/dev/shm` → `4Gi`, RAM-backed, counts against memory) |
| CPU / memory | 4–8 cores, 16–32 GiB |
| Everything else | network `bridge`, skip /tmp mount (`skip_tmp_mount`), `pids_limit` 1024 (GPU tool), cas-proxy (`interactive_apps`), no entrypoint override |

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
Makefile              make build/push (calls bash/Makefile) + GPU targets: pull-base build-gpu test-gpu push-gpu run-gpu
bash/
  Dockerfile          multi-arch image definition
  entry.sh            container entrypoint (iRODS config, S3 mounts, launches ttyd+tmux)
  01-custom           MESA ANSI splash screen (/etc/motd)
  mesa-prompt.sh      shell prompt (/etc/profile.d)
  environment.yml     geospatial conda env
  osn-mount.sh        s3fs mounts for OSN/S3 buckets
  configs/            agent-CLI configs + aiverde-setup helper
gpu/                  NVIDIA GPU variant (:gpu), layered on the CPU image
  Dockerfile          GPU layer: CUDA PyTorch, Ollama, cuda-compat, GPU tools
  common/             GPU scripts shared verbatim by the five MESA images
  pip-guard.py        build check: GPU pip installs never downgrade CPU packages
  test-gpu.sh         GPU smoke test (make test-gpu)
  de-tool.json        DE admin tool-import body for mesa-cli-gpu
docs/
  mesa-terminal.html  splash-screen design mockup
.github/workflows/
  harbor.yml          CPU image CI (push to main, weekly; skips gpu/-, README- and Makefile-only pushes)
  harbor-gpu.yml      GPU image build + push (manual only)
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/)
- MESA org: <https://github.com/idss-mesa>
