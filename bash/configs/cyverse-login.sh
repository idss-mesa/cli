#!/usr/bin/env bash
# cyverse-login — authenticate to your private CyVerse Data Store (iRODS).
#
# Writes the standard iRODS credential files:
#   ~/.irods/irods_environment.json  (host / port / zone / your username)
#   ~/.irods/.irodsA                 (your scrambled password, chmod 600)
# These are read by GoCommands (gocmd), the iRODS/mesa MCP servers, and the
# agent CLIs, so one login authenticates them all. Without this you get
# anonymous, public-data-only access.
#
# Your password is stored only in ~/.irods/.irodsA in this ephemeral container
# home; it is never committed or sent anywhere but data.cyverse.org.
set -euo pipefail

HOST="${IRODS_HOST:-data.cyverse.org}"
PORT="${IRODS_PORT:-1247}"
ZONE="${IRODS_ZONE_NAME:-iplant}"
ENVDIR="$HOME/.irods"
ENVFILE="$ENVDIR/irods_environment.json"
AUTHFILE="$ENVDIR/.irodsA"

c_cyan=$'\e[38;2;45;212;191m'; c_green=$'\e[38;2;74;222;128m'
c_orange=$'\e[38;2;212;113;42m'; c_muted=$'\e[38;2;74;98;114m'; c_off=$'\e[0m'
say()  { printf '%s%s%s\n' "$c_cyan" "$1" "$c_off"; }
warn() { printf '%s%s%s\n' "$c_orange" "$1" "$c_off"; }
note() { printf '%s%s%s\n' "$c_muted" "$1" "$c_off"; }

say "CyVerse Data Store login ($HOST, zone $ZONE)"
default_user="${IPLANT_USER:-}"
if [ -n "$default_user" ]; then
  printf '%sCyVerse username [%s]:%s ' "$c_green" "$default_user" "$c_off"; read -r user
  user="${user:-$default_user}"
else
  printf '%sCyVerse username:%s ' "$c_green" "$c_off"; read -r user
fi
[ -z "$user" ] && { warn "No username entered; aborting."; exit 1; }
printf '%sCyVerse password:%s ' "$c_green" "$c_off"; read -rs pw; echo
[ -z "$pw" ] && { warn "No password entered; aborting."; exit 1; }

mkdir -p "$ENVDIR"; chmod 700 "$ENVDIR"
cat > "$ENVFILE" <<JSON
{
    "irods_host": "$HOST",
    "irods_port": $PORT,
    "irods_zone_name": "$ZONE",
    "irods_user_name": "$user",
    "irods_authentication_scheme": "native"
}
JSON

# Scramble the password into ~/.irods/.irodsA (same format iinit writes),
# using python-irodsclient from the mesa venv.
PW="$pw" /opt/mesa/bin/python3 - "$AUTHFILE" <<'PY'
import os, sys
from irods.password_obfuscation import encode
with open(sys.argv[1], "w") as f:
    f.write(encode(os.environ["PW"]))
os.chmod(sys.argv[1], 0o600)
PY

# Note: formation (CyVerse Discovery Environment) is a hosted, OAuth-protected
# remote MCP (https://de.cyverse.org/formation/mcp). It does NOT use these
# Data Store credentials — you authenticate to it in-agent with your CyVerse
# account (run /mcp in Claude Code or OpenCode and follow the login prompt).
unset pw

# Verify the credentials actually work, using the same python-irodsclient
# library the mesa/irods MCP servers use — so a pass here means they will
# authenticate too.
say "Verifying against /$ZONE/home/$user ..."
if /opt/mesa/bin/python3 - "$ENVFILE" "/$ZONE/home/$user" <<'PY'
import sys
from irods.session import iRODSSession
try:
    with iRODSSession(irods_env_file=sys.argv[1]) as s:
        s.collections.get(sys.argv[2])
except Exception as e:
    print(e, file=sys.stderr); sys.exit(1)
PY
then
  say "Authenticated as $user. gocmd, the iRODS/mesa MCP servers, and the agent CLIs now use your account."
  note "Restart any already-open agent (claude / opencode) so its MCP servers pick up the new credentials."
else
  warn "Wrote credentials, but the login test failed — removing them to keep you on"
  warn "safe anonymous access. Check your username/password and rerun cyverse-login."
  rm -f "$AUTHFILE"
  exit 1
fi
