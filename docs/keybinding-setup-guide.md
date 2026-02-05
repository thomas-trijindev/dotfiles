# Complete Keybinding Setup Guide: Mac + Linux (niri/keyd)

## Table of Contents

1. [Philosophy & Design Principles](#philosophy--design-principles)
2. [Installation & Setup](#installation--setup)
3. [keyd Configuration (User Service)](#keyd-configuration-user-service)
4. [niri Configuration](#niri-configuration)
5. [Terminal Application Bindings](#terminal-application-bindings)
6. [Additional Features & Enhancements](#additional-features--enhancements)
7. [Dotfile Management Integration](#dotfile-management-integration)
8. [Troubleshooting](#troubleshooting)
9. [Quick Reference](#quick-reference)

---

## Philosophy & Design Principles

### Cross-Platform Consistency

This setup maintains muscle memory between macOS and Linux by:
- Using Cmd (Super) for system-level operations on both platforms
- Reserving Ctrl for terminal applications (tmux, vim, CLI tools)
- Using Caps Lock as Hyper for advanced window management (Linux-specific enhancement)
- Mirroring common macOS shortcuts where sensible

### Modifier Hierarchy

| Modifier | Primary Use | Examples | Conflicts to Avoid |
|----------|-------------|----------|-------------------|
| **Hyper (Mod3)** | Window/workspace management (Linux only) | Focus, move, resize windows | None - rarely used by apps |
| **Super (Mod4)** | Application launchers, global actions | Launch apps, screenshots, system menus | Similar to macOS Cmd |
| **Ctrl** | Reserved for applications | Tmux, vim, terminal, browser | Never use for WM bindings |
| **Alt** | Application shortcuts, secondary actions | Terminal tabs, vim windows | Keep minimal for WM |
| **Shift** | Modifier for existing bindings | With Hyper/Super for variants | Combined use only |

### Why This Design Works

**No conflicts with tmux:**
- Tmux typically uses `Ctrl+b` or `Ctrl+a` prefix
- Your Hyper keys won't interfere
- Tmux window navigation (prefix + hjkl) remains untouched

**No conflicts with vim:**
- Vim uses Ctrl+w for window commands
- Vim uses Ctrl for various commands (Ctrl+d, Ctrl+u, Ctrl+o, etc.)
- Your Hyper keys are completely separate
- Vim hjkl navigation won't conflict because vim doesn't capture Mod3

**Clean separation:**
- **Hyper (Caps)**: Hands stay on home row for WM control
- **Mod (Super)**: Left thumb for launching apps
- **Ctrl**: Free for terminal/tmux/vim
- **Alt**: Free for application-specific shortcuts

---

## Installation & Setup

### Prerequisites (CachyOS)

```bash
# Install required packages
sudo pacman -S keyd niri rofi-wayland grimblast cliphist wl-clipboard playerctl brightnessctl

# Optional but recommended
sudo pacman -S mako waybar alacritty tmux neovim
```

### Setup Overview

We'll configure keyd as a **user service** (non-root) for better dotfile management:

**Benefits of User Service:**
- ✅ Config in `~/.config/keyd/` (no sudo needed for changes)
- ✅ Easy version control with chezmoi/Ansible
- ✅ User-specific configurations
- ✅ Integrated with systemd user session

---

## keyd Configuration (User Service)

### Method 1: User Service with Input Group (Recommended)

This is the best approach for single-user systems and laptops.

#### Step 1: Add Your User to Input Group

```bash
# Add yourself to the input group (one-time sudo)
sudo usermod -aG input $USER

# Verify membership
groups $USER

# Log out and back in for this to take effect
# Or use: newgrp input
```

#### Step 2: Create Local keyd Configuration

```bash
# Create config directory
mkdir -p ~/.config/keyd

# Create your config file
nano ~/.config/keyd/default.conf
```

**File: `~/.config/keyd/default.conf`**

```ini
[ids]
*

[main]
# Caps Lock becomes Hyper modifier (Mod3)
# This is your power key for window management
capslock = layer(hyper)

# Optional: Make Escape+Caps output actual Caps Lock (for rare cases)
# esc = capslock

[hyper:M]
# M suffix makes this a modifier layer
# When Caps is held, these keys become available

# Navigation enhancement - makes Hyper+hjkl also send arrows
# This provides compatibility with apps that don't recognize Mod3
h = left
j = down
k = up
l = right

# Quick access to special keys
backspace = delete
space = escape

# Number row becomes function keys (Hyper+1 = F1, etc.)
1 = f1
2 = f2
3 = f3
4 = f4
5 = f5
6 = f6
7 = f7
8 = f8
9 = f9
0 = f10
minus = f11
equal = f12

# Optional: Additional convenience mappings
# semicolon = return
# apostrophe = backspace
```

#### Step 3: Create User systemd Service

```bash
# Create systemd user service directory
mkdir -p ~/.config/systemd/user

# Create the service file
nano ~/.config/systemd/user/keyd.service
```

**File: `~/.config/systemd/user/keyd.service`**

```ini
[Unit]
Description=keyd keyboard remapping daemon (user service)
Documentation=man:keyd(1)

[Service]
Type=simple
ExecStart=/usr/bin/keyd -c %h/.config/keyd
Restart=always
RestartSec=3

# Security hardening (optional but recommended)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/keyd

[Install]
WantedBy=default.target
```

#### Step 4: Enable and Start Service

```bash
# Reload systemd user daemon
systemctl --user daemon-reload

# Enable service to start on login
systemctl --user enable keyd.service

# Start the service now
systemctl --user start keyd.service

# Check status
systemctl --user status keyd.service
```

#### Step 5: Verify It's Working

```bash
# Monitor keyd events (test your Caps key)
sudo keyd monitor
# Or if running as user service:
keyd monitor

# Press Caps+H, should show: hyper down, h down, left down
# Press Caps+J, should show: hyper down, j down, down down
```

### Method 2: User Service with udev Rules (More Secure)

If you prefer not to add your user to the input group, use specific udev rules.

#### Create udev Rule

```bash
# Create udev rule (requires sudo once)
sudo tee /etc/udev/rules.d/90-keyd.rules << 'EOF'
# Allow users in 'keyd' group to access input devices
KERNEL=="event*", SUBSYSTEM=="input", TAG+="uaccess", GROUP="keyd", MODE="0660"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", GROUP="keyd", MODE="0660"
EOF

# Create keyd group
sudo groupadd keyd

# Add your user to keyd group
sudo usermod -aG keyd $USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Verify
groups $USER
```

Then follow steps 2-5 from Method 1.

### Auto-reload on Config Change (Optional)

Create a path unit to automatically reload keyd when config changes:

**File: `~/.config/systemd/user/keyd-reload.path`**

```ini
[Unit]
Description=Monitor keyd config for changes

[Path]
PathChanged=%h/.config/keyd/default.conf

[Install]
WantedBy=default.target
```

**File: `~/.config/systemd/user/keyd-reload.service`**

```ini
[Unit]
Description=Reload keyd on config change

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl --user restart keyd.service
```

Enable it:

```bash
systemctl --user enable --now keyd-reload.path
```

---

## niri Configuration

### File Location

**`~/.config/niri/config.kdl`**

### Complete Bindings Configuration

```kdl
// ============================================================================
// KEY BINDINGS - Cross-platform optimized for Mac/Linux workflow
// ============================================================================

bindings {
    // ------------------------------------------------------------------------
    // SUPER (Mod4) - Application Launchers & System Actions
    // Mirrors macOS Command key behavior
    // ------------------------------------------------------------------------
    
    // Application launching
    Mod+Return { spawn "alacritty"; }                    // Terminal
    Mod+D { spawn "rofi" "-show" "drun"; }               // App launcher (like Spotlight)
    Mod+Shift+D { spawn "rofi" "-show" "run"; }          // Command launcher
    Mod+E { spawn "nautilus"; }                          // File manager
    Mod+B { spawn "firefox"; }                           // Browser
    
    // Screenshots (Mac-style Cmd+Shift+3/4/5)
    Mod+Shift+3 { spawn "grimblast" "copy" "screen"; }   // Full screen
    Mod+Shift+4 { spawn "grimblast" "copy" "area"; }     // Selection
    Mod+Shift+5 { spawn "grimblast" "copy" "window"; }   // Window capture
    
    // System controls
    Mod+L { spawn "swaylock"; }                          // Lock screen
    Mod+Shift+E { spawn "wlogout"; }                     // Power menu
    Mod+Shift+R { spawn "niri" "msg" "action" "reload-config"; }
    Mod+Shift+Q { quit; }                                // Quit niri
    
    // Media controls (F7-F12 like Mac)
    Mod+F7 { spawn "playerctl" "previous"; }
    Mod+F8 { spawn "playerctl" "play-pause"; }
    Mod+F9 { spawn "playerctl" "next"; }
    Mod+F10 { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    Mod+F11 { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    Mod+F12 { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    
    // Brightness (F1/F2 like Mac)
    Mod+F1 { spawn "brightnessctl" "set" "5%-"; }
    Mod+F2 { spawn "brightnessctl" "set" "5%+"; }
    
    // Notifications
    Mod+N { spawn "makoctl" "dismiss"; }
    Mod+Shift+N { spawn "makoctl" "dismiss" "--all"; }
    
    // ------------------------------------------------------------------------
    // HYPER (Mod3 via Caps Lock) - Window & Workspace Management
    // Linux enhancement - no macOS equivalent needed
    // ------------------------------------------------------------------------
    
    // Window focus - Vim-style HJKL
    Mod3+H { focus-column-left; }
    Mod3+J { focus-window-down; }
    Mod3+K { focus-window-up; }
    Mod3+L { focus-column-right; }
    
    // Alternative: Arrow keys for same actions
    Mod3+Left { focus-column-left; }
    Mod3+Down { focus-window-down; }
    Mod3+Up { focus-window-up; }
    Mod3+Right { focus-column-right; }
    
    // Window movement - Shift+HJKL
    Mod3+Shift+H { move-column-left; }
    Mod3+Shift+J { move-window-down; }
    Mod3+Shift+K { move-window-up; }
    Mod3+Shift+L { move-column-right; }
    
    Mod3+Shift+Left { move-column-left; }
    Mod3+Shift+Down { move-window-down; }
    Mod3+Shift+Up { move-window-up; }
    Mod3+Shift+Right { move-column-right; }
    
    // Window resizing - Ctrl+HJKL
    // Safe because Hyper+Ctrl won't conflict with tmux (which uses just Ctrl)
    Mod3+Ctrl+H { set-column-width "-10%"; }
    Mod3+Ctrl+J { set-window-height "-10%"; }
    Mod3+Ctrl+K { set-window-height "+10%"; }
    Mod3+Ctrl+L { set-column-width "+10%"; }
    
    Mod3+Ctrl+Left { set-column-width "-10%"; }
    Mod3+Ctrl+Down { set-window-height "-10%"; }
    Mod3+Ctrl+Up { set-window-height "+10%"; }
    Mod3+Ctrl+Right { set-column-width "+10%"; }
    
    // Reset window size
    Mod3+R { reset-window-height; }
    Mod3+Shift+R { set-column-width "50%"; }
    
    // Window actions
    Mod3+F { fullscreen-window; }
    Mod3+M { maximize-column; }
    Mod3+C { center-column; }
    Mod3+Q { close-window; }
    
    // Window arrangement presets
    Mod3+Ctrl+F { set-column-width "100%"; }             // Full width
    Mod3+Ctrl+T { set-column-width "33%"; }              // Third
    Mod3+Ctrl+W { set-column-width "66%"; }              // Two-thirds
    
    // Workspace switching - Numbers (1-9, 0 for workspace 10)
    Mod3+1 { focus-workspace 1; }
    Mod3+2 { focus-workspace 2; }
    Mod3+3 { focus-workspace 3; }
    Mod3+4 { focus-workspace 4; }
    Mod3+5 { focus-workspace 5; }
    Mod3+6 { focus-workspace 6; }
    Mod3+7 { focus-workspace 7; }
    Mod3+8 { focus-workspace 8; }
    Mod3+9 { focus-workspace 9; }
    Mod3+0 { focus-workspace 10; }
    
    // Move window to workspace - Shift+Numbers
    Mod3+Shift+1 { move-column-to-workspace 1; }
    Mod3+Shift+2 { move-column-to-workspace 2; }
    Mod3+Shift+3 { move-column-to-workspace 3; }
    Mod3+Shift+4 { move-column-to-workspace 4; }
    Mod3+Shift+5 { move-column-to-workspace 5; }
    Mod3+Shift+6 { move-column-to-workspace 6; }
    Mod3+Shift+7 { move-column-to-workspace 7; }
    Mod3+Shift+8 { move-column-to-workspace 8; }
    Mod3+Shift+9 { move-column-to-workspace 9; }
    Mod3+Shift+0 { move-column-to-workspace 10; }
    
    // Workspace navigation - Brackets (niri scrollable feature)
    Mod3+BracketLeft { focus-workspace-down; }           // Previous workspace
    Mod3+BracketRight { focus-workspace-up; }            // Next workspace
    
    // Alternative: Page Up/Down
    Mod3+Prior { focus-workspace-down; }
    Mod3+Next { focus-workspace-up; }
    
    // Workspace with window - Ctrl+Brackets
    Mod3+Ctrl+BracketLeft { move-column-to-workspace-down; }
    Mod3+Ctrl+BracketRight { move-column-to-workspace-up; }
    
    // Monitor focus (multi-monitor setups)
    Mod3+Comma { focus-monitor-left; }
    Mod3+Period { focus-monitor-right; }
    Mod3+Shift+Comma { move-column-to-monitor-left; }
    Mod3+Shift+Period { move-column-to-monitor-right; }
    
    // Consume/expel window from column
    Mod3+I { consume-window-into-column; }
    Mod3+O { expel-window-from-column; }
    
    // ------------------------------------------------------------------------
    // ADDITIONAL SUPER SHORTCUTS
    // ------------------------------------------------------------------------
    
    // Window switching (Alt+Tab replacement)
    Mod+Tab { focus-window-down-or-right; }
    Mod+Shift+Tab { focus-window-up-or-left; }
    
    // Window switcher with rofi
    Mod+W { spawn "rofi" "-show" "window"; }
    
    // Clipboard history (Mac-style Cmd+Shift+V)
    Mod+Shift+V { spawn "sh" "-c" "cliphist list | rofi -dmenu | cliphist decode | wl-copy"; }
    
    // Emoji picker (like macOS Cmd+Ctrl+Space)
    Mod+Ctrl+Space { spawn "rofi" "-show" "emoji" "-modi" "emoji"; }
    
    // Color picker
    Mod+Shift+C { spawn "hyprpicker" "-a"; }
    
    // Scratchpad terminal (quake-style dropdown)
    Mod+Grave { spawn "scratchpad-toggle"; }
    
    // ------------------------------------------------------------------------
    // MOUSE BINDINGS
    // ------------------------------------------------------------------------
    
    Mod+WheelScrollDown { focus-workspace-down; }
    Mod+WheelScrollUp { focus-workspace-up; }
    Mod+WheelScrollRight { focus-column-right; }
    Mod+WheelScrollLeft { focus-column-left; }
}

// ============================================================================
// WORKSPACE CONFIGURATION
// ============================================================================

workspaces {
    1 { name "main"; }
    2 { name "dev"; }
    3 { name "web"; }
    4 { name "chat"; }
    5 { name "media"; }
    6 { name "misc"; }
}

// ============================================================================
// WINDOW RULES
// ============================================================================

window-rules {
    // Float specific apps (like macOS)
    match app-id="org.gnome.Calculator" {
        default-floating true;
        default-width 400;
        default-height 600;
    }
    
    // Picture-in-picture
    match title="Picture-in-Picture" {
        default-floating true;
        focus-ring false;
    }
    
    // Assign apps to specific workspaces
    match app-id="firefox" {
        open-on-workspace "web";
    }
    
    match app-id="Slack" {
        open-on-workspace "chat";
    }
    
    // Scratchpad terminal
    match app-id="scratchpad" {
        default-floating true;
        default-width 1200;
        default-height 700;
    }
}
```

---

## Terminal Application Bindings

### tmux Configuration

Keep tmux prefix as **Ctrl+b** (or Ctrl+a) - completely separate from WM bindings.

**File: `~/.tmux.conf`**

```bash
# Standard tmux prefix - no conflicts with Hyper/Super
set -g prefix C-b
bind C-b send-prefix

# Better defaults
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# Window navigation (prefix + hjkl) - no conflicts
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Pane resizing (prefix + HJKL) - no conflicts
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Split panes using | and -
bind | split-window -h
bind - split-window -v

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded!"

# Mac clipboard integration
if-shell "uname | grep -q Darwin" {
    bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel 'pbcopy'
    bind-key -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel 'pbcopy'
}

# Linux clipboard integration (Wayland)
if-shell "uname | grep -q Linux" {
    bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel 'wl-copy'
    bind-key -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel 'wl-copy'
}

# Vi mode
setw -g mode-keys vi
bind-key -T copy-mode-vi v send-keys -X begin-selection
```

### vim/neovim Configuration

Your vim bindings remain completely untouched.

**Common vim shortcuts that won't conflict:**

```vim
" Window navigation - Ctrl+w then hjkl (no conflicts)
" Or set up direct Ctrl+hjkl navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Tab navigation using Alt (no conflicts with Hyper/Super)
nnoremap <A-h> :tabprevious<CR>
nnoremap <A-l> :tabnext<CR>
nnoremap <A-1> 1gt
nnoremap <A-2> 2gt
nnoremap <A-3> 3gt
nnoremap <A-4> 4gt
nnoremap <A-5> 5gt
```

### Alacritty Configuration

**File: `~/.config/alacritty/alacritty.toml`**

```toml
# Font configuration
[font]
size = 12.0

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

# Keyboard shortcuts
[[keyboard.bindings]]
# Mac-style new tab (creates tmux window)
key = "T"
mods = "Super"
chars = "\u0002c"  # Ctrl+B then c

[[keyboard.bindings]]
# Mac-style close tab (kills tmux window)
key = "W"
mods = "Super"
chars = "\u0002&"  # Ctrl+B then &

[[keyboard.bindings]]
# Switch to tmux window 1
key = "Key1"
mods = "Super"
chars = "\u00021"

[[keyboard.bindings]]
key = "Key2"
mods = "Super"
chars = "\u00022"

[[keyboard.bindings]]
key = "Key3"
mods = "Super"
chars = "\u00023"

[[keyboard.bindings]]
key = "Key4"
mods = "Super"
chars = "\u00024"

[[keyboard.bindings]]
key = "Key5"
mods = "Super"
chars = "\u00025"

[[keyboard.bindings]]
# Copy (Mac-style)
key = "C"
mods = "Super"
action = "Copy"

[[keyboard.bindings]]
# Paste (Mac-style)
key = "V"
mods = "Super"
action = "Paste"

[[keyboard.bindings]]
# Increase font size
key = "Plus"
mods = "Super"
action = "IncreaseFontSize"

[[keyboard.bindings]]
# Decrease font size
key = "Minus"
mods = "Super"
action = "DecreaseFontSize"

[[keyboard.bindings]]
# Reset font size
key = "Key0"
mods = "Super"
action = "ResetFontSize"

[[keyboard.bindings]]
# Search
key = "F"
mods = "Super"
action = "SearchForward"

[[keyboard.bindings]]
# New instance
key = "N"
mods = "Super"
action = "CreateNewWindow"

# Colors (example - adjust to your preference)
[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"
```

---

## Additional Features & Enhancements

### Clipboard Manager

Install and configure cliphist:

```bash
# Install
sudo pacman -S cliphist wl-clipboard

# Add to your autostart (if using waybar or similar)
wl-paste --watch cliphist store &
```

Usage is already configured in niri with `Mod+Shift+V`.

### Emoji Picker

```bash
# Install rofi-emoji
yay -S rofi-emoji

# Already bound to Mod+Ctrl+Space in niri config
```

### Color Picker

```bash
# Install hyprpicker
sudo pacman -S hyprpicker

# Already bound to Mod+Shift+C in niri config
```

### Scratchpad Terminal

Create `~/bin/scratchpad-toggle`:

```bash
#!/bin/bash
# Toggle scratchpad terminal

if pgrep -f "alacritty.*scratchpad" > /dev/null; then
    # Kill existing scratchpad
    pkill -f "alacritty.*scratchpad"
else
    # Launch new scratchpad
    alacritty --class scratchpad -e tmux new-session -A -s scratchpad &
fi
```

Make it executable:

```bash
chmod +x ~/bin/scratchpad-toggle
```

### Screen Recording

Create `~/bin/record-toggle`:

```bash
#!/bin/bash
# Toggle screen recording with wf-recorder

PID_FILE="/tmp/wf-recorder.pid"

if [ -f "$PID_FILE" ]; then
    # Stop recording
    kill $(cat "$PID_FILE")
    rm "$PID_FILE"
    notify-send "Recording stopped" "Video saved to ~/Videos/"
else
    # Start recording
    wf-recorder -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4 &
    echo $! > "$PID_FILE"
    notify-send "Recording started"
fi
```

Install wf-recorder:

```bash
sudo pacman -s wf-recorder
chmod +x ~/bin/record-toggle
```

### Notification Management

Configure mako for notifications:

**File: `~/.config/mako/config`**

```ini
# Mako notification daemon config
font=JetBrainsMono Nerd Font 10
background-color=#1a1b26
text-color=#c0caf5
border-color=#7aa2f7
border-size=2
border-radius=8
margin=10
padding=15
default-timeout=5000
ignore-timeout=0

[urgency=low]
border-color=#565f89

[urgency=normal]
border-color=#7aa2f7

[urgency=high]
border-color=#f7768e
default-timeout=0
```

Start mako:

```bash
# Add to your autostart
mako &
```

### Touchpad Gestures (Optional)

For macOS-like gestures:

```bash
# Install libinput-gestures
sudo pacman -S libinput-gestures

# Add user to input group (already done for keyd)
sudo usermod -aG input $USER
```

**File: `~/.config/libinput-gestures.conf`**

```
# Workspace switching (3 fingers swipe)
gesture swipe left 3 niri msg action focus-workspace-up
gesture swipe right 3 niri msg action focus-workspace-down

# App switcher (3 fingers swipe up)
gesture swipe up 3 rofi -show window

# App launcher (3 fingers swipe down)
gesture swipe down 3 rofi -show drun

# Pinch to show all workspaces (if supported)
# gesture pinch in rofi -show window
```

Enable and start:

```bash
libinput-gestures-setup autostart start
```

---

## Dotfile Management Integration

### With chezmoi

#### Initial Setup

```bash
# Initialize chezmoi if not already done
chezmoi init

# Add keyd config
chezmoi add ~/.config/keyd/default.conf
chezmoi add ~/.config/systemd/user/keyd.service

# Add niri config
chezmoi add ~/.config/niri/config.kdl

# Add terminal configs
chezmoi add ~/.tmux.conf
chezmoi add ~/.config/alacritty/alacritty.toml

# Add helper scripts
chezmoi add ~/bin/scratchpad-toggle
chezmoi add ~/bin/record-toggle
```

#### Create Setup Script

**File: `~/.local/share/chezmoi/run_once_setup_keybinding.sh`**

```bash
#!/bin/bash

echo "🔧 Setting up keybinding environment..."

# Add user to input group
if ! groups | grep -q input; then
    echo "➕ Adding $USER to input group..."
    sudo usermod -aG input $USER
    echo "⚠️  Please log out and back in for group changes to take effect"
fi

# Create bin directory
mkdir -p ~/bin

# Reload systemd user daemon
systemctl --user daemon-reload

# Enable and start keyd user service
systemctl --user enable --now keyd.service

# Enable keyd auto-reload on config change
if [ -f ~/.config/systemd/user/keyd-reload.path ]; then
    systemctl --user enable --now keyd-reload.path
fi

# Install optional tools if not present
if ! command -v rofi &> /dev/null; then
    echo "📦 Consider installing: rofi-wayland cliphist wl-clipboard"
fi

echo "✅ Keybinding setup complete!"
echo ""
echo "Service status: systemctl --user status keyd.service"
echo "Test keyd: keyd monitor"
```

Make it executable:

```bash
chmod +x ~/.local/share/chezmoi/run_once_setup_keybinding.sh
```

### With Ansible

**Directory structure:**

```
ansible/
├── playbooks/
│   └── keybinding-setup.yml
├── files/
│   ├── keyd/
│   │   └── default.conf
│   ├── systemd/
│   │   └── user/
│   │       ├── keyd.service
│   │       ├── keyd-reload.path
│   │       └── keyd-reload.service
│   ├── niri/
│   │   └── config.kdl
│   ├── alacritty/
│   │   └── alacritty.toml
│   └── scripts/
│       ├── scratchpad-toggle
│       └── record-toggle
```

**Playbook: `playbooks/keybinding-setup.yml`**

```yaml
---
- name: Setup complete keybinding environment
  hosts: localhost
  vars:
    user_home: "{{ ansible_env.HOME }}"
    
  tasks:
    # ========================================
    # System-level setup (requires sudo)
    # ========================================
    
    - name: Ensure input group exists
      group:
        name: input
        state: present
      become: yes

    - name: Add user to input group
      user:
        name: "{{ ansible_user_id }}"
        groups: input
        append: yes
      become: yes
      register: group_added

    - name: Notify about group change
      debug:
        msg: "⚠️  Please log out and back in for input group changes to take effect"
      when: group_added.changed

    # ========================================
    # keyd configuration
    # ========================================
    
    - name: Create keyd config directory
      file:
        path: "{{ user_home }}/.config/keyd"
        state: directory
        mode: '0755'

    - name: Copy keyd configuration
      copy:
        src: files/keyd/default.conf
        dest: "{{ user_home }}/.config/keyd/default.conf"
        mode: '0644'
      notify: Restart keyd user service

    # ========================================
    # systemd user services
    # ========================================
    
    - name: Create systemd user directory
      file:
        path: "{{ user_home }}/.config/systemd/user"
        state: directory
        mode: '0755'

    - name: Copy keyd user service
      copy:
        src: files/systemd/user/keyd.service
        dest: "{{ user_home }}/.config/systemd/user/keyd.service"
        mode: '0644'
      notify:
        - Reload systemd user daemon
        - Restart keyd user service

    - name: Copy keyd auto-reload path unit
      copy:
        src: files/systemd/user/keyd-reload.path
        dest: "{{ user_home }}/.config/systemd/user/keyd-reload.path"
        mode: '0644'
      notify:
        - Reload systemd user daemon
        - Enable keyd reload path

    - name: Copy keyd auto-reload service
      copy:
        src: files/systemd/user/keyd-reload.service
        dest: "{{ user_home }}/.config/systemd/user/keyd-reload.service"
        mode: '0644'
      notify: Reload systemd user daemon

    # ========================================
    # niri configuration
    # ========================================
    
    - name: Create niri config directory
      file:
        path: "{{ user_home }}/.config/niri"
        state: directory
        mode: '0755'

    - name: Copy niri configuration
      copy:
        src: files/niri/config.kdl
        dest: "{{ user_home }}/.config/niri/config.kdl"
        mode: '0644'

    # ========================================
    # Terminal configurations
    # ========================================
    
    - name: Create alacritty config directory
      file:
        path: "{{ user_home }}/.config/alacritty"
        state: directory
        mode: '0755'

    - name: Copy alacritty configuration
      copy:
        src: files/alacritty/alacritty.toml
        dest: "{{ user_home }}/.config/alacritty/alacritty.toml"
        mode: '0644'

    - name: Copy tmux configuration
      copy:
        src: files/tmux/tmux.conf
        dest: "{{ user_home }}/.tmux.conf"
        mode: '0644'

    # ========================================
    # Helper scripts
    # ========================================
    
    - name: Create bin directory
      file:
        path: "{{ user_home }}/bin"
        state: directory
        mode: '0755'

    - name: Copy helper scripts
      copy:
        src: "{{ item }}"
        dest: "{{ user_home }}/bin/{{ item | basename }}"
        mode: '0755'
      loop:
        - files/scripts/scratchpad-toggle
        - files/scripts/record-toggle

    # ========================================
    # Package installation
    # ========================================
    
    - name: Install required packages
      package:
        name:
          - keyd
          - niri
          - rofi-wayland
          - grimblast
          - cliphist
          - wl-clipboard
          - playerctl
          - brightnessctl
          - mako
          - alacritty
          - tmux
        state: present
      become: yes
      when: ansible_os_family == "Archlinux"

  handlers:
    - name: Reload systemd user daemon
      systemd:
        daemon_reload: yes
        scope: user
      environment:
        XDG_RUNTIME_DIR: "/run/user/{{ ansible_user_uid }}"

    - name: Restart keyd user service
      systemd:
        name: keyd.service
        state: restarted
        enabled: yes
        scope: user
      environment:
        XDG_RUNTIME_DIR: "/run/user/{{ ansible_user_uid }}"

    - name: Enable keyd reload path
      systemd:
        name: keyd-reload.path
        enabled: yes
        state: started
        scope: user
      environment:
        XDG_RUNTIME_DIR: "/run/user/{{ ansible_user_uid }}"
```

**Run the playbook:**

```bash
ansible-playbook playbooks/keybinding-setup.yml
```

---

## Troubleshooting

### keyd Issues

#### Permission Denied

```bash
# Check if you're in the input group
groups

# If not showing 'input', log out and back in
# Or use newgrp:
newgrp input

# Then restart service
systemctl --user restart keyd.service
```

#### Service Fails to Start

```bash
# Check detailed logs
journalctl --user -u keyd.service -f

# Test keyd manually
keyd -c ~/.config/keyd

# Check if keyd binary exists
which keyd

# Verify config syntax
keyd -c ~/.config/keyd -d  # Dry run
```

#### Keys Not Remapping

```bash
# Monitor keyd events
keyd monitor

# Check service status
systemctl --user status keyd.service

# Restart service
systemctl --user restart keyd.service

# Check if config file is correct
cat ~/.config/keyd/default.conf
```

### niri Issues

#### Bindings Not Working

```bash
# Reload niri config
niri msg action reload-config

# Check niri logs
journalctl --user -u niri -f

# Test specific binding
# Press the key combination and check if anything happens
```

#### Mod3 Not Recognized

```bash
# Verify keyd is running
systemctl --user status keyd.service

# Test with keyd monitor
keyd monitor
# Press Caps Lock + H, should show Mod3

# If not working, check keyd config
cat ~/.config/keyd/default.conf
```

### General Issues

#### After System Update

```bash
# Reload all configs
systemctl --user daemon-reload
systemctl --user restart keyd.service
niri msg action reload-config
```

#### Conflicting Key Bindings

```bash
# List all active key grabbers
# Check what's capturing your keys
xev  # For X11
wev  # For Wayland

# Monitor input events
sudo evtest
```

---

## Quick Reference

### Command Cheat Sheet

```bash
# keyd user service management
systemctl --user status keyd.service      # Check status
systemctl --user restart keyd.service     # Restart service
systemctl --user enable keyd.service      # Enable on login
systemctl --user disable keyd.service     # Disable on login
journalctl --user -u keyd.service -f      # View logs
keyd monitor                              # Monitor key events

# niri management
niri msg action reload-config             # Reload config
niri msg version                          # Check version
niri msg action quit                      # Quit niri

# Config file locations
~/.config/keyd/default.conf               # keyd config
~/.config/systemd/user/keyd.service       # keyd service
~/.config/niri/config.kdl                 # niri config
```

### Keyboard Shortcuts Quick Reference

#### 🚀 Launch & System (Super/Mod)

| Shortcut | Action |
|----------|--------|
| `Mod + Return` | Terminal |
| `Mod + D` | App launcher |
| `Mod + E` | File manager |
| `Mod + B` | Browser |
| `Mod + L` | Lock screen |
| `Mod + Shift + 3` | Screenshot (full) |
| `Mod + Shift + 4` | Screenshot (area) |
| `Mod + Shift + 5` | Screenshot (window) |
| `Mod + Shift + V` | Clipboard history |
| `Mod + Ctrl + Space` | Emoji picker |

#### 🪟 Window Management (Hyper/Caps)

| Shortcut | Action |
|----------|--------|
| `Caps + H/J/K/L` | Focus window (left/down/up/right) |
| `Caps + Shift + H/J/K/L` | Move window |
| `Caps + Ctrl + H/J/K/L` | Resize window |
| `Caps + F` | Fullscreen |
| `Caps + M` | Maximize |
| `Caps + C` | Center window |
| `Caps + Q` | Close window |
| `Caps + R` | Reset window size |

#### 🔢 Workspaces (Hyper/Caps)

| Shortcut | Action |
|----------|--------|
| `Caps + 1-9` | Switch to workspace |
| `Caps + Shift + 1-9` | Move window to workspace |
| `Caps + [ / ]` | Previous/Next workspace |
| `Caps + Ctrl + [ / ]` | Move window to prev/next workspace |

#### ⌨️ Terminal (No Conflicts)

| Shortcut | Action |
|----------|--------|
| `Ctrl + B` | tmux prefix |
| `Ctrl + W` | vim window commands |
| `Mod + C/V` | Copy/Paste (terminal) |
| `Mod + T` | New tmux window |
| `Mod + W` | Close tmux window |
| `Mod + 1-5` | Switch tmux window |

---

## Conflict Resolution Matrix

| Key Combo | macOS | Linux (niri) | tmux | vim | Conflicts? |
|-----------|-------|--------------|------|-----|------------|
| Ctrl+H/J/K/L | Terminal | ❌ Never | Pane nav | Window nav | ✅ None |
| Caps+H/J/K/L | - | Window focus | - | - | ✅ None |
| Caps+Shift+H/J/K/L | - | Move window | - | - | ✅ None |
| Caps+Ctrl+H/J/K/L | - | Resize window | - | - | ✅ None |
| Mod+Tab | App switch | Window focus | - | - | ✅ Similar |
| Mod+1-9 | App/Tab | ❌ Not WM | Window | - | ✅ Terminal |
| Caps+1-9 | - | Workspace | - | - | ✅ None |
| Mod+C/V | Copy/Paste | Copy/Paste | Copy mode | Visual | ✅ Context-aware |
| Mod+Shift+3/4 | Screenshot | Screenshot | - | - | ✅ Identical |

---

## macOS Comparison & Muscle Memory Map

| Task | macOS | Linux (This Setup) |
|------|-------|-------------------|
| Launch app | Cmd+Space | Mod+D |
| Terminal | Cmd+N | Mod+Return |
| Close window | Cmd+W | Caps+Q or Mod+W (context) |
| Switch apps | Cmd+Tab | Mod+Tab |
| Full screen | Cmd+Ctrl+F | Caps+F |
| Lock screen | Cmd+Ctrl+Q | Mod+L |
| Screenshot (full) | Cmd+Shift+3 | Mod+Shift+3 |
| Screenshot (area) | Cmd+Shift+4 | Mod+Shift+4 |
| Copy/Paste | Cmd+C/V | Mod+C/V |
| Emoji picker | Cmd+Ctrl+Space | Mod+Ctrl+Space |
| Clipboard history | - | Mod+Shift+V |

---

## Learning Path

### Week 1: Core Navigation
- Focus on **Caps+H/J/K/L** for window focus
- Practice **Caps+1-9** for workspace switching
- Use **Mod+Return** for terminal
- Get comfortable with keyd service management

### Week 2: Window Management
- Add **Caps+Shift+H/J/K/L** for moving windows
- Practice **Caps+F** for fullscreen
- Learn **Caps+Q** for closing windows
- Test workspace movement with **Caps+Shift+1-9**

### Week 3: Advanced Features
- Add **Caps+Ctrl+H/J/K/L** for resizing
- Customize launcher shortcuts
- Try clipboard history and emoji picker
- Set up scratchpad terminal

### Week 4: Refinement
- Fine-tune any conflicts
- Add application-specific shortcuts
- Customize window rules
- Integrate with dotfile management (chezmoi/Ansible)

---

## Final Setup Checklist

```bash
# 1. Install packages
sudo pacman -S keyd niri rofi-wayland grimblast cliphist wl-clipboard playerctl brightnessctl mako alacritty tmux

# 2. Add user to input group (one-time sudo)
sudo usermod -aG input $USER

# 3. Create config directories
mkdir -p ~/.config/{keyd,niri,systemd/user,alacritty,mako}
mkdir -p ~/bin

# 4. Copy configurations (use this guide or your dotfiles)
# - ~/.config/keyd/default.conf
# - ~/.config/systemd/user/keyd.service
# - ~/.config/niri/config.kdl
# - ~/.config/alacritty/alacritty.toml
# - ~/.tmux.conf

# 5. Enable and start keyd user service
systemctl --user daemon-reload
systemctl --user enable --now keyd.service

# 6. Log out and back in (for input group to take effect)

# 7. Test keyd
keyd monitor
# Press Caps+H, should show Mod3+H and left arrow

# 8. Start niri and test bindings
# Try Caps+H/J/K/L for window navigation
# Try Mod+Return for terminal

# 9. Optional: Add to dotfile management
chezmoi add ~/.config/keyd/default.conf
chezmoi add ~/.config/niri/config.kdl
# or use Ansible playbook

# 10. Enjoy your new keybinding setup! 🎉
```

---

## Notes & Tips

- **Hyper key (Caps Lock)** is your power key - almost nothing conflicts with Mod3
- **Super (Mod)** mirrors macOS Command key - familiar muscle memory
- **Ctrl** is sacred - reserved exclusively for terminal apps
- **User service** means no sudo needed for config changes
- Config files are user-owned and perfect for version control
- Changes to keyd config require service restart: `systemctl --user restart keyd.service`
- Changes to niri config: `niri msg action reload-config`

This setup gives you:
- ✅ Consistent muscle memory between Mac and Linux
- ✅ Zero conflicts with tmux/vim
- ✅ Ergonomic (hands stay on home row)
- ✅ Scalable (easy to add more shortcuts)
- ✅ Professional (follows best practices)
- ✅ Dotfile-friendly (no root permissions needed)
- ✅ User-specific (runs as user service)

Happy tiling! 🚀
