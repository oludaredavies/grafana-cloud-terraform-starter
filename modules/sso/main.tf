terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "settings" {
  type = object({
    provider_name         = string
    client_id             = string
    auth_url              = optional(string)
    token_url             = optional(string)
    api_url               = optional(string)
    scopes                = optional(string)
    allowed_groups        = optional(string)
    groups_attribute_path = optional(string)
    role_attribute_path   = optional(string)
    allow_sign_up         = optional(bool)
    skip_org_role_sync    = optional(bool)
  })
}

variable "client_secret" {
  type      = string
  sensitive = true
}

# OAuth2 SSO on the stack. SAML and LDAP: configure in the UI or extend here.
# Team sync maps the groups claim to grafana_team.team_sync groups
# (modules/teams). With SCIM, the IdP pushes users and teams instead.
resource "grafana_sso_settings" "this" {
  provider_name = var.settings.provider_name

  oauth2_settings {
    name                  = var.settings.provider_name
    client_id             = var.settings.client_id
    client_secret         = var.client_secret
    auth_url              = var.settings.auth_url
    token_url             = var.settings.token_url
    api_url               = var.settings.api_url
    scopes                = var.settings.scopes
    allowed_groups        = var.settings.allowed_groups
    groups_attribute_path = var.settings.groups_attribute_path
    role_attribute_path   = var.settings.role_attribute_path
    allow_sign_up         = var.settings.allow_sign_up
    skip_org_role_sync    = var.settings.skip_org_role_sync
    enabled               = true
  }

  lifecycle {
    precondition {
      condition     = var.client_secret != null
      error_message = "Set TF_VAR_sso_client_secret."
    }
  }
}
