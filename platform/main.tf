data "grafana_cloud_stack" "this" {
  provider = grafana.cloud
  slug     = var.stack_slug
}

locals {
  # Team keys and folder keys share one namespace: both are folder targets.
  teams = {
    for k, t in var.teams : k => merge(t, {
      selector = coalesce(t.selector, "{${var.label_key}=\"${coalesce(t.label_value, k)}\"}")
    })
  }
  all_folders = merge(var.folders, var.exported_folders)

  # Every folder UID by key: team folders plus the tree below them.
  # Exported alert rule files reference this as local.folder_uids["<key>"].
  folder_uids = merge(module.teams.folder_uids, module.folders.folder_uids)

  persona_unknown_keys = distinct(flatten([
    for p in values(var.personas) : concat(
      [for k in p.folder_keys : k if !contains(concat(keys(var.teams), keys(local.all_folders)), k)],
      [for t in p.assign_to_teams : t if !contains(keys(var.teams), t)],
    )
  ]))
}

# Hard stops before anything is created.
resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = length(setintersection(keys(var.teams), keys(local.all_folders))) == 0
      error_message = "A folders key repeats a team key. Keys must be unique across both."
    }
    precondition {
      condition     = length(module.folders.unplaced) == 0
      error_message = "Folders with an unknown parent or deeper than three levels: ${join(", ", module.folders.unplaced)}."
    }
    precondition {
      condition     = length(local.persona_unknown_keys) == 0
      error_message = "personas reference unknown team or folder keys: ${join(", ", local.persona_unknown_keys)}."
    }
    precondition {
      condition     = length(module.content.unknown) == 0
      error_message = "Dashboards under platform/dashboards/ in an unknown folder key: ${join(", ", module.content.unknown)}."
    }
  }
}

# Order matters: teams and access before content.
module "teams" {
  source      = "../modules/teams"
  name_prefix = var.name_prefix
  teams       = local.teams
}

module "folders" {
  source           = "../modules/folders"
  name_prefix      = var.name_prefix
  folders          = local.all_folders
  team_folder_uids = module.teams.folder_uids
}

module "access" {
  source               = "../modules/access"
  name_prefix          = var.name_prefix
  stack                = data.grafana_cloud_stack.this
  teams                = local.teams
  team_ids             = module.teams.team_ids
  per_team_datasources = var.per_team_datasources
}

module "lbac" {
  count       = var.enable_lbac ? 1 : 0
  source      = "../modules/lbac"
  name_prefix = var.name_prefix
  stack       = data.grafana_cloud_stack.this
  teams       = local.teams
  team_ids    = module.teams.team_ids
  team_uids   = module.teams.team_uids
}

module "rbac" {
  source      = "../modules/rbac"
  name_prefix = var.name_prefix
  personas    = var.personas
  folder_uids = local.folder_uids
  team_ids    = module.teams.team_numeric_ids
}

module "labels" {
  source         = "../modules/labels"
  name_prefix    = var.name_prefix
  label_key      = var.label_key
  required       = var.required_labels
  datasource_uid = var.hygiene_datasource_uid
}

module "content" {
  source         = "../modules/content"
  dashboards_dir = "${path.root}/dashboards"
  folder_uids    = local.folder_uids
}

module "sso" {
  count         = var.sso == null ? 0 : 1
  source        = "../modules/sso"
  settings      = var.sso
  client_secret = var.sso_client_secret
}

# The stack's default data sources read every series. Lock them to Admins so
# teams only query through their label-scoped data sources.
resource "grafana_data_source_permission" "defaults" {
  for_each        = var.lock_default_datasources ? var.default_datasource_uids : {}
  datasource_uid  = each.key
  datasource_type = each.value

  permissions {
    built_in_role = "Admin"
    permission    = "Query"
  }
}
