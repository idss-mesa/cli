#!/bin/bash
# mesa-gpu-entrypoint — GPU-variant entrypoint prefix for the MESA VICE images.
# Shared file: keep identical in the five idss-mesa GPU image repos.
#
# Usage (Dockerfile): ENTRYPOINT ["/usr/local/bin/mesa-gpu-entrypoint", <CPU image ENTRYPOINT...>]
#
#  1. sources /etc/profile.d/mesa-gpu-env.sh (CUDA forward-compat when the host
#     driver is older than R580), so the IDE and everything it spawns inherit it;
#  2. sources app-specific hooks from /etc/mesa/gpu-entrypoint.d/*.sh;
#  3. starts the local Ollama server in the background (MESA_OLLAMA_AUTOSTART=0
#     disables it);
#  4. execs the CPU image's original entrypoint unchanged.
. /etc/profile.d/mesa-gpu-env.sh || true

for hook in /etc/mesa/gpu-entrypoint.d/*.sh; do
    # shellcheck source=/dev/null
    [ -r "$hook" ] && . "$hook"
done
unset hook

if [ "${MESA_OLLAMA_AUTOSTART:-1}" = 1 ] && command -v mesa-ollama-start >/dev/null 2>&1; then
    mesa-ollama-start --no-wait >/dev/null 2>&1 || true
fi

exec "$@"
