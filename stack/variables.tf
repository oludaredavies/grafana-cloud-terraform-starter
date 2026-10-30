variable "cloud_access_policy_token" {
  description = "Grafana Cloud access policy token. Scopes: stacks:read, stack-service-accounts:write, plus stacks:write and stacks:delete if create_stack = true."
  type        = string
  sensitive   = true
}

variable "stack_slug" {
  description = "Slug of the production stack: <slug>.grafana.net."
  type        = string
}

variable "create_stack" {
  description = "False: look up a stack Grafana already provisioned for you. True: create it here."
  type        = bool
  default     = false
}

variable "stack_name" {
  description = "Display name, used only when create_stack = true. Defaults to the slug."
  type        = string
  default     = null
}

variable "region_slug" {
  description = "Region, used only when create_stack = true, e.g. prod-eu-west-2. List: GET https://grafana.com/api/stack-regions."
  type        = string
  default     = null
}

variable "delete_protection" {
  description = "Blocks stack deletion. Keep true for production. Set false only on a throwaway test stack."
  type        = bool
  default     = true
}

variable "bootstrap_service_account" {
  description = "Create the Admin service account and token that platform/ uses. False if you bring your own."
  type        = bool
  default     = true
}

variable "service_account_token_ttl_seconds" {
  description = "Lifetime of the bootstrap token. 0 means no expiry; rotate by tainting the token resource."
  type        = number
  default     = 0
}
