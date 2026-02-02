# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is an Ansible-based system configuration repository that automates the setup of Linux (Arch/CachyOS, Fedora, Ubuntu/Debian) and macOS machines with developer tools, packages, and configurations.

## Commands

```bash
# Run the full playbook (primary method)
./ansible/run.sh

# Direct execution with password prompt
ansible-playbook ansible/local.yml --ask-become-pass

# Run specific components via tags
ansible-playbook ansible/local.yml --tags base      # Packages only
ansible-playbook ansible/local.yml --tags power     # Power management only

# Override variables
ansible-playbook ansible/local.yml -e "install_nordvpn=false"

# Install Ansible collections (required before first run)
ansible-galaxy collection install -r ansible/requirements.yml
```

## Architecture

### Execution Flow
`local.yml` orchestrates everything: **pre_tasks** (detect OS, chassis type, user UID) → **roles** (base, power) → **post_tasks** (completion message)

### Key Files
- `ansible/local.yml` - Main playbook entry point
- `ansible/group_vars/all.yml` - All configurable variables (packages, feature flags, power settings)
- `ansible/requirements.yml` - External Ansible collections (community.general, kewlfft.aur)

### Roles
- **base** (`roles/base/tasks/`) - Package installation and optional tools
  - `packages.yml` - Cross-platform package installation via native package managers
  - `aur.yml` - Arch User Repository support (installs paru, builds AUR packages)
  - `nordvpn.yml`, `chezmoi.yml`, `claude.yml` - Optional tool installations (controlled by feature flags)
- **power** (`roles/power/`) - Laptop power management (Linux only)
  - Configures systemd-logind via `templates/power.conf.j2`
  - Deploys swayidle user service via `templates/swayidle.service.j2`

### Multi-Platform Pattern
Tasks use `when:` conditions with `ansible_facts`:
- `ansible_facts['os_family'] == "Archlinux"` - Arch, CachyOS, Manjaro
- `ansible_facts['os_family'] == "Debian"` - Ubuntu, Debian
- `ansible_facts['distribution'] == "Fedora"` - Fedora specifically
- `ansible_facts['os_family'] == "Darwin"` - macOS

### Configuration Hierarchy
1. Defaults in `group_vars/all.yml`
2. Command-line overrides via `-e "variable=value"`
3. Templates render variables into config files (`.j2` files)

## Adding New Functionality

### Adding a package
Edit `ansible/group_vars/all.yml`:
- `packages_common` for packages with same name across all distros
- `packages_arch`, `packages_fedora`, `packages_ubuntu`, `packages_macos` for distro-specific names

### Adding a new optional tool
1. Create `ansible/roles/base/tasks/mytool.yml` with platform-specific installation tasks
2. Add feature flag `install_mytool: true` to `group_vars/all.yml`
3. Import in `roles/base/tasks/main.yml` with `when: install_mytool | default(false)`

### Adding a new role
1. Create `ansible/roles/myrole/tasks/main.yml`
2. Add handlers in `roles/myrole/handlers/main.yml` if needed
3. Add templates in `roles/myrole/templates/` if needed
4. Include in `local.yml` under `roles:` with appropriate `when:` conditions and tags
