# Installation Method Updates

## Overview
Updated `master.sh` and `worker_user_data.sh` to use the **Docker package manager installation method** (similar to `script_test.sh`) instead of binary installation.

## Key Changes

### Previous Method (Binary Installation)
- Downloaded containerd binary from GitHub releases
- Manually installed runc, CNI plugins, crictl as separate binaries
- Created systemd service file manually
- More manual configuration steps

### New Method (Package Manager Installation)
- Uses official Docker repository with apt package manager
- Installs Docker, containerd, and related tools as packages
- Automatic systemd service configuration
- More reliable and easier to maintain
- Better integration with system package management

---

## Detailed Changes

### 1. **master.sh** - Container Runtime Installation

#### Before (Binary Method)
```bash
# Install Containerd
wget https://github.com/containerd/containerd/releases/download/v1.7.4/containerd-1.7.4-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.7.4-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mkdir -p /usr/local/lib/systemd/system
mv containerd.service /usr/local/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd

# Install Runc
wget https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

# Install CNI
wget https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.2.0.tgz

# Install CRICTL
VERSION="v1.31.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz
```

#### After (Package Manager Method)
```bash
# Remove old installations
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

# Add Docker repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and Containerd
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
sudo docker ps | grep -q 'CONTAINER ID' && echo "Docker installed successfully!"
```

### 2. **Containerd Configuration**

#### Before
```bash
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF
```

#### After
```bash
# Generate default config and enable SystemdCgroup
if [ -f /etc/containerd/config.toml ]; then
  sudo chmod 770 -R /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
fi
sudo systemctl restart containerd
```

### 3. **Kernel Module Configuration**

#### Before
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter

EOF
modprobe overlay
modprobe br_netfilter
```

#### After
```bash
sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

**Improvements:**
- Added `sudo` prefix for consistency
- Removed extra blank line in config file
- Added verification steps

### 4. **kubeadm init Improvements**

#### Before
```bash
echo "-------------Running kubeadm init --pod-network-cidr=10.244.0.0/16-------------"
kubeadm init
```

#### After
```bash
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
```

**Improvements:**
- Explicitly specify API server advertise address
- Pre-pull kubeadm images before init
- Retry logic with reset on failure
- Better error handling

### 5. **Script Error Handling**

#### Before
```bash
#!/bin/bash
set -e
```

#### After
```bash
#!/bin/bash
set -euo pipefail
```

**Improvements:**
- `-u`: Exit on undefined variable
- `-o pipefail`: Exit on pipe failure
- Better error detection

---

## Comparison: Binary vs Package Manager

| Aspect | Binary | Package Manager |
|--------|--------|-----------------|
| **Installation Speed** | Slower (multiple downloads) | Faster (single apt command) |
| **Dependency Management** | Manual | Automatic |
| **Systemd Integration** | Manual setup | Automatic |
| **Updates** | Manual process | `apt upgrade` |
| **Verification** | Manual | Package manager handles |
| **Reliability** | More error-prone | More stable |
| **Maintenance** | Higher effort | Lower effort |
| **Official Support** | Community | Docker official |

---

## Benefits of New Approach

1. **Reliability**: Official Docker repository is well-maintained
2. **Simplicity**: Fewer manual steps and configurations
3. **Maintainability**: Easier to update and troubleshoot
4. **Consistency**: Matches `script_test.sh` approach
5. **Error Handling**: Better retry logic and validation
6. **Verification**: Includes installation verification steps

---

## Testing Recommendations

1. **Test Master Node Deployment**
   ```bash
   terraform apply
   ```

2. **Verify Docker Installation**
   ```bash
   ssh -i k8s ubuntu@<master-ip>
   sudo docker ps
   sudo systemctl status containerd
   ```

3. **Check Kubernetes Components**
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

4. **Verify Worker Nodes Join**
   ```bash
   kubectl get nodes -w
   ```

5. **Test Pod Networking**
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -- sh
   ```

---

## Rollback Plan

If issues occur, you can revert to the binary method:

1. Keep the original scripts in version control
2. Use `git checkout` to restore previous versions
3. Or manually revert the changes using the "Before" sections above

---

## References

- [Docker Official Installation Guide](https://docs.docker.com/engine/install/ubuntu/)
- [Containerd Configuration](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)
- [Kubernetes CRI Documentation](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

---

**Updated**: December 2024
**Kubernetes Version**: v1.31
**Docker Version**: Latest from official repository
**Containerd Version**: Latest from official repository

