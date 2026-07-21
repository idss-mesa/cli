FROM quay.io/jupyter/minimal-notebook:latest

LABEL org.label-schema.name="CyVerse VICE Cloud Shell" \
      org.label-schema.description="Built from Ubuntu 24.04 w/ MiniConda3" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/cyverse-vice/cli" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

USER root

# Target architecture set by buildx: amd64 or arm64
ARG TARGETARCH

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
    tmux curl grep sed dpkg && \
    curl -L "https://github.com/krallin/tini/releases/download/v0.19.0/tini-${TARGETARCH}" > /usr/bin/tini && \
    chmod +x /usr/bin/tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Go
RUN wget -q -c https://dl.google.com/go/go1.25.5.linux-${TARGETARCH}.tar.gz -O - | sudo tar -xz -C /usr/local

# Build the iRODS MCP server (stdio MCP access to the CyVerse Data Store)
# https://github.com/idss-mesa/irods-mcp-server
# NOTE: the base image sets ENV HOME=/home/jovyan even for root, so keep the
# Go caches in /tmp or they land root-owned in jovyan's home
RUN git clone --depth 1 https://github.com/idss-mesa/irods-mcp-server /tmp/irods-mcp-server && \
    cd /tmp/irods-mcp-server && \
    CGO_ENABLED=0 GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -o /usr/local/bin/irods-mcp-server ./cmd/main.go && \
    cd / && rm -rf /tmp/irods-mcp-server /tmp/go /tmp/go-cache

# install ttyd
RUN TTYD_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    curl -L "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" > ttyd && \
    chmod a+x ttyd && \
    mv ttyd /usr/local/bin/ttyd

# Install remaining packages: locales, terminal tools, s3fs, Node/NPM
RUN apt-get update && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y locales lolcat neofetch figlet w3m-img imagemagick s3fs fuse nodejs socat bubblewrap && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install GoCommands
# https://learning.cyverse.org/ds/gocommands/
RUN cd /usr/local/bin && \
    GOCMD_VER=$(curl -L -s https://raw.githubusercontent.com/cyverse/gocommands/main/VERSION.txt); \
    curl -L -s https://github.com/cyverse/gocommands/releases/download/${GOCMD_VER}/gocmd-${GOCMD_VER}-linux-${TARGETARCH}.tar.gz | tar zxvf -

ENV PATH=${PATH}:/usr/games

# install git-credential-manager
RUN GCM_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) && \
    wget https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.7.3/gcm-linux-${GCM_ARCH}-2.7.3.deb && \
    apt-get update && \
    apt-get install -y ./gcm-linux-${GCM_ARCH}-2.7.3.deb && \
    rm gcm-linux-${GCM_ARCH}-2.7.3.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt update && apt install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# install AWS CLI
RUN AWS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo aarch64 || echo x86_64) && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf awscliv2.zip aws

# Install mesa-mcp and mesa-ducklake (https://github.com/idss-mesa)
# into a dedicated venv: they need Python >=3.11 and the geospatial
# conda env pins 3.10, so they get the base conda Python instead.
RUN /opt/conda/bin/python3 -m venv /opt/mesa && \
    /opt/mesa/bin/pip install --no-cache-dir \
      git+https://github.com/idss-mesa/mesa-ducklake.git \
      git+https://github.com/idss-mesa/mesa-mcp.git && \
    ln -s /opt/mesa/bin/mesa-mcp /opt/mesa/bin/mesa-ducklake /usr/local/bin/

# Configure FUSE for non-root users and create OSN directory
RUN echo "user_allow_other" >> /etc/fuse.conf && \
    chmod 644 /etc/fuse.conf && \
    mkdir -p /osn && \
    chmod 755 /osn && \
    chown 1000:100 /osn

# set the ENV for the credential type
ENV GCM_CREDENTIAL_STORE=cache

USER jovyan

# Install Claude Code, OpenAI Codex, and Claude Code Router via npm
# (npm install is preferred over claude.ai/install.sh for Docker builds)
# ccr (claude-code-router) lets Claude Code talk to AI Verde's non-Anthropic
# models; see aiverde-setup and https://github.com/musistudio/claude-code-router
RUN npm config set prefix /home/jovyan/.npm-global && \
    npm install -g @anthropic-ai/claude-code @openai/codex @musistudio/claude-code-router && \
    npm cache clean --force

# Install Antigravity CLI (replaces deprecated Google Gemini CLI — deadline June 18 2026)
# https://antigravity.google/blog/introducing-google-antigravity-cli
# Binary: agy, installed to ~/.local/bin
RUN mkdir -p /home/jovyan/.cache/antigravity/staging && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash

# Install OpenCode (https://opencode.ai/) — --no-modify-path avoids shell detection hang in Docker
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Configure bashrc
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo ". /etc/profile.d/mesa-prompt.sh" >> ~/.bashrc && \
    echo '[ ! -z "$TERM" -a -r /etc/motd ] && /etc/motd' >> ~/.bashrc && \
    echo $'\n# upgrade GoCommands\nsudo gocmd upgrade > /dev/null' >> ~/.bashrc

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

# activate base Python environment using mamba
COPY environment.yml /home/jovyan/
RUN mamba env create -f /home/jovyan/environment.yml

# Configure bash_profile for non-interactive tty containers
RUN echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/jovyan/.bash_profile && \
    echo "conda activate geospatial" >> /home/jovyan/.bash_profile

# Build formation-mcp (Go MCP server for the CyVerse Discovery Environment /
# Formation API — launch apps, manage analyses). https://github.com/idss-mesa/formation-mcp
# After the conda layer so it does not bust that cache; Go caches to /tmp.
RUN git clone --depth 1 https://github.com/idss-mesa/formation-mcp /tmp/formation-mcp && \
    cd /tmp/formation-mcp && \
    CGO_ENABLED=0 GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -o /tmp/formation-mcp-bin ./cmd/formation-mcp && \
    sudo install -m 0755 /tmp/formation-mcp-bin /usr/local/bin/formation-mcp && \
    cd / && sudo rm -rf /tmp/formation-mcp /tmp/formation-mcp-bin /tmp/go /tmp/go-cache

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
# (Claude Code, Codex, OpenCode, Antigravity).
COPY --chown=1000:100 configs/claude.json /home/jovyan/.claude.json
COPY --chown=1000:100 configs/codex-config.toml /home/jovyan/.codex/config.toml
COPY --chown=1000:100 configs/opencode.json /home/jovyan/.config/opencode/opencode.json
COPY --chown=1000:100 configs/antigravity-mcp_config.json /home/jovyan/.gemini/config/mcp_config.json

# COPY --chown does not chown the parent dirs it auto-creates, so ~/.config
# is left root-owned and jovyan cannot create ~/.config/aiverde at runtime
# (aiverde-setup). Restore ownership of jovyan's config tree.
RUN sudo chown -R 1000:100 /home/jovyan/.config /home/jovyan/.codex /home/jovyan/.gemini

# tmux config: hide the status bar, and enable mouse mode so the scroll wheel
# reaches the terminal scrollback (ttyd runs the shell inside tmux; see entry.sh).
RUN printf 'set-option -g status off\nset -g mouse on\n' >> /home/jovyan/.tmux.conf

ENTRYPOINT ["bash", "/bin/entry.sh"]

CMD ["ttyd", "bash"]
