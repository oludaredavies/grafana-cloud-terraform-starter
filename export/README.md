# export/

Moves only what you list from the trial to this repo. Read-only: GET requests only.

1. Service account token on the trial. We tested with Admin.
2. Edit `keep.txt`. Kinds: dashboard, folder (tree), alerts (folder or folder/group), contact_point, datasource.
3. After `platform/` is applied: `terraform output team_datasources`, write `ds-map.json`
   (trial UID to new UID) from `ds-map.example.json`. A value may be `{"<folder key>": uid, "*": uid}`.
4. `SOURCE_URL=https://<trial>.grafana.net SOURCE_TOKEN=... python3 export/export.py`
5. Dashboards land in `platform/dashboards/<key>/`, folders in `platform/exported-folders.auto.tfvars.json`.
   Rules, contact points, data sources land in `out/*.tf`; secrets as variables in `out/exported-secrets.tf`.
6. Review, move `out/*.tf` into `platform/`, set `TF_VAR_` for each secret,
   `terraform test -test-directory=migration-tests`, plan, apply.

Each run replaces `out/*.tf`. Anything not on the keep list stays with the trial.
