# syntax=docker/dockerfile:1
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

LABEL org.label-schema.name="CyVerse VICE MESA CLI (AI Sandbox)" \
      org.label-schema.description="MESA CLI for CyVerse VICE with sudo and every privilege-escalation path removed: the AI-agent sandbox variant" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/idss-mesa/cli" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The lockdown script is shared verbatim by the five idss-mesa repos.
COPY --chmod=755 mesa-sandbox-lockdown.sh /usr/local/sbin/mesa-sandbox-lockdown
RUN /usr/local/sbin/mesa-sandbox-lockdown jovyan && rm -f /usr/local/sbin/mesa-sandbox-lockdown

ENV MESA_SANDBOX=1
USER jovyan
WORKDIR /home/jovyan/data-store
