# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is an Ansible-based system configuration repository that automates the setup of Linux (Arch/CachyOS) and macOS machines with developer tools, packages, and configurations.

## Commands

```bash
# Run the full playbook (primary method)
# Prompts for sudo password, then vault password if vault.yml exists
./ansible/run.sh

# Run specific roles via tags
./ansible/run.sh --tags base      # Packages only
./ansible/run.sh --tags power -e "force_power_management=true"  # Power (must force — chassis detection is in pre_tasks)
./ansible/run.sh --tags mounts    # NAS mounts only

# Override variables
ansible-playbook ansible/local.yml --ask-become-pass --ask-vault-pass -e "install_nordvpn=false"

# Install Ansible collections (required before first run)
ansible-galaxy collection install -r ansible/requirements.yml

# Vault operations
ansible-vault create ansible/group_vars/vault.yml   # First-time setup
ansible-vault edit ansible/group_vars/vault.yml     # Edit secrets
```

## Architecture

### Execution Flow
`local.yml` orchestrates everything: **pre_tasks** (detect OS, chassis type, gather `primary_user_uid`) → **roles** (base, power, mounts) → **post_tasks** (completion message)

**Important:** `detected_chassis` and `primary_user_uid` are set in pre_tasks. When running with `--tags`, pre_tasks are skipped and these variables are undefined. Use `| default(...)` guards or `-e "force_power_management=true"` to work around this.

### Key Files
- `ansible/local.yml` - Main playbook entry point
- `ansible/group_vars/all.yml` - All configurable variables (packages, feature flags, power/NAS settings)
- `ansible/group_vars/vault.yml` - AES-256 encrypted secrets (NAS credentials) — safe to commit
- `ansible/requirements.yml` - External Ansible collections (community.general, kewlfft.aur)

### Roles
- **base** (`roles/base/tasks/`) - Package installation and optional tools
  - `packages.yml` - Cross-platform package installation via native package managers
  - `aur.yml` - AUR support: bootstraps paru, then clones/builds/installs via makepkg + pacman (not paru directly — avoids TTY sudo issues)
  - `mise.yml`, `nordvpn.yml`, `chezmoi.yml`, `claude.yml`, `ssh_agent.yml` - Optional tools (feature flags)
- **power** (`roles/power/`) - Laptop power management (Linux only)
  - Configures systemd-logind via `templates/power.conf.j2`
  - Deploys swayidle user service via `templates/swayidle.service.j2` (uses `ConditionEnvironment=WAYLAND_DISPLAY` to skip in TTY)
  - Configures GDM idle via dconf, TLP battery thresholds
- **mounts** (`roles/mounts/`) - AutoFS SMB/CIFS NAS mounts (Arch only)
  - Mounts shares on demand under `/mnt/<share>`, unmounts after 60s inactivity
  - autofs config lives in `/etc/autofs/` (Arch default) — not `/etc/`
  - autofs AUR package requires GPG key import before build; deps (sssd, rpcsvc-proto) must be pre-installed before makepkg

### Dotfiles (chezmoi)
Source root is `home/` (set via `.chezmoiroot`). Shell uses XDG layout — `ZDOTDIR=$HOME/.config/zsh` is set in `~/.zshenv`, so zsh loads `~/.config/zsh/.zshrc`, **not** `~/.zshrc`. Any shell env exports must go in `home/dot_config/zsh/dot_zshrc.tmpl`.

### Multi-Platform Pattern
Tasks use `when:` conditions with `ansible_facts`:
- `ansible_facts['os_family'] == "Archlinux"` - Arch, CachyOS
- `ansible_facts['os_family'] == "Darwin"` - macOS

### Configuration Hierarchy
1. Defaults in `group_vars/all.yml`
2. Encrypted secrets in `group_vars/vault.yml`
3. Command-line overrides via `-e "variable=value"`
4. Templates render variables into config files (`.j2` files)

## Adding New Functionality

### Adding a package
Edit `ansible/group_vars/all.yml`:
- `packages_common` for packages with same name across all distros
- `packages_arch`, `packages_macos` for platform-specific names
- `packages_aur` for AUR-only packages (built via makepkg pattern in `aur.yml`)

### Adding a new optional tool
1. Create `ansible/roles/base/tasks/mytool.yml` with platform-specific installation tasks
2. Add feature flag `install_mytool: true` to `group_vars/all.yml`
3. Import in `roles/base/tasks/main.yml` with `when: install_mytool | default(false)`

### Adding a new role
1. Create `ansible/roles/myrole/tasks/main.yml`
2. Add handlers in `roles/myrole/handlers/main.yml` if needed
3. Add templates in `roles/myrole/templates/` if needed
4. Include in `local.yml` under `roles:` with appropriate `when:` conditions and tags
