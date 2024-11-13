# 3. Connect GKE cluster to CAST AI in read-only mode.

# Configure Data sources and providers required for CAST AI connection.

data "google_client_config" "default" {}

provider "castai" {
  api_url   = var.castai_api_url
  api_token = var.castai_api_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}

# Configure GKE cluster connection using CAST AI gke-cluster module.
module "castai-gke-iam" {
  source = "castai/gke-iam/castai"

  project_id       = var.project_id
  gke_cluster_name = var.cluster_name
}

module "castai-gke-cluster" {
  source = "castai/gke-cluster/castai"

  api_url                = var.castai_api_url
  castai_api_token       = var.castai_api_token
  wait_for_cluster_ready = true

  project_id           = var.project_id
  gke_cluster_name     = var.cluster_name
  gke_cluster_location = module.gke.location

  gke_credentials            = module.castai-gke-iam.private_key
  delete_nodes_on_disconnect = var.delete_nodes_on_disconnect

  default_node_configuration = module.castai-gke-cluster.castai_node_configurations["default"]

  node_configurations = {
    default = {
      disk_cpu_ratio = 25
      subnets        = [module.vpc.subnets_ids[0]]
      tags           = var.tags
    }

  }

  node_templates = {
    default_by_castai = {
      name             = "default-by-castai"
      configuration_id = module.castai-gke-cluster.castai_node_configurations["default"]
      is_default       = true
      should_taint     = false

      constraints = {
        on_demand          = true
        spot               = true
        use_spot_fallbacks = true

        enable_spot_diversity                       = false
        spot_diversity_price_increase_limit_percent = 20
      }
    }
  }

  // Configure Autoscaler policies as per API specification https://api.cast.ai/v1/spec/#/PoliciesAPI/PoliciesAPIUpsertClusterPolicies.
  // Here:
  //  - unschedulablePods - Unscheduled pods policy
  //  - nodeDownscaler    - Node deletion policy
  autoscaler_policies_json = <<-EOT
    {
         "unschedulablePods": {
            "enabled": false
        },
        "nodeDownscaler": {
            "enabled": false,
            "emptyNodes": {
                "enabled": false
            },
            "evictor": {
                "aggressiveMode": true,
                "cycleInterval": "5s",
                "dryRun": false,
                "enabled": true,
                "nodeGracePeriodMinutes": 0,
                "scopedMode": false
            }
        },
        "clusterLimits": {
            "cpu": {
                "maxCores": 20,
                "minCores": 1
            },
            "enabled": false
        }
    }
  EOT

  // depends_on helps terraform with creating proper dependencies graph in case of resource creation and in this case destroy
  // module "castai-gke-cluster" has to be destroyed before module "castai-gke-iam" and "module.gke"
  depends_on = [module.gke, module.castai-gke-iam]
}

resource "helm_release" "castai-workload-autoscaler" {
  name         = "castai-workload-autoscaler"
  namespace    = "castai-agent"
  repository   = "https://castai.github.io/helm-charts"
  chart        = "castai-workload-autoscaler"
  force_update = true
  depends_on   = [module.gke, module.castai-gke-cluster, module.castai-gke-iam]
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
  depends_on   = [module.gke, module.castai-gke-cluster, module.castai-gke-iam]
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
    value = "GKE"
  }
  set {
    name  = "apiKey"
    value = base64encode(var.castai_api_token)
  }
}