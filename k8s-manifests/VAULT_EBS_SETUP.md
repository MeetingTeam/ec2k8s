# Hướng dẫn cấu hình Vault với EBS CSI Driver

## Tổng quan
Tài liệu này hướng dẫn cách cấu hình Vault với AWS EBS CSI Driver để sử dụng persistent storage trên Kubernetes.

## Các thay đổi đã thực hiện

### 1. IAM Policy cho EBS CSI Driver
File `iam.tf` đã được cập nhật với IAM policy cần thiết cho EBS CSI Driver, bao gồm:
- Quyền tạo/xóa EBS volumes
- Quyền attach/detach volumes
- Quyền tạo/xóa snapshots
- Quyền modify volumes

Policy này được attach vào IAM role của worker nodes.

### 2. Manifest files

#### a. ebs-csi-driver.yaml
Manifest để cài đặt AWS EBS CSI Driver bao gồm:
- ServiceAccounts cho controller và node
- ClusterRoles và ClusterRoleBindings
- Deployment cho CSI Controller (2 replicas)
- DaemonSet cho CSI Node
- CSIDriver resource

#### b. ebs-storageclass.yaml
Định nghĩa 2 StorageClasses:
- **ebs-sc**: Sử dụng gp3 volumes (khuyến nghị)
  - IOPS: 3000
  - Throughput: 125 MB/s
  - Encryption: enabled
- **ebs-gp2-csi**: Sử dụng gp2 volumes (legacy support)

#### c. vault-values.yaml
Cấu hình Helm values cho Vault:
- Storage sử dụng StorageClass `ebs-sc`
- DataStorage: 10Gi
- AuditStorage: 5Gi (optional)
- NodePort service: 30082
- Resource limits và requests

## Các bước triển khai

### Bước 1: Apply Terraform changes
```bash
# Chạy Terraform để cập nhật IAM policies
terraform plan
terraform apply
```

### Bước 2: Cài đặt EBS CSI Driver
```bash
kubectl apply -f k8s-manifests/ebs-csi-driver.yaml
```

Kiểm tra trạng thái:
```bash
# Kiểm tra controller
kubectl get deployment ebs-csi-controller -n kube-system

# Kiểm tra node daemonset
kubectl get daemonset ebs-csi-node -n kube-system

# Xem logs nếu cần
kubectl logs -n kube-system -l app=ebs-csi-controller
```

### Bước 3: Tạo StorageClasses
```bash
kubectl apply -f k8s-manifests/ebs-storageclass.yaml
```

Kiểm tra:
```bash
kubectl get storageclass
```

### Bước 4: Cài đặt Vault với EBS storage

#### Option 1: Sử dụng script tự động
```bash
chmod +x k8s-manifests/setup-vault-ebs.sh
./k8s-manifests/setup-vault-ebs.sh
```

#### Option 2: Cài đặt thủ công
```bash
# Add Vault Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace
kubectl create namespace vault

# Install Vault
helm upgrade --install vault hashicorp/vault \
    --namespace vault \
    --values k8s-manifests/vault-values.yaml \
    --wait
```

### Bước 5: Initialize và Unseal Vault

```bash
# Initialize Vault
kubectl exec -n vault vault-0 -- vault operator init

# Lưu lại unseal keys và root token!

# Unseal Vault (cần 3 keys)
kubectl exec -n vault vault-0 -- vault operator unseal <KEY1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY3>
```

### Bước 6: Verify cài đặt

```bash
# Kiểm tra Vault pods
kubectl get pods -n vault

# Kiểm tra PVCs
kubectl get pvc -n vault

# Kiểm tra PVs
kubectl get pv

# Kiểm tra Vault status
kubectl exec -n vault vault-0 -- vault status

# Kiểm tra EBS volumes trong AWS Console
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=vault"
```

## Truy cập Vault

### Via NodePort
```bash
# Get NodePort
kubectl get svc -n vault vault

# Access via browser
http://<NODE_IP>:30082
```

### Via Port Forward
```bash
kubectl port-forward -n vault vault-0 8200:8200

# Access via browser
http://localhost:8200
```

## Cấu hình nâng cao

### High Availability Mode
Để enable HA mode, uncomment phần `ha` trong `vault-values.yaml`:

```yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
```

### Thay đổi kích thước storage
Edit `vault-values.yaml`:

```yaml
server:
  dataStorage:
    size: 20Gi  # Thay đổi từ 10Gi lên 20Gi
```

Upgrade Vault:
```bash
helm upgrade vault hashicorp/vault \
    --namespace vault \
    --values k8s-manifests/vault-values.yaml
```

### Snapshot và Backup

Tạo VolumeSnapshot:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: vault-data-snapshot
  namespace: vault
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: data-vault-0
EOF
```

## Troubleshooting

### EBS CSI Driver không hoạt động
```bash
# Kiểm tra logs
kubectl logs -n kube-system -l app=ebs-csi-controller
kubectl logs -n kube-system -l app=ebs-csi-node

# Kiểm tra IAM permissions
aws iam get-role-policy --role-name k8s-worker-role --policy-name AmazonEKS_EBS_CSI_Driver_Policy
```

### PVC pending
```bash
# Kiểm tra PVC status
kubectl describe pvc -n vault

# Kiểm tra events
kubectl get events -n vault --sort-by='.lastTimestamp'

# Kiểm tra StorageClass
kubectl get storageclass ebs-sc -o yaml
```

### Vault pod không start
```bash
# Kiểm tra pod logs
kubectl logs -n vault vault-0

# Kiểm tra PVC mount
kubectl describe pod -n vault vault-0

# Kiểm tra node có đủ capacity
kubectl describe node
```

## Best Practices

1. **Backup thường xuyên**: Tạo snapshots của EBS volumes định kỳ
2. **Monitor storage**: Theo dõi usage của PVCs
3. **Security**: Enable encryption cho EBS volumes
4. **HA setup**: Sử dụng Raft storage backend với 3+ replicas trong production
5. **Resource limits**: Set appropriate CPU/Memory limits cho Vault pods
6. **Auto-unseal**: Cấu hình AWS KMS auto-unseal trong production

## Tài liệu tham khảo

- [AWS EBS CSI Driver Documentation](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Vault on Kubernetes](https://www.vaultproject.io/docs/platform/k8s)
- [Vault Helm Chart](https://github.com/hashicorp/vault-helm)
