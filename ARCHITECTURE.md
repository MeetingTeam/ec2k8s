# EC2K8s - Kubernetes Cluster Architecture

## Project Overview

**EC2K8s** is an Infrastructure-as-Code (IaC) project that automates the deployment of a **Kubernetes v1.31 cluster on AWS EC2** using **Terraform** and **Kubeadm**. The project provisions a highly available, scalable Kubernetes cluster with:

- **1 Master Node** (Control Plane) - Runs Kubernetes API server, etcd, scheduler, and controller manager
- **Auto-Scaling Worker Nodes** - Managed by AWS Auto Scaling Group (ASG) with mixed On-Demand and Spot instances
- **Containerization** - Uses containerd as the container runtime
- **Networking** - Weave Net for pod-to-pod communication
- **Infrastructure** - AWS VPC with public/private subnets, NAT gateway, security groups

---

## High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Account                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    VPC (172.16.0.0/16)                     │   │
│  │                                                            │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │         Public Subnet (172.16.1.0/24)               │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  K8s Master Node (t3.medium)                │  │  │   │
│  │  │  │  - Kubernetes Control Plane                 │  │  │   │
│  │  │  │  - API Server (6443)                        │  │  │   │
│  │  │  │  - etcd (2379-2380)                         │  │  │   │
│  │  │  │  - Scheduler, Controller Manager            │  │  │   │
│  │  │  │  - Weave Net Pod Network                    │  │  │   │
│  │  │  │  - Helm 3 Package Manager                   │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  NAT Gateway                                │  │  │   │
│  │  │  │  (Provides egress for private subnet)       │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  Internet Gateway                           │  │  │   │
│  │  │  │  (Provides ingress/egress to internet)      │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │                                                            │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │         Private Subnet (172.16.2.0/24)              │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  Worker Node 1 (t3.medium - Spot/On-Demand) │  │  │   │
│  │  │  │  - Kubelet                                  │  │  │   │
│  │  │  │  - Container Runtime (containerd)           │  │  │   │
│  │  │  │  - Weave Net Agent                          │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  Worker Node 2 (t3.large - Spot/On-Demand)  │  │  │   │
│  │  │  │  - Kubelet                                  │  │  │   │
│  │  │  │  - Container Runtime (containerd)           │  │  │   │
│  │  │  │  - Weave Net Agent                          │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │                                                     │  │   │
│  │  │  ┌──────────────────────────────────────────────┐  │  │   │
│  │  │  │  Worker Node N (Auto Scaling Group)         │  │  │   │
│  │  │  │  - Managed by ASG (min:1, max:4, desired:1) │  │  │   │
│  │  │  │  - Mixed instance types (t3.medium/large,   │  │  │   │
│  │  │  │    t2.large)                                │  │  │   │
│  │  │  │  - Spot allocation strategy: price-capacity │  │  │   │
│  │  │  │    optimized                                │  │  │   │
│  │  │  └──────────────────────────────────────────────┘  │  │   │
│  │  │                                                     │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              AWS Systems Manager (SSM)                   │   │
│  │  - Parameter Store: /k8s/join-command                   │   │
│  │    (Stores kubeadm join command for worker nodes)       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Architecture

### 1. **Infrastructure Layer (Terraform)**

#### VPC & Networking (`vpc.tf`)
- **VPC**: 172.16.0.0/16 CIDR block
- **Public Subnet**: 172.16.1.0/24 (Master node, NAT gateway)
- **Private Subnet**: 172.16.2.0/24 (Worker nodes)
- **Internet Gateway**: Provides internet connectivity to public subnet
- **NAT Gateway**: Enables outbound internet access for private subnet
- **Route Tables**: 
  - Public route table routes 0.0.0.0/0 → IGW
  - Private route table routes 0.0.0.0/0 → NAT Gateway

#### Security Groups (`security_groups.tf`)

**Master Security Group (`k8s_master_sg`)**
- SSH (22): Open to 0.0.0.0/0
- Kubernetes API Server (6443): Open to 0.0.0.0/0
- etcd (2379-2380): Open to 0.0.0.0/0
- Weave Net TCP (6783): Open to 0.0.0.0/0
- Weave Net UDP (6784): Open to 0.0.0.0/0
- Kubelet API (10248-10260): Open to 0.0.0.0/0
- NodePort Services (30000-32767): Open to 0.0.0.0/0
- All egress allowed

**Worker Security Group (`k8s_worker_sg`)**
- SSH (22): Open to 0.0.0.0/0
- Weave Net TCP (6783): Open to 0.0.0.0/0
- Weave Net UDP (6784): Open to 0.0.0.0/0
- Kubelet API (10248-10260): Open to 0.0.0.0/0
- NodePort Services (30000-32767): Open to 0.0.0.0/0
- All egress allowed

#### Key Pair (`keypair.tf`)
- SSH key pair for EC2 instance access
- Public key: `k8s.pub`
- Private key: `k8s` (must be protected with `chmod 600`)

#### IAM Roles & Policies (`iam.tf`)

**Master Node IAM Role**
- Policy: `k8s-master-ssm-write`
- Permissions: 
  - `ssm:PutParameter` - Write join command to SSM
  - `ssm:GetParameter` - Read join command from SSM
- Resource: `arn:aws:ssm:{region}:{account}:parameter/k8s/join-command`

**Worker Node IAM Role**
- Policy: `k8s-worker-ssm-read`
- Permissions:
  - `ssm:GetParameter` - Read join command from SSM
- Resource: `arn:aws:ssm:{region}:{account}:parameter/k8s/join-command`

### 2. **Compute Layer**

#### Master Node (`main.tf`)
- **Instance Type**: t3.medium (configurable)
- **AMI**: Ubuntu 22.04 LTS (ami-0a2fc2446ff3412c3)
- **Subnet**: Public subnet (172.16.1.0/24)
- **Storage**: 35 GB gp3 EBS volume
- **IAM Profile**: k8s-master-instance-profile
- **Provisioning**:
  1. File provisioner: Copies `master.sh` to instance
  2. Remote-exec: Executes master.sh with hostname and SSM parameter name
  3. Local-exec: Runs Ansible playbook to fetch join command

#### Worker Nodes (`asg.tf`)
- **Launch Template**: `k8s_worker_lt`
  - AMI: Ubuntu 22.04 LTS
  - Instance types: t3.medium, t3.large, t2.large (configurable)
  - Storage: 30 GB gp3 EBS volume
  - IAM Profile: k8s-worker-instance-profile
  - User data: Templated `worker_user_data.sh` with SSM parameter name

- **Auto Scaling Group**: `k8s_workers`
  - Min size: 1
  - Max size: 4
  - Desired capacity: 1
  - Placement: Private subnet (172.16.2.0/24)
  - Mixed Instances Policy:
    - On-Demand base capacity: 0
    - On-Demand percentage above base: 0 (all Spot)
    - Spot allocation strategy: price-capacity-optimized
  - Capacity rebalance: Enabled
  - Health check: EC2

### 3. **Kubernetes Control Plane**

#### Master Node Setup (`master.sh`)

**Step 1: System Configuration**
- Set hostname
- Disable swap (required by Kubernetes)
- Configure kernel modules: overlay, br_netfilter
- Enable IP forwarding and bridge netfilter

**Step 2: Container Runtime Installation**
- **Containerd** v1.7.4
  - Downloaded from GitHub releases
  - Installed to /usr/local
  - Systemd service configured and enabled
- **runc** v1.1.9 (OCI runtime)
- **CNI Plugins** v1.2.0 (Container Networking Interface)
- **crictl** v1.31.0 (Container Runtime Interface CLI)

**Step 3: Kubernetes Components Installation**
- Add Kubernetes APT repository (v1.31)
- Install: kubelet, kubeadm, kubectl
- Mark packages as held (prevent auto-updates)

**Step 4: Kubernetes Cluster Initialization**
- `kubeadm init` with pod network CIDR: 10.244.0.0/16
- Copy kubeconfig to /root/.kube/config and /home/ubuntu/.kube/config
- Wait for API server readiness (up to 10 minutes)

**Step 5: Pod Network Setup**
- Deploy Weave Net v2.8.1 as CNI plugin
- Configure Weave Net IPALLOC_RANGE: 10.244.0.0/16 (avoids overlap with VPC 172.16.0.0/16)
- Wait for Weave Net DaemonSet rollout

**Step 6: Package Manager & Join Command**
- Install Helm 3 (Kubernetes package manager)
- Generate kubeadm join command: `kubeadm token create --print-join-command`
- Save join command to /home/ubuntu/join-command.sh
- Publish join command to AWS SSM Parameter Store: `/k8s/join-command`

#### Worker Node Setup (`worker_user_data.sh`)

**Step 1: System Configuration**
- Set hostname with random UUID suffix
- Disable swap
- Configure kernel modules and IP forwarding
- Install dependencies: apt-transport-https, curl, ca-certificates, gpg, jq, awscli

**Step 2: Container Runtime Installation**
- Same as master: containerd, runc, CNI plugins, crictl

**Step 3: Kubernetes Components Installation**
- Same as master: kubelet, kubeadm, kubectl (v1.31)

**Step 4: Retrieve Join Command**
- Query AWS IMDS for region
- Retrieve join command from SSM Parameter Store: `/k8s/join-command`
- Retry mechanism: Up to 60 attempts with 10-second intervals (~10 minutes)

**Step 5: Join Cluster**
- Execute `kubeadm join` command
- Retry mechanism: Up to 30 attempts with 10-second intervals (~5 minutes)
- Enable and restart kubelet service

### 4. **Networking & Service Mesh**

#### Weave Net (Pod Network)
- **Version**: v2.8.1
- **CIDR**: 10.244.0.0/16 (pod network)
- **Protocol**: TCP (6783) and UDP (6784) for inter-node communication
- **DaemonSet**: Runs on all nodes (master + workers)
- **Features**:
  - Overlay network for pod-to-pod communication
  - Automatic IP allocation to pods
  - Cross-node networking

#### Service Communication
- **ClusterIP Services**: Internal cluster communication via Weave Net
- **NodePort Services**: Exposed on ports 30000-32767 on all nodes
- **API Server**: Accessible on port 6443

### 5. **Orchestration & Automation**

#### Terraform (`*.tf` files)
- **Provider**: AWS (v5.21.0)
- **Region**: ap-southeast-1 (configurable)
- **State Management**: Local (can be configured for remote backend)
- **Key Files**:
  - `provider.tf`: AWS provider configuration
  - `variables.tf`: Input variables with defaults
  - `main.tf`: Master node EC2 instance
  - `asg.tf`: Worker node launch template and ASG
  - `vpc.tf`: VPC, subnets, gateways, route tables
  - `security_groups.tf`: Security group rules
  - `iam.tf`: IAM roles and policies
  - `keypair.tf`: SSH key pair
  - `outputs.tf`: Terraform outputs

#### Ansible (`playbook.yml`)
- **Purpose**: Fetch join command from master node after provisioning
- **Task**: Fetch `/home/ubuntu/join-command.sh` from master to local `./join-command.sh`
- **Execution**: Triggered by Terraform `local-exec` provisioner

#### AWS Systems Manager Parameter Store
- **Parameter**: `/k8s/join-command`
- **Type**: String
- **Purpose**: Centralized storage for kubeadm join command
- **Access**:
  - Master writes join command after cluster initialization
  - Workers read join command during initialization
  - Enables asynchronous cluster joining without direct master access

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Deployment Flow                              │
└─────────────────────────────────────────────────────────────────┘

1. Terraform Initialization
   ├─ terraform init
   ├─ terraform plan
   └─ terraform apply

2. Master Node Provisioning
   ├─ Create EC2 instance in public subnet
   ├─ Attach IAM role (k8s-master-ssm-write)
   ├─ Copy master.sh to instance
   ├─ Execute master.sh:
   │  ├─ Install containerd, runc, CNI, crictl
   │  ├─ Install kubelet, kubeadm, kubectl
   │  ├─ Run kubeadm init
   │  ├─ Deploy Weave Net
   │  ├─ Generate join command
   │  └─ Write join command to SSM Parameter Store
   └─ Run Ansible playbook to fetch join command

3. Worker Node Provisioning (via ASG)
   ├─ Create launch template with user_data script
   ├─ Create Auto Scaling Group
   ├─ ASG launches worker instances in private subnet
   └─ Each worker instance executes user_data:
      ├─ Install containerd, runc, CNI, crictl
      ├─ Install kubelet, kubeadm, kubectl
      ├─ Query AWS IMDS for region
      ├─ Retrieve join command from SSM Parameter Store
      ├─ Execute kubeadm join
      └─ Enable and start kubelet

4. Cluster Readiness
   ├─ Master node: API server, etcd, scheduler, controller manager ready
   ├─ Worker nodes: Kubelet running, joined to cluster
   ├─ Weave Net: Pod network operational
   └─ Cluster ready for workload deployment

┌─────────────────────────────────────────────────────────────────┐
│                    Communication Flow                           │
└─────────────────────────────────────────────────────────────────┘

Master Node (Public Subnet)
    ↓
    ├─ Kubernetes API Server (6443)
    │  ├─ Kubelet on workers → API Server (status reports, pod management)
    │  └─ kubectl clients → API Server (cluster management)
    │
    ├─ etcd (2379-2380)
    │  └─ Kubernetes components → etcd (cluster state storage)
    │
    └─ Weave Net (6783 TCP, 6784 UDP)
       ├─ Pod-to-pod communication across nodes
       └─ Service discovery via DNS

Worker Nodes (Private Subnet)
    ├─ Kubelet (10248-10260)
    │  └─ Container runtime management
    │
    ├─ Weave Net Agent
    │  └─ Pod network overlay
    │
    └─ Container Runtime (containerd)
       └─ Pod execution

NAT Gateway
    └─ Outbound internet access for private subnet

SSM Parameter Store
    ├─ Master writes: /k8s/join-command
    └─ Workers read: /k8s/join-command
```

---

## Deployment Workflow

### Prerequisites
1. AWS account with appropriate permissions
2. Terraform installed (v1.0+)
3. Ansible installed (for playbook execution)
4. AWS CLI configured with credentials
5. SSH key pair generated (k8s/k8s.pub)

### Deployment Steps

```bash
# 1. Clone repository
git clone https://github.com/MeetingTeam/ec2k8s.git
cd ec2k8s

# 2. Set SSH key permissions
chmod 600 k8s

# 3. Configure AWS credentials
aws configure

# 4. Initialize Terraform
terraform init

# 5. Review planned changes
terraform plan

# 6. Deploy infrastructure
terraform apply

# 7. Wait for master node initialization (~5-10 minutes)
# Monitor: terraform logs, EC2 console, SSM Parameter Store

# 8. Verify cluster
# Get master IP from terraform output
MASTER_IP=$(terraform output -raw master)
ssh -i k8s ubuntu@$MASTER_IP

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# 9. Scale worker nodes (optional)
terraform apply -var="worker_asg_desired_capacity=3"

# 10. Cleanup (when done)
terraform destroy
```

---

## Configuration & Customization

### Key Variables (`variables.tf`)

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | ap-southeast-1 | AWS region |
| `ami` | ami-0a2fc2446ff3412c3 | Ubuntu 22.04 LTS AMI |
| `instance_type.master` | t3.medium | Master node instance type |
| `instance_type.worker` | t2.medium | Worker node instance type |
| `worker_asg_min_size` | 1 | Minimum worker nodes |
| `worker_asg_max_size` | 4 | Maximum worker nodes |
| `worker_asg_desired_capacity` | 1 | Desired worker nodes |
| `worker_asg_instance_types` | [t3.medium, t3.large, t2.large] | Worker instance types |
| `worker_asg_on_demand_base_capacity` | 0 | On-Demand base capacity |
| `worker_asg_on_demand_percentage_above_base_capacity` | 0 | On-Demand percentage (0 = all Spot) |
| `worker_asg_spot_allocation_strategy` | price-capacity-optimized | Spot allocation strategy |
| `ssm_join_param_name` | /k8s/join-command | SSM parameter for join command |

### Customization Examples

**Change Master Instance Type**
```bash
terraform apply -var="instance_type.master=t3.large"
```

**Scale to 3 Worker Nodes**
```bash
terraform apply -var="worker_asg_desired_capacity=3"
```

**Use Different Region**
```bash
terraform apply -var="region=us-east-1"
```

**Mix On-Demand and Spot (50/50)**
```bash
terraform apply \
  -var="worker_asg_on_demand_base_capacity=1" \
  -var="worker_asg_on_demand_percentage_above_base_capacity=50"
```

---

## Security Considerations

### Current Security Posture

⚠️ **WARNING**: This configuration is designed for **development/testing** and has open security group rules.

**Issues**:
- Security groups allow SSH (22) from 0.0.0.0/0
- API Server (6443) accessible from internet
- etcd (2379-2380) accessible from internet
- All ports open to 0.0.0.0/0

### Production Hardening Recommendations

1. **Restrict SSH Access**
   ```hcl
   cidr_blocks = ["YOUR_IP/32"]  # Replace with your IP
   ```

2. **Restrict API Server Access**
   ```hcl
   cidr_blocks = ["YOUR_IP/32", "172.16.0.0/16"]  # Your IP + VPC CIDR
   ```

3. **Restrict etcd Access**
   ```hcl
   # Only allow from master and worker nodes within VPC
   cidr_blocks = ["172.16.0.0/16"]
   ```

4. **Enable EBS Encryption**
   ```hcl
   encrypted = true  # In root_block_device and block_device_mappings
   ```

5. **Use Secrets Management**
   - Store kubeconfig in AWS Secrets Manager
   - Rotate credentials regularly

6. **Enable VPC Flow Logs**
   - Monitor network traffic
   - Detect anomalies

7. **Implement Network Policies**
   - Deploy Kubernetes NetworkPolicies
   - Restrict pod-to-pod communication

8. **Enable Audit Logging**
   - Configure Kubernetes audit logs
   - Send to CloudWatch

---

## Troubleshooting

### Master Node Initialization Fails
1. SSH into master instance
2. Check `/var/log/syslog` for errors
3. Verify containerd status: `systemctl status containerd`
4. Check kubeadm logs: `journalctl -u kubelet -n 50`

### Worker Nodes Fail to Join
1. Check SSM Parameter Store: `/k8s/join-command` exists and has valid command
2. Verify worker IAM role has `ssm:GetParameter` permission
3. Check worker user_data logs: `/var/log/cloud-init-output.log`
4. Verify security group allows communication to master on port 6443

### Pods Stuck in Pending
1. Check node resources: `kubectl describe node <node-name>`
2. Verify Weave Net is running: `kubectl get pods -n kube-system`
3. Check pod events: `kubectl describe pod <pod-name>`

### Network Connectivity Issues
1. Verify security group rules allow Weave Net ports (6783, 6784)
2. Check Weave Net logs: `kubectl logs -n kube-system -l app=weave-net`
3. Test pod-to-pod connectivity: `kubectl run -it --rm debug --image=busybox --restart=Never -- sh`

---

## Project Structure

```
ec2k8s/
├── main.tf                  # Master node EC2 instance
├── asg.tf                   # Worker nodes launch template and ASG
├── vpc.tf                   # VPC, subnets, gateways, route tables
├── security_groups.tf       # Security group rules
├── iam.tf                   # IAM roles and policies
├── keypair.tf               # SSH key pair
├── provider.tf              # AWS provider configuration
├── variables.tf             # Input variables
├── outputs.tf               # Terraform outputs
├── master.sh                # Master node initialization script
├── worker_user_data.sh      # Worker node initialization script
├── worker.sh                # Alternative worker initialization (legacy)
├── playbook.yml             # Ansible playbook for join command fetch
├── ansible.cfg              # Ansible configuration
├── k8s                      # SSH private key (generated)
├── k8s.pub                  # SSH public key (generated)
├── README.md                # Quick start guide
├── SUMMARY.md               # Project summary
├── ARCHITECTURE.md          # This file
├── k8s_quick_fix.sh         # Quick fix script (legacy)
├── script_test.sh           # Test script (legacy)
└── restart.txt              # Restart notes (legacy)
```

---

## Performance & Cost Optimization

### Cost Optimization
1. **Spot Instances**: Worker nodes use Spot instances (up to 90% savings)
2. **Mixed Instance Policy**: Automatically selects cheapest instance types
3. **Auto Scaling**: Scale down during off-peak hours
4. **Smaller Master**: t3.medium is sufficient for small clusters

### Performance Optimization
1. **gp3 EBS Volumes**: Better performance than gp2
2. **Weave Net**: Efficient overlay network with minimal overhead
3. **containerd**: Lightweight container runtime
4. **Spot Allocation Strategy**: price-capacity-optimized balances cost and availability

### Monitoring & Logging
- **CloudWatch**: Monitor EC2 instances, ASG metrics
- **Kubernetes Metrics**: Use Prometheus/Grafana for cluster monitoring
- **Logs**: Configure CloudWatch agent for centralized logging

---

## References

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Weave Net Documentation](https://www.weave.works/docs/net/latest/overview/)
- [containerd Documentation](https://containerd.io/)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)

---

## License & Attribution

This project is based on:
- [YouTube Series by Vikram Kunchala](https://github.com/kunchalavikram1427/YouTube_Series)
- [Ansible-Terraform Integration](https://github.com/kunchalavikram1427/ansible-terraform-integration)

---

**Last Updated**: December 2024
**Kubernetes Version**: v1.31
**Terraform Version**: 5.21.0
**AWS Region**: ap-southeast-1 (configurable)

