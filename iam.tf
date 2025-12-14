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

# IAM policy for EBS CSI Driver
resource "aws_iam_policy" "ebs_csi_driver_policy" {
  name        = "AmazonEKS_EBS_CSI_Driver_Policy"
  description = "Policy for EBS CSI Driver"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateTags"
        ],
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ],
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteTags"
        ],
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateVolume"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "aws:RequestTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateVolume"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "aws:RequestTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteVolume"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteVolume"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteVolume"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/created-for/pvc/name" = "*"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteSnapshot"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeSnapshotName" = "*"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DeleteSnapshot"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_worker_ebs_csi_attach" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = aws_iam_policy.ebs_csi_driver_policy.arn
}

resource "aws_iam_instance_profile" "k8s_worker_profile" {
  name = "k8s-worker-instance-profile"
  role = aws_iam_role.k8s_worker_role.name
}

# Attach custom EBS CSI policy to master role as well
resource "aws_iam_role_policy_attachment" "k8s_master_ebs_csi_attach" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = aws_iam_policy.ebs_csi_driver_policy.arn
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

# Attach AWS managed policies to worker role
resource "aws_iam_role_policy_attachment" "k8s_worker_ec2_full" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_worker_elb_full" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_worker_iam_readonly" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_worker_ebs_csi_managed" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Attach AWS managed policies to master role
resource "aws_iam_role_policy_attachment" "k8s_master_ec2_full" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_master_elb_full" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_master_iam_readonly" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "k8s_master_ebs_csi_managed" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# IAM policy for Cloud Controller Manager and Load Balancer Controller
resource "aws_iam_policy" "k8s_cloud_controller_policy" {
  name        = "K8sCloudControllerPolicy"
  description = "Additional permissions for AWS Cloud Controller Manager and Load Balancer Controller"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:CreateServiceLinkedRole"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s_worker_cloud_controller" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = aws_iam_policy.k8s_cloud_controller_policy.arn
}

resource "aws_iam_role_policy_attachment" "k8s_master_cloud_controller" {
  role       = aws_iam_role.k8s_master_role.name
  policy_arn = aws_iam_policy.k8s_cloud_controller_policy.arn
}
