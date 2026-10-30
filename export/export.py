#!/usr/bin/env python3
"""Pull ONLY the keep list from a source stack (your trial or PoC) into this repo.

Read-only against the source: GET requests only. Python 3.8+, standard library only.

    export SOURCE_URL=https://<trial>.grafana.net
    export SOURCE_TOKEN=<service account token on the trial; tested with Admin>
    python3 export/export.py              # reads export/keep.txt and export/ds-map.json

Writes:
    platform/dashboards/<folder-key>/<slug>.json      dashboards, data source UIDs rewritten
    platform/exported-folders.auto.tfvars.json        folder tree, picked up by terraform
    export/out/alerts-<folder-key>.tf                 grafana_rule_group resources
    export/out/contact-points.tf                      grafana_contact_point resources
    export/out/datasources.tf                         grafana_data_source resources
    export/out/exported-secrets.tf                    one variable per redacted secret

Review export/out/*.tf, then move them into platform/. Secrets: TF_VAR_<name>.
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DASH_DIR = os.path.join(ROOT, "platform", "dashboards")
FOLDERS_FILE = os.path.join(ROOT, "platform", "exported-folders.auto.tfvars.json")
OUT = os.path.join(HERE, "out")

# Data sources and folders every stack provisions for itself. They exist on the new stack already.
PROVISIONED_DS_PREFIX = "grafanacloud-"
PROVISIONED_FOLDERS = ("grafanacloud",)


def die(msg):
    sys.exit("export: " + msg)


def slug(text, limit=24):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (s[:limit].rstrip("-")) or "x"


def ident(text):
    s = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return s if s and not s[0].isdigit() else "x_" + s


class Source(object):
    def __init__(self, url, token):
        self.url = url.rstrip("/")
        self.token = token

    def get(self, path, raw=False):
        req = urllib.request.Request(self.url + path, headers={"Authorization": "Bearer " + self.token})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            raise RuntimeError("GET %s -> %s" % (path, e.code))
        return body if raw else json.loads(body)


def q(v):
    return urllib.parse.quote(v, safe="")


def hcl_escape(s):
    # Terraform interpolates ${ and %{ inside strings; exported text must stay literal.
    return s.replace("${", "$${").replace("%{", "%%{")


class Exporter(object):
    def __init__(self, src, ds_map):
        self.src = src
        self.ds_map = ds_map
        self.folders = {}          # key -> {title, parent}
        self.secrets = []          # (var name, description)
        self.skipped = 0
        self.files = []

    # ---- data source UID rewrite --------------------------------------------
    # ds-map.json values: a UID for every folder, or {"<folder key>": uid, "*": uid}
    # so each team's content lands on that team's data source.

    def mapping(self, key):
        out = {}
        for old, new in self.ds_map.items():
            if isinstance(new, dict):
                new = new.get(key, new.get("*"))
            if new:
                out[old] = new
        return out

    def rewrite_json(self, node, m):
        if isinstance(node, dict):
            out = {}
            for k, v in node.items():
                if k in ("uid", "datasource") and isinstance(v, str) and v in m:
                    out[k] = m[v]
                else:
                    out[k] = self.rewrite_json(v, m)
            return out
        if isinstance(node, list):
            return [self.rewrite_json(v, m) for v in node]
        return node

    def rewrite_text(self, text, key):
        for old, new in self.mapping(key).items():
            text = text.replace('"%s"' % old, '"%s"' % new).replace('\\"%s\\"' % old, '\\"%s\\"' % new)
        return text

    # ---- folders --------------------------------------------------------------

    def find_folder(self, title):
        hits = [f for f in self.src.get("/api/search?type=dash-folder&query=" + q(title))
                if f.get("title", "").lower() == title.lower()]
        if len(hits) != 1:
            raise LookupError("folder %r: %d exact matches" % (title, len(hits)))
        return hits[0]["uid"]

    def new_key(self, title):
        base = slug(title)
        key, n = base, 2
        while key in self.folders:
            key = "%s-%d" % (base[:21], n)
            n += 1
        return key

    def export_folder_tree(self, parent_key, uid, title, depth=1):
        if depth == 1 and title.lower() in PROVISIONED_FOLDERS:
            print("SKIP  folder %s: provisioned on every stack, with the same dashboard UIDs" % title)
            self.skipped += 1
            return
        if depth > 3:
            print("SKIP  folder %s: deeper than three levels below a team folder" % title)
            self.skipped += 1
            return
        key = self.new_key(title)
        self.folders[key] = {"title": title, "parent": parent_key}
        print("OK    folder %s -> key %s (parent %s)" % (title, key, parent_key))
        for d in self.src.get("/api/search?type=dash-db&folderUIDs=" + q(uid)):
            self.export_dashboard(key, d["uid"], d["title"])
        for child in self.src.get("/api/folders?parentUid=" + q(uid) + "&limit=1000"):
            self.export_folder_tree(key, child["uid"], child["title"], depth + 1)

    # ---- dashboards -----------------------------------------------------------

    def export_dashboard(self, key, uid, title):
        got = self.src.get("/api/dashboards/uid/" + q(uid))
        if got.get("meta", {}).get("provisioned"):
            # Stack or app provisioned (GrafanaCloud, Asserts, SLO apps): the new stack
            # provisions its own copy under the same UID, and the API refuses to overwrite it.
            print("SKIP  dashboard %s: provisioned on the source stack" % title)
            self.skipped += 1
            return
        dash = got["dashboard"]
        for k in ("id", "version"):
            dash.pop(k, None)
        dash = self.rewrite_json(dash, self.mapping(key))
        os.makedirs(os.path.join(DASH_DIR, key), exist_ok=True)
        path = os.path.join(DASH_DIR, key, slug(title, 60) + ".json")
        with open(path, "w") as f:
            json.dump(dash, f, indent=2, sort_keys=True)
            f.write("\n")
        print("OK    dashboard %s -> platform/dashboards/%s/%s" % (title, key, os.path.basename(path)))

    def dashboard_by_title(self, key, title):
        hits = [d for d in self.src.get("/api/search?type=dash-db&query=" + q(title))
                if d.get("title", "").lower() == title.lower()]
        if len(hits) != 1:
            raise LookupError("dashboard %r: %d exact matches" % (title, len(hits)))
        self.export_dashboard(key, hits[0]["uid"], hits[0]["title"])

    # ---- alert rules ------------------------------------------------------------

    def export_alerts(self, key, spec):
        folder_title, _, group = spec.partition("/")
        fuid = self.find_folder(folder_title)
        if group:
            path = "/api/v1/provisioning/folder/%s/rule-groups/%s/export?format=hcl" % (q(fuid), q(group))
        else:
            path = "/api/v1/provisioning/alert-rules/export?folderUid=%s&format=hcl" % q(fuid)
        text = self.src.get(path, raw=True)
        text = re.sub(r'(?m)^\s*org_id\s*=.*\n', "", text)
        text = re.sub(r'folder_uid\s*=\s*"%s"' % re.escape(fuid), 'folder_uid = local.folder_uids["%s"]' % key, text)
        text = re.sub(r'resource "grafana_rule_group" "([^"]+)"',
                      lambda m: 'resource "grafana_rule_group" "%s_%s"' % (ident(key), ident(m.group(1))), text)
        text = self.rewrite_text(text, key)
        name = "alerts-%s.tf" % key
        self.write_out(name, text, append=True)
        print("OK    alerts %s -> export/out/%s" % (spec, name))

    # ---- contact points -------------------------------------------------------

    def export_contact_point(self, name):
        text = self.src.get("/api/v1/provisioning/contact-points/export?format=hcl&name=" + q(name), raw=True)
        if "grafana_contact_point" not in text:
            raise LookupError("contact point %r not found" % name)
        rid = ident(name)
        text = re.sub(r'(?m)^\s*org_id\s*=.*\n', "", text)
        text = re.sub(r'resource "grafana_contact_point" "[^"]+"', 'resource "grafana_contact_point" "%s"' % rid, text)
        counter = [0]

        def secret(m):
            counter[0] += 1
            var = "cp_%s_secret_%d" % (rid, counter[0])
            self.secrets.append((var, "Contact point %s, field %s" % (name, m.group(1))))
            return "%s = var.%s" % (m.group(1), var)

        text = re.sub(r'(\w+)\s*=\s*"\[REDACTED\]"', secret, text)
        self.write_out("contact-points.tf", text, append=True)
        print("OK    contact point %s -> export/out/contact-points.tf (%d secret(s) as variables)" % (name, counter[0]))

    # ---- data sources ---------------------------------------------------------

    def export_datasource(self, uid):
        if uid.startswith(PROVISIONED_DS_PREFIX):
            print("SKIP  data source %s: provisioned on every stack; map it in ds-map.json" % uid)
            return
        ds = self.src.get("/api/datasources/uid/" + q(uid))
        rid = ident(ds["name"])
        new_uid = self.mapping("*").get(uid, uid)
        lines = ['resource "grafana_data_source" "%s" {' % rid,
                 '  name = %s' % json.dumps(hcl_escape(ds["name"])),
                 '  type = %s' % json.dumps(ds["type"]),
                 '  uid  = %s' % json.dumps(new_uid)]
        if ds.get("url"):
            lines.append('  url  = %s' % json.dumps(hcl_escape(ds["url"])))
        if ds.get("access") and ds["access"] != "proxy":
            lines.append('  access_mode = %s' % json.dumps(ds["access"]))
        if ds.get("isDefault"):
            lines.append('  is_default = true')
        if ds.get("basicAuth"):
            lines.append('  basic_auth_enabled  = true')
            lines.append('  basic_auth_username = %s' % json.dumps(hcl_escape(ds.get("basicAuthUser", ""))))
        if ds.get("database"):
            lines.append('  database_name = %s' % json.dumps(hcl_escape(ds["database"])))
        if ds.get("user"):
            lines.append('  username = %s' % json.dumps(hcl_escape(ds["user"])))
        if ds.get("jsonData"):
            lines.append('  json_data_encoded = jsonencode(%s)' % hcl_escape(json.dumps(ds["jsonData"], indent=2, sort_keys=True)).replace("\n", "\n  "))
        secure = sorted(k for k, v in (ds.get("secureJsonFields") or {}).items() if v)
        if secure:
            pairs = []
            for k in secure:
                var = "ds_%s_%s" % (rid, ident(k))
                self.secrets.append((var, "Data source %s, secureJsonData.%s" % (ds["name"], k)))
                pairs.append("    %s = var.%s" % (json.dumps(k), var))
            lines.append("  secure_json_data_encoded = jsonencode({\n%s\n  })" % "\n".join(pairs))
        lines.append("}")
        self.write_out("datasources.tf", "\n".join(lines) + "\n", append=True)
        print("OK    data source %s -> export/out/datasources.tf (%d secret(s) as variables)" % (ds["name"], len(secure)))

    # ---- output ---------------------------------------------------------------

    def write_out(self, name, text, append=False):
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name)
        mode = "a" if append and name in self.files else "w"
        with open(path, mode) as f:
            f.write(text if text.endswith("\n") else text + "\n")
            f.write("\n")
        if name not in self.files:
            self.files.append(name)

    def finish(self):
        if self.folders:
            with open(FOLDERS_FILE, "w") as f:
                json.dump({"exported_folders": self.folders}, f, indent=2, sort_keys=True)
                f.write("\n")
            print("OK    %d folder(s) -> platform/exported-folders.auto.tfvars.json" % len(self.folders))
        if self.secrets:
            body = "".join(
                'variable "%s" {\n  description = %s\n  type        = string\n  sensitive   = true\n}\n\n' % (v, json.dumps(d))
                for v, d in self.secrets)
            self.write_out("exported-secrets.tf", "# Set each with TF_VAR_<name>. Never in a file.\n\n" + body)
            print("NOTE  %d secret(s) did not leave the source. Set TF_VAR_ for each in export/out/exported-secrets.tf" % len(self.secrets))
        print("Done. %d item(s) skipped. Review every file before terraform plan." % self.skipped)


def main():
    url, token = os.environ.get("SOURCE_URL"), os.environ.get("SOURCE_TOKEN")
    if not url or not token:
        die("set SOURCE_URL and SOURCE_TOKEN")
    keep = os.environ.get("KEEP_FILE", os.path.join(HERE, "keep.txt"))
    map_file = os.path.join(HERE, "ds-map.json")
    ds_map = json.load(open(map_file)) if os.path.exists(map_file) else {}

    # A fresh run replaces earlier output rather than appending to it.
    if os.path.isdir(OUT):
        for name in os.listdir(OUT):
            if name.endswith(".tf"):
                os.remove(os.path.join(OUT, name))

    ex = Exporter(Source(url, token), ds_map)
    for n, line in enumerate(open(keep), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 3:
            die("keep.txt line %d: want <kind>|<folder key>|<name>" % n)
        kind, key, name = parts
        try:
            if kind == "dashboard":
                ex.dashboard_by_title(key, name)
            elif kind == "folder":
                ex.export_folder_tree(key, ex.find_folder(name), name)
            elif kind == "alerts":
                ex.export_alerts(key, name)
            elif kind == "contact_point":
                ex.export_contact_point(name)
            elif kind == "datasource":
                ex.export_datasource(name)
            else:
                die("keep.txt line %d: unknown kind %r" % (n, kind))
        except (LookupError, RuntimeError) as e:
            print("SKIP  %s" % e)
            ex.skipped += 1
    ex.finish()


if __name__ == "__main__":
    main()
