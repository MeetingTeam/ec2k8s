# Launch Template for worker nodes
resource "aws_launch_template" "k8s_worker_lt" {
  name_prefix   = "k8s-worker-lt-"
  image_id      = var.ami["worker"]
  instance_type = var.instance_type["worker"]
  key_name      = aws_key_pair.k8s.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.k8s_worker_profile.name
  }

  vpc_security_group_ids = [aws_security_group.k8s_worker.id]

  user_data = base64encode(templatefile("${path.module}/worker_user_data.sh", {
    ssm_join_param_name = var.ssm_join_param_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "k8s-worker"
    }
  }
}

# Auto Scaling Group for worker nodes
resource "aws_autoscaling_group" "k8s_workers" {
  name                      = "k8s-workers-asg"
  min_size                  = var.worker_asg_min_size
  max_size                  = var.worker_asg_max_size
  desired_capacity          = var.worker_asg_desired_capacity
  force_delete              = true
  health_check_type         = "EC2"
  vpc_zone_identifier       = [aws_subnet.k8s_private_subnet.id]
  wait_for_capacity_timeout = "10m"
  depends_on                = [aws_instance.k8s_master]

  launch_template {
    id      = aws_launch_template.k8s_worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "k8s-worker"
    propagate_at_launch = true
  }
}


