# Offline wiring test. No network, no tokens: both providers are mocked.
#   cd platform && terraform init -backend=false && terraform test

mock_provider "grafana" {
  alias = "cloud"

  mock_data "grafana_cloud_stack" {
    defaults = {
      id                 = "100001"
      slug               = "acmeprod"
      url                = "https://acmeprod.grafana.net"
      region_slug        = "prod-eu-west-2"
      prometheus_url     = "https://prometheus.example.invalid"
      prometheus_user_id = 1
      logs_url           = "https://logs.example.invalid"
      logs_user_id       = 2
      otlp_url           = "https://otlp.example.invalid"
    }
  }
}

mock_provider "grafana" {
  mock_data "grafana_role" {
    defaults = {
      uid = "fixed-explorer-uid"
    }
  }

  mock_data "grafana_team" {
    defaults = {
      id       = "1:900"
      team_id  = 900
      team_uid = "scim-team-uid"
    }
  }
}

variables {
  cloud_access_policy_token     = "test-not-a-token"
  grafana_service_account_token = "test-not-a-token"
  stack_slug                    = "acmeprod"
  name_prefix                   = "acme"

  teams = {
    platform = { display_name = "Platform", idp_group_ids = ["grafana-platform"] }
    payments = { display_name = "Payments", selector = "{namespace=~\"payments-.*\"}" }
    web      = { display_name = "Web", externally_managed = true }
  }

  folders = {
    payments-services = { title = "Services", parent = "payments" }
    payments-slo      = { title = "SLOs", parent = "payments-services" }
    payments-deep     = { title = "Deep", parent = "payments-slo" }
  }

  personas = {
    "alert-author" = {
      description     = "Alert rules in the Payments tree."
      folder_keys     = ["payments", "payments-slo"]
      folder_actions  = ["folders:read", "alert.rules:write"]
      datasource_uids = ["acme-payments-prom"]
      assign_to_teams = ["payments"]
    }
  }
}

run "day_one_rbac_and_lbac" {
  command = apply

  assert {
    condition     = length(module.teams.folder_uids) == 3 && module.teams.folder_uids["payments"] == "acme-payments"
    error_message = "One locked folder per team, UID <prefix>-<key>."
  }

  assert {
    condition     = local.folder_uids["payments-deep"] == "acme-payments-deep"
    error_message = "Three-level folder tree resolves into local.folder_uids."
  }

  assert {
    condition     = local.teams["platform"].selector == "{team=\"platform\"}" && local.teams["payments"].selector == "{namespace=~\"payments-.*\"}"
    error_message = "Default selector is label_key=key; a team selector overrides it."
  }

  assert {
    condition     = module.access.team_datasource_uids["web"].logs == "acme-web-loki"
    error_message = "Per-team data sources exist for SCIM teams too."
  }

  assert {
    condition     = module.lbac[0].datasource_uids["metrics"] == "acme-lbac-prom" && module.lbac[0].datasource_uids["logs"] == "acme-lbac-loki"
    error_message = "LBAC metrics and logs data sources on by default."
  }

  assert {
    condition     = jsondecode(module.lbac[0].rules_json["metrics"])["scim-team-uid"][0] == "{ team=\"web\" }"
    error_message = "LBAC rules keyed by team UID, SCIM team included."
  }

  assert {
    condition     = length(grafana_data_source_permission.defaults) == 2
    error_message = "Stack default data sources locked to Admins."
  }
}

run "explore_per_persona" {
  command = apply

  variables {
    personas = {
      "alert-author" = {
        description     = "Default explore."
        folder_keys     = ["payments"]
        folder_actions  = ["folders:read"]
        assign_to_teams = ["payments"]
      }
      "engineer" = {
        description     = "Explore only."
        assign_to_teams = ["platform"]
      }
      "dashboard-reader" = {
        description     = "No explore."
        folder_keys     = ["web"]
        folder_actions  = ["dashboards:read"]
        assign_to_teams = ["web"]
        explore         = false
      }
    }
  }

  assert {
    condition     = join(",", module.rbac.explore_teams) == "payments,platform"
    error_message = "explore defaults true, false keeps the team off fixed:datasources:explorer."
  }
}

run "lbac_off_and_defaults_open" {
  command = plan

  variables {
    enable_lbac              = false
    lock_default_datasources = false
  }

  assert {
    condition     = length(module.lbac) == 0 && length(grafana_data_source_permission.defaults) == 0
    error_message = "Both switches turn their resources off."
  }
}

run "bad_prefix_rejected" {
  command = plan

  variables {
    name_prefix = "Acme_Corp"
  }

  expect_failures = [var.name_prefix]
}

run "orphan_folder_flagged" {
  command = plan

  variables {
    folders = {
      lost = { title = "Lost", parent = "nobody" }
    }
    personas = {}
  }

  expect_failures = [terraform_data.guards]
}

run "folder_key_clash_rejected" {
  command = plan

  variables {
    folders = {
      web = { title = "Clash", parent = "platform" }
    }
    personas = {}
  }

  expect_failures = [terraform_data.guards]
}

run "persona_unknown_folder_rejected" {
  command = plan

  variables {
    folders = {}
  }

  expect_failures = [terraform_data.guards]
}
