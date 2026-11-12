# syntax=docker/dockerfile:1.29.0@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# MESA CLI — NVIDIA GPU variant. Adds CUDA-capable PyTorch (conda base env),
# Ollama for local LLMs and GPU tooling on top of the published CPU image
# (bash/Dockerfile, harbor.cyverse.org/vice/mesa-cli:latest); see ../README.md
# "GPU variant". Build context is gpu/:  make build-gpu
ARG BASE_IMAGE=harbor.cyverse.org/vice/mesa-cli:latest
# Build stage only (compiles cuda-probe); index digest.
ARG CUDA_PROBE_IMAGE=ubuntu:24.04@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5

# cuda-probe: tiny glibc-only helper used by mesa-gpu-env.sh and mesa-gpu-check
FROM ${CUDA_PROBE_IMAGE} AS cuda-probe
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
COPY --chmod=644 common/cuda-probe.c /src/cuda-probe.c
RUN gcc -O2 -Wall -o /cuda-probe /src/cuda-probe.c -ldl

# Build-time helpers, bind-mounted into RUN steps that run as jovyan. A bind
# mount of the build context keeps the host file mode (root-owned in the
# build), so a checkout made under umask 077 would be unreadable to jovyan;
# copying them here with an explicit mode first makes the build umask-proof.
FROM scratch AS build-scripts
COPY --chmod=644 pip-guard.py common/patch-agent-configs.py /

FROM ${BASE_IMAGE}

# Version, revision, source and vendor labels are inherited from the base.
ARG BASE_IMAGE
LABEL org.opencontainers.image.title="MESA Cloud Shell (NVIDIA GPU)" \
      org.opencontainers.image.description="MESA cloud shell + NVIDIA GPU: CUDA PyTorch, Ollama, nvtop/nvitop" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

USER root

# The jupyter base already runs RUN under bash -o pipefail; restated so the
# pipes below (zstd | tar, the driver guard) fail the build even if the base
# changes.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Layers go heaviest and most stable first: Ubuntu packages, PyTorch, the
# CUDA forward-compat driver, Ollama, then scripts. Each version ARG is
# declared just above the first RUN that uses it: an ARG is part of the cache
# key of every later RUN, so an OLLAMA_* or CUDA_COMPAT_VERSION bump declared
# up here would re-run (and re-push) the ~7 GB PyTorch layer.

# Ubuntu archive only: nvtop, zstd (Ollama tarball), curl, and gcc + libc6-dev:
# Triton (torch.compile) builds a small C launcher on first use and the CPU
# image ships no C compiler. The NVIDIA repo comes with cuda-compat below,
# whose driver guard also covers this layer.
# Ubuntu 26.04 packages nvtop with the file capability cap_perfmon. A container
# does not have that capability in its bounding set, so the kernel refuses to
# start the binary at all ("Operation not permitted"). Monitoring NVIDIA GPUs
# does not need it: reinstalling the file drops the capability, and the
# version check fails the build if nvtop still cannot start.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd nvtop gcc libc6-dev && \
    install -m 0755 /usr/bin/nvtop /usr/bin/nvtop.nocap && mv -f /usr/bin/nvtop.nocap /usr/bin/nvtop && nvtop --version && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# PyTorch into the conda BASE env (/opt/conda, Python 3.13): the `python` of
# the ttyd terminal (see README "GPU variant"). The geospatial env (Python
# 3.10) is left untouched. cu126 is the CUDA 12 build: it runs on any driver
# >= R525 (T4/A16/A100). NEVER plain `pip install torch` (PyPI ships the
# CUDA 13 build, which needs R580+). Move TORCH_INDEX_URL to .../cu130 once
# every DE GPU node runs R580+.
# ---------------------------------------------------------------------------
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126
ARG TORCH_VERSION=2.14.0
ARG TORCHVISION_VERSION=0.29.0

# Pins torch/torchvision to the index's local version (+cu126) for users:
# `pip install -c /etc/mesa/torch-constraints.txt --extra-index-url
# <TORCH_INDEX_URL> <pkg>` can never swap torch for PyPI's. The build itself
# installs from locks/gpu-pip.amd64.txt, whose torch pins must equal these
# ARGs (asserted below).
RUN mkdir -p /etc/mesa && \
    cuda_tag=$(basename "${TORCH_INDEX_URL}") && \
    printf 'torch==%s+%s\ntorchvision==%s+%s\n' \
        "${TORCH_VERSION}" "${cuda_tag}" "${TORCHVISION_VERSION}" "${cuda_tag}" > /etc/mesa/torch-constraints.txt

# torch + torchvision (cu126), GPU monitor (nvitop + NVML bindings), Hugging
# Face Hub (`hf` CLI), transformers + accelerate and the Ollama Python client,
# from locks/gpu-pip.amd64.txt: every wheel by sha256, resolved by `make
# relock` against the CPU image's package set (locks/gpu-pip.in).
# As jovyan (owner of /opt/conda), so users can still pip-manage the env.
# pip-guard.py fails the build if anything the CPU image ships is downgraded
# or removed; `pip check` must stay clean.
COPY locks/gpu-pip.amd64.txt /usr/share/mesa/locks/
USER jovyan
RUN --mount=type=bind,from=build-scripts,source=/pip-guard.py,target=/tmp/pip-guard.py \
    /opt/conda/bin/python /tmp/pip-guard.py snapshot /tmp/pip-before.json && \
    /opt/conda/bin/pip install --no-cache-dir --no-deps --require-hashes --only-binary :all: \
        --extra-index-url "${TORCH_INDEX_URL}" -r /usr/share/mesa/locks/gpu-pip.amd64.txt && \
    /opt/conda/bin/pip check && \
    /opt/conda/bin/python /tmp/pip-guard.py check /tmp/pip-before.json && \
    rm -f /tmp/pip-before.json && \
    cuda_tag=$(basename "${TORCH_INDEX_URL}") && \
    /opt/conda/bin/python -c "from importlib.metadata import version as v; import sys; want = {'torch': '${TORCH_VERSION}+${cuda_tag}', 'torchvision': '${TORCHVISION_VERSION}+${cuda_tag}'}; got = {n: v(n) for n in want}; sys.exit(0 if got == want else f'lock and ARGs disagree: {got} != {want}')"

USER root

# One pin for the CUDA forward-compat driver: the apt package
# (cuda-compat-13-4) and its versioned path (MESA_CUDA_COMPAT_DIR, read by
# /etc/profile.d/mesa-gpu-env.sh) both derive from it, so a bump cannot leave
# the env pointing at a directory that does not exist.
ARG CUDA_COMPAT_VERSION=13.4
ARG CUDA_COMPAT_PKG_VERSION=615.71.10-1ubuntu1
ARG CUDA_KEYRING_VERSION=1.1-1
ARG CUDA_KEYRING_SHA256=d2a6b11c096396d868758b86dab1823b25e14d70333f1dfa74da5ddaf6a06dba
ENV MESA_CUDA_COMPAT_DIR=/usr/local/cuda-${CUDA_COMPAT_VERSION}/compat

# NVIDIA apt repo for the CUDA forward-compat driver only — never driver
# packages: the NVIDIA runtime injects the host's. The driver guard checks the
# whole dpkg database (so the Ubuntu packages above too) and greps to
# /dev/null instead of `grep -q`: under pipefail an early grep exit gives dpkg
# SIGPIPE, the pipeline fails and the check would silently pass.
# The keyring .deb is checked by sha256 and cuda-compat is installed at an
# exact version (both as listed in the NVIDIA repo's Packages file).
RUN curl -fsSL -o /tmp/cuda-keyring.deb "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_${CUDA_KEYRING_VERSION}_all.deb" && \
    echo "${CUDA_KEYRING_SHA256}  /tmp/cuda-keyring.deb" | sha256sum -c - && \
    dpkg -i /tmp/cuda-keyring.deb && rm -f /tmp/cuda-keyring.deb && \
    apt-get update && apt-get install -y --no-install-recommends "cuda-compat-$(printf '%s' "${CUDA_COMPAT_VERSION}" | tr . -)=${CUDA_COMPAT_PKG_VERSION}" && \
    test -e "${MESA_CUDA_COMPAT_DIR}/libcuda.so.1" && \
    test ! -e /usr/local/cuda/compat && \
    if dpkg -l | grep -E '^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)' >/dev/null; then \
        echo 'NVIDIA driver userspace must not be baked into the image' >&2; exit 1; fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ollama (pinned, sha256-checked; never ollama.com/install.sh: with no
# nvidia-smi at build time it bakes the cuda-drivers userspace into the image).
# The real binary is ollama.bin; /usr/local/bin/ollama is the compat wrapper.
# Last of the heavy layers: bumping OLLAMA_* re-runs only this 2.2 GB layer.
ARG OLLAMA_VERSION=0.40.11
ARG OLLAMA_SHA256=7bedab90dd122661be78798e9f0edf37fccf0cccf2699d2c58ea1a3afdc04b6d
RUN curl -fsSL -o /tmp/ollama.tar.zst "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" && \
    echo "${OLLAMA_SHA256}  /tmp/ollama.tar.zst" | sha256sum -c - && \
    zstd -dc /tmp/ollama.tar.zst | tar -xf - -C /usr/local && rm -f /tmp/ollama.tar.zst && \
    mv /usr/local/bin/ollama /usr/local/bin/ollama.bin

# ---------------------------------------------------------------------------
# Shared GPU scripts (gpu/common, identical in the five MESA images) and
# config last, so editing them rebuilds in seconds without re-downloading
# PyTorch or Ollama.
# ---------------------------------------------------------------------------
# Every COPY sets its mode, so the image does not depend on the umask of the
# checkout it was built from (644: sourced/config files, 755: executables).
COPY --chmod=755 --from=cuda-probe /cuda-probe /usr/local/bin/cuda-probe
COPY --chmod=644 common/mesa-gpu-env.sh /etc/profile.d/mesa-gpu-env.sh
# apt refuses NVIDIA driver packages (they would shadow the host driver the
# runtime injects; see the file). Remove it to install them on purpose.
COPY --chmod=644 common/apt-no-nvidia-driver.pref /etc/apt/preferences.d/mesa-no-nvidia-driver
COPY --chmod=755 common/ollama-wrapper.sh /usr/local/bin/ollama
COPY --chmod=755 common/mesa-ollama-start.sh /usr/local/bin/mesa-ollama-start
COPY --chmod=755 common/mesa-gpu-entrypoint.sh /usr/local/bin/mesa-gpu-entrypoint
COPY --chmod=755 common/mesa-gpu-check.sh /usr/local/bin/mesa-gpu-check
COPY --chmod=755 common/ollama-setup.sh /usr/local/bin/ollama-setup
COPY --chmod=755 common/motd-gpu.sh /etc/mesa/motd-gpu.sh

# Landing screen: ~/.bashrc runs /etc/motd in every interactive shell. Keep
# the CPU splash (now /etc/mesa/motd-base) and append the GPU panel.
RUN mv /etc/motd /etc/mesa/motd-base && \
    printf '#!/bin/bash\n/etc/mesa/motd-base\n/etc/mesa/motd-gpu.sh\n' > /etc/motd && chmod 755 /etc/motd

# ttyd's terminal inherits the forward-compat env from the entrypoint, but
# `docker exec` / `kubectl exec ... bash -i` shells do not descend from it and
# non-login shells skip /etc/profile.d: source it from /etc/bash.bashrc too
# (interactive shells only; idempotent and safe under set -e/-u).
RUN printf '\n# MESA GPU: CUDA forward-compat env for shells not started by the IDE (docker/kubectl exec)\nif [ -r /etc/profile.d/mesa-gpu-env.sh ]; then . /etc/profile.d/mesa-gpu-env.sh; fi\n' >> /etc/bash.bashrc

# NVIDIA_VISIBLE_DEVICES is deliberately NOT set: the DE's device plugin (or
# `docker run --gpus`) sets it; baking `all` could expose every GPU on a node.
# OLLAMA_CONTEXT_LENGTH: one 16 GB GPU would get a 4096-token default, far too
# small for coding agents. MESA_TORCH_PYTHON tells mesa-gpu-check where torch is.
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    MESA_TORCH_PYTHON=/opt/conda/bin/python \
    OLLAMA_HOST=127.0.0.1:11434 OLLAMA_CONTEXT_LENGTH=32768 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
    OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 CUDA_CACHE_MAXSIZE=1073741824

USER jovyan

# Register the local Ollama server with OpenCode (an `ollama` provider next to
# `aiverde`) and Codex (`codex --oss`). Run as jovyan so the configs stay 1000:100.
RUN --mount=type=bind,from=build-scripts,source=/patch-agent-configs.py,target=/tmp/patch-agent-configs.py \
    /opt/conda/bin/python /tmp/patch-agent-configs.py \
        --opencode /home/jovyan/.config/opencode/opencode.json \
        --codex /home/jovyan/.codex/config.toml

WORKDIR /home/jovyan/data-store

# The jupyter base's HEALTHCHECK polls a Jupyter server on 8888 that this image
# never runs, so plain Docker marks every container unhealthy. Check ttyd
# instead (VICE/Kubernetes ignores Docker HEALTHCHECK either way).
HEALTHCHECK --interval=30s --timeout=5s --start-period=2m --retries=3 \
    CMD ["sh", "-c", "curl -fsS -o /dev/null http://127.0.0.1:7681/ || exit 1"]

# GPU env (CUDA forward-compat when the host driver predates R580) + Ollama in
# the background, then the CPU image's entrypoint unchanged. A child ENTRYPOINT
# resets CMD, so the CPU image's CMD is re-declared.
ENTRYPOINT ["/usr/local/bin/mesa-gpu-entrypoint", "bash", "/bin/entry.sh"]

CMD ["ttyd", "bash"]
