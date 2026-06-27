# dotfiles

Ansible-based machine setup for Fedora and macOS. Installs packages, configures tools, and deploys dotfiles via chezmoi.

## Prerequisites

Ansible runs sudo non-interactively (no TTY, so fingerprint/PAM auth won't work). Set up passwordless sudo once before first run:

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible-nopasswd
sudo chmod 440 /etc/sudoers.d/ansible-nopasswd
```

## Quick Start

```bash
# Install Ansible collections (first time only)
ansible-galaxy collection install -r ansible/requirements.yml

# Run full setup
./ansible/run.sh
# Prompts: vault password only (if vault.yml exists)
# Requires NOPASSWD sudoers — see Prerequisites below
```

If you want `CLAUDE_CODE_OAUTH_TOKEN` rendered into your zshrc, export it first:

```bash
export CLAUDE_CODE_OAUTH_TOKEN="your-token"
./ansible/run.sh
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

chezmoi is the source of truth. The workflow depends on where you make the change:

### You edited a file directly in `~` (e.g. `~/.config/zsh/.zshrc`)

chezmoi will detect the drift. Pull it back into the source:

```bash
chezmoi re-add ~/.config/zsh/.zshrc
```

Then commit and push from this repo:

```bash
cd ~/dev/personal/dotfiles
git add home/dot_config/zsh/dot_zshrc.tmpl
git commit -m "..."
git push
```

On next deploy, `./ansible/run.sh` will run `chezmoi update --force` which pulls from the repo and applies.

### You edited a file in this repo (e.g. `home/dot_config/zsh/dot_zshrc.tmpl`)

Commit and push, then apply locally:

```bash
git add home/...
git commit -m "..."
git push
chezmoi update
```

### You want to preview what chezmoi would change before applying

```bash
chezmoi diff
```

### Useful chezmoi commands

```bash
chezmoi diff                        # Preview unapplied changes
chezmoi apply                       # Apply source to home directory
chezmoi update                      # Pull from repo + apply
chezmoi re-add ~/.config/zsh/.zshrc # Pull live file back into source
chezmoi cd                          # cd into chezmoi source dir (~/.local/share/chezmoi)
chezmoi edit ~/.config/zsh/.zshrc   # Edit source file for a given target
```

> **Note:** `~/.local/share/chezmoi` is chezmoi's working copy of this repo (cloned from GitHub). Edits there are equivalent to editing `home/` here.

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
