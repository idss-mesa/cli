# shellcheck shell=sh
# /etc/profile.d/mesa-gpu-env.sh — MESA GPU session environment (sourced, POSIX sh).
# Shared file: keep identical in the five idss-mesa GPU image repos.
#
# The NVIDIA container runtime injects the HOST driver's libcuda. CUDA 13
# software (Ollama's cuda_v13 runner, default PyPI torch, cupy-cuda13x, ...)
# needs an R580+ driver. On older driver branches (e.g. R535, CUDA 12.2) this
# script puts NVIDIA's CUDA forward-compat user-mode driver (cuda-compat-13-x,
# supported on data-center GPUs: A16, A100, T4, ...) first on LD_LIBRARY_PATH:
#
#   * only when the host CUDA driver API is < 13 (R580+ hosts are left alone);
#   * only when cuInit actually succeeds with the compat libcuda (GPUs that do
#     not support forward compatibility, e.g. GeForce, keep the host driver);
#   * never through /usr/local/cuda/compat, which the container toolkit may
#     force onto every process with no fallback.
#
# CUDA 12 builds (the image's cu126 PyTorch, R torch cu128, ...) run on the
# host driver or the compat driver alike. Set MESA_DISABLE_CUDA_COMPAT=1 to
# opt out. Safe under `set -e` / `set -u`, idempotent, never exits the shell.
if [ -z "${MESA_GPU_ENV_DONE:-}" ]; then
    MESA_GPU_ENV_DONE=1
    export MESA_GPU_ENV_DONE
    : "${MESA_CUDA_COMPAT_DIR:=/usr/local/cuda-13.4/compat}"
    export MESA_CUDA_COMPAT_DIR
    MESA_CUDA_COMPAT=0
    case ":${LD_LIBRARY_PATH:-}:" in
        *":$MESA_CUDA_COMPAT_DIR:"*)
            MESA_CUDA_COMPAT=1 ;;
        *)
            if [ "${MESA_DISABLE_CUDA_COMPAT:-0}" != 1 ] && [ -e /dev/nvidiactl ] \
                && [ -e "$MESA_CUDA_COMPAT_DIR/libcuda.so.1" ] && command -v cuda-probe >/dev/null 2>&1; then
                _mesa_api=$(cuda-probe --api 2>/dev/null) || _mesa_api=
                case "$_mesa_api" in
                    ''|*[!0-9]*) ;;
                    *)
                        if [ "$_mesa_api" -lt 13 ] && LD_LIBRARY_PATH="$MESA_CUDA_COMPAT_DIR" cuda-probe >/dev/null 2>&1; then
                            LD_LIBRARY_PATH="$MESA_CUDA_COMPAT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                            export LD_LIBRARY_PATH
                            MESA_CUDA_COMPAT=1
                        fi ;;
                esac
                unset _mesa_api
            fi ;;
    esac
    export MESA_CUDA_COMPAT
fi
true
