# Offline test of both stack paths. No network, no tokens.
#   cd stack && terraform init -backend=false && terraform test

mock_provider "grafana" {
  mock_data "grafana_cloud_stack" {
    defaults = {
      id                 = "100001"
      slug               = "acmeprod"
      url                = "https://acmeprod.grafana.net"
      region_slug        = "prod-eu-west-2"
      prometheus_user_id = 1
      logs_user_id       = 2
    }
  }

  mock_resource "grafana_cloud_stack" {
    defaults = {
      id                 = "100002"
      url                = "https://acmetest.grafana.net"
      prometheus_user_id = 3
      logs_user_id       = 4
    }
  }
}

variables {
  cloud_access_policy_token = "test-not-a-token"
  stack_slug                = "acmeprod"
}

run "lookup_existing_stack" {
  command = apply

  assert {
    condition     = output.stack.id == "100001" && length(grafana_cloud_stack.this) == 0
    error_message = "Default path looks the stack up and creates nothing."
  }

  assert {
    condition     = length(grafana_cloud_stack_service_account_token.terraform) == 1
    error_message = "Bootstrap Admin token for platform/."
  }
}

run "create_test_stack" {
  command = apply

  variables {
    stack_slug        = "acmetest"
    create_stack      = true
    region_slug       = "prod-eu-west-2"
    delete_protection = false
  }

  assert {
    condition     = output.stack.id == "100002" && output.stack.slug == "acmetest"
    error_message = "Create path returns the created stack."
  }
}

run "create_needs_region" {
  command = plan

  variables {
    create_stack = true
  }

  expect_failures = [grafana_cloud_stack.this]
}
