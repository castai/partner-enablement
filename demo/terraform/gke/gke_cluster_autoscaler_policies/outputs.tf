output "castai_cluster_id" {
  value = nonsensitive(module.castai-gke-cluster.cluster_id)
}