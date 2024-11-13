# 2. Create EKS cluster.
module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  version      = "19.4.2"
  putin_khuylo = true

  cluster_name                   = var.cluster_name
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    # Add the CAST AI IAM role which required for CAST AI nodes to join the cluster.
    {
      rolearn  = module.castai-eks-role-iam.instance_profile_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  self_managed_node_groups = {
    node_group_1 = {
      name          = "${var.cluster_name}-ng-1"
      instance_type = "m5.large"
      max_size      = var.machines
      min_size      = var.machines
      desired_size  = var.machines
    }
  }

  cluster_tags = {
    "owner" = "${var.owner}"
    "persist" = "true"
  }
}

# Example additional security group.
resource "aws_security_group" "additional" {
  name_prefix = "${var.cluster_name}-additional"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}
