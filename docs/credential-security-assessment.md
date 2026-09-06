# Credential exposure assessment: MESA CLI container

**Date:** 2026-09-05 · **Scope:** `bash/` as of the version-pin/`ant`/DuckDB update · **Question:** can the bundled AI agents (Claude Code, Codex, OpenCode, Goose, Antigravity, `ant`, `ccr`) read or leak a user's credentials?

## Short answer

Yes. Every credential a user brings into the container is readable by every agent, because all of them run as the same Unix user (`jovyan`) with unrestricted shell tools and passwordless `sudo`. Nothing in the image leaks secrets on its own, and the image ships no secrets. The exposure is structural: one user, one home directory, one process environment, shared by the human and six autonomous agents. The fixes below reduce that surface substantially without changing how users work.

## Threat model

The adversary is not the user. It is any of:

- a prompt injection reaching an agent through a file, a web page, an MCP tool result, or Data Store content;
- an agent misbehaving on its own (wrong `rm`, pasting a key into a commit or a chat);
- a compromised upstream release of one of the seven CLIs or their MCP servers.

Each of these executes with the agent's privileges. In this container, those are the user's full privileges plus root via `sudo`.

## What the image already does right

- **No secrets baked in.** Configs reference keys with placeholders (`{env:LLM_API_KEY}`) and `.dockerignore` excludes repo metadata.
- **Runs as `jovyan`, not root**, and credential files are written `600` inside `700` directories.
- **Keys are validated before they are stored.** `aiverde-setup` checks the key against `/v1/models`; `cyverse-login` removes the iRODS credential if the login test fails.
- **Hosted MCPs use OAuth in-agent** (`irods-auth`, `formation`), so those tokens are scoped and revocable rather than being the account password.
- **No runtime npm fetch for the MCP servers.** After this update the filesystem MCP server runs from a pre-installed, version-pinned binary instead of `npx -y` at each agent start, the agent CLIs are pinned by `ARG` (Antigravity excepted: its installer has no version option), and `ant` is verified against its release checksums. One runtime download remains: `sudo gocmd upgrade` in `~/.bashrc` (finding 8).
- **Goose ships in `smart_approve` mode** (`GOOSE_MODE: smart_approve` is set explicitly in `bash/configs/goose-config.yaml`), so it prompts before risky tool calls.

## Credential inventory at runtime

| Credential | Location | How it arrives | Readable by any agent? |
| --- | --- | --- | --- |
| CyVerse Data Store password | `~/.irods/.irodsA` | `cyverse-login` | Yes, and reversible: the file is iRODS obfuscation, not encryption. `/opt/mesa/bin/python3 -c "from irods.password_obfuscation import decode; ..."` recovers the plaintext. This is the user's CyVerse account password. |
| AI Verde API key | `~/.config/aiverde/env` **and** the environment of every interactive shell (`LLM_API_KEY`, `OPENAI_API_KEY`, sometimes `ANTHROPIC_API_KEY`) | `aiverde-setup` appends a `source` line to `~/.bashrc` | Yes. Inherited by every agent, every Bash tool subprocess, and every stdio MCP server. `env` in any tool call prints it. |
| AI Verde key, again | `~/.claude-code-router/config.json` | `ccr code` first-run wizard | Yes, plaintext. |
| AWS / OSN access keys | `~/.aws/credentials` | `entry.sh` copies `~/.aws` from the user's Data Store home at boot; also used as the s3fs `passwd_file` | Yes. |
| SSH private keys | `~/.ssh/` | `entry.sh` copies the directory at boot | Yes. |
| Git credentials | GCM `cache` store (in-memory daemon, same-UID socket); `~/.gitconfig` copied at boot | `GCM_CREDENTIAL_STORE=cache`, `entry.sh` | Yes while cached: `git credential fill` returns the token to any same-user process. |
| GitHub CLI token | `~/.config/gh/hosts.yml` | `gh auth login` | Yes. |
| Anthropic API key (`ant`, native Claude Code) | `ANTHROPIC_API_KEY` env or `ant auth login` store | user | Yes. |
| Each agent's own OAuth/session tokens | `~/.claude/`, `~/.codex/auth.json`, `~/.local/share/opencode/auth.json`, `~/.gemini/`, MCP OAuth tokens for `irods-auth` and `formation` | agent logins | Yes, cross-agent: any agent can lift the others' tokens. |
| The Data Store itself | `/home/jovyan/data-store` (VICE mount) | platform | Full read/write/delete through the filesystem MCP and shell. |

## Findings

Ranked by impact. "Fix" gives the concrete change; "Cost" is the user-visible effect.

### 1. HIGH: API keys live in the process environment of every shell

`aiverde-setup` writes `export OPENAI_API_KEY=...` lines and sources them from `~/.bashrc`, so every process the user or any agent starts carries the key. Environment variables are the most-leaked kind of secret: they show up in `env`/`printenv`, crash reports, subprocess logs, `/proc/<pid>/environ`, and telemetry uploads. An agent does not need to "decide" to read a file; the key is already in its address space and in every child it spawns, including the MCP servers.

**Fix.** Keep the key in one `600` file and hand it only to the tool that needs it:

- `aiverde-setup`: write the bare key to `~/.config/aiverde/key` (600); stop appending the `source` line to `~/.bashrc`; keep `env` only for users who opt in.
- OpenCode: `"apiKey": "{file:~/.config/aiverde/key}"` in `opencode.json` (OpenCode supports `{file:...}` substitution).
- Claude Code: set `"apiKeyHelper": "cat ~/.config/aiverde/key"` in `~/.claude/settings.json` instead of exporting `ANTHROPIC_API_KEY`, and set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` so Bash-tool subprocesses do not inherit auth vars.
- Goose: launch through a wrapper that injects `OPENAI_API_KEY` for that one process (`OPENAI_API_KEY=$(cat ~/.config/aiverde/key) exec goose "$@"`). Goose's own shell tool still inherits it, but nothing else on the system does.
- `ccr`: leave as is (it already reads its own config file), but note that file is plaintext.

**Cost.** None for the user; the `aiverde-setup` prompt and flow stay the same.

### 2. HIGH: `jovyan ALL=(ALL) NOPASSWD: ALL`

Any agent is root. Root can read every file regardless of mode bits, read other processes' environments from `/proc`, rewrite `/etc/sudoers`, replace binaries on `PATH` (`claude`, `gocmd`, `mesa-mcp`), and disable any sandbox added later.

What actually uses `sudo` today:

- At runtime, from `entry.sh` and `osn-mount.sh`: `mkdir -p`, `chown jovyan:jovyan`, `s3fs`, `umount`, and (in `osn-mount.sh`) `rmdir`, all on `/osn/<bucket>`; and `sudo gocmd upgrade` from `~/.bashrc` (finding 8).
- At build time, after `USER jovyan` in `bash/Dockerfile`: `RUN sudo rm -f /usr/local/bin/mesa-mcp` (so the shim `COPY` does not write through the venv symlink) and `RUN sudo chown -R 1000:100 ~/.config ~/.codex ~/.gemini`. Both need the unrestricted rule still in force when they run.

A sudoers allowlist of those raw commands is not a fix. sudoers matches command arguments with glob patterns in which `*` also matches `/` and white space, so `/usr/bin/umount /osn/*` permits `sudo umount /osn/../../home/jovyan/data-store`, `/usr/bin/mkdir -p /osn/*` permits `sudo mkdir -p /osn/../etc/cron.d/x`, and `/usr/bin/chown jovyan\:jovyan /osn/*` permits `sudo chown jovyan:jovyan /osn/../etc/sudoers`. A bare `/usr/bin/s3fs` entry allows every s3fs option, including an arbitrary `passwd_file=` and mount target. Each is a one-line root escalation for an agent that already has a shell.

**Fix.** Put the privileged sequence in a root-owned helper and allow only the helper:

- Add `bash/configs/osn-helper.sh`, installed by `COPY --chmod=755` to `/usr/local/sbin/osn-helper` (`root:root`, so `jovyan` cannot edit it). It accepts exactly `mount <bucket> [profile] [endpoint]` and `unmount <bucket>` and nothing else. It validates `<bucket>` against `^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$` (the S3 bucket grammar: no `/`, no `..`, no leading dot), `profile` against `^[A-Za-z0-9_-]+$`, and `endpoint` against `^https?://[A-Za-z0-9.-]+(:[0-9]+)?$`, and exits non-zero otherwise. It builds `mount_point=/osn/$bucket` itself and runs `mkdir -p`, `chown 1000:100`, and `s3fs "$bucket" "$mount_point" -o passwd_file=/home/jovyan/.aws/credentials,profile=$profile,use_path_request_style,allow_other,uid=1000,gid=100,umask=0022,mp_umask=0022[,url=$endpoint]` for `mount`, or `umount` followed by `rmdir` for `unmount`. The option string is assembled inside the helper from validated fields; the caller cannot pass `-o` or any path.
- Replace the `sudo mkdir` / `sudo chown` / `sudo s3fs` / `sudo umount` / `sudo rmdir` sequences in `entry.sh` and `osn-mount.sh` with `sudo /usr/local/sbin/osn-helper mount "$bucket" "$profile" "$endpoint"` and `sudo /usr/local/sbin/osn-helper unmount "$bucket"`. The two scripts keep their `~/.aws/config` parsing; only the privileged part moves.
- Remove `sudo gocmd upgrade` from `~/.bashrc` (finding 8).
- Swap the sudoers rule as the **last instruction before `ENTRYPOINT`**, after every build step that still uses `sudo`, in a `USER root` block (a `sudo`-driven chain would revoke its own access after the first command):

  ```dockerfile
  USER root
  RUN sed -i '/^jovyan ALL=(ALL) NOPASSWD: ALL$/d' /etc/sudoers && \
      echo 'jovyan ALL=(root) NOPASSWD: /usr/local/sbin/osn-helper' > /etc/sudoers.d/jovyan-osn && \
      chmod 440 /etc/sudoers.d/jovyan-osn && \
      visudo -cf /etc/sudoers.d/jovyan-osn && visudo -c
  USER jovyan
  ```

  The resulting policy is one line with no wildcards and no argument matching: the only root code an agent can invoke is the helper's fixed logic on a validated bucket name.

**Cost.** Users lose ad-hoc `apt install` and similar; document `pip`/`conda`/`npm --prefix` as the user-space alternatives. If interactive root is a hard requirement, keep it behind a separate `sudo -i` that requires a password set at boot from a VICE-provided secret, so agents cannot use it non-interactively.

### 3. HIGH: SSH keys and cloud credentials are copied into the agent-visible home at boot

`entry.sh` copies `~/.ssh`, `~/.aws`, and `~/.gitconfig` from the user's Data Store home into the container unconditionally. A user who stored an SSH key or an OSN key pair in the Data Store for their own convenience now has it readable by six agents, before they have run a single command.

**Fix.**

- Make the import opt-in: only copy when `MESA_IMPORT_DOTFILES=1` (settable as a VICE app parameter), and print what was imported on the splash.
- For s3fs, the mount runs via `sudo`, so the `passwd_file` can be root-owned: copy `~/.aws/credentials` to `/etc/s3fs/<profile>` (`root:root 600`) for the mount and do not leave a copy in `~/.aws` unless the user opts in.
- For SSH, prefer `gh auth login` + Git Credential Manager over long-lived keys. If a key is imported, load it into `ssh-agent` at boot and shred the file: an agent can still push through the socket but cannot exfiltrate the private key.

**Cost.** One extra checkbox in the VICE launch form for users who want their dotfiles.

### 4. MEDIUM: the Data Store password is stored reversibly

`~/.irods/.irodsA` is the standard iRODS credential and is reversible by design. In this image the decoder (`python-irodsclient`) is installed in `/opt/mesa`, so recovering the plaintext is a one-liner. Because CyVerse uses the same password for the Discovery Environment and Keycloak, leaking it hands over the whole account, not just Data Store access.

**Fix.** Keep `cyverse-login` (it is what GoCommands and the local MCP servers need), but:

- add `cyverse-logout` that removes `~/.irods/.irodsA` and update the splash to show it;
- print a one-line warning at login that the stored credential is the account password and applies to all agents;
- prefer the OAuth-backed hosted MCP (`irods-auth`) for Claude Code users, which already exists;
- ask CyVerse whether the iRODS deployment accepts PAM or time-limited (`--ttl`) credentials so the stored secret can expire.

### 5. MEDIUM: agents can read each other's tokens

Claude Code, Codex, OpenCode, Antigravity, `ant`, `gh`, and the MCP OAuth tokens each persist under `~`. A prompt injection in one agent can collect all of them. Without per-agent Unix users there is no OS boundary, so the practical control is a read-deny list inside whichever agents support one (finding 6).

### 6. MEDIUM: no sandbox is shipped, although the dependencies are

`bubblewrap` and `socat` are installed (the Linux dependencies for Claude Code's Bash sandbox) but no `~/.claude/settings.json` enables it, and Codex is left at its default `sandbox_mode`. Shipping a default policy is the single most effective change available today for Claude Code because its `sandbox.credentials` block can deny or mask specific files and variables for every sandboxed command and child process.

**Fix.** Add `bash/configs/claude-settings.json`, copied to `~/.claude/settings.json`:

```json
{
  "sandbox": {
    "enabled": true,
    "credentials": {
      "files": [
        { "path": "~/.ssh", "mode": "deny" },
        { "path": "~/.aws", "mode": "deny" },
        { "path": "~/.irods", "mode": "deny" },
        { "path": "~/.config/aiverde", "mode": "deny" },
        { "path": "~/.config/gh", "mode": "deny" },
        { "path": "~/.codex", "mode": "deny" },
        { "path": "~/.gemini", "mode": "deny" },
        { "path": "~/.local/share/opencode", "mode": "deny" },
        { "path": "~/.claude-code-router", "mode": "deny" }
      ],
      "envVars": [
        { "name": "LLM_API_KEY", "mode": "deny" },
        { "name": "OPENAI_API_KEY", "mode": "deny" },
        { "name": "ANTHROPIC_API_KEY", "mode": "deny" }
      ]
    }
  }
}
```

For Codex, set `sandbox_mode = "workspace-write"` explicitly in `codex-config.toml` and document `approval_policy`. For OpenCode, add a `permission` block that asks before `bash` outside the workspace.

**Caveat to verify on the VICE cluster.** bubblewrap needs unprivileged user namespaces. Ubuntu 24.04's AppArmor profile restricts them (`sysctl kernel.apparmor_restrict_unprivileged_userns`), and Kubernetes pods commonly run with `seccomp`/`no_new_privs` settings that block them entirely. If the sandbox cannot start, Claude Code falls back to prompting rather than failing silently, but the read-deny rules then do nothing. Test with `/sandbox` inside a running VICE analysis before relying on this.

### 7. MEDIUM: ttyd is writable and unauthenticated

`entry.sh` runs `ttyd -W ... bash` with no `-c user:pass`. Inside VICE this sits behind the Discovery Environment's authenticating proxy, which is the intended deployment. The README's local run command, `docker run -p 7681:7681`, binds every interface and exposes a shell with passwordless `sudo` to the local network.

**Fix.** Change the README to `-p 127.0.0.1:7681:7681`, and let `entry.sh` pass `-c "$TTYD_CREDENTIAL"` when that variable is set.

### 8. LOW: `sudo gocmd upgrade` runs at every shell start

`~/.bashrc` downloads and replaces a root-owned binary from GitHub on each interactive shell, as root, with no version pin or checksum. Any agent that opens a shell triggers it. GoCommands is already installed at build time and the image rebuilds weekly.

**Fix.** Delete the line. This also removes the last reason for unrestricted `sudo`.

### 9. LOW: `ccr` listens on localhost without authentication

Claude Code Router serves `127.0.0.1:3456` and, unless `APIKEY` is set in its config, any local process can spend the user's AI Verde quota through it. Its config file also holds the provider key in plaintext.

**Fix.** Have `aiverde-setup` write a `ccr` config with a random `APIKEY` and the `{file:}`-style key reference if `ccr` gains one; otherwise document the exposure.

### 10. LOW: build-time supply chain

Build-time only, and improved by this update, but still worth closing:

- `quay.io/jupyter/minimal-notebook:latest` is a floating tag; pin by digest.
- GitHub Actions are pinned by major tag (`@v5`, `@v6`); pin by commit SHA.
- The NodeSource setup script and the OpenCode, Goose, and Antigravity installers are `curl | bash`; the AWS CLI is a downloaded zip whose bundled installer runs unverified; Go, tini, ttyd, GCM, GoCommands, and DuckDB (a gzipped binary) are raw downloads. Versions are now pinned for all of these except Antigravity, GoCommands, the AWS CLI, and Node.js; only `ant` verifies a checksum. Where upstream publishes checksums or signatures, verify them.

### 11. INFO: filesystem MCP scope includes the whole Data Store mount

Not a credential issue, but `/home/jovyan/data-store` is the user's entire Data Store, and every agent has write and delete through both the MCP server and the shell. Consider defaulting the MCP scope to `/home/jovyan/work` and letting users add the Data Store path explicitly.

## Recommended order of work

1. Restrict `sudo` to the `osn-helper` wrapper and drop `sudo gocmd upgrade` (findings 2, 8): add `configs/osn-helper.sh` plus its `COPY`, point `entry.sh` and `osn-mount.sh` at it, delete the `gocmd upgrade` line from the `~/.bashrc` step, and swap the sudoers rule in a `USER root` block as the last instruction before `ENTRYPOINT`, after the build's own `sudo rm`/`sudo chown` steps. Largest privilege reduction; touches two scripts, one new file, and the tail of the Dockerfile.
2. Stop exporting API keys into the shell environment; move to file-based references per tool (finding 1).
3. Ship the Claude Code sandbox settings with the credential deny list, and set Codex `sandbox_mode` explicitly (findings 5, 6). Verify bubblewrap works on the VICE cluster first.
4. Make dotfile import opt-in and move the s3fs password file out of `~` (finding 3).
5. Add `cyverse-logout`, the login warning, and the localhost bind in the README (findings 4, 7).
6. Pin the base image digest and Actions SHAs (finding 10).

Items 1, 2, 4, and 5 are changes to `entry.sh`, `osn-mount.sh`, `aiverde-setup.sh`, `cyverse-login.sh`, the README, and the tail of the Dockerfile (a `COPY` for `osn-helper` and the sudoers swap before `ENTRYPOINT`). Item 3 adds one config file and a `COPY`. All of these sit below the conda layer, so none change the build's cache structure.
