#!/usr/bin/env bash
# Launcher shim for mesa-mcp, installed at /usr/local/bin/mesa-mcp.
#
# mesa_mcp.config coerces every MESA_MCP_* env var, turning an EMPTY value into
# None. An empty MESA_MCP_IRODS__USER therefore overrides the "anonymous"
# default and fails pydantic Config validation, so the server exits 1 before the
# stdio handshake — every agent CLI then reports the mesa server as failed
# (JSON-RPC -32000). Strip any empty MESA_MCP_* var so a stray empty value
# (from a spawner, base image, or shell) can never break startup again.
for v in $(compgen -e | grep '^MESA_MCP_'); do
  [ -z "${!v}" ] && unset "$v"
done
exec /opt/mesa/bin/mesa-mcp "$@"
