#!/bin/sh
# /usr/local/bin/ollama — MESA wrapper around the pinned Ollama binary.
# Shared file: keep identical in the five idss-mesa GPU image repos.
#
# `ollama serve` re-runs the CUDA forward-compat probe (mesa-gpu-env.sh) so the
# server reaches the GPU even when started from an environment that dropped
# the entrypoint's LD_LIBRARY_PATH (sudo, supervisord, RStudio sessions).
# Ollama >= 0.30.11 refuses its CUDA 12.8 runner on drivers < 550 and its
# CUDA 13 runner needs R580+, so on R535 hosts the compat driver is what keeps
# it off the CPU. Client subcommands (pull, run, ps, ...) are passed through.
if [ "${1:-}" = serve ] && [ -r /etc/profile.d/mesa-gpu-env.sh ]; then
    unset MESA_GPU_ENV_DONE
    . /etc/profile.d/mesa-gpu-env.sh
fi
exec /usr/local/bin/ollama.bin "$@"
