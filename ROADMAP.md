# Roadmap

Planned future additions to this repo.

---

## Pending

### AutoFS SMB Mounts

Mount NAS shares from `192.168.0.6` via autofs.

**Shares to mount:**

| Share | Mount point |
|-------|-------------|
| `maps` | `/mnt/nas/maps` |
| `reference_drawings` | `/mnt/nas/reference_drawings` |
| `reject_images` | `/mnt/nas/reject_images` |

**Implementation:**

- New Ansible role `roles/mounts/` (or task file in `roles/base/tasks/autofs.yml`)
- Feature flag: `install_autofs: false` in `group_vars/all.yml`
- Install `autofs` and `cifs-utils` packages (Arch)
- Deploy `/etc/autofs.conf` (timeout, browse_mode off)
- Deploy `/etc/auto.master.d/smb.autofs` → points to `/etc/auto.smb`
- Deploy `/etc/auto.smb` — one entry per share:
  ```
  maps           -fstype=cifs,credentials=/etc/samba/credentials,uid=<user>,gid=<user>  ://192.168.0.6/maps
  reference_drawings  ...
  reject_images  ...
  ```
- Deploy `/etc/samba/credentials` (via Ansible vault or chezmoi secret) with `username=` / `password=`
- Enable and start `autofs` systemd service
- Cron health-check: verify mount accessible every N minutes, remount if dead

---

## Completed

### Chezmoi-Managed Dotfiles

ZSH (XDG-compliant, oh-my-zsh + spaceship), tmux, and neovim configs deployed via chezmoi.

- `~/.zshenv` — sets `ZDOTDIR`, XDG paths, cargo env
- `~/.config/zsh/.zshrc` — full env setup, mise activation, fzf, SSH agent, secrets via chezmoi template
- `~/.config/zsh/ohmyzsh_settings` — spaceship theme + plugins
- `~/.config/zsh/zsh_aliases` — cross-platform aliases
- `~/.config/tmux/tmux.conf` — gruvbox, `C-a` prefix, mouse mode
- `~/.config/nvim/` — lazy.nvim, tokyonight, lsp-zero + Mason, nvim-cmp, telescope, trouble, which-key

### mise Runtime Version Manager

Installed via AUR (`mise-bin`) on Arch, Homebrew on macOS. Activated in zshrc.

### Built-in SSH Agent

Replaced 1Password SSH agent with OpenSSH's built-in agent via systemd user service. `SSH_AUTH_SOCK` set via `environment.d` and zshrc.
