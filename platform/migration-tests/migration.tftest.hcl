# Migration check: run after export/export.py, with export/out/*.tf moved into platform/.
# Uses your terraform.tfvars; tokens are placeholders, nothing is sent.
#   terraform test -test-directory=migration-tests
# Exported secrets need TF_VAR_ values; any placeholder works here.

mock_provider "grafana" {
  alias = "cloud"

  mock_data "grafana_cloud_stack" {
    defaults = {
      id                 = "100001"
      url                = "https://acmeprod.grafana.net"
      region_slug        = "prod-eu-west-2"
      prometheus_user_id = 1
      logs_user_id       = 2
    }
  }
}

mock_provider "grafana" {}

variables {
  cloud_access_policy_token     = "test-not-a-token"
  grafana_service_account_token = "test-not-a-token"
}

run "exported_content_lands" {
  command = apply

  assert {
    condition     = length(module.content.dashboard_uids) == length(fileset("${path.module}/dashboards", "*/*.json"))
    error_message = "Every exported dashboard maps to a folder."
  }

  assert {
    condition     = alltrue([for k in keys(var.exported_folders) : contains(keys(local.folder_uids), k)])
    error_message = "Every exported folder is created."
  }
}
