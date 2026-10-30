terraform {
  required_version = ">= 1.7"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.50"
    }
  }

  # Remote state with encryption at rest. State holds access policy tokens.
  # See ../README.md "Remote state". Never commit a local terraform.tfstate.
  # backend "s3" {}
}

# Cloud API only, to look up the stack (breaks the provider/data source cycle).
provider "grafana" {
  alias                     = "cloud"
  cloud_access_policy_token = var.cloud_access_policy_token
}

# Default provider for both APIs:
#   cloud_access_policy_token: access policies and tokens (Cloud API)
#   url + auth: teams, folders, roles, data sources, dashboards, alerts (stack API)
# Both from TF_VAR_ environment variables, never a file.
provider "grafana" {
  url                       = data.grafana_cloud_stack.this.url
  auth                      = var.grafana_service_account_token
  cloud_access_policy_token = var.cloud_access_policy_token
}
