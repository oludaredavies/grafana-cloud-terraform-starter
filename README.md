# Grafana Cloud Terraform starter

Move from a trial or PoC stack to production, selectively, with RBAC and LBAC from day one.
Security and labelling first, content second.
Provider `grafana/grafana` ~> 4.50, Terraform >= 1.7, Python 3.8+ for the export.

Status: tested live on a fresh stack (30-10-2026): create, apply, migrate from a source stack,
no drift, destroy and re-apply, per-team access, and LBAC for metrics and logs passed with a Viewer in one team. Offline tests pass.

## Layout

| Path | What it does |
|---|---|
| `stack/` | Looks up the production stack, or creates it. Mints the Admin service account token `platform/` uses. |
| `platform/` | Root you apply. Wires the modules below. |
| `modules/teams` | Teams from your IdP (team sync, or SCIM lookup). One locked folder per team. |
| `modules/folders` | Folder tree under the team folders, three levels. Permissions inherit. |
| `modules/access` | Per team: label-scoped read policy, token, metrics and logs data sources. Per team collector write token. |
| `modules/lbac` | Shared metrics and logs data sources with one LBAC rule per team. |
| `modules/rbac` | Custom roles per persona, scoped to folders and data sources. Explore per persona (`explore`, default true). |
| `modules/labels` | Label contract. Alert on data arriving without the team label. |
| `modules/content` | Dashboards from `platform/dashboards/<folder-key>/*.json`. |
| `modules/sso` | Optional OAuth2 SSO: Okta, Entra ID, Google, generic. |
| `export/` | Pulls only your keep list from the trial into this repo. |
| `examples/` | `stack.tfvars.example`, `platform.tfvars.example`. |
| `*/tests/` | Offline `terraform test` with mocked providers. No tokens needed. |

## Tokens

Environment variables only. Never in a file, never in tfvars.

| Variable | What | Scopes or role |
|---|---|---|
| `TF_VAR_cloud_access_policy_token` | Cloud access policy token, org level | `stacks:read`, `stack-service-accounts:write`, `accesspolicies:read`, `accesspolicies:write`, `accesspolicies:delete`; plus `stacks:write`, `stacks:delete` to create a stack |
| `TF_VAR_grafana_service_account_token` | Stack service account | Admin. `stack/` outputs one |
| `TF_VAR_sso_client_secret` | OAuth2 client secret | Only if `sso` is set |
| `SOURCE_URL`, `SOURCE_TOKEN` | Trial stack, for `export/` | Service account, Admin (we tested with Admin) |

## Apply order

1. `stack/`: `cp examples/stack.tfvars.example stack/terraform.tfvars`, edit, `terraform init`, `plan`, `apply`.
2. `export TF_VAR_grafana_service_account_token=$(terraform -chdir=stack output -raw service_account_token)`
3. `platform/`: `cp examples/platform.tfvars.example platform/terraform.tfvars`, edit. Apply with no dashboards first:
   teams, folders, roles, data sources, LBAC rules, label alert.
4. Point collectors at the new stack with each team's write token (`terraform output -json collector_write_tokens`).
   Stamp the team label. Watch the label alert go quiet.
5. Export from the trial (below). Apply the content.
6. `terraform plan` shows no changes. Retire the trial.

Every apply: `terraform plan -out plan.tfplan`, read it, `terraform apply plan.tfplan`.

## Move from your trial

1. List what moves in `export/keep.txt`: dashboards, folder trees, alert rule folders or groups,
   contact points, data sources. Anything not listed stays behind. That is the point.
2. After step 3 above: `terraform output team_datasources`, then write `export/ds-map.json`
   (trial data source UID to new UID). Start from `ds-map.example.json`. A value can be a map
   by folder key (`"*"` for the rest), so each team's dashboards and rules land on its own data source.
   The trial's `GrafanaCloud` folder and any provisioned dashboard are skipped: every stack has its own.
3. `SOURCE_URL=https://<trial>.grafana.net SOURCE_TOKEN=... python3 export/export.py`
4. Dashboards land in `platform/dashboards/`, the folder tree in `platform/exported-folders.auto.tfvars.json`.
   Alert rules, contact points and data sources land in `export/out/*.tf`. Review, move them into `platform/`.
5. Secrets never leave the trial. Each becomes a variable in `exported-secrets.tf`: set `TF_VAR_<name>`.
6. `terraform test -test-directory=migration-tests` in `platform/`, then plan, review, apply.

## Access model

- People: shared LBAC data sources. One rule per team, its label selector.
- Alerts and automation: per-team data sources. The token carries the selector, so Grafana Cloud
  enforces it for every caller. Point alert rules here.
- A team's selector defaults to `{<label_key>="<team key>"}`. Override with `selector`,
  e.g. `{namespace=~"payments-.*"}` or `{cluster="prod-eu"}`.
- The stack's own `grafanacloud-*` data sources read everything. Locked to Admins.
- Team folders are authoritative: owning team plus Admins. Subfolders inherit.
- Plugin install stays with org Admins. Keep Admin with the platform team.
- SSO: set `sso` (OAuth2), or configure SAML in the UI. With SCIM, set `externally_managed = true`
  on the team and apply after the first SCIM push.
- Private connectivity (PrivateLink, Private Service Connect) is not in this starter.

## Remote state

State holds access policy tokens. Use a backend with encryption and locking. Uncomment one in
`stack/versions.tf` and `platform/versions.tf`, separate keys per root:

    backend "s3"      { bucket = "...", key = "grafana/platform.tfstate", region = "...", encrypt = true, use_lockfile = true }   # use_lockfile: Terraform 1.10+
    backend "azurerm" { resource_group_name = "...", storage_account_name = "...", container_name = "tfstate", key = "grafana/platform.tfstate" }
    backend "gcs"     { bucket = "...", prefix = "grafana/platform" }

Terraform Cloud, Spacelift and similar runners: leave the backend block out and let the runner
hold state; set the tokens as secret environment variables in the runner.

## Tests

    terraform -chdir=stack init -backend=false && terraform -chdir=stack test
    terraform -chdir=platform init -backend=false && terraform -chdir=platform test

Mocked providers: no network, no tokens. They prove wiring, guards and keys, not API behaviour.
`plan` against the real stack is the real test.

Live test, 30-10-2026, on a throwaway stack: `stack/` created it and its token; `platform/` applied
63 resources; an export from a trial (two folders, a dashboard, a rule group, a contact point, two
data sources) applied 7 more; `plan` then showed no changes. `destroy` and re-apply: 70 and 70,
no changes after. Per-team tokens returned only that team's series, metrics and logs.

Traps we hit building this: `GOTCHAS.md`. Driving the repo with a coding agent: `AGENTS.md`.
