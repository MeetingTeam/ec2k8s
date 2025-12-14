#!/bin/bash

# 1) Basic setup
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y apt-transport-https curl ca-certificates gpg jq awscli

# 2) Set hostname (optional: suffix with short-uuid)
sudo hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/local-hostname)


# 3) Disable swap
echo "Disabling swap..."
sudo swapoff -a || true
sudo sed -i.bak '/\bswap\b/ s/^/#/' /etc/fstab || true

# ---------- Configure prerequisites (kubernetes.io/docs/setup/production-environment/container-runtimes/)
echo "Configuring kernel modules and sysctl parameters..."
sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay || true
sudo modprobe br_netfilter || true

sudo cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
# Ensure Universe repo is enabled (conntrack is in universe on some Ubuntu images)
sudo apt-get update -y
sudo apt-get install -y software-properties-common || true
if ! grep -R "^deb .* universe" /etc/apt/sources.list /etc/apt/sources.list.d/* >/dev/null 2>&1; then
  sudo add-apt-repository -y universe || true
fi
sudo apt-get update -y
sudo apt-get install -y conntrack || true


# 4) Installation of CRI - CONTAINERD and Docker using Package
# Reference: https://docs.docker.com/engine/install/ubuntu/
echo "Installing Docker and Containerd via Package Manager..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
if sudo docker ps | grep -q 'CONTAINER ID'; then
  echo "Docker installed successfully!"
else
  echo "Docker installation failed"
  exit 1
fi

# 5) Edit the Containerd Config file /etc/containerd/config.toml
# By default this config file contains disabled CRI, so we need to enable it
echo "Configuring Containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# 6) Installing kubeadm, kubelet and kubectl
echo "Installing Kubernetes components (kubeadm, kubelet, kubectl)..."
sudo apt-get update
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "Kubernetes components installed successfully"

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 7) Fetch join command from SSM and join cluster
# Discover region from IMDS
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
PARAM_NAME="${ssm_join_param_name}"

# Try to retrieve join config from SSM with retries (up to ~10 minutes)
echo "Retrieving kubeadm join configuration from SSM Parameter Store..."
ATTEMPTS=0
MAX_ATTEMPTS=60
SLEEP_SECONDS=10
JOIN_CONFIG=""
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  set +e
  JOIN_CONFIG=$(aws ssm get-parameter --name "$PARAM_NAME" --with-decryption --query Parameter.Value --output text --region "$REGION" 2>/dev/null)
  STATUS=$?
  set -e
  if [ $STATUS -eq 0 ] && [ -n "$JOIN_CONFIG" ] && [[ "$JOIN_CONFIG" == *"apiVersion"* ]]; then
    echo "Obtained join configuration from SSM."
    break
  fi
  ATTEMPTS=$((ATTEMPTS+1))
  echo "Waiting for join configuration in SSM ($ATTEMPTS/$MAX_ATTEMPTS)..."
  sleep $SLEEP_SECONDS
done

if [ -z "$JOIN_CONFIG" ] || [[ "$JOIN_CONFIG" != *"apiVersion"* ]]; then
  echo "Failed to retrieve join configuration from SSM parameter: $PARAM_NAME" >&2
  exit 1
fi

# Save join configuration to file
echo "$JOIN_CONFIG" > /tmp/kubeadm-join-config.yaml
echo "kubeadm-join-config.yaml created:"
cat /tmp/kubeadm-join-config.yaml

# Ensure kubelet is enabled
sudo systemctl enable kubelet

# 8) Retry kubeadm join for up to ~5 minutes (30 x 10s)
echo "Joining Kubernetes cluster with config file..."
ATTEMPTS=0
MAX_ATTEMPTS=30
SLEEP_SECONDS=10
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  if sudo kubeadm join --config /tmp/kubeadm-join-config.yaml; then
    echo "kubeadm join succeeded"
    break
  fi
  ATTEMPTS=$((ATTEMPTS+1))
  echo "kubeadm join failed, retry $ATTEMPTS/$MAX_ATTEMPTS..."
  sleep $SLEEP_SECONDS
done

if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
  echo "kubeadm join failed after retries" >&2
  exit 1
fi

# Ensure kubelet running
sudo systemctl restart kubelet

echo "Worker node initialization complete"
