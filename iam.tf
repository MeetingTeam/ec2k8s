data "aws_caller_identity" "current" {}

# IAM role for worker nodes to read join command from SSM Parameter Store
resource "aws_iam_role" "k8s_worker_role" {
  name               = "k8s-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "k8s_worker_ssm_read" {
  name        = "k8s-worker-ssm-read"
  description = "Allow workers to read K8s join command from SSM"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter"],
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_join_param_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_worker_ssm_read_attach" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = aws_iam_policy.k8s_worker_ssm_read.arn
}

resource "aws_iam_instance_profile" "k8s_worker_profile" {
  name = "k8s-worker-instance-profile"
  role = aws_iam_role.k8s_worker_role.name
}

# IAM role for master to write join command to SSM Parameter Store
resource "aws_iam_role" "k8s_master_role" {
  name               = "k8s-master-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "k8s_master_ssm_write" {
  name        = "k8s-master-ssm-write"
  description = "Allow master to write K8s join command to SSM"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ssm:PutParameter", "ssm:GetParameter"],
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_join_param_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_master_ssm_write_attach" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = aws_iam_policy.k8s_master_ssm_write.arn
}

resource "aws_iam_instance_profile" "k8s_master_profile" {
  name = "k8s-master-instance-profile"
  role = aws_iam_role.k8s_master_role.name
}


