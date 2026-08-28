# Roadmap

Planned future additions to this repo.

---

## Pending

### Mac Deployment (`feat/deploy_mac`)

Full end-to-end playbook support for macOS. Core package install and dotfiles already work; the remaining gaps are bootstrap, macOS-native config, and cask app management.

#### Phase 1 — Bootstrap

- **Homebrew install task** (`roles/base/tasks/homebrew.yml`): install Homebrew if `brew` is not already present, including Xcode CLT. Must run before `packages.yml` on Darwin. Import in `main.yml` with `when: Darwin`.
- **Audit `packages_common` names**: verify every package in the common list resolves correctly under both `dnf` and `brew` (e.g. `fd`, `ripgrep`, `neovim`). Split any divergent names into `packages_fedora` / `packages_macos`.

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

### Arch/Omarchy Config Sync (`dev`)

Machine-specific fixes made directly on an Omarchy (Hyprland/Arch) laptop aren't captured in this repo yet. chezmoi isn't even initialized on that machine — `nvim`/`ghostty` there are still stock Omarchy defaults, not this repo's versions, so `chezmoi diff`/`chezmoi apply` needs care before it touches anything.

#### Phase 1 — Point chezmoi at this checkout

- Before `chezmoi init`, set the `sourceDir` override so chezmoi uses this clone instead of cloning a second copy into `~/.local/share/chezmoi` (see README's "Want a separate dev checkout?" section):
  ```bash
  mkdir -p ~/.config/chezmoi
  cat > ~/.config/chezmoi/chezmoi.toml <<'EOF'
  sourceDir = "/home/tjunkie/dev/personal/dotfiles"
  EOF
  chezmoi init
  ```
- Run `chezmoi diff` before applying anything — the live `nvim`/`ghostty` configs on that machine are plain Omarchy defaults, not this repo's versions, and would otherwise get silently overwritten.

#### Phase 2 — Pull machine-specific fixes into the source

Using `chezmoi re-add <path>` → `git add home/...` → commit, per the README's "Updating Dotfiles" flow:

- `~/.config/hypr/looknfeel.lua` — `render.direct_scanout = false` (fixes NVIDIA/Hyprland window corruption during video playback)
- `~/.config/hypr/input.lua` — `input.natural_scroll = true` (mouse wheel, to match touchpad)
- `~/.config/chrome-flags.conf` / `~/.config/chromium-flags.conf` — `--disable-accelerated-video-decode` (fixes black-screen-on-YouTube caused by the `libva-nvidia-driver` VA-API path on hybrid Intel/NVIDIA graphics)
- `~/.config/tmux/tmux.conf` — currently has a hardcoded `default-shell /usr/bin/bash`, patched over the repo's original hardcoded `/bin/zsh`

No `hypr/` directory exists in `home/dot_config/` yet — this is net-new.

#### Phase 3 — Fix the tmux shell-path hardcoding

- Convert `home/dot_config/tmux/tmux.conf` to `tmux.conf.tmpl` and resolve `default-shell` per-machine at apply time (e.g. via chezmoi's `lookPath` template function), matching the `{{ if eq .chezmoi.os ... }}` pattern already used in `dot_zshrc.tmpl` — instead of a path hardcoded for one OS breaking on another.

#### Phase 4 — Dropbox selective sync isn't a dotfile

- The Dropbox selective-sync exclude list lives in Dropbox's own sqlite state (`~/.dropbox/`), not a plain config file — chezmoi can't manage it directly.
- Add a small idempotent script (`bin/`) or an ansible task that runs `dropbox-cli exclude add <folders>` once Dropbox is installed on a fresh machine, so selective sync survives a reinstall.

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

Installed via official installer (`curl https://mise.run | sh`) — works on Fedora and macOS. Activated in zshrc.

### Built-in SSH Agent

Replaced 1Password SSH agent with OpenSSH's built-in agent via systemd user service. `SSH_AUTH_SOCK` set via `environment.d` and zshrc.
