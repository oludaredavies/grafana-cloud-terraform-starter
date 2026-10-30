output "folder_uids" {
  description = "Folder UID by key. Exported alert rules reference local.folder_uids."
  value       = local.folder_uids
}

output "team_datasources" {
  description = "Per-team data source UIDs. Use these in export/ds-map.json."
  value       = module.access.team_datasource_uids
}

output "lbac_datasources" {
  description = "Shared LBAC data source UIDs, if enable_lbac."
  value       = var.enable_lbac ? module.lbac[0].datasource_uids : null
}

output "collector_write_tokens" {
  description = "Per-team write tokens for collectors. Read with: terraform output -json collector_write_tokens"
  value       = module.access.write_tokens
  sensitive   = true
}

output "endpoints" {
  description = "Write endpoints for collectors."
  value = {
    prometheus_remote_write = data.grafana_cloud_stack.this.prometheus_remote_write_endpoint
    prometheus_user_id      = data.grafana_cloud_stack.this.prometheus_user_id
    logs_url                = data.grafana_cloud_stack.this.logs_url
    logs_user_id            = data.grafana_cloud_stack.this.logs_user_id
    otlp_url                = data.grafana_cloud_stack.this.otlp_url
  }
}

output "label_contract" {
  value = module.labels.contract
}
