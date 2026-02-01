#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

echo "Running playbook..."
ansible-playbook local.yml --ask-become-pass "$@"
