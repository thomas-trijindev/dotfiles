#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

echo "Running playbook..."
if [ -f group_vars/vault.yml ]; then
    ansible-playbook local.yml --ask-vault-pass "$@"
else
    ansible-playbook local.yml "$@"
fi
