# Checking if minimum desired count is reached
resource "null_resource" "check_minimum_nodes_available" {
  provisioner "local-exec" {
    command     = abspath("../../shell/nodes_minimum_available.sh")
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = abspath("../../../clusters/${var.cluster_name}/kubeconfig") # Path to your kubeconfig file
      CLUSTER_NAME = var.cluster_name
      REGION = var.cluster_region
      CLOUD_PROVIDER = "gke"
    }
  }

  depends_on = [module.gke, module.castai-gke-cluster]

  # This triggers the execution of the provisioner only once
  triggers = {
    always_run = "${timestamp()}"
  }

}

# Checking if all the nodes achieved ready state before redeploying the release
resource "null_resource" "check_nodes_ready" {
  provisioner "local-exec" {
    command     = abspath("../../shell/nodes_in_ready_state.sh")
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = abspath("../../../clusters/${var.cluster_name}/kubeconfig") # Path to your kubeconfig file
    }
  }

  depends_on = [null_resource.check_minimum_nodes_available]

  # This triggers the execution of the provisioner only once
  triggers = {
    always_run = "${timestamp()}"
  }

}
