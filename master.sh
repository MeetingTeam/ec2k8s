#!/bin/bash
set -e

# Set hostname
echo "-------------Setting hostname-------------"
# Arg1: hostname, Arg2: SSM parameter name for join command (optional)
hostnamectl set-hostname $1
SSM_PARAM_NAME=${2:-/k8s/join-command}

# Disable swap
echo "-------------Disabling swap-------------"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install Containerd
echo "-------------Installing Containerd-------------"
wget https://github.com/containerd/containerd/releases/download/v1.7.4/containerd-1.7.4-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.4-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/local/lib/systemd/system
mv containerd.service /usr/local/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd

# Install Runc
echo "-------------Installing Runc-------------"
wget https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# Install CNI
echo "-------------Installing CNI-------------"
wget https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.2.0.tgz

# Install CRICTL
echo "-------------Installing CRICTL-------------"
VERSION="v1.28.0" # check latest version in /releases page
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz

cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# Forwarding IPv4 and letting iptables see bridged traffic
echo "-------------Setting IPTables-------------"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter

EOF
modprobe overlay
modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
modprobe br_netfilter
sysctl -p /etc/sysctl.conf

# Install kubectl, kubelet and kubeadm
echo "-------------Installing Kubectl, Kubelet and Kubeadm-------------"
apt-get update && sudo apt-get install -y apt-transport-https curl ca-certificates gpg awscli jq

# Add Kubernetes repository (new method)
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /
EOF

apt update -y
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "-------------Printing Kubeadm version-------------"
kubeadm version

echo "-------------Pulling Kueadm Images -------------"
kubeadm config images pull

echo "-------------Running kubeadm init-------------"
kubeadm init

echo "-------------Copying Kubeconfig-------------"
mkdir -p /root/.kube
cp -iv /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

# Copy kubeconfig for ubuntu user
mkdir -p /home/ubuntu/.kube
cp -iv /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

echo "-------------Exporting Kubeconfig-------------"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "-------------Waiting for API server to be ready-------------"
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

# Wait additional time for all control plane components
echo "-------------Waiting for control plane components-------------"
sleep 20

echo "-------------Deploying Weavenet Pod Networking-------------"
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

echo "-------------Creating join command and publishing-------------"
JOIN_CMD=$(kubeadm token create --print-join-command)
# Save locally for troubleshooting and Ansible fetch
echo "$JOIN_CMD" | tee /home/ubuntu/join-command.sh >/dev/null
chmod +x /home/ubuntu/join-command.sh

# Publish to SSM Parameter Store so ASG workers can retrieve it
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
aws ssm put-parameter --name "$SSM_PARAM_NAME" --value "$JOIN_CMD" --type "String" --overwrite --region "$REGION"
 