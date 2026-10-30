output "stack" {
  description = "Endpoints the platform root and your collectors need."
  value       = local.stack
}

output "service_account_token" {
  description = "Admin token for platform/. Read with: export TF_VAR_grafana_service_account_token=$(terraform output -raw service_account_token)"
  value       = var.bootstrap_service_account ? grafana_cloud_stack_service_account_token.terraform[0].key : null
  sensitive   = true
}
