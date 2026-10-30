terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "folders" {
  description = "Key to {title, parent}. Parent is a team key or another key here."
  type = map(object({
    title  = string
    parent = string
  }))
}

variable "team_folder_uids" {
  type = map(string)
}

# Nested folders inherit permissions from their parent, so no permission
# resources here: the team folder's grant covers the whole subtree.
#
# One resource per depth: a resource cannot depend on its own instances,
# and Grafana rejects a child created before its parent.
locals {
  depth1 = { for k, f in var.folders : k => f if contains(keys(var.team_folder_uids), f.parent) }
  depth2 = { for k, f in var.folders : k => f if contains(keys(local.depth1), f.parent) }
  depth3 = { for k, f in var.folders : k => f if contains(keys(local.depth2), f.parent) }
  placed = merge(local.depth1, local.depth2, local.depth3)
}

resource "grafana_folder" "depth1" {
  for_each          = local.depth1
  title             = each.value.title
  uid               = "${var.name_prefix}-${each.key}"
  parent_folder_uid = var.team_folder_uids[each.value.parent]
}

resource "grafana_folder" "depth2" {
  for_each          = local.depth2
  title             = each.value.title
  uid               = "${var.name_prefix}-${each.key}"
  parent_folder_uid = grafana_folder.depth1[each.value.parent].uid
}

resource "grafana_folder" "depth3" {
  for_each          = local.depth3
  title             = each.value.title
  uid               = "${var.name_prefix}-${each.key}"
  parent_folder_uid = grafana_folder.depth2[each.value.parent].uid
}

output "folder_uids" {
  value = merge(
    { for k, f in grafana_folder.depth1 : k => f.uid },
    { for k, f in grafana_folder.depth2 : k => f.uid },
    { for k, f in grafana_folder.depth3 : k => f.uid },
  )
}

output "unplaced" {
  description = "Folder keys with an unknown parent or deeper than three levels."
  value       = setsubtract(keys(var.folders), keys(local.placed))
}
