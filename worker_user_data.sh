#!/bin/bash
set -euo pipefail

# 1) Basic setup
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https curl ca-certificates gpg jq awscli

# 2) Set hostname (optional: suffix with short-uuid)
HNAME="k8s-worker-$(head -c8 /proc/sys/kernel/random/uuid)"
hostnamectl set-hostname "$HNAME"

# 3) Disable swap
swapoff -a || true
sed -i '/ swap / s/^.*/# &/g' /etc/fstab || true

# 4) Install containerd
cd /tmp
wget -q https://github.com/containerd/containerd/releases/download/v1.7.4/containerd-1.7.4-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local containerd-1.7.4-linux-amd64.tar.gz
wget -q https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/local/lib/systemd/system
mv containerd.service /usr/local/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd

# Generate containerd config
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
# Ensure containerd uses systemd cgroups to match kubelet default
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# 5) Install runc
wget -q https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# 6) Install CNI plugins
wget -q https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.2.0.tgz

# 7) Install crictl
CRICTL_VER="v1.31.0"
wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VER/crictl-$CRICTL_VER-linux-amd64.tar.gz
sudo tar zxvf crictl-$CRICTL_VER-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VER-linux-amd64.tar.gz


cat <<EOF | tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# 8) Kernel settings
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# 9) Install kubeadm, kubelet, kubectl
apt-get update -y && apt-get install -y apt-transport-https curl ca-certificates gpg
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF | tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /
EOF
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# 10) Fetch join command from SSM and join cluster
# Discover region from IMDS
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
PARAM_NAME="${ssm_join_param_name}"

# Try to retrieve join command from SSM with retries (up to ~10 minutes)
ATTEMPTS=0
MAX_ATTEMPTS=60
SLEEP_SECONDS=10
JOIN_CMD=""
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  set +e
  JOIN_CMD=$(aws ssm get-parameter --name "$PARAM_NAME" --with-decryption --query Parameter.Value --output text --region "$REGION" 2>/dev/null)
  STATUS=$?
  set -e
  if [ $STATUS -eq 0 ] && [ -n "$JOIN_CMD" ] && [[ "$JOIN_CMD" == kubeadm* ]]; then
    echo "Obtained join command from SSM."
    break
  fi
  ATTEMPTS=$((ATTEMPTS+1))
  echo "Waiting for join command in SSM ($ATTEMPTS/$MAX_ATTEMPTS)..."
  sleep $SLEEP_SECONDS
done

if [ -z "$JOIN_CMD" ] || [[ "$JOIN_CMD" != kubeadm* ]]; then
  echo "Failed to retrieve join command from SSM parameter: $PARAM_NAME" >&2
  exit 1
fi

# Ensure kubelet is enabled
systemctl enable kubelet

# Retry kubeadm join for up to ~5 minutes (30 x 10s)
ATTEMPTS=0
MAX_ATTEMPTS=30
SLEEP_SECONDS=10
while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  if bash -lc "$JOIN_CMD"; then
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
systemctl restart kubelet

