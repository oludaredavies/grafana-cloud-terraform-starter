# Default path: the stack already exists (Grafana provisioning creates paid stacks). Look it up.
data "grafana_cloud_stack" "this" {
  count = var.create_stack ? 0 : 1
  slug  = var.stack_slug
}

# Optional path: create it here.
resource "grafana_cloud_stack" "this" {
  count             = var.create_stack ? 1 : 0
  name              = coalesce(var.stack_name, var.stack_slug)
  slug              = var.stack_slug
  region_slug       = var.region_slug
  delete_protection = var.delete_protection

  lifecycle {
    precondition {
      condition     = var.region_slug != null
      error_message = "Set region_slug when create_stack = true."
    }
  }
}

# The resource and the data source have different object types, so pick per attribute.
locals {
  created = one(grafana_cloud_stack.this)
  found   = one(data.grafana_cloud_stack.this)
  stack = {
    for k in ["id", "slug", "url", "region_slug", "prometheus_url", "prometheus_user_id", "logs_url", "logs_user_id", "otlp_url"] :
    k => tostring(var.create_stack ? local.created[k] : local.found[k])
  }
}

# The Admin service account platform/ authenticates with. Created through the
# Cloud API, so nobody has to click through the new stack's UI first.
resource "grafana_cloud_stack_service_account" "terraform" {
  count      = var.bootstrap_service_account ? 1 : 0
  stack_slug = local.stack.slug
  name       = "terraform"
  role       = "Admin"
}

resource "grafana_cloud_stack_service_account_token" "terraform" {
  count              = var.bootstrap_service_account ? 1 : 0
  stack_slug         = local.stack.slug
  service_account_id = grafana_cloud_stack_service_account.terraform[0].id
  name               = "terraform"
  seconds_to_live    = var.service_account_token_ttl_seconds > 0 ? var.service_account_token_ttl_seconds : null
}
