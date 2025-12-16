# Launch Template for worker nodes
resource "aws_launch_template" "k8s_worker_lt" {
  name_prefix = "k8s-worker-lt-"
  image_id    = var.ami["worker"]
  key_name    = aws_key_pair.k8s.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_worker_profile.name
  }

  vpc_security_group_ids = [aws_security_group.k8s_worker.id]

  # EBS configuration for worker nodes
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp2"
      volume_size           = 20
      delete_on_termination = true
      encrypted             = false
    }
  }

  user_data = base64encode(templatefile("${path.module}/worker_user_data.sh", {
    ssm_join_param_name = var.ssm_join_param_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "k8s-worker"
      "kubernetes.io/cluster/ec2k8s" = "owned"

    }
  }
}

# Auto Scaling Group for worker nodes (Mixed Instances Policy + Spot)
resource "aws_autoscaling_group" "k8s_workers" {
  name                      = "k8s-workers-asg"
  min_size                  = var.worker_asg_min_size
  max_size                  = var.worker_asg_max_size
  desired_capacity          = var.worker_asg_desired_capacity
  force_delete              = true
  health_check_type         = "EC2"
  vpc_zone_identifier       = [aws_subnet.k8s_private_subnet.id]
  wait_for_capacity_timeout = "10m"
  capacity_rebalance        = true
  depends_on                = [aws_instance.k8s_master]

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.k8s_worker_lt.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.worker_asg_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.worker_asg_on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.worker_asg_on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = var.worker_asg_spot_allocation_strategy
    }
  }

  tag {
    key                 = "kubernetes.io/cluster/ec2k8s"
    value               = "owned"
    
    propagate_at_launch = true
  
  }
}
