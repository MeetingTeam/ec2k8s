output "master" {
  value = aws_instance.k8s_master.public_ip
}

output "worker_private_ips" {
  value = aws_instance.k8s_worker[*].private_ip
}