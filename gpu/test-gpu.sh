#!/usr/bin/env bash
# gpu/test-gpu.sh — smoke test for the MESA CLI NVIDIA GPU image.
#
#   gpu/test-gpu.sh [IMAGE]        (make test-gpu; default harbor.cyverse.org/vice/mesa-cli:gpu)
#   GPU=<index>|all                GPU to test on (default 0)
#
# Needs an NVIDIA GPU + driver, nvidia-container-toolkit (docker run --gpus) and
# network access (T3 pulls qwen3:0.6b, ~0.5 GB, into the throwaway container).
#   T1  static: nvidia-smi works, libcuda.so.1 is the HOST driver's (nothing baked);
#       image contents (pip check, torch build, agent configs, file modes, apt
#       pin, ENTRYPOINT/CMD); after `apt-get update` in a throwaway container,
#       apt refuses driver packages but still offers the CUDA toolkit (SKIP
#       with a note when there is no network)
#   T2  starts like VICE (--user 1000, IPLANT_USER, default entrypoint): ttyd
#       answers HTTP 200 on 7681, the container keeps running and (checked
#       after T4) Docker's HEALTHCHECK reports it healthy
#   T3  mesa-gpu-check --ollama: CUDA, forward-compat, PyTorch, Ollama 100% on GPU
#   T4  in a real ttyd terminal (websocket -> tmux -> bash, like a browser tab):
#       `python` is the conda base env with CUDA torch + torch.compile, the GPU
#       env reached the shell, and `bash -l` switches to the geospatial env
#   T5  without a GPU: ttyd and a terminal still work; mesa-gpu-check reports
#       the missing GPU (exit 1) without crashing
#   T6  `docker exec ... bash -i` (non-login and not descended from the
#       entrypoint, like kubectl exec): same forward-compat env as the terminal,
#       nvitop on PATH; a `set -e` script sourcing the bashrc files completes
# Exit status is non-zero if any check fails. Containers are removed on exit.
set -uo pipefail

IMAGE=${1:-harbor.cyverse.org/vice/mesa-cli:gpu}
GPU=${GPU:-0}
if [ "$GPU" = all ]; then GPU_ARGS=(--gpus all); else GPU_ARGS=(--gpus "device=$GPU"); fi
PORT=7681
PREFIX=mesa-gpu-cli-test-$$
NAMES=()
RESULTS=()
FAILED=0
SKIPPED=0

cleanup() { [ ${#NAMES[@]} -eq 0 ] || docker rm -f "${NAMES[@]}" >/dev/null 2>&1; }
trap cleanup EXIT
trap 'exit 130' INT TERM

result() { # result NAME 0|1 DETAIL
    local status=PASS
    [ "$2" = 0 ] || { status=FAIL; FAILED=$((FAILED + 1)); }
    RESULTS+=("$(printf '%-4s  %-36s %s' "$status" "$1" "$3")")
    printf '[%s] %s: %s\n' "$status" "$1" "$3"
}
skip() { # skip NAME DETAIL: listed in the results, but not a failure
    SKIPPED=$((SKIPPED + 1))
    RESULTS+=("$(printf '%-4s  %-36s %s' SKIP "$1" "$2")")
    printf '[SKIP] %s: %s\n' "$1" "$2"
}
hdr() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

start() { # start NAME [docker run args...]  -> prints 127.0.0.1:<host port>
    # Runs inside $(...): the caller must add NAME to NAMES (for cleanup) first.
    local name=$1
    shift
    docker run -d --name "$name" --user 1000 -e IPLANT_USER=mesa-test \
        -p "127.0.0.1::$PORT" "$@" "$IMAGE" >/dev/null || return 1
    docker port "$name" "$PORT/tcp" | head -1
}

wait_http() { # wait_http NAME ADDR -> 0 once ttyd answers 200 (<= 5 min) while the container runs
    local deadline=$((SECONDS + 300)) code=000
    while [ $SECONDS -lt $deadline ]; do
        if [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" != true ]; then
            echo "container exited:" >&2
            docker logs --tail 40 "$1" >&2
            return 1
        fi
        code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$2/")
        [ "$code" = 200 ] && return 0
        sleep 2
    done
    echo "last HTTP status: $code" >&2
    return 1
}

# Minimal ttyd client (Node 22 WebSocket, run inside the container): opens a
# terminal the way the browser does (ttyd -> tmux -> interactive bash), waits
# for the MESA prompt, types one command line and waits for DONE_FILE.
TTYD_CLIENT=$(cat <<'EOF'
const fs = require('fs');
const [, , port, line, doneFile, timeoutS] = process.argv;
const enc = new TextEncoder();
const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, ['tty']);
ws.binaryType = 'arraybuffer';
let out = '', sent = false;
const send = () => { if (!sent) { sent = true; ws.send(enc.encode('0' + line + '\r')); } };
ws.onopen = () => {
  ws.send(enc.encode(JSON.stringify({ AuthToken: '', columns: 200, rows: 50 })));
  setTimeout(send, 60000);  // fallback if the prompt is never recognised
};
ws.onmessage = (e) => {
  const d = Buffer.from(e.data);
  if (d[0] === 0x30) out += d.subarray(1).toString();
  if (!sent && out.includes('$>')) setTimeout(send, 500);
};
ws.onerror = (e) => { console.error('websocket error:', e.message || e); process.exit(2); };
const deadline = Date.now() + Number(timeoutS) * 1000;
setInterval(() => {
  if (fs.existsSync(doneFile)) { ws.close(); process.exit(0); }
  if (Date.now() > deadline) {
    console.error('timeout; terminal output tail:\n' + out.slice(-3000));
    process.exit(1);
  }
}, 500);
EOF
)

ttyd_type() { # ttyd_type NAME 'command line' DONE_FILE TIMEOUT_S
    printf '%s\n' "$TTYD_CLIENT" | docker exec -i -u 1000 "$1" sh -c 'cat > /tmp/mesa-ttyd-client.js' &&
        docker exec -u 1000 "$1" node /tmp/mesa-ttyd-client.js "$PORT" "$2" "$3" "$4"
}

echo "Image: $IMAGE ($(docker image inspect -f '{{.Id}} {{.Size}} bytes' "$IMAGE" 2>/dev/null || echo 'not found'))"
echo "GPU:   $GPU"

# ---------------------------------------------------------------------------
hdr "T1 static"
out=$(docker run --rm -i "${GPU_ARGS[@]}" --entrypoint bash "$IMAGE" -s 2>&1 <<'EOF'
nvidia-smi -L || { echo "nvidia-smi failed"; exit 1; }
drv=$(sed -nE 's/.*Kernel Module( for [a-z0-9_]+)?[[:space:]]+([0-9]+\.[0-9.]+).*/\2/p' /proc/driver/nvidia/version | head -1)
real=$(readlink -f "$(ldconfig -p | awk '/libcuda\.so\.1 /{print $NF; exit}')")
echo "host driver $drv; libcuda.so.1 -> $real"
case "$real" in *"libcuda.so.$drv") ;; *) echo "libcuda.so.1 is not the host driver's"; exit 1 ;; esac
if dpkg -l | grep -E '^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)'; then
    echo "NVIDIA driver userspace is baked into the image"; exit 1
fi
[ ! -e /usr/local/cuda/compat ] || { echo "/usr/local/cuda/compat exists"; exit 1; }
EOF
)
rc=$?
printf '%s\n' "$out"
result "T1 host driver injected, none baked" "$rc" "$(printf '%s' "$out" | grep -m1 'libcuda.so.1' || printf '%s' "$out" | tail -1)"

out=$(docker run --rm -i --entrypoint bash "$IMAGE" -s 2>&1 <<'EOF'
fail=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
tv=$(/opt/conda/bin/python -c 'import torch; print(torch.__version__)' 2>/dev/null)
echo "torch $tv; constraints: $(tr '\n' ' ' < /etc/mesa/torch-constraints.txt)"
chk "pip check (conda base)" '/opt/conda/bin/pip check'
chk "torch matches /etc/mesa/torch-constraints.txt" 'grep -qx "torch==$tv" /etc/mesa/torch-constraints.txt'
chk "torch/site-packages owned by jovyan" '[ "$(stat -c %U /opt/conda/lib/python3.13/site-packages/torch)" = jovyan ]'
chk "ollama wrapper first on PATH" '[ "$(command -v ollama)" = /usr/local/bin/ollama ] && [ -x /usr/local/bin/ollama.bin ]'
missing=$(for c in nvtop nvitop hf cuda-probe mesa-gpu-check ollama-setup; do command -v "$c" >/dev/null || printf '%s ' "$c"; done)
chk "GPU CLIs present (nvtop nvitop hf cuda-probe mesa-gpu-check ollama-setup)${missing:+ - missing: $missing}" '[ -z "$missing" ]'
chk "forward-compat driver at \$MESA_CUDA_COMPAT_DIR ($MESA_CUDA_COMPAT_DIR)" '[ -e "$MESA_CUDA_COMPAT_DIR/libcuda.so.1" ]'
chk "OpenCode has the ollama provider" '/opt/conda/bin/python -c "import json,sys; sys.exit(\"ollama\" not in json.load(open(\"/home/jovyan/.config/opencode/opencode.json\"))[\"provider\"])"'
chk "Codex oss_provider = ollama" 'grep -qx "oss_provider = \"ollama\"" /home/jovyan/.codex/config.toml'
chk "agent configs owned by 1000:100" '[ "$(stat -c %u:%g /home/jovyan/.config/opencode/opencode.json /home/jovyan/.codex/config.toml | sort -u)" = 1000:100 ]'
chk "motd runs the CPU splash + GPU panel" '[ -x /etc/mesa/motd-base ] && [ -x /etc/mesa/motd-gpu.sh ] && grep -q motd-gpu /etc/motd'
chk "no build leftovers in /tmp" '! ls /tmp/pip-guard.py /tmp/pip-before.json /tmp/patch-agent-configs.py'
# Every COPY sets its mode (umask-proof build): list the files that differ.
modes=$( { stat -c '%a %U %n' /etc/profile.d/mesa-gpu-env.sh /etc/apt/preferences.d/mesa-no-nvidia-driver \
        /etc/mesa/torch-constraints.txt | awk '$1 != 644 || $2 != "root"'
    stat -c '%a %U %n' /usr/local/bin/cuda-probe /usr/local/bin/ollama /usr/local/bin/ollama.bin \
        /usr/local/bin/mesa-ollama-start /usr/local/bin/mesa-gpu-entrypoint /usr/local/bin/mesa-gpu-check \
        /usr/local/bin/ollama-setup /etc/mesa/motd-gpu.sh /etc/motd | awk '$1 != 755 || $2 != "root"'; } 2>&1 | tr '\n' ' ')
chk "MESA files root-owned, 644 config / 755 executables${modes:+ - got: $modes}" '[ -z "$modes" ]'
chk "apt pin /etc/apt/preferences.d/mesa-no-nvidia-driver (driver packages at -1)" \
    'grep -q "^Pin-Priority: -1" /etc/apt/preferences.d/mesa-no-nvidia-driver && grep -q "nvidia-driver-\*" /etc/apt/preferences.d/mesa-no-nvidia-driver'
chk "/etc/bash.bashrc sources mesa-gpu-env.sh (docker/kubectl exec shells)" 'grep -q "\. /etc/profile.d/mesa-gpu-env.sh" /etc/bash.bashrc'
exit $fail
EOF
)
rc=$?
cfg=$(docker image inspect -f '{{json .Config.Entrypoint}} {{json .Config.Cmd}} {{.Config.User}} {{.Config.WorkingDir}}' "$IMAGE")
want='["/usr/local/bin/mesa-gpu-entrypoint","bash","/bin/entry.sh"] ["ttyd","bash"] jovyan /home/jovyan/data-store'
if [ "$cfg" = "$want" ]; then out+=$'\n'"ok   entrypoint/cmd/user/workdir: $cfg"; else out+=$'\n'"FAIL entrypoint/cmd/user/workdir: $cfg"; rc=1; fi
# grep >/dev/null, not grep -q: under pipefail an early grep -q exit can SIGPIPE
# the left side, and the failed pipeline would read as "not set".
if docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | grep '^NVIDIA_VISIBLE_DEVICES=' >/dev/null; then
    out+=$'\n'"FAIL NVIDIA_VISIBLE_DEVICES is baked into the image"; rc=1
else
    out+=$'\n'"ok   NVIDIA_VISIBLE_DEVICES not set in the image"
fi
printf '%s\n' "$out"
result "T1 image contents" "$rc" "$(printf '%s' "$out" | grep -c '^ok') ok, $(printf '%s' "$out" | grep -c '^FAIL') failed; $(printf '%s' "$out" | grep -m1 '^torch')"

# The pin only matters once apt has package lists (the image ships none), so
# fetch them as root in a throwaway container: driver packages must have no
# install candidate, while the CUDA toolkit stays installable. apt-get update
# exits 0 even when every fetch fails, so "no network" means it downloaded no
# package lists (cleared first, so only this fetch counts): SKIP, not FAIL.
out=$(docker run --rm -i --user root --entrypoint bash "$IMAGE" -s 2>&1 <<'EOF'
rm -rf /var/lib/apt/lists/*
timeout 300 apt-get update >/tmp/apt-update.log 2>&1
if ! compgen -G '/var/lib/apt/lists/*_Packages*' >/dev/null; then
    echo "NO-NETWORK: apt-get update fetched no package lists ($(grep -m1 -E '^(Err|W|E):' /tmp/apt-update.log || echo 'no error logged'))"
    exit 3
fi
apt-cache policy nvidia-driver-580 cuda-drivers cuda-nvcc-12-6
echo "install-dry-run: $(apt-get install -s -y nvidia-driver-580 2>&1 | grep -m1 -iE 'no installation candidate|^Inst nvidia-driver' || echo '?')"
EOF
)
rc=$?
printf '%s\n' "$out"
if [ "$rc" = 3 ]; then
    skip "T1 apt refuses driver packages" "no network for apt-get update: $(grep -m1 '^NO-NETWORK' <<<"$out" | cut -c13- | cut -c1-160)"
else
    policy() { awk -v p="$1:" '$1 == p {f = 1; next} f && /^[^ ]/ {exit} f' <<<"$out"; } # one package's block
    cand() { policy "$1" | awk '$1 == "Candidate:" {print $2; exit}'; }
    drv_cand=$(cand nvidia-driver-580) cudadrv_cand=$(cand cuda-drivers) nvcc_cand=$(cand cuda-nvcc-12-6)
    # Versions pinned at -1 prove apt knows the driver packages (a package apt
    # has never heard of shows no candidate either).
    rc=1
    [ "$drv_cand" = "(none)" ] && [ "$cudadrv_cand" = "(none)" ] &&
        policy nvidia-driver-580 | grep -E '^ +[0-9][^ ]* -1$' >/dev/null &&
        policy cuda-drivers | grep -E '^ +[0-9][^ ]* -1$' >/dev/null &&
        grep -q '^install-dry-run: .*no installation candidate' <<<"$out" &&
        [ -n "$nvcc_cand" ] && [ "$nvcc_cand" != "(none)" ] && rc=0
    result "T1 apt refuses driver packages" "$rc" "Candidate: nvidia-driver-580 ${drv_cand:-?}, cuda-drivers ${cudadrv_cand:-?}; toolkit cuda-nvcc-12-6 ${nvcc_cand:-?}"
fi

# ---------------------------------------------------------------------------
hdr "T2 start like VICE (GPU $GPU)"
C=$PREFIX-gpu
NAMES+=("$C")
t0=$SECONDS
t_start=$t0
if addr=$(start "$C" "${GPU_ARGS[@]}") && wait_http "$C" "$addr"; then
    result "T2 ttyd HTTP 200 (with GPU)" 0 "http://$addr/ after $((SECONDS - t0)) s, user $(docker exec "$C" id -un)"
    up=1
else
    result "T2 ttyd HTTP 200 (with GPU)" 1 "no HTTP 200 on $PORT within 300 s"
    up=0
fi

# ---------------------------------------------------------------------------
hdr "T3 mesa-gpu-check --ollama"
if [ "$up" = 1 ]; then
    out=$(docker exec -u 1000 "$C" mesa-gpu-check --ollama 2>&1)
    rc=$?
    out=$(strip <<<"$out")
    printf '%s\n' "$out"
    if [ "$rc" = 0 ] && grep -q 'PASS.*torch .* on ' <<<"$out" && grep -q 'PASS.*ran 100% on the GPU' <<<"$out"; then
        result "T3 mesa-gpu-check --ollama" 0 "$(grep 'Summary' <<<"$out" | sed 's/^== //'); $(grep -o 'fp16 matmul[^,]*' <<<"$out")"
    else
        result "T3 mesa-gpu-check --ollama" 1 "exit $rc; $(grep -E '\[(FAIL|WARN)\]' <<<"$out" | head -3 | tr '\n' ' ')"
    fi
else
    result "T3 mesa-gpu-check --ollama" 1 "skipped: container not up"
fi

# ---------------------------------------------------------------------------
hdr "T4 ttyd terminal: python, torch, GPU env"
if [ "$up" = 1 ]; then
    docker exec -i -u 1000 "$C" sh -c 'cat > /tmp/mesa-t4.sh' <<'EOF'
# Sourced INSIDE the ttyd terminal's shell: reports what a user gets there.
echo "shell=$(shopt -q login_shell && echo login || echo non-login) interactive=$(case $- in *i*) echo yes ;; *) echo no ;; esac) tmux=${TMUX:+yes}"
echo "python=$(command -v python)"
echo "compat=${MESA_CUDA_COMPAT:-unset} ld=${LD_LIBRARY_PATH:-}"
python - <<'PY'
import sys, torch
ok = torch.cuda.is_available()
print("torch", sys.executable, torch.__version__, "cuda=%s" % ok, torch.cuda.get_device_name(0) if ok else "-")
x = torch.randn(2048, 2048, device="cuda")
print("matmul_ok=%s" % bool(torch.isfinite(x @ x).all()))
f = torch.compile(lambda t: torch.sin(t) * 2 + 1)
y = torch.randn(4096, device="cuda")
print("compile_ok=%s" % bool(torch.allclose(f(y), torch.sin(y) * 2 + 1, atol=1e-5)))
PY
bash -l -c 'echo "login_python=$(command -v python)"; python -c "import torch" 2>/dev/null && echo login_torch=yes || echo login_torch=no; /opt/conda/bin/python -c "import torch; print(\"login_base_cuda=%s\" % torch.cuda.is_available())"'
echo "motd=$(/etc/motd 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -m1 -E '^ +GPU ' | sed 's/^ *//')"
EOF
    t0=$SECONDS
    if ttyd_type "$C" 'source /tmp/mesa-t4.sh > /tmp/mesa-t4.out 2>&1; echo $? > /tmp/mesa-t4.done' /tmp/mesa-t4.done 300; then
        out=$(docker exec "$C" cat /tmp/mesa-t4.out)
        printf '%s\n' "$out"
        expect_compat=$(docker exec -u 1000 "$C" bash -c 'unset MESA_GPU_ENV_DONE; . /etc/profile.d/mesa-gpu-env.sh; echo $MESA_CUDA_COMPAT')
        compat_dir=$(docker exec -u 1000 "$C" printenv MESA_CUDA_COMPAT_DIR)
        get() { grep -m1 -o "$1=[^ ]*" <<<"$out" | cut -d= -f2-; }

        rc=1
        grep -q '^shell=non-login interactive=yes tmux=yes' <<<"$out" && [ "$(get python)" = /opt/conda/bin/python ] &&
            grep -q '^torch /opt/conda/bin/python .*cuda=True' <<<"$out" && [ "$(get matmul_ok)" = True ] && rc=0
        result "T4 ttyd shell: python = torch env" "$rc" "$(grep -m1 '^shell=' <<<"$out"); python=$(get python); $(grep -m1 '^torch ' <<<"$out" | cut -d' ' -f3-)"

        rc=1
        if [ "$(get compat)" = "$expect_compat" ]; then
            if [ "$expect_compat" = 1 ]; then [ -n "$compat_dir" ] && grep -qF "compat=1 ld=$compat_dir" <<<"$out" && rc=0; else rc=0; fi
        fi
        result "T4 ttyd shell: GPU env inherited" "$rc" "MESA_CUDA_COMPAT=$(get compat) (fresh probe: $expect_compat), LD_LIBRARY_PATH=$(get ld)"

        rc=1
        [ "$(get compile_ok)" = True ] && rc=0
        result "T4 ttyd shell: torch.compile (Triton)" "$rc" "compile_ok=$(get compile_ok) $(grep -m1 -E 'Error|error:' <<<"$out")"

        rc=1
        [ "$(get login_python)" = /opt/conda/envs/geospatial/bin/python ] && [ "$(get login_base_cuda)" = True ] && rc=0
        result "T4 bash -l: geospatial python" "$rc" "python=$(get login_python) (torch: $(get login_torch)); /opt/conda/bin/python torch.cuda=$(get login_base_cuda)"

        rc=1
        grep -q '^motd=GPU .*[0-9]' <<<"$out" && rc=0
        result "T4 landing screen GPU panel" "$rc" "$(grep -m1 '^motd=' <<<"$out" | cut -d= -f2-)"
    else
        result "T4 ttyd shell" 1 "terminal did not run the probe within 300 s (see output above)"
    fi
    echo "(T4 took $((SECONDS - t0)) s)"
else
    result "T4 ttyd shell" 1 "skipped: container not up"
fi

# ---------------------------------------------------------------------------
hdr "T6 docker exec shell (non-login, interactive)"
if [ "$up" = 1 ]; then
    # The terminal (ttyd, exec'd by the entrypoint chain) shares PID 1's environment.
    ide_compat=$(docker exec -u 1000 "$C" sh -c 'tr "\0" "\n" < /proc/1/environ' | sed -n 's/^MESA_CUDA_COMPAT=//p')
    ide_ld=$(docker exec -u 1000 "$C" sh -c 'tr "\0" "\n" < /proc/1/environ' | sed -n 's/^LD_LIBRARY_PATH=//p')
    out=$(docker exec -u 1000 "$C" bash -i -c 'echo "exec_compat=${MESA_CUDA_COMPAT:-unset} exec_ld=${LD_LIBRARY_PATH:-} exec_nvitop=$(command -v nvitop)"; nvitop --version' 2>&1 | strip)
    get() { grep -m1 -o "$1=[^ ]*" <<<"$out" | cut -d= -f2-; }
    rc=1
    [ -n "$ide_compat" ] && [ "$(get exec_compat)" = "$ide_compat" ] && [ "$(get exec_ld)" = "$ide_ld" ] && rc=0
    result "T6 exec bash -i: forward-compat env" "$rc" "MESA_CUDA_COMPAT=$(get exec_compat) LD_LIBRARY_PATH=$(get exec_ld) (IDE: ${ide_compat:-unset}, ${ide_ld:-empty})"

    rc=1
    nv_ver=$(grep -m1 -iE '^nvitop' <<<"$out")
    [ "$(get exec_nvitop)" = /opt/conda/bin/nvitop ] && [ -n "$nv_ver" ] && rc=0
    result "T6 exec bash -i: nvitop on PATH" "$rc" "command -v nvitop = $(get exec_nvitop); ${nv_ver:-nvitop --version printed nothing}"

    # kasm's vnc_startup (and user scripts) source bashrc files under set -e:
    # the appended block must not abort them, and sourcing twice must not
    # prepend the compat dir twice.
    out=$(docker exec -u 1000 "$C" bash -c 'set -e; PS1="$ "; . /etc/bash.bashrc; . /etc/bash.bashrc; . ~/.bashrc >/dev/null 2>&1; echo "sete_ok compat=${MESA_CUDA_COMPAT:-unset} ld=${LD_LIBRARY_PATH:-}"' 2>&1 | strip)
    rc=1
    [ "$(get compat)" = "$ide_compat" ] && [ "$(get ld)" = "$ide_ld" ] && grep -q '^sete_ok ' <<<"$out" && rc=0
    result "T6 set -e script sourcing bashrc" "$rc" "$(grep -m1 '^sete_ok' <<<"$out" || tail -2 <<<"$out" | tr '\n' ' ')"
else
    result "T6 exec shell" 1 "skipped: container not up"
fi

# ---------------------------------------------------------------------------
hdr "T2 Docker health"
if [ "$up" = 1 ]; then
    deadline=$((SECONDS + 150)) hs=
    while [ $SECONDS -lt $deadline ]; do
        hs=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$C")
        [ "$hs" = starting ] || break
        sleep 5
    done
    rc=1
    [ "$hs" = healthy ] && rc=0
    result "T2 Docker health (ttyd check)" "$rc" "$hs $((SECONDS - t_start)) s after start; test $(docker image inspect -f '{{json .Config.Healthcheck.Test}}' "$IMAGE")"
else
    result "T2 Docker health (ttyd check)" 1 "skipped: container not up"
fi

# ---------------------------------------------------------------------------
hdr "T5 no GPU"
C=$PREFIX-nogpu
NAMES+=("$C")
t0=$SECONDS
if addr=$(start "$C") && wait_http "$C" "$addr"; then
    result "T5 ttyd HTTP 200 (no GPU)" 0 "http://$addr/ after $((SECONDS - t0)) s"
    if ttyd_type "$C" '/etc/motd > /tmp/mesa-t5.out 2>&1; echo $? > /tmp/mesa-t5.done' /tmp/mesa-t5.done 120; then
        motd=$(docker exec "$C" cat /tmp/mesa-t5.out | strip | grep -m1 'no NVIDIA GPU visible' | sed 's/^ *//')
        rc=1
        [ -n "$motd" ] && rc=0
        result "T5 terminal + landing screen (no GPU)" "$rc" "${motd:-no 'no NVIDIA GPU visible' line in /etc/motd output}"
    else
        result "T5 terminal + landing screen (no GPU)" 1 "terminal did not open without a GPU"
    fi
    out=$(docker exec -u 1000 "$C" mesa-gpu-check 2>&1)
    rc=$?
    out=$(strip <<<"$out")
    printf '%s\n' "$out"
    if [ "$rc" = 1 ] && grep -q 'FAIL.*no NVIDIA GPU in this container' <<<"$out" && grep -q '^== Summary' <<<"$out"; then
        result "T5 mesa-gpu-check reports no GPU" 0 "exit 1; $(grep -m1 'no NVIDIA GPU' <<<"$out" | sed 's/^ *\[FAIL\] //' | cut -c1-70)..."
    else
        result "T5 mesa-gpu-check reports no GPU" 1 "exit $rc (want 1 with a 'no NVIDIA GPU' failure and a summary)"
    fi
else
    result "T5 ttyd HTTP 200 (no GPU)" 1 "no HTTP 200 on $PORT within 300 s"
fi

# ---------------------------------------------------------------------------
hdr "Results ($IMAGE, GPU=$GPU)"
printf '%s\n' "${RESULTS[@]}"
if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASSED (${#RESULTS[@]} checks, $SKIPPED skipped)"
else
    echo "$FAILED of ${#RESULTS[@]} checks FAILED"
fi
[ "$FAILED" -eq 0 ]
