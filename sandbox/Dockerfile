# syntax=docker/dockerfile:1.29.0@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# MESA CLI — AI Sandbox variant. The published image with every path from
# UID 1000 to root removed: no sudo, no setuid/setgid binaries, no file
# capabilities, no account passwords. Built on the CPU image (-> :sandbox) or
# the GPU image (-> :gpu-sandbox):
#   make build-sandbox        # BASE_IMAGE=harbor.cyverse.org/vice/mesa-cli:latest
#   make build-gpu-sandbox    # BASE_IMAGE=harbor.cyverse.org/vice/mesa-cli:gpu
# Humans keep the sudo-enabled :latest/:gpu images (the VICE "modify your
# environment" feature); AI agents run in these. See ../README.md "AI Sandbox".
ARG BASE_IMAGE=harbor.cyverse.org/vice/mesa-cli:latest
FROM ${BASE_IMAGE}

# Version, revision, source and vendor labels are inherited from the base.
ARG BASE_IMAGE
LABEL org.opencontainers.image.title="MESA Cloud Shell (AI Sandbox)" \
      org.opencontainers.image.description="MESA cloud shell with sudo and every privilege-escalation path removed: the AI-agent sandbox variant" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The lockdown script is shared verbatim by the five idss-mesa repos.
COPY --chmod=755 mesa-sandbox-lockdown.sh /usr/local/sbin/mesa-sandbox-lockdown
RUN /usr/local/sbin/mesa-sandbox-lockdown jovyan && rm -f /usr/local/sbin/mesa-sandbox-lockdown

ENV MESA_SANDBOX=1
USER jovyan
WORKDIR /home/jovyan/data-store
