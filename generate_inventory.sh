#!/bin/bash
# Generate Ansible inventory with master as bastion

MASTER_IP=$1

cat > inventory.ini <<EOF
[master]
${MASTER_IP}

[workers]
# Workers will be added dynamically from ASG

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=./k8s
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# For workers in private subnet, use master as jump host
[workers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@${MASTER_IP} -i ./k8s"'
EOF

echo "Inventory generated with master IP: ${MASTER_IP}"
