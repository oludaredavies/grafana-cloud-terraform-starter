terraform {
  required_version = ">= 1.7"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.50"
    }
  }

  # Remote state with encryption at rest. State holds the bootstrap service account token.
  # See ../README.md "Remote state" for s3, azurerm, gcs and Terraform Cloud / Spacelift.
  # backend "s3" {}
}

# Cloud API only. Token from TF_VAR_cloud_access_policy_token, never a file.
provider "grafana" {
  cloud_access_policy_token = var.cloud_access_policy_token
}
