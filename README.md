# dotfiles

Ansible-based machine setup for Arch/CachyOS and macOS. Installs packages, configures tools, and deploys dotfiles via chezmoi.

## Quick Start

```bash
# Install Ansible collections (first time only)
ansible-galaxy collection install -r ansible/requirements.yml

# Run full setup
./ansible/run.sh
# Prompts: sudo password, then vault password (if vault.yml exists)
```

If you want `CLAUDE_CODE_OAUTH_TOKEN` rendered into your zshrc, export it first:

```bash
export CLAUDE_CODE_OAUTH_TOKEN="your-token"
./ansible/run.sh
```

## What Gets Installed

| Component | Arch/CachyOS | macOS | Controlled by |
|-----------|-------------|-------|---------------|
| Common packages (git, neovim, tmux, fzf, ripgrep, etc.) | pacman | homebrew | always |
| Platform packages (fd, bat, eza, fastfetch, etc.) | pacman | homebrew | always |
| AUR packages (autojump) | paru | — | always |
| NordVPN | AUR | cask | `install_nordvpn` |
| oh-my-zsh + spaceship + plugins | shell script | shell script | `install_ohmyzsh` |
| chezmoi + dotfiles | pacman | homebrew | `install_chezmoi` |
| Claude Code CLI | npm | npm | `install_claude` |
| mise (runtime version manager) | AUR | homebrew | `install_mise` |
| SSH agent (systemd) | systemd user service | — | `install_ssh_agent` |
| Power management (TLP + swayidle) | systemd | — | laptop detection |
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

Shell uses XDG layout — `ZDOTDIR` is set to `~/.config/zsh` in `~/.zshenv`.

## Selective Runs

```bash
# Packages only
ansible-playbook ansible/local.yml --tags base

# Power management only
ansible-playbook ansible/local.yml --tags power

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
├── requirements.yml        # community.general, kewlfft.aur
├── group_vars/
│   ├── all.yml             # All variables and feature flags
│   └── vault.yml           # Encrypted secrets (NAS credentials, etc.)
└── roles/
    ├── base/
    │   └── tasks/
    │       ├── main.yml
    │       ├── packages.yml
    │       ├── aur.yml
    │       ├── ohmyzsh.yml
    │       ├── chezmoi.yml
    │       ├── claude.yml
    │       ├── mise.yml
    │       ├── nordvpn.yml
    │       └── ssh_agent.yml
    ├── power/
    │   ├── tasks/main.yml
    │   └── templates/
    └── mounts/
        ├── tasks/main.yml
        ├── handlers/main.yml
        └── templates/
home/                       # chezmoi source root
docs/                       # Setup guides
```

## Configuration

All variables and feature flags are in `ansible/group_vars/all.yml`. Secrets go in `ansible/group_vars/vault.yml`.
