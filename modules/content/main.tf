terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "dashboards_dir" {
  description = "Holds <folder-key>/<dashboard>.json. A folder key is a team key or a folders key."
  type        = string
}

variable "folder_uids" {
  type = map(string)
}

locals {
  dashboard_files = fileset(var.dashboards_dir, "*/*.json")
  unknown         = [for f in local.dashboard_files : f if !contains(keys(var.folder_uids), dirname(f))]
}

resource "grafana_dashboard" "this" {
  for_each    = { for f in local.dashboard_files : f => f if contains(keys(var.folder_uids), dirname(f)) }
  folder      = var.folder_uids[dirname(each.value)]
  config_json = file("${var.dashboards_dir}/${each.value}")
  overwrite   = true
}

output "unknown" {
  description = "Dashboard files whose folder key is not a team or folders key. platform/ refuses to plan while any exist."
  value       = local.unknown
}

output "dashboard_uids" {
  value = { for f, d in grafana_dashboard.this : f => d.uid }
}

# Alert rules, contact points and data sources: export/export.py writes them
# as Terraform into export/out/. Review, then move the .tf files into platform/.
