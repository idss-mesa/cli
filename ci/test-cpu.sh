#!/usr/bin/env bash
# test-cpu.sh IMAGE — smoke test of the CPU image: the tools answer, the
# Python environments import, the terminal comes up. No GPU, no network.
set -euo pipefail
img="${1:?usage: test-cpu.sh IMAGE}"
name="cpu-test-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

echo "-- tools and environments"
docker run --rm --network none --entrypoint bash "$img" -c '
  set -e
  claude --version
  codex --version
  opencode --version
  goose --version
  agy --version
  gh --version | head -1
  duckdb --version
  test -x /home/jovyan/.npm-global/bin/mcp-server-filesystem
  command -v mesa-mcp mesa-ducklake irods-mcp-server gocmd aws ttyd tini >/dev/null
  /opt/mesa/bin/python -c "from importlib.metadata import version as v; print(\"mesa-mcp\", v(\"mesa-mcp\"), \"mesa-ducklake\", v(\"mesa-ducklake\"))"
  /opt/conda/bin/python -c "import duckdb; print(\"duckdb\", duckdb.__version__)"
  /opt/conda/envs/geospatial/bin/python -c "from osgeo import gdal; import pdal, geopandas; print(\"gdal\", gdal.__version__)" 2>/dev/null
  test -z "$(find /home/jovyan -xdev ! -user jovyan -print -quit)"
'

echo "-- ttyd answers on 7681"
docker run -d --name "$name" -e IPLANT_USER=cputest -p 127.0.0.1::7681 "$img" >/dev/null
port=$(docker port "$name" 7681/tcp | head -1 | sed 's/.*://')
for _ in $(seq 60); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/")" = 200 ]; then
    echo "PASS $img"
    exit 0
  fi
  sleep 2
done
docker logs "$name" 2>&1 | tail -20
echo "FAIL $img: ttyd did not answer" >&2
exit 1
