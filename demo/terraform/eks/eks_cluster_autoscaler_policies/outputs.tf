output "castai_cluster_id" {
  value = nonsensitive(module.castai-eks-cluster.cluster_id)
}