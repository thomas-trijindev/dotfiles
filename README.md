# dotfiles

Ansible-based machine setup for Fedora and macOS. Installs packages, configures tools, and deploys dotfiles via chezmoi.

## Prerequisites

Ansible runs sudo non-interactively (no TTY, so fingerprint/PAM auth won't work). Set up passwordless sudo once before first run:

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible-nopasswd
sudo chmod 440 /etc/sudoers.d/ansible-nopasswd
```

### Want a separate dev checkout? Do this before running anything below

By default, chezmoi manages its own clone of this repo at `~/.local/share/chezmoi` — you never need to think about it. Skip this if that's all you want.

If instead you want to edit dotfiles from a normal clone somewhere like `~/dev/personal/dotfiles` (your own IDE, Claude Code, etc.), point chezmoi at it **before** running `./ansible/run.sh` or `chezmoi init`, otherwise you'll end up with two independent clones to keep in sync manually (see [Updating Dotfiles](#updating-dotfiles)):

```bash
git clone <repo-url> ~/dev/personal/dotfiles
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml <<'EOF'
sourceDir = "/home/<user>/dev/personal/dotfiles"
EOF
```

With this in place, `chezmoi init` (including the one `./ansible/run.sh` runs via `ansible/roles/base/tasks/chezmoi.yml`) detects the source dir already exists and applies from your checkout instead of cloning a second copy.

If you only added this **after** chezmoi already cloned into the default location, reconcile the two by checking `chezmoi diff` is empty, then delete the now-redundant `~/.local/share/chezmoi`.

## Quick Start

```bash
# Install Ansible collections (first time only)
ansible-galaxy collection install -r ansible/requirements.yml

# Run full setup
./ansible/run.sh
# Prompts: vault password only (if vault.yml exists)
# Requires NOPASSWD sudoers — see Prerequisites below
```

## What Gets Installed

| Component | Fedora | macOS | Controlled by |
|-----------|--------|-------|---------------|
| Common packages (git, neovim, tmux, fzf, ripgrep, etc.) | dnf | homebrew | always |
| Platform packages (fd-find, bat, eza, fastfetch, etc.) | dnf | homebrew | always |
| NordVPN | RPM repo | homebrew cask | `install_nordvpn` |
| oh-my-zsh + spaceship + plugins | shell script | shell script | `install_ohmyzsh` |
| chezmoi + dotfiles | dnf | homebrew | `install_chezmoi` |
| Claude Code CLI | official installer | official installer | `install_claude` |
| mise (runtime version manager) | official installer | official installer | `install_mise` |
| SSH agent (systemd) | systemd user service | — | `install_ssh_agent` |
| AutoFS NAS mounts (SMB/CIFS) | autofs + cifs-utils | — | `install_autofs` |

## Dotfiles (via chezmoi)

Managed under `home/`, deployed to `~` via chezmoi:

| Source | Destination |
|--------|-------------|
| `home/dot_zshenv` | `~/.zshenv` |
| `home/dot_config/zsh/dot_zprofile` | `~/.config/zsh/.zprofile` |
| `home/dot_config/zsh/dot_zshrc.tmpl` | `~/.config/zsh/.zshrc` |
| `home/dot_config/zsh/ohmyzsh_settings` | `~/.config/zsh/ohmyzsh_settings` |
| `home/dot_config/zsh/zsh_aliases` | `~/.config/zsh/zsh_aliases` |
| `home/dot_config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` |
| `home/dot_config/nvim/` | `~/.config/nvim/` |

Shell uses XDG layout — `ZDOTDIR` is set to `~/.config/zsh` in `~/.zshenv`. Any shell environment exports must go in `dot_zshrc.tmpl`, **not** `~/.zshrc` (which is never loaded).

## Updating Dotfiles

This checkout (`~/dev/personal/dotfiles`) is chezmoi's source directory — configured via `sourceDir` in `~/.config/chezmoi/chezmoi.toml`. There is no separate `~/.local/share/chezmoi` clone to keep in sync; `chezmoi source-path` should always point back into this repo's `home/`.

> A brand-new machine provisioned via `./ansible/run.sh` won't have this override yet, since it has no pre-existing checkout to point at — `ansible/roles/base/tasks/chezmoi.yml` runs the default `chezmoi init <repo>`, which clones into `~/.local/share/chezmoi`. Add the `sourceDir` override manually afterward if you also want a separate dev checkout like this one.

### You edited a file directly in `~` (e.g. `~/.config/ghostty/config`)

Pull the change back into the source, then commit and push:

```bash
chezmoi re-add ~/.config/ghostty/config
git add home/dot_config/ghostty/config
git commit -m "..."
git push
```

### You edited a file in this repo (e.g. `home/dot_config/ghostty/config`)

Commit and push, then apply:

```bash
git add home/...
git commit -m "..."
git push
chezmoi apply
```

### Useful chezmoi commands

```bash
chezmoi diff                          # Preview unapplied changes
chezmoi apply                         # Apply source to home directory
chezmoi status                        # Short diff summary
chezmoi re-add ~/.config/ghostty/config  # Pull live file back into source
chezmoi edit ~/.config/ghostty/config    # Edit source file for a given target
chezmoi source-path                   # Print the source root chezmoi is using
```

### Templates (`.tmpl` files)

Files like `home/dot_config/zsh/dot_zshrc.tmpl` are Go templates rendered at apply time — useful for OS-specific values (`{{ if eq .chezmoi.os "darwin" }}`) or reading env vars at apply time. Avoid baking machine-specific secrets or short-lived values (e.g. OAuth access tokens) into a template — those belong in the tool's own credential storage, not a shell rc file.

## Selective Runs

```bash
# Packages only
ansible-playbook ansible/local.yml --tags base

# NAS mounts only
./ansible/run.sh --tags mounts

# Skip a component
ansible-playbook ansible/local.yml -e "install_nordvpn=false"
```

## Secrets (Ansible Vault)

Sensitive values (NAS credentials, etc.) are stored encrypted in `ansible/group_vars/vault.yml`. The vault file is committed to the repo — it is AES-256 encrypted and safe to store in git. You only need the vault password to decrypt it.

**First-time setup on a new machine:**
```bash
# Create the vault file
ansible-vault create ansible/group_vars/vault.yml
```

Add your secrets inside:
```yaml
nas_username: myuser
nas_password: mypass
```

**Edit existing vault:**
```bash
ansible-vault edit ansible/group_vars/vault.yml
```

**View vault contents:**
```bash
ansible-vault view ansible/group_vars/vault.yml
```

**Change vault password:**
```bash
ansible-vault rekey ansible/group_vars/vault.yml
```

`run.sh` automatically detects the vault file and prompts for the vault password at deploy time.

## Structure

```
ansible/
├── local.yml               # Main playbook
├── run.sh                  # Convenience wrapper
├── requirements.yml        # community.general
├── group_vars/
│   ├── all.yml             # All variables and feature flags
│   └── vault.yml           # Encrypted secrets (NAS credentials, etc.)
└── roles/
    ├── base/
    │   └── tasks/
    │       ├── main.yml
    │       ├── packages.yml
    │       ├── ohmyzsh.yml
    │       ├── chezmoi.yml
    │       ├── claude.yml
    │       ├── mise.yml
    │       ├── nordvpn.yml
    │       └── ssh_agent.yml
    └── mounts/
        ├── tasks/main.yml
        ├── handlers/main.yml
        └── templates/
home/                       # chezmoi source root
```

## Configuration

All variables and feature flags are in `ansible/group_vars/all.yml`. Secrets go in `ansible/group_vars/vault.yml`.
