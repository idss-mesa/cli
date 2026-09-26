#!/bin/bash
# /etc/mesa/motd-gpu.sh — GPU panel appended to the MESA landing screen
# (/etc/motd runs the CPU image's splash, now /etc/mesa/motd-base, then this).
# Shared file: keep identical in the five idss-mesa GPU image repos.
R=$'\e[0m'
C=$'\e[38;2;45;212;191m'; T=$'\e[38;2;205;217;229m'
M=$'\e[38;2;74;98;114m'; G=$'\e[38;2;74;222;128m'; O=$'\e[38;2;212;113;42m'
kv() { printf '  %s%-7s%s%s%s\n' "$C" "$1" "$T" "$2" "$R"; }

# Shells that did not descend from the entrypoint (docker/kubectl exec) may not
# have run the forward-compat probe yet; run it here only to report the state.
if [ -r /etc/profile.d/mesa-gpu-env.sh ]; then
    . /etc/profile.d/mesa-gpu-env.sh
fi

gpus=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | sed 's/, / /' | paste -sd ';' -)
if [ -n "$gpus" ]; then
    drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    compat=""
    [ "${MESA_CUDA_COMPAT:-0}" = 1 ] && compat=" · CUDA 13 via forward-compat"
    kv GPU "${gpus//;/ · }"
    kv DRIVER "${drv}${compat}"
else
    printf '  %s%-7s%sno NVIDIA GPU visible: launch the GPU app / tool with a GPU%s\n' "$C" GPU "$O" "$R"
fi
if curl -fsS -m 1 "http://${OLLAMA_HOST:-127.0.0.1:11434}/api/version" >/dev/null 2>&1; then
    kv OLLAMA "running on ${OLLAMA_HOST:-127.0.0.1:11434}"
elif pgrep -f 'ollama.bin serve' >/dev/null 2>&1; then
    kv OLLAMA "starting on ${OLLAMA_HOST:-127.0.0.1:11434}"
else
    kv OLLAMA "stopped (start: mesa-ollama-start)"
fi
monitors=nvtop
command -v nvitop >/dev/null 2>&1 && monitors="nvtop / nvitop"
printf '  %sLocal LLMs on this GPU:%s %sollama-setup%s  %s(no API key; pulls qwen3.5:9b)%s\n' "$C" "$R" "$G" "$R" "$M" "$R"
printf '  %sGPU diagnostics:%s %smesa-gpu-check%s  %s· live monitor: %s%s\n\n' "$C" "$R" "$G" "$R" "$M" "$monitors" "$R"
