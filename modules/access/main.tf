terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "stack" {
  description = "The grafana_cloud_stack data source object."
  type        = any
}

variable "teams" {
  type = map(object({
    display_name = string
    selector     = string
  }))
}

variable "team_ids" {
  type = map(string)
}

variable "per_team_datasources" {
  type = bool
}

# ---------------------------------------------------------------------------
# One data source per team.
#
# Each team's data sources authenticate with a Cloud access policy token whose
# label selector is that team's selector. Mimir and Loki enforce it for ANY
# caller: people, service accounts and Grafana-managed alert rules alike.
# Point alert rules and automation here, not at the LBAC data sources.
# ---------------------------------------------------------------------------

locals {
  read_teams = var.per_team_datasources ? var.teams : {}
}

resource "grafana_cloud_access_policy" "read" {
  for_each     = local.read_teams
  name         = "${var.name_prefix}-${each.key}-read"
  display_name = "${each.value.display_name} read"
  region       = var.stack.region_slug
  scopes       = ["metrics:read", "logs:read"]

  realm {
    type       = "stack"
    identifier = var.stack.id

    label_policy {
      selector = each.value.selector
    }
  }
}

resource "grafana_cloud_access_policy_token" "read" {
  for_each         = local.read_teams
  name             = "${var.name_prefix}-${each.key}-read"
  region           = var.stack.region_slug
  access_policy_id = grafana_cloud_access_policy.read[each.key].policy_id
}

# prometheus_url is the bare host; the query API sits under /api/prom.
resource "grafana_data_source" "metrics" {
  for_each            = local.read_teams
  name                = "${each.value.display_name} metrics"
  uid                 = "${var.name_prefix}-${each.key}-prom"
  type                = "prometheus"
  url                 = "${var.stack.prometheus_url}/api/prom"
  basic_auth_enabled  = true
  basic_auth_username = tostring(var.stack.prometheus_user_id)

  json_data_encoded = jsonencode({
    httpMethod = "POST"
  })

  secure_json_data_encoded = jsonencode({
    basicAuthPassword = grafana_cloud_access_policy_token.read[each.key].token
  })
}

resource "grafana_data_source" "logs" {
  for_each            = local.read_teams
  name                = "${each.value.display_name} logs"
  uid                 = "${var.name_prefix}-${each.key}-loki"
  type                = "loki"
  url                 = var.stack.logs_url
  basic_auth_enabled  = true
  basic_auth_username = tostring(var.stack.logs_user_id)

  secure_json_data_encoded = jsonencode({
    basicAuthPassword = grafana_cloud_access_policy_token.read[each.key].token
  })
}

# Authoritative: only the owning team may query its data sources.
resource "grafana_data_source_permission" "metrics" {
  for_each        = local.read_teams
  datasource_uid  = grafana_data_source.metrics[each.key].uid
  datasource_type = "prometheus"

  permissions {
    team_id    = var.team_ids[each.key]
    permission = "Query"
  }
}

resource "grafana_data_source_permission" "logs" {
  for_each        = local.read_teams
  datasource_uid  = grafana_data_source.logs[each.key].uid
  datasource_type = "loki"

  permissions {
    team_id    = var.team_ids[each.key]
    permission = "Query"
  }
}

# ---------------------------------------------------------------------------
# Collector write tokens: one per team, for that team's collectors.
# The collector must stamp the team's label on everything it sends.
# ---------------------------------------------------------------------------

resource "grafana_cloud_access_policy" "write" {
  for_each     = var.teams
  name         = "${var.name_prefix}-${each.key}-write"
  display_name = "${each.value.display_name} collectors"
  region       = var.stack.region_slug
  scopes       = ["metrics:write", "logs:write", "traces:write"]

  realm {
    type       = "stack"
    identifier = var.stack.id
  }
}

resource "grafana_cloud_access_policy_token" "write" {
  for_each         = var.teams
  name             = "${var.name_prefix}-${each.key}-write"
  region           = var.stack.region_slug
  access_policy_id = grafana_cloud_access_policy.write[each.key].policy_id
}

output "team_datasource_uids" {
  value = {
    for k, _ in local.read_teams : k => {
      metrics = grafana_data_source.metrics[k].uid
      logs    = grafana_data_source.logs[k].uid
    }
  }
}

output "write_tokens" {
  value     = { for k, t in grafana_cloud_access_policy_token.write : k => t.token }
  sensitive = true
}
