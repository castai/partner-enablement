# 3. Connect EKS cluster to CAST AI.

locals {
  role_name = "castai-eks-role"
}

# Configure Data sources and providers required for CAST AI connection.
data "aws_caller_identity" "current" {}

resource "castai_eks_user_arn" "castai_user_arn" {
  cluster_id = castai_eks_clusterid.cluster_id.id
}


provider "castai" {
  api_url   = var.castai_api_url
  api_token = var.castai_api_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed.
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.cluster_region]
    }
  }
}

# Create AWS IAM policies and a user to connect to CAST AI.
module "castai-eks-role-iam" {
  source = "castai/eks-role-iam/castai"

  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_cluster_region = var.cluster_region
  aws_cluster_name   = var.cluster_name
  aws_cluster_vpc_id = module.vpc.vpc_id

  castai_user_arn = castai_eks_user_arn.castai_user_arn.arn

  create_iam_resources_per_cluster = true
}

# Configure EKS cluster connection using CAST AI eks-cluster module.
resource "castai_eks_clusterid" "cluster_id" {
  account_id   = data.aws_caller_identity.current.account_id
  region       = var.cluster_region
  cluster_name = var.cluster_name
}

module "castai-eks-cluster" {
  source = "castai/eks-cluster/castai"

  api_url                = var.castai_api_url
  castai_api_token       = var.castai_api_token
  wait_for_cluster_ready = true

  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_cluster_region = var.cluster_region
  aws_cluster_name   = module.eks.cluster_name

  install_security_agent = true

  aws_assume_role_arn        = module.castai-eks-role-iam.role_arn
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

  default_node_configuration = module.castai-eks-cluster.castai_node_configurations["default"]

  node_configurations = {
    default = {
      subnets         = module.vpc.private_subnets
      tags            = var.tags
      security_groups = [
        module.eks.cluster_security_group_id,
        module.eks.node_security_group_id,
        aws_security_group.additional.id,
      ]
      instance_profile_arn = module.castai-eks-role-iam.instance_profile_arn
    }
  }

  node_templates = {
    default_by_castai = {
      name             = "default-by-castai"
      configuration_id = module.castai-eks-cluster.castai_node_configurations["default"]
      is_default       = true
      should_taint     = false

      constraints = {
        on_demand          = true
        spot               = true
        use_spot_fallbacks = true

        enable_spot_diversity                       = false
        spot_diversity_price_increase_limit_percent = 20

        spot_interruption_predictions_enabled = true
        spot_interruption_predictions_type    = "aws-rebalance-recommendations"
      }
    }
  }

  autoscaler_settings = {
    enabled                                 = true
    is_scoped_mode                          = false
    node_templates_partial_matching_enabled = false

    unschedulable_pods = {
      enabled = false
    }

    node_downscaler = {
      enabled = false

      empty_nodes = {
        enabled = true
      }

      evictor = {
        aggressive_mode           = true
        cycle_interval            = "5s"
        dry_run                   = false
        enabled                   = true
        node_grace_period_minutes = 0
        scoped_mode               = false
      }
    }

    cluster_limits = {
      enabled = false

      cpu = {
        max_cores = 20
        min_cores = 1
      }
    }
  }

  # depends_on helps Terraform with creating proper dependencies graph in case of resource creation and in this case destroy.
  # module "castai-eks-cluster" has to be destroyed before module "castai-eks-role-iam".
  depends_on = [module.castai-eks-role-iam]
}

resource "helm_release" "castai-workload-autoscaler" {
  name       = "castai-workload-autoscaler"
  namespace  = "castai-agent"
  repository = "https://castai.github.io/helm-charts"
  chart      = "castai-workload-autoscaler"
  depends_on = [module.eks, module.castai-eks-cluster]
  set {
    name  = "castai.apiKeySecretRef"
    value = "castai-agent"
  }

  set {
    name  = "castai.configMapRef"
    value = "castai-cluster-controller"
  }
}

resource "helm_release" "castai-hibernate" {
  name         = "castai-hibernate"
  namespace    = "castai-agent"
  repository   = "https://castai.github.io/helm-charts"
  chart        = "castai-hibernate"
  depends_on   = [module.eks, module.castai-eks-cluster]
  force_update = true
  set {
    name  = "timeZone"
    value = var.time_zone
  }

  set {
    name  = "pauseCronSchedule"
    value = var.pause_cron_schedule
  }
  set {
    name  = "resumeCronSchedule"
    value = var.resume_cron_schedule
  }
  set {
    name  = "cloud"
    value = "EKS"
  }
  set {
    name  = "apiKey"
    value = base64encode(var.castai_api_token)
  }
}

resource "helm_release" "castai-egressd" {
  name       = "castai-egressd"
  namespace  = "castai-agent"
  repository = "https://castai.github.io/helm-charts"
  chart      = "egressd"
  depends_on = [module.eks, module.castai-eks-cluster]
  set {
    name  = "castai.apiKey"
    value = var.castai_api_token
  }
  set {
    name  = "castai.clusterID"
    value = castai_eks_clusterid.cluster_id.id
  }
}