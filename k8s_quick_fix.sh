#!/bin/bash

# Kubernetes Quick Fix Script
# Run this on the master node to diagnose and attempt recovery

set -e

echo "=========================================="
echo "Kubernetes Cluster Quick Diagnostic"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# 1. Check kubelet status
echo -e "\n${YELLOW}1. Checking kubelet status...${NC}"
sudo systemctl is-active kubelet > /dev/null 2>&1
print_status $? "Kubelet service"

# 2. Check container runtime
echo -e "\n${YELLOW}2. Checking container runtime...${NC}"
sudo crictl ps > /dev/null 2>&1
print_status $? "Container runtime (containerd)"

# 3. Check etcd
echo -e "\n${YELLOW}3. Checking etcd...${NC}"
ETCD_CONTAINER=$(sudo crictl ps -a | grep etcd | awk '{print $1}' | head -1)
if [ -n "$ETCD_CONTAINER" ]; then
    echo "etcd container ID: $ETCD_CONTAINER"
    ETCD_STATUS=$(sudo crictl ps -a | grep etcd | awk '{print $3}')
    echo "etcd status: $ETCD_STATUS"
    if [ "$ETCD_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓ etcd is running${NC}"
    else
        echo -e "${RED}✗ etcd is not running - showing logs:${NC}"
        sudo crictl logs $ETCD_CONTAINER | tail -30
    fi
else
    echo -e "${RED}✗ etcd container not found${NC}"
fi

# 4. Check API server
echo -e "\n${YELLOW}4. Checking kube-apiserver...${NC}"
APISERVER_CONTAINER=$(sudo crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1)
if [ -n "$APISERVER_CONTAINER" ]; then
    echo "API server container ID: $APISERVER_CONTAINER"
    APISERVER_STATUS=$(sudo crictl ps -a | grep kube-apiserver | awk '{print $3}')
    echo "API server status: $APISERVER_STATUS"
    if [ "$APISERVER_STATUS" = "Running" ]; then
        echo -e "${GREEN}✓ API server is running${NC}"
    else
        echo -e "${RED}✗ API server is not running - showing logs:${NC}"
        sudo crictl logs $APISERVER_CONTAINER | tail -30
    fi
else
    echo -e "${RED}✗ API server container not found${NC}"
fi

# 5. Check port 6443
echo -e "\n${YELLOW}5. Checking if port 6443 is listening...${NC}"
sudo ss -tlnp | grep 6443 > /dev/null 2>&1
print_status $? "Port 6443 listening"

# 6. Check disk space
echo -e "\n${YELLOW}6. Checking disk space...${NC}"
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
echo "Root disk usage: ${DISK_USAGE}%"
if [ "$DISK_USAGE" -gt 90 ]; then
    echo -e "${RED}✗ Disk usage is critical (>90%)${NC}"
elif [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "${YELLOW}⚠ Disk usage is high (>80%)${NC}"
else
    echo -e "${GREEN}✓ Disk usage is normal${NC}"
fi

# 7. Check certificates
echo -e "\n${YELLOW}7. Checking certificate expiration...${NC}"
if command -v kubeadm &> /dev/null; then
    sudo kubeadm certs check-expiration 2>/dev/null | grep -E "CERTIFICATE|apiserver" || echo "Could not check certificates"
else
    echo "kubeadm not found"
fi

# 8. Check kubelet logs for errors
echo -e "\n${YELLOW}8. Recent kubelet errors...${NC}"
sudo journalctl -u kubelet -n 20 --no-pager | grep -i error || echo "No recent errors found"

# 9. Suggest fixes
echo -e "\n${YELLOW}========== RECOMMENDATIONS ==========${NC}"

if [ -z "$ETCD_CONTAINER" ] || [ "$ETCD_STATUS" != "Running" ]; then
    echo -e "${RED}ACTION: etcd is not running${NC}"
    echo "  1. Check etcd logs: sudo crictl logs <container_id>"
    echo "  2. Check /var/lib/etcd/ permissions: ls -la /var/lib/etcd/"
    echo "  3. Restart kubelet: sudo systemctl restart kubelet"
    echo "  4. If corrupted, reset: sudo rm -rf /var/lib/etcd/*"
fi

if [ -z "$APISERVER_CONTAINER" ] || [ "$APISERVER_STATUS" != "Running" ]; then
    echo -e "${RED}ACTION: API server is not running${NC}"
    echo "  1. Check API server logs: sudo crictl logs <container_id>"
    echo "  2. Verify etcd is running first"
    echo "  3. Restart kubelet: sudo systemctl restart kubelet"
fi

if [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "${RED}ACTION: Disk space is low${NC}"
    echo "  1. Clean up old containers: sudo crictl rm -f \$(sudo crictl ps -a -q)"
    echo "  2. Clean up images: sudo crictl rmi --prune"
    echo "  3. Check /var/log/ size: du -sh /var/log/"
fi

echo -e "\n${YELLOW}========== RECOVERY STEPS ==========${NC}"
echo "If the above checks fail, try these steps in order:"
echo ""
echo "Step 1: Restart kubelet"
echo "  sudo systemctl restart kubelet"
echo "  sleep 30"
echo "  kubectl get nodes"
echo ""
echo "Step 2: If still failing, check kubelet logs"
echo "  sudo journalctl -u kubelet -f"
echo ""
echo "Step 3: If etcd is corrupted, reset it"
echo "  sudo systemctl stop kubelet"
echo "  sudo rm -rf /var/lib/etcd/*"
echo "  sudo systemctl start kubelet"
echo "  sleep 60"
echo ""
echo "Step 4: If all else fails, full reset"
echo "  sudo kubeadm reset -f"
echo "  sudo kubeadm init --apiserver-advertise-address=10.0.1.194 --pod-network-cidr=10.244.0.0/16"
echo ""

