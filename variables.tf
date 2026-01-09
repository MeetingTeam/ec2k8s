variable "region" {
  default = "ap-southeast-1"
}

variable "ami" {
  type = map(string)
  default = {
    master = "ami-0827b3068f1548bf6"
    worker = "ami-0827b3068f1548bf6"
  }
}

variable "instance_type" {
  type = map(string)
  default = {
    master = "t3.medium"
    worker = "t3.medium"
  }
}

variable "worker_instance_count" {
  type    = number
  default = 0
}

# Autoscaling configuration for worker nodes
variable "worker_asg_min_size" {
  type    = number
  default = 0
}

variable "worker_asg_max_size" {
  type    = number
  default = 4
}

variable "worker_asg_desired_capacity" {
  type    = number
  default = 2
}

# SSM Parameter Store name to publish the kubeadm join command
variable "ssm_join_param_name" {
  type    = string
  default = "/k8s/join-command"
}

# Mixed Instances Policy for worker ASG
variable "worker_asg_instance_types" {
  description = "List of instance types to use for worker ASG (overrides)"
  type        = list(string)
  default     = [
    "t3.medium",
    "t3.large",
    "c6i.large"
  ]
}

variable "worker_asg_on_demand_base_capacity" {
  description = "Base capacity served by On-Demand before using Spot"
  type        = number
  default     = 2
}

variable "worker_asg_on_demand_percentage_above_base_capacity" {
  description = "Percent of additional capacity to be On-Demand (0 = all Spot)"
  type        = number
  default     = 0
}

variable "worker_asg_spot_allocation_strategy" {
  description = "Spot allocation strategy (price-capacity-optimized recommended)"
  type        = string
  default     = "price-capacity-optimized"
}
