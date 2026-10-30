terraform {
  required_providers {
    grafana = { source = "grafana/grafana" }
  }
}

variable "name_prefix" {
  type = string
}

variable "label_key" {
  type = string
}

variable "required" {
  description = "Other mandatory labels, name to meaning."
  type        = map(string)
}

variable "datasource_uid" {
  description = "An unfiltered metrics data source, so the rule can see unlabelled series."
  type        = string
}

# The label contract. Access control keys on label_key, so it is mandatory.
# Set these in the collector (external labels or a relabel stage), not by hand.
# Converge duplicates (e.g. Team, team_name, squad) to these names in the
# collector before data leaves it.
locals {
  contract = merge(var.required, {
    (var.label_key) = "Owning team. Mandatory. Drives data access."
  })
}

resource "grafana_folder" "platform" {
  title = "Platform hygiene"
  uid   = "${var.name_prefix}-hygiene"
}

# Fires when any scrape target arrives without the team label.
resource "grafana_rule_group" "label_hygiene" {
  name             = "label-hygiene"
  folder_uid       = grafana_folder.platform.uid
  interval_seconds = 300

  rule {
    name           = "Data arriving without a ${var.label_key} label"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "{{ $labels.job }} sends series with no ${var.label_key} label. Nobody can see it on a per-team data source."
    }

    labels = {
      severity = "warning"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasource_uid

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        refId   = "A"
        expr    = "count by (job) (up{${var.label_key}=\"\"})"
        instant = true
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        refId      = "B"
        type       = "reduce"
        expression = "A"
        reducer    = "last"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        conditions = [{ evaluator = { type = "gt", params = [0] } }]
      })
    }
  }
}

output "contract" {
  value = local.contract
}
