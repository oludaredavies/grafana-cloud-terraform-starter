# Gotchas

Symptom, cause, fix. Found building and testing this repo, offline and on a live stack
(30-10-2026). Entries marked (expected) are known product behaviour we have not reproduced
in this repo's own tests yet.

## Stack data sources reject LBAC rules

- Symptom: `403 Cannot update read-only data source` writing LBAC rules to `grafanacloud-prom` or `grafanacloud-logs`.
- Cause: the stack provisions its own data sources read-only.
- Fix: `modules/lbac` creates its own metrics and logs data sources on the same tenant and puts the rules there.

## LBAC does not cover alert rules or service accounts

- Symptom: an alert rule or automation on an LBAC data source sees every team's data.
- Cause: LBAC filters by the user's team membership. Live test: a service account querying the LBAC data sources saw every team's series. Field tests: Grafana-managed alert rules were not filtered either.
- Fix: point alert rules and automation at the per-team data sources (`modules/access`). Their token carries the selector, enforced for any caller.

## LBAC rules are a full replace

- Symptom: rules for one team vanish after another team's change.
- Cause: the API replaces the whole rule set on every write.
- Fix: exactly one `grafana_data_source_config_lbac_rules` per data source, all teams in it. Never add a second.

## Exported secrets come back redacted

- Symptom: contact point export shows `"[REDACTED]"`; data source export lists `secureJsonFields` with no values.
- Cause: the source stack never returns secrets.
- Fix: `export.py` turns each into a variable in `exported-secrets.tf`. Set `TF_VAR_<name>`. A missing one fails at plan, by design.

## Stack-provisioned data sources do not export

- Symptom: `SKIP data source grafanacloud-prom`.
- Cause: every stack provisions its own `grafanacloud-*` sources; copying them would collide.
- Fix: map the trial UID to the new stack's UID in `export/ds-map.json`. Dashboards and rules are rewritten on export.

## PDC data sources need PDC on the new stack (expected)

- Symptom: an exported data source has `pdcInjected = true` in its JSON data.
- Cause: it reaches a private network through Private Data Source Connect on the trial.
- Fix: set up a PDC network and agent on the new stack before applying that data source.

## A persona naming an unknown folder

- Symptom (before the fix): `Invalid index ... var.folder_uids[pair[1]]` deep in `modules/rbac`.
- Cause: a persona's `folder_keys` or `assign_to_teams` named a key that is not a team or folder.
- Fix: `platform/` checks every persona key up front and names the bad ones.

## Dashboards in an unknown folder key

- Symptom (before the fix): dashboards under `platform/dashboards/<dir>/` silently not created.
- Cause: `<dir>` matched no team or folders key.
- Fix: plan now fails and lists the files. Rename the directory or add the key.

## check blocks only warn

- Symptom: a bad folder parent or key clash planned anyway, with a warning.
- Cause: Terraform `check` blocks never fail a plan, and `terraform test` cannot expect failures from a check inside a module.
- Fix: guards are `precondition`s on `terraform_data.guards` in `platform/main.tf`.

## Folder UIDs collide

- Symptom (before the fix): a team keyed `platform` clashed with the label hygiene folder.
- Cause: both used `<prefix>-platform`.
- Fix: the hygiene folder is `<prefix>-hygiene`. Team and folders keys share one namespace; plan rejects a repeat.

## SCIM teams do not exist yet (expected)

- Symptom: `grafana_team` data source not found at plan.
- Cause: `externally_managed = true` looks the team up by name; the IdP has not pushed it yet.
- Fix: run the first SCIM push, check the team name matches `display_name` exactly, then plan.

## Team sync on a plan without it (expected)

- Cause: team sync is an Enterprise feature; not every Cloud plan includes it.
- Fix: leave `idp_group_ids` empty; the module then sends no team sync block.

## Metrics data sources return 404

- Symptom (before the fix): every query on a per-team or LBAC metrics data source: `404 page not found`.
- Cause: the stack's `prometheus_url` is the bare host. The query API is under `/api/prom`.
- Fix: both modules append `/api/prom`. Loki needs no suffix.

## LBAC rules show a change on every plan

- Symptom (before the fix): `{team="web"}` -> `{ team="web" }` on `grafana_data_source_config_lbac_rules` after every apply.
- Cause: the API stores selectors with a space inside each brace.
- Fix: `modules/lbac` sends them in that form. Several matchers: write them `a="x", b="y"`.

## Trial GrafanaCloud dashboards collide

- Symptom (before the fix): exporting the trial's `GrafanaCloud` folder wrote Usage Insights and Cardinality dashboards whose UIDs the new stack already has, provisioned.
- Cause: every stack provisions that folder and those dashboards itself; provisioned dashboards cannot be overwritten.
- Fix: `export.py` skips the `GrafanaCloud` folder and any dashboard the source marks provisioned.

## One data source map for every team

- Symptom (before the fix): `grafanacloud-prom` mapped to one team's data source, so every other team's migrated dashboards queried a source they cannot read.
- Cause: `ds-map.json` was one UID per trial UID.
- Fix: a value can be `{"<folder key>": "<uid>", "*": "<uid>"}`. Content under each folder key gets its own team's source.

## LBAC as a team member needs a real user

- Symptom: no headless way to prove LBAC filtering for a person.
- Cause: Grafana Cloud users come from grafana.com or SSO; `POST /api/admin/users` returns 403 to a service account, and service accounts are not filtered.
- Fix: sign in as a non-Admin user in one team and query the LBAC source in Explore. The per-team data sources need no such test: the token enforces the selector for any caller.
- Tested 30-10-2026: passed for metrics and logs. A Viewer in one team, with Explore, saw only that team's series on both LBAC sources.

## Team members are not in Terraform

- Symptom: no `members` on `grafana_team`; a new user sees no team data.
- Cause: membership comes from the IdP (team sync or SCIM); `ignore_externally_synced_members = true`. A grafana.com user appears in the stack only after first sign-in.
- Fix: with SSO, add the user to the IdP group. Without SSO, add them after first sign-in: Administration > Teams, or `POST /api/teams/<id>/members` with `{"userId": n}`. Test with a Viewer in one team: that is the case we proved.

## Org role of a grafana.com-invited user cannot be changed in the stack
- Symptom: PATCH /api/org/users/<id> returns 403 `org.externallySynced` "cannot change role for externally synced user".
- Cause: users invited through the grafana.com org get their stack role from the grafana.com org membership.
- Fix: set the role at grafana.com (Org > Members), or use SSO/SCIM role mapping. Test LBAC with a Viewer in one team: that is the case we proved.
- Timing: the stack picks up a grafana.com role change only at a fresh grafana.com sign-in. An open session keeps the old role (tested 30-10-2026: changed 12:20, still Editor at 12:36, Viewer after log out and in).

## Viewers get no Explore; team Query is not enough

- Symptom: a Viewer in Payments could not open Explore, though the team has Query on its data sources (live, 30-10-2026).
- Cause: Viewers lack `datasources:explore` by default. Data source Query permission does not add it.
- Fix: each persona has `explore` (default true). Its teams get `fixed:datasources:explorer` via `grafana_role_assignment_item`. Set `explore = false` for exec and read-only personas. A team with no persona gets no Explore: give it one, like `engineer` in examples/.
