# EKS module variables.
variable "cluster_name" {
  type        = string
  description = "EKS cluster name in AWS account."
}

variable "cluster_region" {
  type        = string
  description = "AWS Region in which EKS cluster and supporting resources will be created."
}

variable "cluster_version" {
  type        = string
  description = "EKS cluster version."
  default     = "1.24"
}

variable "castai_api_url" {
  type        = string
  description = "URL of alternative CAST AI API to be used during development or testing"
  default     = "https://api.cast.ai"
}

# Variables required for connecting EKS cluster to CAST AI.
variable "castai_api_token" {
  type        = string
  description = "CAST AI API token created in console.cast.ai API Access keys section"
}

variable "delete_nodes_on_disconnect" {
  type        = bool
  description = "Optional parameter, if set to true - CAST AI provisioned nodes will be deleted from cloud on cluster disconnection. For production use it is recommended to set it to false."
  default     = true
}

variable "tags" {
  type        = map(any)
  description = "Optional tags for new cluster nodes. This parameter applies only to new nodes - tags for old nodes are not reconciled."
  default     = {}
}

variable "owner" {
  type        = string
  description = "The owner of the environment"
  default     = "Unknown"
}

variable "machines" {
  type        = number
  description = "The number of machines"
  default     = 5
}

variable "time_zone" {
  type        = string
  description = "The timezone for hibernate"
  default     = "EST"
}

variable "pause_cron_schedule" {
  type        = string
  description = "The pause cron schedule for hibernate"
  default     = "0 22 * * 1-5"
}

variable "resume_cron_schedule" {
  type        = string
  description = "The resume cron schedule for hibernate"
  default     = "0 5 * * 1-5"
}

variable "demo_app" {
  type        = bool
  description = "Install demo application"
  default     = true
}
