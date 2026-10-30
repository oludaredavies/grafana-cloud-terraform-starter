terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "stack" {
  type = any
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

variable "team_uids" {
  type = map(string)
}

# ---------------------------------------------------------------------------
# Shared LBAC data sources: one metrics, one logs, every team queries them and
# sees only its own selector. For people browsing and Explore.
#
# Caveats:
#   1. LBAC filters by team membership. Field tests: service accounts and
#      Grafana-managed alert rules were not filtered. Use the per-team data
#      sources (modules/access) for alerts and automation.
#   2. The rules API replaces the whole rule set on every write. Exactly one
#      grafana_data_source_config_lbac_rules per data source.
#   3. The stack's own grafanacloud-* data sources are read-only and reject
#      LBAC writes. That is why this module creates its own.
#   4. LBAC supports Prometheus/Mimir and Loki, not Tempo.
#   5. Only teams in var.teams get Query here, and each has a rule.
# ---------------------------------------------------------------------------

resource "grafana_cloud_access_policy" "this" {
  name         = "${var.name_prefix}-lbac-read"
  display_name = "Shared LBAC read"
  region       = var.stack.region_slug
  scopes       = ["metrics:read", "logs:read"]

  realm {
    type       = "stack"
    identifier = var.stack.id
  }
}

resource "grafana_cloud_access_policy_token" "this" {
  name             = "${var.name_prefix}-lbac-read"
  region           = var.stack.region_slug
  access_policy_id = grafana_cloud_access_policy.this.policy_id
}

locals {
  sources = {
    metrics = { type = "prometheus", url = "${var.stack.prometheus_url}/api/prom", user = var.stack.prometheus_user_id, suffix = "prom", json = { httpMethod = "POST" } }
    logs    = { type = "loki", url = var.stack.logs_url, user = var.stack.logs_user_id, suffix = "loki", json = {} }
  }
}

resource "grafana_data_source" "this" {
  for_each            = local.sources
  name                = "Shared ${each.key} (LBAC)"
  uid                 = "${var.name_prefix}-lbac-${each.value.suffix}"
  type                = each.value.type
  url                 = each.value.url
  basic_auth_enabled  = true
  basic_auth_username = tostring(each.value.user)
  json_data_encoded   = jsonencode(each.value.json)

  secure_json_data_encoded = jsonencode({
    basicAuthPassword = grafana_cloud_access_policy_token.this.token
  })
}

# The API stores a selector as `{ <matchers> }`, spaces inside the braces.
# Send it in that form or every plan shows a change.
locals {
  rule_selectors = {
    for k, t in var.teams : k => "{ ${trimspace(trimsuffix(trimprefix(trimspace(t.selector), "{"), "}"))} }"
  }
}

# One resource for the whole rule set (caveat 2). Team UID to selectors.
resource "grafana_data_source_config_lbac_rules" "this" {
  for_each       = local.sources
  datasource_uid = grafana_data_source.this[each.key].uid
  rules = jsonencode({
    for k, t in var.teams : var.team_uids[k] => [local.rule_selectors[k]]
  })
}

resource "grafana_data_source_permission" "this" {
  for_each        = local.sources
  datasource_uid  = grafana_data_source.this[each.key].uid
  datasource_type = each.value.type

  dynamic "permissions" {
    for_each = var.team_ids
    content {
      team_id    = permissions.value
      permission = "Query"
    }
  }

  # The rules land before any team can query.
  depends_on = [grafana_data_source_config_lbac_rules.this]
}

output "datasource_uids" {
  value = { for k, d in grafana_data_source.this : k => d.uid }
}

output "rules_json" {
  value = { for k, r in grafana_data_source_config_lbac_rules.this : k => r.rules }
}
