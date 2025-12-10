# Launch master node
resource "aws_instance" "k8s_master" {
  ami                    = var.ami["master"]
  instance_type          = var.instance_type["master"]
  subnet_id              = aws_subnet.k8s_public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_master.id]
  key_name               = aws_key_pair.k8s.key_name
  iam_instance_profile   = aws_iam_instance_profile.k8s_master_profile.name

  tags = {
    Name = "k8s-master"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("k8s")
    host        = self.public_ip
  }
  provisioner "file" {
    source      = "./master.sh"
    destination = "/home/ubuntu/master.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/master.sh",
      "sudo sh /home/ubuntu/master.sh k8s-master"
    ]
  }
  provisioner "local-exec" {
    command = "ansible-playbook -i '${self.public_ip},' playbook.yml"
  }
}

# Launch worker nodes (in private subnet via NAT, SSH through master as bastion)
resource "aws_instance" "k8s_worker" {
  count                  = var.worker_instance_count
  ami                    = var.ami["worker"]
  instance_type          = var.instance_type["worker"]
  subnet_id              = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]
  key_name               = aws_key_pair.k8s.key_name
  depends_on             = [aws_instance.k8s_master]

  tags = {
    Name = "k8s-worker-${count.index}"
  }

  connection {
    type                = "ssh"
    user                = "ubuntu"
    private_key         = file("k8s")
    host                = self.private_ip
    bastion_host        = aws_instance.k8s_master.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file("k8s")
  }

  provisioner "file" {
    source      = "./worker.sh"
    destination = "/home/ubuntu/worker.sh"
  }
  provisioner "file" {
    source      = "./join-command.sh"
    destination = "/home/ubuntu/join-command.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/worker.sh",
      "sudo sh /home/ubuntu/worker.sh k8s-worker-${count.index}",
      "sudo sh /home/ubuntu/join-command.sh"
    ]
  }
}
