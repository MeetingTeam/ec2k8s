#!/bin/bash
set -euo pipefail

# Set hostname
echo "-------------Setting hostname-------------"
# Arg1: hostname, Arg2: SSM parameter name for join command (optional)
HOSTNAME=${1:-k8s-master}
SSM_PARAM_NAME=${2:-/k8s/join-command}
sudo hostnamectl set-hostname "$HOSTNAME"

# Disable swap
echo "-------------Disabling swap-------------"
sudo swapoff -a
# Comment swap entry in fstab file
sudo sed -i.bak '/\bswap\b/ s/^/#/' /etc/fstab

# ---------- Configure prerequisites (kubernetes.io/docs/setup/production-environment/container-runtimes/)
echo "-------------Configuring kernel modules and sysctl parameters-------------"
sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
sudo apt-get install -y conntrack-tools

# Verify kernel modules are loaded
echo "Verifying kernel modules..."
lsmod | grep br_netfilter
lsmod | grep overlay

# Verify sysctl parameters
echo "Verifying sysctl parameters..."
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# ---------- Installation of CRI - CONTAINERD and Docker using Package
# Reference: https://docs.docker.com/engine/install/ubuntu/
echo "-------------Installing Docker and Containerd via Package Manager-------------"
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
echo "Verifying Docker installation..."
if sudo docker ps | grep -q 'CONTAINER ID'; then
  echo "Docker installed successfully!"
else
  echo "Docker installation failed"
  exit 1
fi

# ---------- Edit the Containerd Config file /etc/containerd/config.toml
# By default this config file contains disabled CRI, so we need to enable it
echo "-------------Configuring Containerd-------------"
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# ---------- Installing kubeadm, kubelet and kubectl
echo "-------------Installing Kubernetes components (kubeadm, kubelet, kubectl)-------------"
sudo apt-get update
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl awscli jq
sudo apt-mark hold kubelet kubeadm kubectl

echo "Installing of Kubernetes components is successful"

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# ---------- Master Node (Control-plane) Initialization
echo "-------------Initializing Kubernetes Control Plane-------------"

# Get the node's IP address
USER_IP=$(hostname -I | awk '{print $1}')
echo "Using IP address: $USER_IP"

# Pull kubeadm images
echo "Pulling kubeadm images..."
sudo kubeadm config images pull

# Initialize kubeadm with retry logic
echo "Running kubeadm init..."
KUBEADM_ATTEMPTS=0
MAX_KUBEADM_ATTEMPTS=3
until sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address="$USER_IP" --ignore-preflight-errors=all; do
  KUBEADM_ATTEMPTS=$((KUBEADM_ATTEMPTS + 1))
  if [ $KUBEADM_ATTEMPTS -ge $MAX_KUBEADM_ATTEMPTS ]; then
    echo "kubeadm init failed after $MAX_KUBEADM_ATTEMPTS attempts"
    exit 1
  fi
  echo "kubeadm init failed, retrying... (attempt $KUBEADM_ATTEMPTS/$MAX_KUBEADM_ATTEMPTS)"
  sudo kubeadm reset -f || true
  sudo systemctl daemon-reload
  sudo systemctl restart kubelet
  sleep 10
done

# ---------- Setup kubeconfig for root user
echo "-------------Setting up kubeconfig for root user-------------"
sudo mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

# Setup kubeconfig for ubuntu user
echo "-------------Setting up kubeconfig for ubuntu user-------------"
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Export kubeconfig
export KUBECONFIG=/etc/kubernetes/admin.conf

# ---------- Wait for API server to be ready
echo "-------------Waiting for Kubernetes API server to be ready-------------"
ATTEMPTS=0
MAX_ATTEMPTS=60
until kubectl get --raw='/readyz?verbose' &> /dev/null; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo "API server failed to become ready after $MAX_ATTEMPTS attempts"
    exit 1
  fi
  echo "Waiting for Kubernetes API server... (attempt $ATTEMPTS/$MAX_ATTEMPTS)"
  sleep 10
done
echo "API server is ready!"

# ---------- Installing Weave Net (Pod Network)
echo "-------------Deploying Weave Net Pod Networking-------------"
DEPLOY_ATTEMPTS=0
MAX_DEPLOY_ATTEMPTS=5
until kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml; do
  DEPLOY_ATTEMPTS=$((DEPLOY_ATTEMPTS + 1))
  if [ $DEPLOY_ATTEMPTS -ge $MAX_DEPLOY_ATTEMPTS ]; then
    echo "Failed to deploy Weave network after $MAX_DEPLOY_ATTEMPTS attempts"
    exit 1
  fi
  echo "Retrying Weave deployment... (attempt $DEPLOY_ATTEMPTS/$MAX_DEPLOY_ATTEMPTS)"
  sleep 15
done
echo "Weave network deployed successfully!"

# Set Weave Net IP range to avoid overlap with VPC (10.0.0.0/16)
echo "Configuring Weave Net IP allocation range..."
kubectl -n kube-system set env daemonset/weave-net IPALLOC_RANGE=10.244.0.0/16
kubectl -n kube-system rollout status daemonset/weave-net --timeout=2m || true

# ---------- Verify cluster status
echo "-------------Verifying cluster status-------------"
kubectl get nodes
echo "Control-Plane is Ready!"

# ---------- Installing Helm 3
echo "-------------Installing Helm 3-------------"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# Verify helm for both root and ubuntu user environments
helm version || true
su - ubuntu -c "helm version" || true

# ---------- Creating join command and publishing to SSM Parameter Store
echo "-------------Creating join command and publishing to SSM Parameter Store-------------"
JOIN_CMD=$(sudo kubeadm token create --print-join-command)

# Save locally for troubleshooting and Ansible fetch
echo "$JOIN_CMD" | tee /home/ubuntu/join-command.sh >/dev/null
chmod +x /home/ubuntu/join-command.sh

# Publish to SSM Parameter Store so ASG workers can retrieve it
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
aws ssm put-parameter --name "$SSM_PARAM_NAME" --value "$JOIN_CMD" --type "String" --overwrite --region "$REGION"

echo "Join command saved to SSM Parameter Store: $SSM_PARAM_NAME"
echo "Join command: $JOIN_CMD"
echo "--------- Master node initialization complete ---------"
