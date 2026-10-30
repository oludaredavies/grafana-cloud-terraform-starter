variable "cloud_access_policy_token" {
  description = "Cloud access policy token: stacks:read, accesspolicies:read, accesspolicies:write, accesspolicies:delete."
  type        = string
  sensitive   = true
}

variable "grafana_service_account_token" {
  description = "Stack service account token with the Admin role. stack/ outputs one."
  type        = string
  sensitive   = true
}

variable "stack_slug" {
  description = "Slug of the production stack."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix for every UID and policy name this repo creates, e.g. your company short name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,11}$", var.name_prefix))
    error_message = "name_prefix: lowercase letters, digits and dashes, 1 to 12 characters. UIDs are capped at 40."
  }
}

variable "label_key" {
  description = "The label every series and log stream must carry. Access is enforced on it unless a team sets its own selector."
  type        = string
  default     = "team"
}

variable "required_labels" {
  description = "Label contract published as an output, beside label_key. Name to meaning."
  type        = map(string)
  default = {
    service = "Service name. Mandatory."
    env     = "prod, staging or dev. Mandatory."
  }
}

variable "teams" {
  description = <<-EOT
    One entry per team. Key is a short lowercase id, also a folder key under dashboards/.
      display_name        Grafana team name (for SCIM teams, the exact name the IdP pushes)
      idp_group_ids       IdP group ids synced to the team (Entra object ids, Okta or Google group names)
      externally_managed  true if SCIM creates the team; Terraform then looks it up by display_name
      label_value         value of var.label_key on this team's data (default: the key)
      selector            full label selector, overrides label_key/label_value, e.g. {namespace=~"pay-.*"}
      folder_access       View or Edit on the team's own folder
  EOT
  type = map(object({
    display_name       = string
    idp_group_ids      = optional(list(string), [])
    externally_managed = optional(bool, false)
    label_value        = optional(string)
    selector           = optional(string)
    folder_access      = optional(string, "Edit")
  }))

  validation {
    condition     = alltrue([for k, _ in var.teams : can(regex("^[a-z][a-z0-9-]{0,23}$", k))])
    error_message = "Team keys: lowercase letters, digits and dashes, up to 24 characters."
  }
}

variable "folders" {
  description = <<-EOT
    Folder tree under the team folders. Key is a short lowercase id, also a folder key under dashboards/.
      title   folder title
      parent  a team key or another folders key. Permissions inherit from the parent.
    Up to three levels below a team folder.
  EOT
  type = map(object({
    title  = string
    parent = string
  }))
  default = {}
}

variable "exported_folders" {
  description = "Written by export/export.py to exported-folders.auto.tfvars.json. Same shape as folders. Do not edit by hand."
  type = map(object({
    title  = string
    parent = string
  }))
  default = {}
}

variable "personas" {
  description = <<-EOT
    Custom roles. Key is the role id.
      description       shown in the UI
      folder_keys       team or folder keys the actions apply to
      folder_actions    RBAC actions scoped to those folders
      datasource_uids   data sources this persona may query
      assign_to_teams   team keys that get the role
      explore           Explore for those teams (fixed:datasources:explorer).
                        Default true. Set false for exec and read-only personas.
  EOT
  type = map(object({
    description     = string
    folder_keys     = optional(list(string), [])
    folder_actions  = optional(list(string), [])
    datasource_uids = optional(list(string), [])
    assign_to_teams = list(string)
    explore         = optional(bool, true)
  }))
  default = {}
}

variable "per_team_datasources" {
  description = "One label-scoped metrics and logs data source per team. Enforced for every caller, alert rules included."
  type        = bool
  default     = true
}

variable "enable_lbac" {
  description = "Shared metrics and logs data sources with LBAC rules per team. For people browsing."
  type        = bool
  default     = true
}

variable "lock_default_datasources" {
  description = "Restrict the stack's own unfiltered data sources to org Admins."
  type        = bool
  default     = true
}

variable "default_datasource_uids" {
  description = "Stack-provisioned data sources that read everything. Type by UID."
  type        = map(string)
  default = {
    grafanacloud-prom = "prometheus"
    grafanacloud-logs = "loki"
  }
}

variable "hygiene_datasource_uid" {
  description = "Unfiltered metrics data source the unlabelled-data alert reads."
  type        = string
  default     = "grafanacloud-prom"
}

variable "sso" {
  description = "Optional OAuth2 SSO (okta, azuread, google, generic_oauth). Null leaves SSO to the UI. See examples/."
  type = object({
    provider_name         = string
    client_id             = string
    auth_url              = optional(string)
    token_url             = optional(string)
    api_url               = optional(string)
    scopes                = optional(string, "openid profile email groups")
    allowed_groups        = optional(string)
    groups_attribute_path = optional(string)
    role_attribute_path   = optional(string)
    allow_sign_up         = optional(bool, true)
    skip_org_role_sync    = optional(bool, false)
  })
  default = null
}

variable "sso_client_secret" {
  description = "OAuth2 client secret. TF_VAR_sso_client_secret only."
  type        = string
  default     = null
  sensitive   = true
}
