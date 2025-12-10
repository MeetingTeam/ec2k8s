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
      "sudo bash /home/ubuntu/master.sh k8s-master ${var.ssm_join_param_name}"
    ]
  }
  provisioner "local-exec" {
    command = "ansible-playbook -i '${self.public_ip},' playbook.yml"
  }
}


