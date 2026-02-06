
# TODO: IMPORTANT SSH SETUP IN CHEZMOI

# SSH Agent Setup: Zeus (Mac) ↔ Hades (Linux)

Both machines use **1Password as SSH agent**. The goal is that when SSH'd from zeus into hades, 1Password authentication prompts appear on **zeus** (the originating machine), not on hades.

## The Problem

When both machines have 1Password configured as the SSH agent, hades' local 1Password intercepts all SSH operations — even when agent forwarding is active from zeus. This causes 1Password auth prompts to appear on hades instead of zeus during remote sessions.

Additionally, VS Code's git extension on hades (local) doesn't inherit `SSH_AUTH_SOCK` from the shell profile, so it can't find the 1Password agent for commit signing.

**Root causes:**
- `IdentityAgent ~/.1password/agent.sock` in hades' `~/.ssh/config` overrides the forwarded agent
- `gpg.ssh.program` set to `/opt/1Password/op-ssh-sign` talks directly to hades' local 1Password app, bypassing `SSH_AUTH_SOCK` entirely
- VS Code's git extension runs outside the shell, so `.zshrc` env vars don't apply to it

---

## Zeus (Mac) — `~/.ssh/config`

```ssh-config
Host hades
    Hostname hades
    User tjunkie
    ForwardAgent yes

Host *
    IdentityAgent "~/.1password/agent.sock"
```

- `ForwardAgent yes` forwards zeus' 1Password agent to hades
- `IdentityAgent` points all SSH operations to zeus' 1Password

---

## Hades (Linux) — `~/.ssh/config`

**Use `Match exec` instead of `Host *`** so `IdentityAgent` is only applied during local sessions:

```ssh-config
# Only use local 1Password agent when NOT in an SSH session
Match exec "test -z '$SSH_CONNECTION'"
    IdentityAgent ~/.1password/agent.sock
```

**Why:** `IdentityAgent` in ssh config takes precedence over `SSH_AUTH_SOCK`. A plain `Host *` block would override the forwarded agent from zeus. The `Match exec` conditional checks if `SSH_CONNECTION` is set (which it is during any SSH session, including VS Code remote).

---

## Hades (Linux) — `~/.zshrc`

Belt-and-suspenders: also set `SSH_AUTH_SOCK` conditionally for tools that read the environment variable directly (e.g., `ssh-add`, `git` signing):

```bash
# Use forwarded agent when SSH'd in, local 1Password otherwise
if [ -n "$SSH_CONNECTION" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    # Forwarded agent from zeus — don't touch SSH_AUTH_SOCK
    :
else
    # Local session — use hades' own 1Password
    export SSH_AUTH_SOCK=~/.1password/agent.sock
fi
```

---

## Hades (Linux) — Niri Config

VS Code's git extension runs outside the shell, so it doesn't inherit `SSH_AUTH_SOCK` from `.zshrc`. Set it in the niri window manager config so all GUI apps (including VS Code) get it.

Add to the existing `environment` block in `~/.config/niri/config.kdl` (or whichever included `.kdl` file contains it):

```kdl
environment {
    // ... existing entries ...
    SSH_AUTH_SOCK "/home/tjunkie/.1password/agent.sock"
}
```

**Note:** Requires a full logout and login for niri to pick it up. The `.zshrc` conditional still overrides this for SSH sessions.

---

## Hades (Linux) — Git SSH Signing

**Critical:** Use `ssh-keygen` instead of `op-ssh-sign` for the signing program. `op-ssh-sign` communicates directly with the local 1Password app via IPC, completely bypassing `SSH_AUTH_SOCK` and the forwarded agent. `ssh-keygen` respects `SSH_AUTH_SOCK` and routes to the correct agent.

```bash
git config --global gpg.ssh.program ssh-keygen
```

Full `~/.gitconfig` signing config:

```ini
[user]
    signingkey = ssh-ed25519 AAAA...  # your signing public key
[gpg]
    format = ssh
[gpg "ssh"]
    program = ssh-keygen              # NOT /opt/1Password/op-ssh-sign
[commit]
    gpgsign = true
```

---

## How It Works

| Scenario | `SSH_AUTH_SOCK` | SSH Agent Used | 1Password Prompt On |
|---|---|---|---|
| SSH from zeus → hades terminal | Forwarded from zeus | Zeus' 1Password | **Zeus** |
| VS Code remote from zeus | `/tmp/vscode-ssh-auth-*` (forwarded) | Zeus' 1Password | **Zeus** |
| VS Code remote from zeus (git sign) | `/tmp/vscode-ssh-auth-*` (forwarded) | Zeus' 1Password via `ssh-keygen` | **Zeus** |
| Local terminal on hades | `~/.1password/agent.sock` | Hades' 1Password | **Hades** |
| VS Code local on hades | `~/.1password/agent.sock` (via niri env) | Hades' 1Password | **Hades** |
| VS Code local on hades (git sign) | `~/.1password/agent.sock` (via niri env) | Hades' 1Password via `ssh-keygen` | **Hades** |

---

## Debugging

```bash
# Check which agent is active
echo $SSH_AUTH_SOCK

# Check if in SSH session
echo $SSH_CONNECTION    # non-empty = remote session

# List keys from current agent
ssh-add -l

# Verbose SSH test to GitHub
ssh -vT git@github.com

# Check what git is using for signing
git config --get gpg.ssh.program
git config --list --show-origin | grep -i "ssh\|sign\|gpg"

# Check niri environment is set
systemctl --user show-environment | grep SSH
```

### Key indicators

- **Forwarded agent socket** looks like: `/tmp/ssh-XXXX/agent.XXXX` or `/tmp/vscode-ssh-auth-*`
- **Hades' local 1Password socket**: `~/.1password/agent.sock` or `/tmp/auth-agent*/listener.sock`
- **Forwarded agent** typically shows a different number of keys than the local agent

---

## Common Pitfalls

1. **`IdentityAgent` overrides `SSH_AUTH_SOCK`** — ssh config directives take precedence over environment variables, so both need to be handled
2. **`op-ssh-sign` bypasses the SSH agent** — it talks to 1Password directly via IPC, not through `SSH_AUTH_SOCK`, so switching to `ssh-keygen` is required for remote signing to work
3. **VS Code git extension ignores shell profile** — it doesn't run through `.zshrc`, so `SSH_AUTH_SOCK` must be set at the session/compositor level (niri `environment` block)
4. **`environment.d` may not work with niri** — `~/.config/environment.d/*.conf` wasn't picked up; setting it directly in niri's `environment` block is the reliable approach
5. **VS Code remote server caches environment** — after config changes, fully quit and reopen VS Code (not just reload window)
6. **VS Code sets `SSH_CONNECTION`** — VS Code's remote server process sets this variable, so the `Match exec` and `.zshrc` conditionals work correctly for both terminal SSH and VS Code remote sessions
7. **Niri requires full logout** — changing the `environment` block requires a full logout and login to take effect