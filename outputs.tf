output "master" {
  value = aws_instance.k8s_master.public_ip
}

# With ASG-managed workers, instances are dynamic. Expose ASG info instead.
output "workers_asg_name" {
  value = aws_autoscaling_group.k8s_workers.name
}

output "workers_desired_capacity" {
  value = aws_autoscaling_group.k8s_workers.desired_capacity
}
