# Create VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
    "kubernetes.io/cluster/ec2k8s" = "owned"

  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# Create Public Subnet
resource "aws_subnet" "k8s_public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "k8s-public-subnet"
    "kubernetes.io/cluster/ec2k8s" = "owned"
    "kubernetes.io/role/elb"   = "1"
  }
}

# Create Route Table for Public Subnet
resource "aws_route_table" "k8s_public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s-public-rt"
  }
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "k8s_public_rta" {
  subnet_id      = aws_subnet.k8s_public_subnet.id
  route_table_id = aws_route_table.k8s_public_rt.id
}

# ----------------------
# Private networking for workers
# ----------------------

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "k8s-nat-eip"
  }
}

# NAT Gateway in Public Subnet
resource "aws_nat_gateway" "k8s_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.k8s_public_subnet.id

  # Ensure IGW exists before NAT creation
  depends_on = [aws_internet_gateway.k8s_igw]

  tags = {
    Name = "k8s-nat-gateway"
  }
}

# Private Subnet for workers
resource "aws_subnet" "k8s_private_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "172.16.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "k8s-private-subnet"
    "kubernetes.io/cluster/ec2k8s" = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# Private Route Table routing to NAT for Internet egress
resource "aws_route_table" "k8s_private_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s_nat.id
  }

  tags = {
    Name = "k8s-private-rt"
  }
}

# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "k8s_private_rta" {
  subnet_id      = aws_subnet.k8s_private_subnet.id
  route_table_id = aws_route_table.k8s_private_rt.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}
