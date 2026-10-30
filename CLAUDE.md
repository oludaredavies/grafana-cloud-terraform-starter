# Agent guide: Grafana Cloud Terraform starter

You are working in a Terraform repo that manages a Grafana Cloud production stack.
Read `README.md` for the model and `GOTCHAS.md` before changing a module.

## Layout

- `stack/`: stack lookup or create, bootstrap Admin service account token. Apply first.
- `platform/`: the root that applies `modules/*`. Apply second.
- `modules/`: teams, folders, access, lbac, rbac, labels, content, sso.
- `export/export.py`: read-only pull from the trial stack, driven by `export/keep.txt`.
- `examples/*.tfvars.example`: copy to `<root>/terraform.tfvars` and edit.

## Apply order

1. `stack/` plan and apply.
2. `platform/` with no dashboards: teams, folders, roles, data sources, LBAC.
3. Collectors on the new stack, team label stamped.
4. `export/export.py`, review `export/out/*.tf`, move into `platform/`, plan, apply.

## Exporting from the trial

- Edit `export/keep.txt` only with what the user names. Never export everything.
- Map data source UIDs in `export/ds-map.json` from `terraform output team_datasources`.
- Run `python3 export/export.py` with `SOURCE_URL` and `SOURCE_TOKEN` already in the environment.
- Then `terraform test -test-directory=migration-tests` in `platform/`.

## Guard rails

- Never `terraform apply` without a saved plan the user has read: `plan -out plan.tfplan`, show
  the summary, wait for a yes, then `apply plan.tfplan`. Production applies always need a human.
- Never `terraform destroy` or `-target` on production unless the user asks in those words.
- State is remote. Never create local state for production; never commit `*.tfstate`.
- Secrets come from environment variables (`TF_VAR_*`, `SOURCE_TOKEN`). Never write a token to a
  file, a tfvars file, a commit or your output. Never print `terraform output -json` of sensitive values.
- Run `terraform fmt -recursive`, `terraform validate` and `terraform test` in both roots before
  proposing a change.
- A plan that replaces a team, folder or data source loses its permissions and history. Stop and ask.
- Keep `name_prefix`, team keys and folder keys stable: UIDs derive from them.
