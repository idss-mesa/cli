#!/bin/bash
# test-sandbox.sh IMAGE — start the AI Sandbox image as VICE does (UID 1000) and
# prove the lockdown: no sudo, no root path, no setuid, no file caps, app answers.
# Env: SANDBOX_PORT (required), SANDBOX_PATH (default /), SANDBOX_DOCKER_ARGS (extra
# docker run args, e.g. --shm-size=512m), SANDBOX_WAIT (seconds, default 180).
set -uo pipefail
img="${1:?usage: test-sandbox.sh IMAGE}"
port="${SANDBOX_PORT:?set SANDBOX_PORT}"; path="${SANDBOX_PATH:-/}"; wait="${SANDBOX_WAIT:-180}"
name="sandbox-test-$$"; fail=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }
cleanup() { docker rm -f "$name" >/dev/null 2>&1; }
trap cleanup EXIT

echo "-- image config"
u=$(docker image inspect -f '{{.Config.User}}' "$img")
[ -n "$u" ] && [ "$u" != root ] && [ "$u" != 0 ] && ok "USER is $u" || bad "USER is '$u'"

echo "-- static (as root, before the entrypoint)"
docker run --rm --user 0 --entrypoint /bin/sh "$img" -c '
  r=0
  command -v sudo >/dev/null 2>&1 && { echo "sudo present"; r=1; }
  [ -e /etc/sudoers ] && { echo "/etc/sudoers present"; r=1; }
  s=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | head -3); [ -n "$s" ] && { echo "setuid/setgid: $s"; r=1; }
  c=$(getcap -r / 2>/dev/null | head -3); [ -n "$c" ] && { echo "file caps: $c"; r=1; }
  [ -e /etc/mesa/sandbox ] || { echo "marker /etc/mesa/sandbox missing"; r=1; }
  exit $r' && ok "no sudo, no setuid/setgid, no file caps, marker present" || bad "static lockdown check"

echo "-- runtime as UID 1000"
docker run -d --name "$name" --user 1000 -e IPLANT_USER=sandboxtest ${SANDBOX_DOCKER_ARGS:-} "$img" >/dev/null || { bad "container start"; exit 1; }
for i in $(seq 1 "$((wait/3))"); do
  docker exec -u 1000 "$name" curl -fsS -o /dev/null -m 3 "http://127.0.0.1:${port}${path}" >/dev/null 2>&1 && break
  if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then break; fi
  sleep 3
done
docker exec -u 1000 "$name" curl -fsS -o /dev/null -m 3 "http://127.0.0.1:${port}${path}" >/dev/null 2>&1 \
  && ok "app answers on :${port}${path}" || { bad "app did not answer on :${port}${path} within ${wait}s"; docker logs "$name" 2>&1 | tail -20; }
docker exec -u 1000 "$name" sh -c 'command -v sudo' >/dev/null 2>&1 && bad "sudo on PATH" || ok "no sudo on PATH"
docker exec -u 1000 "$name" sh -c 'su -c id root </dev/null' >/dev/null 2>&1 && bad "su to root worked" || ok "su denied"
docker exec -u 1000 "$name" sh -c 'touch /etc/.probe' >/dev/null 2>&1 && bad "/etc writable" || ok "/etc not writable"
docker exec -u 1000 "$name" sh -c '[ "$(id -u)" = 1000 ] && [ "$(awk "/^Uid:/{print \$2}" /proc/1/status)" = 1000 ]' \
  && ok "PID 1 and shell run as UID 1000" || bad "a process runs as another UID"
root_procs=$(docker exec -u 1000 "$name" sh -c 'for p in /proc/[0-9]*; do awk "/^Uid:/ && \$2==0 {print \"$p\"}" $p/status 2>/dev/null; done' | wc -l)
[ "$root_procs" = 0 ] && ok "no root processes" || bad "$root_procs process(es) run as root"
docker exec -u 1000 "$name" sh -c '[ "$MESA_SANDBOX" = 1 ] || . /etc/profile.d/mesa-sandbox.sh && [ "$MESA_SANDBOX" = 1 ]' \
  && ok "MESA_SANDBOX=1 via /etc/profile.d" || bad "MESA_SANDBOX not set"
[ "$fail" = 0 ] && echo "PASS $img" || { echo "FAIL $img"; exit 1; }
