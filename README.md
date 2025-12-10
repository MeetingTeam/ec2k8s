# Kubernetes v1.28 on AWS using Kubeadm and Terraform
### The guide run on Ubuntu VM 
### Clone the source
```bash
https://github.com/MeetingTeam/ec2k8s.git
```

### Change permission of .pem
```bash
chmod 600 k8s
```
## Installing tools

### Installing Terraform
```bash
sudo snap install terraform --classic
terraform --version
```
### Installing Ansible
```bash
sudo apt install python3-pip -y
pip3 install ansible

# Thêm vào PATH nếu cần
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc

# Kiểm tra Ansible
ansible --version
```
### Installing AWS CLI
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip -y
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Kiểm tra AWS CLI
aws --version
```

## Configure AWS CLI
### Create IAM user and add credentials
```bash
aws configure
```

## Running Terraform

### Initialize Terraform
```bash
terraform init
```

### Preview changes
```bash
terraform plan
```

### Deploy infrastructure
```bash
terraform apply
```

### Destroy infrastructure
```bash
terraform destroy
```

## References
- https://github.com/kunchalavikram1427/YouTube_Series/blob/main/Kubernetes/ClusterSetup/Kubernetes_v1.28_on_aws_with_containerd.md
- https://github.com/kunchalavikram1427/ansible-terraform-integration



