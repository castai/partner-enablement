## Assumptions

You have already registered an account at https://console.cast.ai and have CAST AI token readily available. The token must be exposed as en environment variable `CASTAI_API_TOKEN`

## Demos

The Makefile has specific make targets to help you with rolling aout and manage your demo environments. Under the hood the target applies Terraform IaC and saves all necessary information so that later you can access or cleanup your demo environments.

### AWS EKS Demo

To provision a demo on AWS EKS run the following command:

`make demo-eks`

### Google Cloud GKE Demo

To provision a demo on Google GKE run the following command:

`make demo-gke`

## Accessing Demo Environments

The Makefile has a target to help you to get access to your provisioned cluster. After a successful execution the target return an export comand for a selected cluster, so that you can get an immediate access to one.

Usage:

`make demo-access`

## Refreshing Demo Environment

The Makefile has a target that allows the refresh of the environments earlier provisioned. This is handy when you do not want to spin up entirely new environment but rather reuse the existing one in case of, say, back to back demos. The target will refresh the terraform state and bring the cluster to its original state. It will also reset the setting of the Autoscaler, so that the nodes are not getting deleted immediately.

Usage:

`make demo-refresh`

## Removing Demo Environments

The Makefile has a target that allows you to clean up the environments earlier provisioned if you do not longer need them. The target will show you a selection of clusters that you currently have provisioned and will remove one based on selection.

Usage:

`make demo-cleanup`

