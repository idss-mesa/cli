#!/usr/bin/env bash
# mesa-gpu-check — verify NVIDIA GPU access inside a MESA VICE GPU container.
# Shared file: keep identical in the five idss-mesa GPU image repos.
#
#   mesa-gpu-check           driver, libcuda, CUDA forward-compat, PyTorch / R torch, Ollama
#   mesa-gpu-check --ollama  also pull a tiny model (qwen3:0.6b, ~0.5 GB) and confirm
#                            that Ollama runs it on the GPU
#
# App-specific checks (e.g. OpenGL/VirtualGL on the KASM desktop) live in
# /etc/mesa/gpu-check.d/*.sh and use the ok/bad/warn/info helpers below.
# Exit 0 = no failed checks. Useful first step when a DE tool was launched
# without a GPU (tool needs min_gpus >= 1).
set -u
ollama_test=0
[ "${1:-}" = --ollama ] && ollama_test=1

PASS=0 FAIL=0 WARN=0
ok()   { printf '  \e[32m[PASS]\e[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \e[31m[FAIL]\e[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  \e[33m[WARN]\e[0m %s\n' "$*"; WARN=$((WARN + 1)); }
info() { printf '  [INFO] %s\n' "$*"; }
hdr()  { printf '\n\e[1m== %s\e[0m\n' "$*"; }

. /etc/profile.d/mesa-gpu-env.sh 2>/dev/null || true

hdr "GPU devices and host driver"
host_drv=$(sed -nE 's/.*Kernel Module( for [a-z0-9_]+)?[[:space:]]+([0-9]+\.[0-9.]+).*/\2/p' /proc/driver/nvidia/version 2>/dev/null | head -1)
have_gpu=0
if nvidia-smi -L >/dev/null 2>&1; then
    have_gpu=1
    nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader | sed 's/^/  /'
    ok "nvidia-smi sees $(nvidia-smi -L | wc -l) GPU(s); host driver ${host_drv:-?}"
elif [ -e /dev/nvidiactl ]; then
    bad "nvidia-smi failed: $(nvidia-smi 2>&1 | head -1)"
else
    bad "no NVIDIA GPU in this container (DE tool not GPU-enabled? it needs min_gpus >= 1; locally use docker run --gpus)"
fi
info "NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-unset}  NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-unset}"

hdr "CUDA driver library"
libcuda=$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1 /{print $NF; exit}')
if [ -n "$libcuda" ]; then
    real=$(readlink -f "$libcuda")
    info "libcuda.so.1 -> $real"
    if [ -n "$host_drv" ]; then
        case "$real" in
            *"libcuda.so.$host_drv") ok "libcuda.so.1 is the host driver's ($host_drv), injected by the NVIDIA runtime" ;;
            */compat/*) warn "libcuda.so.1 resolves into a compat directory via ldconfig (toolkit auto-mount)" ;;
            *) bad "libcuda.so.1 ($real) is not the host driver $host_drv: driver userspace is baked into the image" ;;
        esac
    fi
elif [ "$have_gpu" = 1 ]; then
    bad "no libcuda.so.1 in the linker cache (NVIDIA_DRIVER_CAPABILITIES lacks 'compute'?)"
fi
if command -v cuda-probe >/dev/null 2>&1 && [ "$have_gpu" = 1 ]; then
    native=$(env -u LD_LIBRARY_PATH cuda-probe 2>&1)
    info "host driver:      $native"
    effective=$(cuda-probe 2>&1) && ok "CUDA usable: $effective" || bad "CUDA not usable: $effective"
    if [ "${MESA_CUDA_COMPAT:-0}" = 1 ]; then
        info "CUDA forward-compat ON ($MESA_CUDA_COMPAT_DIR): host driver predates R580, CUDA 13 software runs through the compat driver"
    else
        info "CUDA forward-compat off (host driver is R580+, compat unsupported on this GPU, or MESA_DISABLE_CUDA_COMPAT=1)"
    fi
fi

py=${MESA_TORCH_PYTHON:-}
if [ -z "$py" ]; then
    for c in /opt/conda/envs/pytorch/bin/python /opt/conda/bin/python /opt/r-python/bin/python; do
        [ -x "$c" ] && "$c" -c 'import torch' >/dev/null 2>&1 && { py=$c; break; }
    done
fi
if [ -n "$py" ] && [ -x "$py" ]; then
    hdr "PyTorch"
    out=$(timeout 300 "$py" - 2>&1 <<'EOF'
import time, torch
print(f"torch {torch.__version__} (CUDA {torch.version.cuda}, cuDNN {torch.backends.cudnn.version()})", end="")
assert torch.cuda.is_available(), "torch.cuda.is_available() is False"
dev = torch.cuda.get_device_name(0)
cap = "".join(map(str, torch.cuda.get_device_capability(0)))
a = torch.randn(4096, 4096, device="cuda", dtype=torch.float16)
b = a @ a  # warm-up: cuBLAS handle/workspace setup is not throughput
torch.cuda.synchronize(); t = time.time()
for _ in range(20):
    b = a @ a
torch.cuda.synchronize(); dt = time.time() - t
x = torch.randn(8, 3, 224, 224, device="cuda", requires_grad=True)
torch.nn.Conv2d(3, 16, 3).cuda()(x).sum().backward()  # cuDNN forward + backward
print(f" on {dev} sm_{cap}: fp16 matmul ~{20 * 2 * 4096**3 / dt / 1e12:.1f} TFLOPS, cuDNN conv ok")
EOF
    )
    if [ $? -eq 0 ]; then ok "$out"; elif [ "$have_gpu" = 1 ]; then bad "$py: $(printf '%s' "$out" | tail -1)"; else warn "$py: $(printf '%s' "$out" | tail -1)"; fi
elif ! command -v Rscript >/dev/null 2>&1; then
    hdr "PyTorch"
    info "no Python environment with torch found (set MESA_TORCH_PYTHON)"
fi

if command -v Rscript >/dev/null 2>&1 && Rscript -e 'quit(status = !requireNamespace("torch", quietly = TRUE))' >/dev/null 2>&1; then
    hdr "R torch"
    out=$(timeout 300 Rscript -e 'suppressMessages(library(torch)); stopifnot(cuda_is_available()); x <- torch_randn(2048, 2048, device = "cuda"); invisible((x %*% x)$sum()$item()); cat(sprintf("R torch %s: CUDA available, %d device(s), cuDNN %s", as.character(packageVersion("torch")), cuda_device_count(), as.character(backends_cudnn_version())))' 2>&1)
    if [ $? -eq 0 ]; then ok "$(printf '%s' "$out" | tail -1)"; elif [ "$have_gpu" = 1 ]; then bad "R torch: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; else warn "R torch: no GPU"; fi
fi

hdr "Ollama"
if ! command -v ollama >/dev/null 2>&1; then
    info "ollama not installed"
elif ! curl -fsS -m 3 "http://${OLLAMA_HOST:-127.0.0.1:11434}/api/version" >/dev/null 2>&1; then
    if [ "$ollama_test" = 1 ]; then
        bad "ollama server not running on ${OLLAMA_HOST:-127.0.0.1:11434} (see /tmp/ollama-*.log; start it with mesa-ollama-start)"
    else
        warn "ollama server not running on ${OLLAMA_HOST:-127.0.0.1:11434}: start it with mesa-ollama-start"
    fi
else
    ok "ollama $(ollama --version 2>/dev/null | awk '{print $NF}') serving on ${OLLAMA_HOST:-127.0.0.1:11434}"
    # newest server log first: a container can hold logs from servers run as different users
    compute=
    # shellcheck disable=SC2045  # /tmp/ollama-<uid>.log names never contain spaces
    for f in $(ls -t /tmp/ollama-*.log 2>/dev/null); do
        compute=$(grep -h 'msg="inference compute"' "$f" | tail -1)
        [ -n "$compute" ] && break
    done
    case "$compute" in
        *library=CUDA*) ok "ollama GPU backend: $(printf '%s' "$compute" | grep -oE '(library|name|driver|libdirs|total)=("[^"]*"|[^ ]*)' | tr '\n' ' ')" ;;
        *library=Vulkan*) warn "ollama is using Vulkan, not CUDA: $(printf '%s' "$compute" | grep -oE '(name|total)=("[^"]*"|[^ ]*)' | tr '\n' ' ')" ;;
        *library=cpu*) if [ "$have_gpu" = 1 ]; then bad "ollama found no usable GPU (runs on CPU): $(grep -h 'driver too old' /tmp/ollama-*.log 2>/dev/null | tail -1)"; else info "ollama runs on CPU (no GPU)"; fi ;;
        *) info "no 'inference compute' line in /tmp/ollama-*.log yet" ;;
    esac
    if [ "$ollama_test" = 1 ]; then
        model=qwen3:0.6b
        info "pulling $model and running a prompt ..."
        if ollama pull "$model" >/dev/null 2>&1 && ollama run "$model" --think=false 'Reply with one word: hello' >/dev/null 2>&1; then
            proc=$(ollama ps 2>/dev/null | awk -v m="$model" '$1 == m {for (i = 1; i <= NF; i++) if ($i ~ /GPU|CPU/) {print $(i-1), $i; exit}}')
            case "$proc" in *"100% GPU"*) ok "$model ran 100% on the GPU" ;; *) if [ "$have_gpu" = 1 ]; then bad "$model placement: ${proc:-unknown}"; else info "$model placement: ${proc:-unknown}"; fi ;; esac
        else
            bad "could not pull/run $model (network?)"
        fi
    fi
fi

for hook in /etc/mesa/gpu-check.d/*.sh; do
    # shellcheck source=/dev/null
    [ -r "$hook" ] && . "$hook"
done

printf '\n== Summary: %d passed, %d warnings, %d failed\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]
