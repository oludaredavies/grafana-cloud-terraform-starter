terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "personas" {
  type = map(object({
    description     = string
    folder_keys     = list(string)
    folder_actions  = list(string)
    datasource_uids = list(string)
    assign_to_teams = list(string)
    explore         = bool
  }))
}

variable "folder_uids" {
  type = map(string)
}

variable "team_ids" {
  type = map(string)
}

# Plugin install: leave it with org Admins (the default). No persona here
# carries a plugins: action, and the Admin role should sit with the platform
# team only. Users and teams get the basic Viewer role plus a persona.

locals {
  role_permissions = {
    for name, p in var.personas : name => concat(
      [
        for pair in setproduct(p.folder_actions, p.folder_keys) : {
          action = pair[0]
          scope  = "folders:uid:${lookup(var.folder_uids, pair[1], "unknown-${pair[1]}")}"
        }
      ],
      [
        for uid in p.datasource_uids : {
          action = "datasources:query"
          scope  = "datasources:uid:${uid}"
        }
      ]
    )
  }
}

resource "grafana_role" "this" {
  for_each     = var.personas
  name         = "custom:${var.name_prefix}:${each.key}"
  display_name = each.key
  description  = each.value.description
  uid          = "${var.name_prefix}-role-${each.key}"
  global       = false

  dynamic "permissions" {
    for_each = local.role_permissions[each.key]
    content {
      action = permissions.value.action
      scope  = permissions.value.scope
    }
  }
}

# Viewers have no datasources:explore, and team Query on a data source does
# not add it. Personas with explore = true put their teams on the fixed role.
# Per-team items, not grafana_role_assignment: that one is authoritative and
# would strip grants made outside Terraform.
locals {
  explore_teams = toset(distinct(flatten([
    for p in values(var.personas) : p.assign_to_teams if p.explore
  ])))
}

data "grafana_role" "explorer" {
  count = length(local.explore_teams) > 0 ? 1 : 0
  name  = "fixed:datasources:explorer"
}

resource "grafana_role_assignment_item" "explore" {
  for_each = local.explore_teams
  role_uid = data.grafana_role.explorer[0].uid
  team_id  = lookup(var.team_ids, each.key, "unknown")
}

resource "grafana_role_assignment" "this" {
  for_each = var.personas
  role_uid = grafana_role.this[each.key].uid
  teams    = [for t in each.value.assign_to_teams : lookup(var.team_ids, t, "unknown")]
}

output "explore_teams" {
  description = "Team keys on fixed:datasources:explorer."
  value       = sort(keys(grafana_role_assignment_item.explore))
}
