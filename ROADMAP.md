# Roadmap

Planned future additions to this repo.

---

## Pending

### Mac Deployment (`feat/deploy_mac`)

Full end-to-end playbook support for macOS. Core package install and dotfiles already work; the remaining gaps are bootstrap, macOS-native config, and cask app management.

#### Phase 1 — Bootstrap

Emulates the pattern from `bin/mac_deploy.sh` (existing reference script). Three ordered steps in a new `roles/base/tasks/homebrew.yml`, imported in `main.yml` before `packages.yml` with `when: Darwin`.

**Step 1 — Xcode Command Line Tools**
- Check: `xcode-select -p` (rc 0 = installed)
- Install if missing: `xcode-select --install` with a polling wait loop (matches mac_deploy.sh pattern) — this is the official Apple mechanism and triggers a background install without needing softwareupdate
- Gate the install step on `xcode_clt_check.rc != 0`

**Step 2 — Homebrew**
- Check both install locations: `/opt/homebrew/bin/brew` (Apple Silicon) and `/usr/local/bin/brew` (Intel)
- Install if missing via official install script with `NONINTERACTIVE=1`
- After install, run `eval "$(/opt/homebrew/bin/brew shellenv)"` in the Ansible shell environment so subsequent tasks can find `brew` without a new shell

**Step 3 — OrbStack (Docker runtime)**
- Install via `community.general.homebrew_cask` (`become: no`), gated on `install_orbstack | default(true)`
- Add `install_orbstack: true` feature flag to `group_vars/all.yml`
- Existing `packages_macos` / `packages_common` lists in `all.yml` stay as-is — package management remains Ansible-native via `community.general.homebrew` in `packages.yml`

**Packages audit result (already done):** all `packages_common` names are identical on Homebrew — no splits needed.

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

#### Phase 3 — Validation

- Run `./ansible/run.sh` on a fresh macOS machine and verify zero errors.
- Run a second time to confirm idempotency (no changes reported for already-applied tasks).

---

### Fingerprint Role (`roles/fingerprint/`)

Implement and enable the commented-out fingerprint role in `local.yml`. The role should:

- Deploy `/etc/pam.d/sudo` (and optionally `login`, `polkit-1`) from a Jinja2 template
- Use `pam_succeed_if.so quiet env SSH_CONNECTION` to skip fprintd when `SSH_CONNECTION` is set — this correctly handles SSH, SSH→tmux, and local sessions (tmux propagates `SSH_CONNECTION` via its default `update-environment` on attach)
- The existing `rhost = ""` check in the manually-configured `/etc/pam.d/sudo` does not work — sudo doesn't set `PAM_RHOST`, so the condition likely always fails and fprintd is always attempted
- Plain SSH "accidentally" gives password because polkit checks logind: SSH sessions have no logind seat (classified as remote), so polkit denies the fingerprint reader access and fprintd fails silently, falling through to password. SSH+tmux breaks this because the tmux server was started in a local graphical session and holds seat0 — polkit authorizes fprintd and fingerprint works even though the user arrived via SSH. The `SSH_CONNECTION` env var is therefore the only reliable signal.
- Install `fprintd` via the package lists (Arch only)
- Gate the role on `enable_fingerprint | default(false)` and `ansible_facts['os_family'] == "Archlinux"`

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
