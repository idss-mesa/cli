# Every install below reads a pin or a lock file kept in git (locks/, and the
# ARGs here). `make relock` / `make update-pins` regenerate them; nothing in
# this file resolves a version at build time except Ubuntu-archive apt
# packages, which the SBOM records.
#
# Base image: date tag + index digest (covers amd64 and arm64).
ARG BASE_IMAGE=quay.io/jupyter/minimal-notebook:2026-11-10@sha256:29076b0b96c954a16b813cc5c4230f248711ef1d7528cb1208b82397e86a8b52
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="MESA Cloud Shell" \
      org.opencontainers.image.description="CyVerse VICE cloud shell (ttyd) with agent CLIs, geospatial conda env, mesa-mcp" \
      org.opencontainers.image.url="https://github.com/idss-mesa/cli" \
      org.opencontainers.image.source="https://github.com/idss-mesa/cli" \
      org.opencontainers.image.vendor="CyVerse"

USER root

# Target architecture set by buildx: amd64 or arm64
ARG TARGETARCH

# ---------------------------------------------------------------------------
# Pinned, checksum-verified downloads (2026-10 security review). Bump the
# version AND its hash together: a mismatch fails the build. Hashes are the
# sha256 of the upstream release asset. ci/pins.tsv says where each comes from.
# ---------------------------------------------------------------------------
ARG TINI_VERSION=0.19.0
ARG TINI_SHA256_AMD64=93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c
ARG TINI_SHA256_ARM64=07952557df20bfd2a95f9bef198b445e006171969499a1d361bd9e6f8e5e0e81
ARG GO_VERSION=1.27.3
ARG GO_SHA256_AMD64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG GO_SHA256_ARM64=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_X86_64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_AARCH64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165
ARG NODE_VERSION=22.23.4
ARG NODE_SHA256_X64=1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce
ARG NODE_SHA256_ARM64=6287aa46b6c375d816e63ae66d024fbbfd70404825aabdfdf898a970871d2f4b
ARG GOCMD_VERSION=v0.12.5
ARG GOCMD_SHA256_AMD64=af551f8cb2f3f5df63fb3a8eb1bf605c7f27e50ec10283a5375190239db9f57a
ARG GOCMD_SHA256_ARM64=2741c2a2c894ad156b63ea7ca16f5e7931662bd16e6331d4fbcfea904cc76143
ARG GCM_VERSION=2.7.3
ARG GCM_SHA256_X64=a5431e1b6f25aa8b424e747d880f86e74c739ad52e72c924a7b1a25d87ac7e72
ARG GCM_SHA256_ARM64=f5995901ef3a2ffc4442e4a9a92c8dfdc8f1df1affe8ef1d037b7ad3302b923b
ARG AWSCLI_VERSION=2.38.5
ARG AWSCLI_SHA256_X86_64=5def7d1b7e55d892f9a381bb2cb2081a685712464be0d36d5d706af0ac48d0d3
ARG AWSCLI_SHA256_AARCH64=07711a936e9d271045ab937d2c2c5390c25f419e4ba9e25adb9e996031e3f6be
ARG DUCKDB_SHA256_AMD64=c6507206baf7793c6013dbd82368469a45f20dc0e17a6f92f204602f652ed2bc
ARG DUCKDB_SHA256_ARM64=859e1875d2a9515fbb4bf8871061437a14af82320da68c753f094c4b776348fe
ARG GH_VERSION=2.103.3
ARG GH_SHA256_AMD64=e3bafef96328d1a67de3a968bdfe1cc2ffd58cf6aba8b5e201356897ed06bb3d
ARG GH_SHA256_ARM64=cac3ff84b60b68e64cca69f31f303210c26320361cc3286b773655d4226b7b06
# irods-mcp-server is built from source at this commit (go.sum pins its
# modules); the commit is stamped into the binary (`go version -m`)
ARG IRODS_MCP_COMMIT=8b1c231394601df49c66929bde971d167288c001
# Agent CLIs from npm (Claude Code, Codex, claude-code-router, filesystem MCP
# server) are locked in locks/npm/package-lock.json. better-sqlite3 (a
# claude-code-router dependency) ships its native addon as a release asset
# outside the npm lock; it is pinned here and must match the locked version.
ARG BETTER_SQLITE3_VERSION=12.11.1
ARG BETTER_SQLITE3_SHA256_X64=94ce113ea2d9347fcd1cf8e46445cc271d1dbd02d05a64aa460442222f023b11
ARG BETTER_SQLITE3_SHA256_ARM64=00f8035f4322c14ab4dbb3ee6f4b6c9ca25209fe2a77ac2759cd09dd42587d48
ARG OPENCODE_VERSION=1.19.4
ARG OPENCODE_SHA256_X64=849bd6b3d959a1d2ef200ed1634a51c79a45ca236aa26665d75debd694805cce
ARG OPENCODE_SHA256_ARM64=8568230ccd847dc93e95b9f6894379077d3e014a16b48040743573e77c23e85f
ARG GOOSE_VERSION=1.56.0
ARG GOOSE_SHA256_X86_64=e29544421a6e698aab0fe4becda96096218ff36abe85b83785519d41c555c714
ARG GOOSE_SHA256_AARCH64=30b60a49a534ca7af062ec94b752367494ad3a2824744a6d1e8ec3e1040d9922
# Antigravity CLI: version, build id and sha512 as published in Google's
# release manifest (<updater>/manifests/linux_<arch>.json).
ARG AGY_VERSION=1.5.7
ARG AGY_BUILD=6190022064472064
ARG AGY_SHA512_AMD64=60bca280414ed11723f58b3b671962ae394cc2d0c25e3f58e32e1c6847c978cbc77ec6f40e7f3992001c399d80aeb8b64c9ec892abddd591b12413c5ee6d9fce
ARG AGY_SHA512_ARM64=bebd69ad1713414b82e370aec6be0e678a413332bf3c835d9ba22e4befff040b6c74e1bf974fd83ebc4c733ed6e37d2bdc1caae58027c2b326dd04d630bfebb1

# Add sudo to user
ARG LOCAL_USER=jovyan

# Create group 1000 if it doesn't exist (CyVerse VICE may assign this GID)
RUN getent group 1000 || groupadd -g 1000 jovyan-group && \
    usermod -a -G 1000 jovyan

RUN apt-get update && \
    apt-get install -y sudo && \
    echo "jovyan ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Tini
ENV TZ=America/Phoenix
ENV LANG=C.UTF-8 
ENV LC_ALL="en_US.UTF-8"
ENV PATH=/opt/conda/bin:$PATH
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    gettext-base git mercurial subversion \
    tmux curl grep sed dpkg xz-utils unzip && \
    TINI_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$TINI_SHA256_ARM64" || echo "$TINI_SHA256_AMD64") && \
    curl -fsSL -o /usr/bin/tini "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-${TARGETARCH}" && \
    echo "${TINI_SHA256}  /usr/bin/tini" | sha256sum -c - && \
    chmod +x /usr/bin/tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Go (pinned + sha256; Go >= 1.25.7 fixes CVE-2025-68121 in every binary built here)
RUN GO_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GO_SHA256_ARM64" || echo "$GO_SHA256_AMD64") && \
    curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" && \
    echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local -f /tmp/go.tgz && rm -f /tmp/go.tgz

# Build the iRODS MCP server (stdio MCP access to the CyVerse Data Store)
# https://github.com/idss-mesa/irods-mcp-server
# NOTE: the base image sets ENV HOME=/home/jovyan even for root, so HOME and
# the Go caches point at /tmp here, or Go's caches and telemetry counters land
# root-owned in jovyan's home (~/.config)
RUN git init -q /tmp/irods-mcp-server && cd /tmp/irods-mcp-server && \
    git fetch -q --depth 1 https://github.com/idss-mesa/irods-mcp-server "${IRODS_MCP_COMMIT}" && \
    git checkout -q FETCH_HEAD && test "$(git rev-parse HEAD)" = "${IRODS_MCP_COMMIT}" && \
    HOME=/tmp/go-home CGO_ENABLED=0 GOFLAGS=-mod=readonly GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -buildvcs=true -o /usr/local/bin/irods-mcp-server ./cmd && \
    HOME=/tmp/go-home /usr/local/go/bin/go version -m /usr/local/bin/irods-mcp-server | grep -F "vcs.revision=${IRODS_MCP_COMMIT}" && \
    cd / && rm -rf /tmp/irods-mcp-server /tmp/go /tmp/go-cache /tmp/go-home

# install ttyd (pinned + sha256)
RUN TTYD_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    TTYD_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$TTYD_SHA256_AARCH64" || echo "$TTYD_SHA256_X86_64") && \
    curl -fsSL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" && \
    echo "${TTYD_SHA256}  /usr/local/bin/ttyd" | sha256sum -c - && \
    chmod a+x /usr/local/bin/ttyd

# Install remaining packages: locales, terminal tools, s3fs
RUN apt-get update && \
    apt-get install -y locales lolcat fastfetch figlet w3m-img imagemagick s3fs fuse socat bubblewrap && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Node.js from the official tarball (pinned + sha256 from nodejs.org's SHASUMS256.txt)
RUN NODE_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    NODE_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$NODE_SHA256_ARM64" || echo "$NODE_SHA256_X64") && \
    curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" && \
    echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - && \
    tar -xJ -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md' -f /tmp/node.tar.xz && \
    rm -f /tmp/node.tar.xz && node --version && npm --version

# Install GoCommands (pinned + sha256; it is NOT self-upgraded from ~/.bashrc any more)
# https://learning.cyverse.org/ds/gocommands/
RUN GOCMD_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GOCMD_SHA256_ARM64" || echo "$GOCMD_SHA256_AMD64") && \
    curl -fsSL -o /tmp/gocmd.tgz "https://github.com/cyverse/gocommands/releases/download/${GOCMD_VERSION}/gocmd-${GOCMD_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    echo "${GOCMD_SHA256}  /tmp/gocmd.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local/bin -f /tmp/gocmd.tgz && rm -f /tmp/gocmd.tgz && gocmd --version

ENV PATH=${PATH}:/usr/games

# install git-credential-manager (pinned + sha256)
RUN GCM_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    GCM_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GCM_SHA256_ARM64" || echo "$GCM_SHA256_X64") && \
    curl -fsSL -o /tmp/gcm.deb "https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/gcm-linux-${GCM_ARCH}-${GCM_VERSION}.deb" && \
    echo "${GCM_SHA256}  /tmp/gcm.deb" | sha256sum -c - && \
    apt-get update && \
    apt-get install -y /tmp/gcm.deb && \
    rm -f /tmp/gcm.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI from its release .deb (pinned + sha256; no apt repository
# is added, so `apt upgrade` in a running container does not move it)
RUN GH_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GH_SHA256_ARM64" || echo "$GH_SHA256_AMD64") && \
    curl -fsSL -o /tmp/gh.deb "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.deb" && \
    echo "${GH_SHA256}  /tmp/gh.deb" | sha256sum -c - && \
    apt-get update && \
    apt-get install -y /tmp/gh.deb && \
    rm -f /tmp/gh.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    test "$(dpkg-query -W -f '${Version}' gh)" = "${GH_VERSION}"

# install AWS CLI (pinned + sha256)
RUN AWS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    AWS_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$AWSCLI_SHA256_AARCH64" || echo "$AWSCLI_SHA256_X86_64") && \
    curl -fsSL -o /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${AWSCLI_VERSION}.zip" && \
    echo "${AWS_SHA256}  /tmp/awscliv2.zip" | sha256sum -c - && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Install mesa-mcp and mesa-ducklake (https://github.com/idss-mesa)
# into a dedicated venv: they need Python >=3.11 and the geospatial
# conda env pins 3.10, so they get the base conda Python instead.
# Installed from locks/mesa-venv.<arch>.txt (every wheel by sha256, built from
# locks/mesa-venv.in: the wheels attached to the two projects' GitHub
# releases). DuckDB 2.0 (mesa-ducklake >= 0.2) writes catalogs DuckDB 1.x
# cannot open; the assertion fails the build if the venv Python or DuckDB is
# too old. The lock files stay in the image under /usr/share/mesa/locks.
COPY locks/mesa-venv.${TARGETARCH}.txt locks/base-pip.${TARGETARCH}.txt /usr/share/mesa/locks/
RUN /opt/conda/bin/python3 -m venv /opt/mesa && \
    /opt/mesa/bin/pip install --no-cache-dir --no-deps --require-hashes --only-binary :all: \
      -r "/usr/share/mesa/locks/mesa-venv.${TARGETARCH}.txt" && \
    /opt/mesa/bin/pip check && \
    /opt/mesa/bin/python -c "import sys, duckdb; from importlib.metadata import version as v; assert sys.version_info >= (3, 11), sys.version; assert duckdb.__version__.startswith('2.'), duckdb.__version__; print('mesa-mcp', v('mesa-mcp'), 'mesa-ducklake', v('mesa-ducklake'), 'duckdb', duckdb.__version__)" && \
    ln -s /opt/mesa/bin/mesa-mcp /opt/mesa/bin/mesa-ducklake /usr/local/bin/

# DuckDB 2.0 for users: the `duckdb` CLI on PATH (duckdb for the base conda
# Python comes from locks/base-pip below). Same major as /opt/mesa, so catalogs
# mesa-ducklake writes (DuckDB 2-only) open here too.
ARG DUCKDB_VERSION=2.0.0
RUN DUCKDB_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64) && \
    DUCKDB_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$DUCKDB_SHA256_ARM64" || echo "$DUCKDB_SHA256_AMD64") && \
    curl -fsSL -o /tmp/duckdb.tgz "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb-cli-linux-${DUCKDB_ARCH}.tar.gz" && \
    echo "${DUCKDB_SHA256}  /tmp/duckdb.tgz" | sha256sum -c - && \
    tar -xz -C /usr/local/bin -f /tmp/duckdb.tgz duckdb && rm -f /tmp/duckdb.tgz && \
    duckdb --version | grep "^v${DUCKDB_VERSION} "

# Configure FUSE for non-root users and create OSN directory
RUN echo "user_allow_other" >> /etc/fuse.conf && \
    chmod 644 /etc/fuse.conf && \
    mkdir -p /osn && \
    chmod 755 /osn && \
    chown 1000:100 /osn

# set the ENV for the credential type
ENV GCM_CREDENTIAL_STORE=cache

USER jovyan

# The base image sets HOME=/home/jovyan for root too: a root step that writes
# under $HOME leaves directories jovyan cannot use. Fail here, not at runtime.
RUN found=$(find /home/jovyan -xdev ! -user jovyan | head -20) && \
    if [ -n "$found" ]; then echo "not owned by jovyan:" >&2; echo "$found" >&2; exit 1; fi

# Into the base image's /opt/conda Python (owned by jovyan), from
# locks/base-pip.<arch>.txt: duckdb (same version as the CLI above) and the
# security floors for packages the base ships (certifi, urllib3, msgpack;
# Trivy 2026-10).
RUN /opt/conda/bin/pip install --no-cache-dir --no-deps --require-hashes --only-binary :all: \
      -r "/usr/share/mesa/locks/base-pip.${TARGETARCH}.txt" && \
    /opt/conda/bin/pip check && \
    /opt/conda/bin/python -c "import duckdb; assert duckdb.__version__ == '${DUCKDB_VERSION}', duckdb.__version__"

# Install Claude Code, OpenAI Codex, and Claude Code Router via npm
# (npm install is preferred over claude.ai/install.sh for Docker builds)
# ccr (claude-code-router) lets Claude Code talk to AI Verde's non-Anthropic
# models; see aiverde-setup and https://github.com/musistudio/claude-code-router
# The whole dependency tree is installed by `npm ci` from locks/npm/ (every
# tarball by integrity hash) into the same place `npm install -g` used:
# ~/.npm-global/lib/node_modules, commands linked in ~/.npm-global/bin. The
# filesystem MCP server is installed here so the agent configs run it directly
# instead of `npx -y` fetching the newest release at every agent start.
# No package install script runs, except Claude Code's own install.cjs, which
# only links the native binary that came with the locked optional dependency.
COPY --chown=1000:100 locks/npm/package.json locks/npm/package-lock.json /home/jovyan/.npm-global/lib/
RUN npm config set prefix /home/jovyan/.npm-global && \
    cd /home/jovyan/.npm-global/lib && \
    npm ci --ignore-scripts --no-audit --no-fund && \
    test -z "$(find node_modules -maxdepth 2 -name '*-musl')" && \
    (cd node_modules/@anthropic-ai/claude-code && node install.cjs) && \
    test "$(node -p "require('better-sqlite3/package.json').version")" = "${BETTER_SQLITE3_VERSION}" && \
    BS3_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    BS3_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$BETTER_SQLITE3_SHA256_ARM64" || echo "$BETTER_SQLITE3_SHA256_X64") && \
    curl -fsSL -o /tmp/bs3.tgz "https://github.com/WiseLibs/better-sqlite3/releases/download/v${BETTER_SQLITE3_VERSION}/better-sqlite3-v${BETTER_SQLITE3_VERSION}-node-v$(node -p process.versions.modules)-linux-${BS3_ARCH}.tar.gz" && \
    echo "${BS3_SHA256}  /tmp/bs3.tgz" | sha256sum -c - && \
    tar -xz -C node_modules/better-sqlite3 -f /tmp/bs3.tgz && rm -f /tmp/bs3.tgz && \
    node -e "new (require('better-sqlite3'))(':memory:')" && \
    mkdir -p /home/jovyan/.npm-global/bin && \
    for c in claude codex ccr mcp-server-filesystem; do \
      test -x "node_modules/.bin/$c" && ln -s "../lib/node_modules/.bin/$c" "/home/jovyan/.npm-global/bin/$c" || exit 1; \
    done && \
    npm cache clean --force && \
    /home/jovyan/.npm-global/bin/claude --version && /home/jovyan/.npm-global/bin/codex --version

# Install Antigravity CLI (replaces deprecated Google Gemini CLI — deadline June 18 2026).
# Same payload Google's installer fetches (its release manifest gives version,
# URL and sha512), downloaded directly so the version is pinned here.
# https://antigravity.google/blog/introducing-google-antigravity-cli
# Binary: agy, installed to ~/.local/bin
RUN AGY_DIR=$([ "$TARGETARCH" = "arm64" ] && echo linux-arm || echo linux-x64) && \
    AGY_FILE=$([ "$TARGETARCH" = "arm64" ] && echo cli_linux_arm64 || echo cli_linux_x64) && \
    AGY_SHA512=$([ "$TARGETARCH" = "arm64" ] && echo "$AGY_SHA512_ARM64" || echo "$AGY_SHA512_AMD64") && \
    curl -fsSL -o /tmp/agy.tgz "https://storage.googleapis.com/antigravity-public/antigravity-cli/${AGY_VERSION}-${AGY_BUILD}/${AGY_DIR}/${AGY_FILE}.tar.gz" && \
    echo "${AGY_SHA512}  /tmp/agy.tgz" | sha512sum -c - && \
    mkdir -p /home/jovyan/.local/bin /tmp/agy && \
    tar -xz -C /tmp/agy -f /tmp/agy.tgz antigravity && \
    install -m 0755 /tmp/agy/antigravity /home/jovyan/.local/bin/agy && \
    rm -rf /tmp/agy /tmp/agy.tgz && \
    /home/jovyan/.local/bin/agy --version | grep -F "${AGY_VERSION}"

# Install OpenCode (https://opencode.ai/) from its release archive (pinned +
# sha256). The regular x64 build needs AVX2; upstream's installer would pick
# whatever suits the build machine.
RUN OC_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    OC_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$OPENCODE_SHA256_ARM64" || echo "$OPENCODE_SHA256_X64") && \
    curl -fsSL -o /tmp/opencode.tgz "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}.tar.gz" && \
    echo "${OC_SHA256}  /tmp/opencode.tgz" | sha256sum -c - && \
    mkdir -p /home/jovyan/.opencode/bin && \
    tar -xz -C /home/jovyan/.opencode/bin -f /tmp/opencode.tgz opencode && rm -f /tmp/opencode.tgz && \
    /home/jovyan/.opencode/bin/opencode --version | grep -F "${OPENCODE_VERSION}"

# Install Goose CLI (https://block.github.io/goose/) from its release archive
# (pinned + sha256). No setup wizard runs: provider/key are wired at runtime by
# aiverde-setup; MCP servers come from configs/goose-config.yaml.
RUN GOOSE_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    GOOSE_SHA256=$([ "$TARGETARCH" = "arm64" ] && echo "$GOOSE_SHA256_AARCH64" || echo "$GOOSE_SHA256_X86_64") && \
    curl -fsSL -o /tmp/goose.tar.bz2 "https://github.com/block/goose/releases/download/v${GOOSE_VERSION}/goose-${GOOSE_ARCH}-unknown-linux-gnu.tar.bz2" && \
    echo "${GOOSE_SHA256}  /tmp/goose.tar.bz2" | sha256sum -c - && \
    mkdir -p /tmp/goose && tar -xj -C /tmp/goose -f /tmp/goose.tar.bz2 && \
    install -m 0755 "$(find /tmp/goose -type f -name goose | head -1)" /home/jovyan/.local/bin/goose && \
    rm -rf /tmp/goose /tmp/goose.tar.bz2 && \
    /home/jovyan/.local/bin/goose --version | grep -F "${GOOSE_VERSION}"

# A running container should match its SBOM: turn off the self-updaters that
# have a switch (Claude Code, OpenCode). Codex and Goose only notify.
ENV DISABLE_AUTOUPDATER=1 \
    OPENCODE_DISABLE_AUTOUPDATE=1

# Configure bashrc
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo ". /etc/profile.d/mesa-prompt.sh" >> ~/.bashrc && \
    echo '[ ! -z "$TERM" -a -r /etc/motd ] && /etc/motd' >> ~/.bashrc
# (the former per-shell `sudo gocmd upgrade` is gone: gocmd is pinned at build time;
#  a root-run self-updater on every terminal open was a supply-chain path and hung
#  shells whenever egress was slow)

# set path for Go, NPM globals, OpenCode, and Antigravity CLI
ENV PATH="/home/jovyan/.local/bin:/home/jovyan/.npm-global/bin:/home/jovyan/.opencode/bin:/usr/local/go/bin:${PATH}"

# set shell as bash and terminal as linux
ENV SHELL=bash
ENV TERM=xterm

# open port 7681 for ttyd
EXPOSE 7681

#set working directory
WORKDIR /home/jovyan/data-store

# create iRODS directory
RUN mkdir /home/jovyan/.irods

# geospatial conda env from the explicit lock (every package by URL + sha256;
# no solve at build time). environment.yml is the intent `make relock` solves;
# it is copied for reference only.
COPY --chown=1000:100 environment.yml /home/jovyan/
COPY locks/geospatial.${TARGETARCH}.lock locks/geospatial-pip.${TARGETARCH}.txt /usr/share/mesa/locks/
RUN mamba create -y -q -n geospatial --file "/usr/share/mesa/locks/geospatial.${TARGETARCH}.lock" && \
    /opt/conda/envs/geospatial/bin/python -c "from osgeo import gdal; import pdal, geopandas; print('gdal', gdal.__version__, 'pdal', pdal.__version__, 'geopandas', geopandas.__version__)"

# Security floors in the geospatial env (Trivy, 2026-10): urllib3 < 2.8, Brotli < 1.2.1
# and tornado < 6.5.9 carry fixed HIGH/CRITICAL CVEs and conda-forge lags; pip wheels
# are used for these three only (GDAL stays conda-managed). Pillow's fixes are in 13.0,
# which needs Python >= 3.11: the geospatial env (environment.yml) pins 3.10, so its
# pillow 12.3 stays until that env moves to 3.11 (accepted residual; see docs/).
# The three come from locks/geospatial-pip.<arch>.txt (by sha256); the base
# env's floors are in locks/base-pip above.
RUN /opt/conda/envs/geospatial/bin/pip install --no-cache-dir --no-deps --require-hashes --only-binary :all: \
        -r "/usr/share/mesa/locks/geospatial-pip.${TARGETARCH}.txt" && \
    /opt/conda/envs/geospatial/bin/pip check && \
    mamba clean -afy

# Configure bash_profile for non-interactive tty containers
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.bash_profile && \
    echo "conda activate geospatial" >> /home/jovyan/.bash_profile

# formation (CyVerse Discovery Environment / Formation API — launch apps, manage
# analyses) is now a hosted, OAuth-protected remote MCP at
# https://de.cyverse.org/formation/mcp, registered directly in the agent configs
# (opencode.json, claude.json, antigravity). No local binary is built: the old
# Go server hit REST endpoints that are not deployed at that host, and each user
# now authenticates in-agent with their own CyVerse (Keycloak) login.

# ---------------------------------------------------------------------------
# Config / assets last, AFTER the conda layer, so editing the splash, the
# shell prompt, entry.sh, aiverde-setup, or any agent-CLI config rebuilds in
# seconds and does NOT invalidate the expensive `mamba env create` cache.
# ---------------------------------------------------------------------------

# System assets (root-owned). --chmod sets the mode without a separate RUN
# (needed because USER is jovyan here and these live in root-owned paths).
COPY --chmod=755 01-custom /etc/motd
COPY mesa-prompt.sh /etc/profile.d/mesa-prompt.sh
COPY --chmod=755 entry.sh /bin/entry.sh
COPY --chmod=755 osn-mount.sh /usr/local/bin/osn-mount.sh
COPY --chmod=755 configs/aiverde-setup.sh /usr/local/bin/aiverde-setup
COPY --chmod=755 configs/cyverse-login.sh /usr/local/bin/cyverse-login
# Replace the mesa-mcp symlink (from the venv install) with a shim that strips
# empty MESA_MCP_* vars before launching the server. mesa-ducklake stays a symlink.
# Remove the symlink FIRST: COPY writes THROUGH a symlink to its target, which
# would overwrite the real /opt/mesa/bin/mesa-mcp and make the shim exec itself.
RUN sudo rm -f /usr/local/bin/mesa-mcp
COPY --chmod=755 configs/mesa-mcp-shim.sh /usr/local/bin/mesa-mcp

# Pre-load the irods / mesa / filesystem MCP servers for every agent CLI
# (Claude Code, Codex, OpenCode, Antigravity, Goose).
COPY --chown=1000:100 configs/claude.json /home/jovyan/.claude.json
COPY --chown=1000:100 configs/codex-config.toml /home/jovyan/.codex/config.toml
COPY --chown=1000:100 configs/opencode.json /home/jovyan/.config/opencode/opencode.json
COPY --chown=1000:100 configs/antigravity-mcp_config.json /home/jovyan/.gemini/config/mcp_config.json
COPY --chown=1000:100 configs/goose-config.yaml /home/jovyan/.config/goose/config.yaml

# COPY --chown does not chown the parent dirs it auto-creates, so ~/.config
# is left root-owned and jovyan cannot create ~/.config/aiverde at runtime
# (aiverde-setup). Restore ownership of jovyan's config tree.
RUN sudo chown -R 1000:100 /home/jovyan/.config /home/jovyan/.codex /home/jovyan/.gemini

# tmux config: hide the status bar, and enable mouse mode so the scroll wheel
# reaches the terminal scrollback (ttyd runs the shell inside tmux; see entry.sh).
RUN printf 'set-option -g status off\nset -g mouse on\n' >> /home/jovyan/.tmux.conf

# Release identity, last so a new version or commit does not invalidate the
# layers above. Set by the release build; "dev" for local builds.
ARG MESA_VERSION=dev
ARG MESA_REVISION=unknown
ARG BASE_IMAGE
LABEL org.opencontainers.image.version="${MESA_VERSION}" \
      org.opencontainers.image.revision="${MESA_REVISION}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

ENTRYPOINT ["bash", "/bin/entry.sh"]

CMD ["ttyd", "bash"]
