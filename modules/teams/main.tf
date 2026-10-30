terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "teams" {
  description = "platform/ local.teams: var.teams with selector resolved."
  type = map(object({
    display_name       = string
    idp_group_ids      = list(string)
    externally_managed = bool
    selector           = string
    folder_access      = string
  }))
}

locals {
  managed  = { for k, t in var.teams : k => t if !t.externally_managed }
  external = { for k, t in var.teams : k => t if t.externally_managed }
}

# Membership comes from the IdP (team sync or SCIM), not Terraform.
# Removing a user from the IdP group removes their access at next login.
resource "grafana_team" "this" {
  for_each                         = local.managed
  name                             = each.value.display_name
  ignore_externally_synced_members = true

  # Team sync needs a Grafana Cloud plan that includes it. Empty list: no sync block.
  dynamic "team_sync" {
    for_each = length(each.value.idp_group_ids) > 0 ? [1] : []
    content {
      groups = each.value.idp_group_ids
    }
  }
}

# SCIM-provisioned teams: the IdP creates them. Apply after the first SCIM push.
data "grafana_team" "external" {
  for_each = local.external
  name     = each.value.display_name
}

locals {
  team = merge(
    { for k, t in grafana_team.this : k => { id = t.id, team_id = t.team_id, team_uid = t.team_uid } },
    { for k, t in data.grafana_team.external : k => { id = t.id, team_id = t.team_id, team_uid = t.team_uid } },
  )
}

resource "grafana_folder" "this" {
  for_each = var.teams
  title    = each.value.display_name
  uid      = "${var.name_prefix}-${each.key}"
}

# Authoritative: the default Viewer and Editor grants are removed.
# Only the owning team and org Admins see the folder.
resource "grafana_folder_permission" "this" {
  for_each   = var.teams
  folder_uid = grafana_folder.this[each.key].uid

  permissions {
    team_id    = local.team[each.key].id
    permission = each.value.folder_access
  }

  permissions {
    role       = "Admin"
    permission = "Admin"
  }
}

output "team_ids" {
  value = { for k, t in local.team : k => t.id }
}

output "team_numeric_ids" {
  value = { for k, t in local.team : k => tostring(t.team_id) }
}

output "team_uids" {
  value = { for k, t in local.team : k => t.team_uid }
}

output "folder_uids" {
  value = { for k, f in grafana_folder.this : k => f.uid }
}
