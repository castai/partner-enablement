
resource "helm_release" "demo-app" {

  count      = var.demo_app ? 1 : 0
  name       = "demo-app"
  namespace  = "demo-app"
  repository = "oci://us-docker.pkg.dev/online-boutique-ci/charts"
  chart      = "onlineboutique"
  version = "0.9.0"
  depends_on = [null_resource.check_minimum_nodes_available]

  create_namespace = true

  lifecycle {
    replace_triggered_by = [
      # This is just needed to force the replacement of the release to make sure that it is evenly distributed within the cluster
      null_resource.check_minimum_nodes_available
    ]
  }

}
