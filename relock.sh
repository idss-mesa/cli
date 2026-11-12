#!/usr/bin/env bash
# Regenerate every lock file of this repo from its intent file (`make relock`).
# Tool pins that are Dockerfile ARGs are bumped separately (`make update-pins`).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=ci/relock-lib.sh
. ci/relock-lib.sh

# CPU image (bash/)
base_digest bash/Dockerfile BASE_IMAGE --dated latest
base=$(dockerfile_arg bash/Dockerfile BASE_IMAGE)
# 3.13 = the base image's Python (/opt/mesa venv and /opt/conda); 3.10 = the geospatial env
pip_lock bash/locks/mesa-venv.in 3.13
pip_lock bash/locks/base-pip.in 3.13
pip_lock bash/locks/geospatial-pip.in 3.10
npm_lock bash/locks/npm "$(dockerfile_arg bash/Dockerfile NODE_VERSION)"
conda_lock bash/environment.yml bash/locks/geospatial "$base"

# GPU layer (gpu/, amd64 only): Python packages added to /opt/conda, resolved
# against what the CPU image has there (base image + locks/base-pip), with
# torch from PyTorch's cu126 index.
base_digest gpu/Dockerfile CUDA_PROBE_IMAGE
constraints=$(mktemp)
base_pip_constraints "$base" /opt/conda/bin/python bash/locks/base-pip.amd64.txt > "$constraints"
MESA_ARCHES=amd64 pip_lock gpu/locks/gpu-pip.in 3.13 --index-strategy unsafe-best-match -c "$constraints"
rm -f "$constraints"
