# dashboards/

One subfolder per folder key: a team key or a `folders` key. Each `*.json` lands in that folder.

    dashboards/
      payments/checkout.json
      payments-slo/latency-slo.json

Fill it with `export/export.py`. Empty is valid: nothing is created. A subfolder with an
unknown key fails the plan.
