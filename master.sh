#!/bin/bash

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


sudo apt-get install -y conntrack || true

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

# ---------- Configure Containerd
echo "-------------Configuring Containerd-------------"
if [ -f /etc/containerd/config.toml ]; then
        sudo rm /etc/containerd/config.toml
fi

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl restart containerd

# Verify containerd is running
echo "Verifying containerd is running..."
if sudo systemctl is-active --quiet containerd; then
    echo "Containerd is running successfully!"
else
    echo "ERROR: Containerd failed to start"
    sudo systemctl status containerd
    exit 1
fi

# Verify containerd socket
if [ -S /var/run/containerd/containerd.sock ]; then
    echo "Containerd socket is available"
else
    echo "ERROR: Containerd socket not found"
    exit 1
fi

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

# Enable kubelet service (will start after kubeadm init)
sudo systemctl enable kubelet
sudo hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/local-hostname)

# ---------- Master Node (Control-plane) Initialization
echo "-------------Initializing Kubernetes Control Plane-------------"

# Get the node's IP address
USER_IP=$(hostname -I | awk '{print $1}')
echo "Using IP address: $USER_IP"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
# Pull kubeadm images
echo "Pulling kubeadm images..."
if ! sudo kubeadm config images pull; then
    echo "ERROR: Failed to pull kubeadm images"
    echo "Checking containerd status..."
    sudo systemctl status containerd --no-pager
    exit 1
fi

# Create kubeadm configuration file with cloud provider support
echo "Creating kubeadm-config.yaml..."
cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: $(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
  kubeletExtraArgs:
    cloud-provider: external
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ec2k8s
kubernetesVersion: v1.31.0
networking:
  podSubnet: 10.32.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  certSANs:
  - 127.0.0.1
  - "$PUBLIC_IP"
  - "$USER_IP"
  extraArgs:
    bind-address: "0.0.0.0"
    cloud-provider: external
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
    cloud-provider: external
EOF


echo "kubeadm-config.yaml created with cloud provider support"
cat /tmp/kubeadm-config.yaml

# Initialize kubeadm with retry logic using config file
echo "Running kubeadm init with config file..."
KUBEADM_ATTEMPTS=0
MAX_KUBEADM_ATTEMPTS=2
until sudo kubeadm init --config /tmp/kubeadm-config.yaml ; do
  KUBEADM_ATTEMPTS=$((KUBEADM_ATTEMPTS + 1))
  if [ $KUBEADM_ATTEMPTS -ge $MAX_KUBEADM_ATTEMPTS ]; then
    echo "ERROR: kubeadm init failed after $MAX_KUBEADM_ATTEMPTS attempts"
    echo "Checking system status..."
    sudo systemctl status containerd --no-pager
    sudo systemctl status kubelet --no-pager
    exit 1
  fi
  echo "kubeadm init failed, retrying... (attempt $KUBEADM_ATTEMPTS/$MAX_KUBEADM_ATTEMPTS)"
  sudo kubeadm reset -f
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

# ---------- Creating join config file and publishing to SSM Parameter Store
echo "-------------Creating kubeadm join configuration with cloud provider support-------------"

# Generate join command to extract components
JOIN_CMD=$(sudo kubeadm token create --print-join-command)
echo "Join command: $JOIN_CMD"

# Extract token, API server endpoint, and CA cert hash from join command
TOKEN=$(echo "$JOIN_CMD" | grep -oP '(?<=--token )[^ ]+')
API_SERVER=$(echo "$JOIN_CMD" | grep -oP '(?<=kubeadm join )[^ ]+')
CA_CERT_HASH=$(echo "$JOIN_CMD" | grep -oP '(?<=--discovery-token-ca-cert-hash )[^ ]+')

echo "Token: $TOKEN"
echo "API Server: $API_SERVER"
echo "CA Cert Hash: $CA_CERT_HASH"

# Create kubeadm join configuration file with cloud provider support
cat <<EOF > /home/ubuntu/kubeadm-join-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: $TOKEN
    apiServerEndpoint: $API_SERVER
    caCertHashes:
    - $CA_CERT_HASH
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
EOF

echo "kubeadm-join-config.yaml created with cloud provider support:"
cat /home/ubuntu/kubeadm-join-config.yaml

# Set proper permissions
sudo chmod 644 /home/ubuntu/kubeadm-join-config.yaml
sudo chown ubuntu:ubuntu /home/ubuntu/kubeadm-join-config.yaml

# Save legacy join command for backward compatibility
echo "$JOIN_CMD" | sudo tee /home/ubuntu/join-command.sh >/dev/null
sudo chmod 644 /home/ubuntu/join-command.sh
sudo chown ubuntu:ubuntu /home/ubuntu/join-command.sh

# Publish join config to SSM Parameter Store
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
JOIN_CONFIG=$(cat /home/ubuntu/kubeadm-join-config.yaml)
aws ssm put-parameter --name "$SSM_PARAM_NAME" --value "$JOIN_CONFIG" --type "String" --overwrite --region "$REGION"

echo "Join configuration saved to SSM Parameter Store: $SSM_PARAM_NAME"
echo "--------- Master node initialization complete ---------"
