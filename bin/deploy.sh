#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Docker-based Ansible deployment wrapper
# =============================================================================
#
# PURPOSE:
#   Runs ansible/local.yml inside a Docker container (no local Ansible needed).
#   The container SSHs into the target machine to apply configuration.
#
# PREREQUISITES:
#   Run ./bin/bootstrap.sh once to install Docker and enable SSH.
#   macOS: Also enable SSH agent forwarding in Docker Desktop
#          (Settings → Resources → SSH → Enable SSH agent forwarding)
#
# USAGE:
#   ./bin/deploy.sh [target] [ansible options]
#
#   target: hostname or IP to configure (default: localhost)
#
# EXAMPLES:
#   ./bin/deploy.sh                            # configure this machine
#   ./bin/deploy.sh 192.168.1.100             # configure a remote machine
#   ./bin/deploy.sh --tags base               # only run the base role
#   ./bin/deploy.sh --check --diff            # dry run, show diffs
#   ./bin/deploy.sh -e "install_nordvpn=false" # override a variable
#
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="dotfiles-ansible"
OS="$(uname)"

# =============================================================================
# Parse arguments
# First non-flag argument is the target; everything else passes to ansible
# =============================================================================
TARGET="localhost"
PASSTHROUGH=()

if [[ $# -gt 0 && "$1" != -* ]]; then
    TARGET="$1"
    shift
fi
PASSTHROUGH=("$@")

# =============================================================================
# Validate prerequisites
# =============================================================================
if ! command -v docker &>/dev/null; then
    echo "Error: Docker not found. Run ./bin/bootstrap.sh first."
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Error: Docker is not running."
    if [[ "$OS" == "Darwin" ]]; then
        echo "  Start it: open -a Docker"
    else
        echo "  Start it: sudo systemctl start docker"
    fi
    exit 1
fi

if [[ "$TARGET" == "localhost" ]]; then
    if [[ "$OS" == "Darwin" ]]; then
        if ! sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
            echo "Error: SSH (Remote Login) is not enabled."
            echo "  Enable it: sudo systemsetup -setremotelogin on"
            exit 1
        fi
    else
        if ! systemctl is-active --quiet sshd; then
            echo "Error: sshd is not running."
            echo "  Start it: sudo systemctl start sshd"
            exit 1
        fi
    fi
fi

# =============================================================================
# Resolve connection settings
#
# macOS: Docker Desktop runs in a VM so --network host is ignored.
#        The host machine is reachable via host.docker.internal instead.
# Linux: --network host makes 127.0.0.1 resolve to the actual host.
# =============================================================================
if [[ "$TARGET" == "localhost" ]]; then
    if [[ "$OS" == "Darwin" ]]; then
        ANSIBLE_HOST="host.docker.internal"
        NETWORK_FLAG=()
    else
        ANSIBLE_HOST="127.0.0.1"
        NETWORK_FLAG=(--network host)
    fi
else
    ANSIBLE_HOST="$TARGET"
    NETWORK_FLAG=()
fi

# =============================================================================
# SSH agent socket
#
# macOS: Docker Desktop exposes the host SSH agent at this fixed path inside
#        containers when SSH agent forwarding is enabled in Docker Desktop.
#        Works with system keychain and 1Password.
# Linux: Use SSH_AUTH_SOCK from the current session.
# =============================================================================
if [[ "$OS" == "Darwin" ]]; then
    SSH_SOCK="/run/host-services/ssh-auth.sock"
else
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        echo "Error: SSH agent is not running."
        echo "  Start it: eval \$(ssh-agent) && ssh-add"
        exit 1
    fi
    SSH_SOCK="$SSH_AUTH_SOCK"
fi

# =============================================================================
# Generate temporary inventory
#
# Always named "localhost" so it matches `hosts: localhost` in local.yml.
# ansible_connection=ssh overrides `connection: local` in the playbook.
# ansible_host sets the actual IP/hostname the container connects to.
# =============================================================================
INVENTORY=$(mktemp /tmp/ansible-inventory.XXXXXX)
trap "rm -f $INVENTORY" EXIT

cat > "$INVENTORY" <<EOF
localhost ansible_connection=ssh ansible_user=${USER} ansible_host=${ANSIBLE_HOST}
EOF

# =============================================================================
# Build Docker image
# =============================================================================
echo "Building Ansible container..."
docker build -t "$IMAGE_NAME" "$REPO_ROOT/ansible" -q

# =============================================================================
# Run
# =============================================================================
echo "Target: ${TARGET} → ${ANSIBLE_HOST} (user: ${USER})"

DOCKER_ARGS=(--rm -it)
[[ ${#NETWORK_FLAG[@]} -gt 0 ]] && DOCKER_ARGS+=("${NETWORK_FLAG[@]}")
DOCKER_ARGS+=(
    -v "${REPO_ROOT}/ansible:/workspace"
    -v "${INVENTORY}:/inventory.ini:ro"
    -v "${SSH_SOCK}:/ssh-agent.sock"
    -e "SSH_AUTH_SOCK=/ssh-agent.sock"
)

ANSIBLE_ARGS=(-i /inventory.ini local.yml --ask-become-pass)
[[ ${#PASSTHROUGH[@]} -gt 0 ]] && ANSIBLE_ARGS+=("${PASSTHROUGH[@]}")

docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" \
    /opt/venv/bin/ansible-playbook "${ANSIBLE_ARGS[@]}"
