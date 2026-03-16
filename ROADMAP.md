# Roadmap

Planned future additions to this repo.

---

## Pending

### Mac Deployment (`feat/deploy_mac`)

Full end-to-end playbook support for macOS. Core package install and dotfiles already work; the remaining gaps are bootstrap, macOS-native config, and cask app management.

#### Phase 1 — Bootstrap

- **Homebrew install task** (`roles/base/tasks/homebrew.yml`): install Homebrew if `brew` is not already present, including Xcode CLT. Must run before `packages.yml` on Darwin. Import in `main.yml` with `when: Darwin`.
- **Audit `packages_common` names**: verify every package in the common list resolves correctly under both `pacman` and `brew` (e.g. `fd`, `ripgrep`, `neovim`). Split any divergent names into `packages_arch` / `packages_macos`.

#### Phase 2 — macOS Role

New `roles/macos/` role (Darwin-only, included in `local.yml` with `when: ansible_facts['os_family'] == "Darwin"`).

- **`tasks/defaults.yml`**: use `community.general.osx_defaults` to configure system preferences:
  - Dock: autohide, position (`bottom`), tile size
  - Keyboard: key repeat rate, initial key repeat delay, disable autocorrect
  - Finder: show hidden files, show path bar, show status bar, default to home folder
  - Trackpad: tap-to-click, three-finger drag
  - Screenshots: save location to `~/Pictures/Screenshots`
- **`tasks/ssh.yml`**: deploy `~/.ssh/config` (chezmoi template or direct task) with `AddKeysToAgent yes` and `UseKeychain yes` so macOS Keychain handles passphrase storage. Gate behind `when: ansible_facts['os_family'] == "Darwin"` — Linux uses the systemd SSH agent service instead.
- **`handlers/main.yml`**: handler to restart Dock/Finder/SystemUIServer after defaults changes (`killall Dock`, `killall Finder`).

#### Phase 3 — Cask App Management

- Add `packages_macos_cask: []` list to `group_vars/all.yml` for GUI apps (e.g. browsers, terminal emulators).
- Add cask install task in `packages.yml` using `community.general.homebrew_cask`, `become: no`, gated on Darwin.

#### Phase 4 — Validation

- Run `./ansible/run.sh` on a fresh macOS machine and verify zero errors.
- Run a second time to confirm idempotency (no changes reported for already-applied tasks).

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

### Niri + Noctalia-Shell via Chezmoi

Niri compositor config and noctalia-shell desktop config are now managed by chezmoi.

- `~/.config/niri/config.kdl` — root config that includes cfg/*.kdl splits
- `~/.config/niri/cfg/` — animation, autostart, input, layout, rules, display, keybinds, misc
- `~/.config/noctalia/colors.json` — colorscheme overrides (Catppuccin-based)
- `~/.config/noctalia/plugins.json` — enabled plugins (battery-threshold, tailscale)
- `~/.config/noctalia/settings.json` — all noctalia UI/behaviour settings

Note: `plugins/` directory is excluded (auto-installed by noctalia from `plugins.json`). `colorschemes/` is excluded (empty, managed by noctalia). Machine-specific display output config lives in `cfg/display.kdl` (currently inactive via `/-` comment for the output block).

Also fixed: `swayidle.service` now gates on `ConditionEnvironment=NIRI_SOCKET` instead of `WAYLAND_DISPLAY` so it only starts inside a niri session (niri is the only compositor that exports `NIRI_SOCKET` and the only one the `niri msg action` calls are compatible with).

### Built-in SSH Agent

Replaced 1Password SSH agent with OpenSSH's built-in agent via systemd user service. `SSH_AUTH_SOCK` set via `environment.d` and zshrc.
