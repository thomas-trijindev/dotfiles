# Roadmap

Planned future additions to this repo.

---

## 1. AutoFS SMB Mounts

Mount NAS shares from `192.168.0.6` via autofs — same pattern as `kew-infra`.

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
- Cron health-check script (same as kew-infra): verify mount is accessible every N minutes; remount if dead

---

## 2. Chezmoi-Managed Dotfiles

Manage `zsh`, `tmux`, and `neovim` configs via chezmoi. Source material is `dot-example`; repo already has `.chezmoiroot = home/` so all files go under `home/`.

### ZSH — replicate dot-example as-is (oh-my-zsh + spaceship)

The dot-example is a 5-file XDG-compliant structure. Replicate all 5 files under `home/`:

| chezmoi source | deploys to |
|---|---|
| `home/dot_zshenv` | `~/.zshenv` |
| `home/dot_config/zsh/dot_zprofile` | `~/.config/zsh/.zprofile` |
| `home/dot_config/zsh/dot_zshrc.tmpl` | `~/.config/zsh/.zshrc` |
| `home/dot_config/zsh/ohmyzsh_settings` | `~/.config/zsh/ohmyzsh_settings` |
| `home/dot_config/zsh/zsh_aliases` | `~/.config/zsh/zsh_aliases` |

**`dot_zshenv`** — copy as-is, except:
- Remove `SSH_AUTH_SOCK` 1Password lines (not using 1Password); SSH agent handled externally

**`dot_zprofile`** — copy as-is, except:
- Remove `SSH_KEYS` / keychain / 1Password block (Linux section) — replaced by system SSH agent
- Keep `fastfetch` + cowsay/fortune/lolcat login display
- Keep cargo env source
- Remove OrbStack block (macOS only, not needed)

**`dot_zshrc.tmpl`** — copy as-is, except:
- Add secret via chezmoi template (`.tmpl` suffix required):
  ```
  export CLAUDE_CODE_OAUTH_TOKEN="{{ env "CLAUDE_CODE_OAUTH_TOKEN" }}"
  ```
- Adapt FZF for Arch: `fd` (not `fdfind`), FZF path from `/usr/share/fzf/` (Arch package path)

**`ohmyzsh_settings`** — copy as-is:
- Spaceship theme on both macOS and Linux
- Spaceship prompt order: host → dir → git → venv → char
- Spaceship rprompt: node → docker → python → exec_time
- Plugins: zsh-autosuggestions, zsh-syntax-highlighting, autojump

**`zsh_aliases`** — copy as-is, except:
- Linux section: remove Ubuntu `fdfind` alias (Arch has `fd` natively); keep `bat` alias (Arch package is `bat` not `batcat`)
- Pacman aliases already in the file (`paci`/`pacu`) — keep as-is

### Tmux — `home/dot_config/tmux/tmux.conf`

Copy `dot-example/tmux/.config/tmux/tmux.conf` as-is:
- Gruvbox theme
- `C-a` prefix
- Mouse mode
- Split panes open in current path

### Neovim — `home/dot_config/nvim/`

Copy active config from `dot-example/nvim/.config/nvim/` (skip `.bkp` files):

```
home/dot_config/nvim/
├── init.lua
└── lua/tjunkie/
    ├── core/
    │   ├── init.lua
    │   ├── keymaps.lua
    │   ├── options.lua
    │   └── which-key-settings.lua
    ├── lazy.lua
    └── plugins/
        ├── init.lua
        ├── colorscheme.lua
        ├── nvim-cmp.lua
        ├── telescope.lua
        ├── trouble.lua
        ├── which-key.lua
        └── lsp/
            └── lsp.lua
```

Stack: Lazy.nvim, tokyonight, lsp-zero + Mason, nvim-cmp, telescope, trouble, which-key.

**autoread — auto-refresh when file changed by external tool (e.g. Claude Code)**

Add to `lua/tjunkie/core/options.lua`:
```lua
vim.opt.autoread = true
```

`autoread` alone only reacts on user input. Add autocommands to actively poll on focus/cursor idle — add to `lua/tjunkie/core/init.lua` (or a dedicated `autocmds.lua`):
```lua
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  command = "checktime",
})
```

- `FocusGained` / `BufEnter` — reloads when you switch back to nvim or change buffers
- `CursorHold` / `CursorHoldI` — reloads while idle (interval controlled by `updatetime`, default 4000ms; set `vim.opt.updatetime = 1000` for faster refresh)

### Verification steps (when implementing)

1. `chezmoi diff` — preview what chezmoi would apply
2. `chezmoi apply --dry-run` — validate template rendering
3. Confirm `CLAUDE_CODE_OAUTH_TOKEN` is not hardcoded in any committed file (`git grep CLAUDE_CODE_OAUTH_TOKEN`)
4. Open new terminal — zsh config loads without errors
5. Launch `nvim` — Lazy.nvim bootstraps and plugins install
