# 2. Create GKE cluster.

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  version                    = "24.1.0"
  project_id                 = var.project_id
  name                       = var.cluster_name
  region                     = var.cluster_region
  zones                      = var.cluster_zones
  network                    = module.vpc.network_name
  subnetwork                 = module.vpc.subnets_names[0]
  ip_range_pods              = local.ip_range_pods
  ip_range_services          = local.ip_range_services
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  release_channel            = "STABLE"

  cluster_resource_labels = {
    "owner" = "${var.owner}"
  }

  node_pools = [
    {
      name            = "default-node-pool"
      machine_type    = "e2-standard-4"
      local_ssd_count = 0
      disk_size_gb    = 100
      disk_type       = "pd-standard"
      image_type      = "COS_CONTAINERD"
      auto_repair     = true
      auto_upgrade    = true
      preemptible     = false
      node_count      = var.machines
      autoscaling     = false
    },
  ]
}
