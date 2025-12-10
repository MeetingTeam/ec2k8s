variable "region" {
  default = "ap-southeast-1"
}

variable "ami" {
  type = map(string)
  default = {
    master = "ami-0a2fc2446ff3412c3"
    worker = "ami-0a2fc2446ff3412c3"
  }
}

variable "instance_type" {
  type = map(string)
  default = {
    master = "t2.medium"
    worker = "t2.medium"
  }
}

variable "worker_instance_count" {
  type    = number
  default = 2
}

# Autoscaling configuration for worker nodes
variable "worker_asg_min_size" {
  type    = number
  default = 2
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