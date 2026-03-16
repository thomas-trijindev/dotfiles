# Roadmap

Planned future additions to this repo.

---

## Pending

Nothing currently planned.

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

### AutoFS SMB NAS Mounts

`roles/mounts/` role installs autofs + cifs-utils, deploys credentials, master map, and share map for three NAS shares (`maps`, `reference_drawings`, `reject_images`) on `192.168.0.6`. Mounts on demand under `/mnt/<share>`, unmounts after 60s inactivity. Includes a 5-minute cron health check that restarts autofs if any share is unreachable. Credentials stored in Ansible vault (`group_vars/vault.yml`).

### mise Runtime Version Manager

Installed via AUR (`mise-bin`) on Arch, Homebrew on macOS. Activated in zshrc.

### Built-in SSH Agent

Replaced 1Password SSH agent with OpenSSH's built-in agent via systemd user service. `SSH_AUTH_SOCK` set via `environment.d` and zshrc.
