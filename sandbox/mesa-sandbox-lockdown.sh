#!/bin/bash
# mesa-sandbox-lockdown — turns a published MESA VICE image into an AI Sandbox:
# no sudo, no setuid/setgid binaries, no file capabilities, no usable account
# passwords, no group-writable /etc/passwd, no world-writable system files.
# Shared file: keep identical in the five idss-mesa repos (sandbox/).
#
# Usage (build time, as root):  mesa-sandbox-lockdown <session user> [file-cap to keep ...]
#
# What stays: the session user's own home, /opt/conda (user-owned), pip/npm/R
# user-level installs. What goes: every path from UID 1000 to UID 0. VICE runs
# the container as UID 1000 with the default capability set, so after this
# script there is no way to become root inside the pod even though the
# platform does not set allowPrivilegeEscalation=false.
set -euo pipefail
user="$1"; shift
keep_caps=("$@")
export DEBIAN_FRONTEND=noninteractive

# getcap/setcap (libcap2-bin) are not in every base (the jupyter images lack them)
if ! command -v getcap >/dev/null 2>&1 || ! command -v setcap >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq --no-install-recommends libcap2-bin >/dev/null && rm -rf /var/lib/apt/lists/*
fi

echo "== sudo: purge the package and every grant"
# dpkg, not apt: `apt-get purge sudo` also removes every package that Depends on
# sudo (rocker's rstudio-server among them). --force-depends removes only sudo.
# The maintainer scripts are dropped first: sudo's prerm (update-alternatives for
# sudo.ws on 26.04) fails in a layer, and everything it would undo is rm'd below.
for p in sudo sudo-ldap; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        rm -f "/var/lib/dpkg/info/$p.prerm" "/var/lib/dpkg/info/$p.postrm"
        dpkg --purge --force-depends "$p" >/dev/null
    fi
done
rm -rf /etc/sudoers /etc/sudoers.bak /etc/sudoers.d /etc/sudo.conf /etc/sudo_logsrvd.conf /usr/lib/sudo /usr/libexec/sudo \
       /var/lib/sudo /var/log/sudo-io /usr/bin/sudo /usr/bin/sudo.ws /usr/bin/sudoedit /usr/bin/sudoreplay /usr/sbin/visudo \
       /etc/alternatives/sudo /var/lib/dpkg/alternatives/sudo
for g in sudo admin wheel; do
    getent group "$g" >/dev/null 2>&1 && gpasswd -d "$user" "$g" >/dev/null 2>&1 || true
done

echo "== su / pkexec / polkit: nothing may switch user"
rm -f /usr/bin/pkexec /usr/lib/polkit-1/polkit-agent-helper-1 /usr/libexec/polkit-agent-helper-1
printf 'auth requisite pam_deny.so\n' > /etc/pam.d/su

echo "== setuid / setgid bits: none"
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -print0 | xargs -0r chmod ug-s

echo "== file capabilities: none (kept: ${keep_caps[*]:-none})"
getcap -r / 2>/dev/null | awk '{print $1}' | while read -r f; do
    keep=0
    for k in "${keep_caps[@]}"; do [ "$f" = "$k" ] && keep=1; done
    [ "$keep" = 1 ] || setcap -r "$f"
done

echo "== account passwords: lock every account that has one (rocker sets rstudio:rstudio)"
awk -F: '$2 != "" && $2 !~ /^[!*]/ {print $1}' /etc/shadow | while read -r u; do usermod -L "$u"; done
usermod -L root >/dev/null 2>&1 || true

echo "== /etc/passwd, /etc/group: not group-writable (the jupyter base does chmod g+w /etc/passwd)"
chmod 644 /etc/passwd /etc/group
chmod 640 /etc/shadow /etc/gshadow 2>/dev/null || true

echo "== world-writable system files/dirs: none (the Kasm base leaves VNC/squid/cups configs o+w)"
find /etc /usr /opt /var/lib -xdev -type f -perm -o+w -print0 2>/dev/null | xargs -0r chmod o-w
find /etc /usr /opt /var/lib -xdev -type d -perm -o+w ! -perm -1000 -print0 2>/dev/null | xargs -0r chmod o-w
# the Kasm startup script writes its logs under /dockerstartup as the session user
if [ -d /dockerstartup ]; then
    find /dockerstartup -type f -name '*.log' -exec chown "$user" {} + 2>/dev/null || true
    find /dockerstartup -xdev -type f -perm -o+w ! -name '*.log' -print0 | xargs -0r chmod o-w
fi

echo "== marker + session env"
mkdir -p /etc/mesa && : > /etc/mesa/sandbox
printf '# MESA AI Sandbox: no sudo, no setuid, no file capabilities (see /etc/mesa/sandbox)\nexport MESA_SANDBOX=1\n' > /etc/profile.d/mesa-sandbox.sh
chmod 644 /etc/profile.d/mesa-sandbox.sh

echo "== verify"
if command -v sudo >/dev/null 2>&1; then echo "sudo is still present" >&2; exit 1; fi
if [ -e /etc/sudoers ] || [ -d /etc/sudoers.d ]; then echo "sudoers still present" >&2; exit 1; fi
if id -nG "$user" | tr ' ' '\n' | grep -qxE 'sudo|admin|wheel'; then echo "$user is still in an admin group" >&2; exit 1; fi
left=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f | head -5)
if [ -n "$left" ]; then printf 'setuid/setgid files remain:\n%s\n' "$left" >&2; exit 1; fi
caps=$(getcap -r / 2>/dev/null | awk '{print $1}' | sort)
for k in "${keep_caps[@]}"; do caps=$(printf '%s\n' "$caps" | grep -vx "$k" || true); done
if [ -n "$caps" ]; then printf 'file capabilities remain:\n%s\n' "$caps" >&2; exit 1; fi
if awk -F: '$2 != "" && $2 !~ /^[!*]/ {f=1} END {exit !f}' /etc/shadow; then echo "an account still has a usable password" >&2; exit 1; fi
echo "sandbox lockdown complete for $user"
