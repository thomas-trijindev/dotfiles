#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh - Cold-start prerequisites installer
# =============================================================================
#
# PURPOSE:
#   Installs the minimum requirements to run deploy.sh on a fresh machine.
#   Only needs to be run once per machine.
#
# WHAT IT INSTALLS:
#   macOS  : Xcode CLT → Homebrew → Docker Desktop → enables SSH
#   Fedora : Docker → enables sshd
#
# AFTER THIS RUNS:
#   macOS only: Enable SSH agent forwarding in Docker Desktop
#               Settings → Resources → SSH → Enable SSH agent forwarding
#   Then run: ./bin/deploy.sh
#
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[bootstrap]${NC} $*"; }
warn()  { echo -e "${YELLOW}[bootstrap]${NC} $*"; }
error() { echo -e "${RED}[bootstrap]${NC} $*" >&2; exit 1; }

OS="$(uname)"

# =============================================================================
# macOS
# =============================================================================
if [[ "$OS" == "Darwin" ]]; then

    # Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install
        warn "Complete the Xcode CLT installation popup, then re-run this script."
        exit 0
    else
        info "Xcode CLT: ok"
    fi

    # Homebrew
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Apple Silicon: add brew to PATH for this session
        [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        info "Homebrew: ok"
    fi

    # Docker Desktop
    if ! command -v docker &>/dev/null; then
        info "Installing Docker Desktop..."
        brew install --cask docker
    else
        info "Docker: ok"
    fi

    # Start Docker Desktop if not running
    if ! docker info &>/dev/null 2>&1; then
        info "Starting Docker Desktop..."
        open -a Docker
        echo -n "  Waiting for Docker"
        until docker info &>/dev/null 2>&1; do
            echo -n "."
            sleep 2
        done
        echo
    fi

    # SSH (Remote Login)
    if ! sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
        info "Enabling SSH (Remote Login)..."
        sudo systemsetup -setremotelogin on
    else
        info "SSH (Remote Login): ok"
    fi

# =============================================================================
# Fedora
# =============================================================================
elif [[ "$OS" == "Linux" ]]; then

    # Docker (via official Docker CE repository)
    if ! command -v docker &>/dev/null; then
        info "Installing Docker..."
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    else
        info "Docker: ok"
    fi

    # Docker service
    if ! systemctl is-active --quiet docker; then
        info "Enabling Docker service..."
        sudo systemctl enable --now docker
    else
        info "Docker service: ok"
    fi

    # Docker group membership (avoid needing sudo for docker commands)
    if ! groups "$USER" | grep -q docker; then
        info "Adding $USER to docker group..."
        sudo usermod -aG docker "$USER"
        warn "Re-login required for docker group. Run: newgrp docker"
    else
        info "Docker group: ok"
    fi

    # sshd
    if ! systemctl is-active --quiet sshd; then
        info "Enabling sshd..."
        sudo systemctl enable --now sshd
    else
        info "sshd: ok"
    fi

else
    error "Unsupported OS: $OS. Supported: macOS, Fedora."
fi

# =============================================================================
# SSH key in authorized_keys (required for container → host SSH)
# =============================================================================
SSH_PUB=$(find ~/.ssh -maxdepth 1 -name '*.pub' 2>/dev/null | head -1 || true)

if [[ -n "$SSH_PUB" ]]; then
    KEY_CONTENT=$(cat "$SSH_PUB")
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
    if ! grep -qF "$KEY_CONTENT" ~/.ssh/authorized_keys 2>/dev/null; then
        echo "$KEY_CONTENT" >> ~/.ssh/authorized_keys
        info "Added $(basename "$SSH_PUB") to authorized_keys"
    else
        info "authorized_keys: ok"
    fi
else
    warn "No SSH public key found in ~/.ssh/"
    warn "Create one with: ssh-keygen -t ed25519"
    warn "Or export your public key from 1Password and place it in ~/.ssh/"
    warn "Then add it to ~/.ssh/authorized_keys before running deploy.sh"
fi

echo
info "Bootstrap complete."
if [[ "$OS" == "Darwin" ]]; then
    echo
    echo "  Next step (macOS only):"
    echo "  Enable SSH agent forwarding in Docker Desktop:"
    echo "    Settings → Resources → SSH → Enable SSH agent forwarding"
    echo
fi
echo "  Then run: ./bin/deploy.sh"
