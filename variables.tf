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