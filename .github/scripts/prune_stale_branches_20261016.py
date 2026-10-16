#!/usr/bin/env python3
"""One-off conservative pruning of snapshot-listed old VTT remote branches.

The index and branch snapshot are written to main before this is run.
Never delete main, open pull-request heads, the pending #118 data-safety work,
new/unrecorded refs, or a ref whose SHA changed since the snapshot.
Stale unique changes worth retaining are tagged before branch deletion.
"""
import base64
import concurrent.futures
import datetime as dt
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = "francesco-bufalini/VTT"
BASE = "https://api.github.com/repos/" + REPO
TOKEN = os.environ.get("GH_TOKEN", "")
CUTOFF = dt.datetime.fromisoformat("2026-10-12T14:24:06+00:00")
SNAPSHOT = pathlib.Path("docs/history/vtt-branch-snapshot-2026-10-16.json")
LOG = "docs/history/vtt-branch-prune-result-2026-10-16.md"
PROTECTED = {"main", "fix/safe-sync-homebrew-documents"}
ARCHIVE = {
    "refactor/vtt-geometry-boundaries-20261009": "pr-9-geometry",
    "refactor/structured-mechanics-class-tables-20261012": "pr-52-structured-mechanics",
    "fix/creature-gui-localization-captions-20261012": "pr-64-gui-localization",
    "refactor/compact-creature-core-20261013": "pr-87-creature-refactor",
    "backup/campaign-hub-before-context-menu-cleanup-20261004": "kaos-backup-exclusive",
    "test/bonus-cycle-performance-20261011": "bonus-cycle-performance",
}

def request(method, path, body=None):
    url = BASE + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "VTT-prune-20261016",
            **({"Content-Type": "application/json"} if data is not None else {}),
        },
    )
    with urllib.request.urlopen(req, timeout=35) as rsp:
        payload = rsp.read()
        return json.loads(payload) if payload else None

def pages(path):
    out = []
    page = 1
    while True:
        chunk = request("GET", path + ("&" if "?" in path else "?") + "per_page=100&page=" + str(page))
        if not isinstance(chunk, list):
            raise ValueError("Expected paged list response")
        out.extend(chunk)
        if len(chunk) < 100:
            return out
        page += 1

def commit_date(sha):
    data = request("GET", "/git/commits/" + sha)
    value = data["committer"]["date"]
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))

def ensure_archive(branch, sha):
    tag = "archive/2026-10-16/" + ARCHIVE[branch]
    ref = "refs/tags/" + tag
    try:
        request("POST", "/git/refs", {"ref": ref, "sha": sha})
        return tag
    except urllib.error.HTTPError as exc:
        if exc.code != 422:
            raise
        existing = request("GET", "/git/ref/tags/" + urllib.parse.quote(tag, safe="/"))
        if existing.get("object", {}).get("sha") != sha:
            raise ValueError("Archive tag already exists at a different commit: " + tag)
        return tag

def write_log(rows, summaries):
    text = [
        "# Pulizia branch remoti VTT, 16 ottobre 2026", "",
        "Soglia deterministica: `2026-10-12 14:24:06 UTC` (16:24 ora italiana).",
        "Eta valutata sulla data dell'ultimo commit; SHA e nomi confrontati con lo snapshot.",
        "Branch con PR aperte, main, #118, modificati dopo lo snapshot o recenti: mai cancellati.", "",
    ]
    for kind, records in summaries.items():
        text += [f"## {kind} ({len(records)})", ""]
        text += records if records else ["Nessuno."]
        text += [""]
    text += ["## Dettaglio dei branch esaminati", "", "| Branch | SHA | Commit UTC | Esito |", "|---|---|---|---|"]
    for row in rows:
        text.append("| `" + row["name"] + "` | `" + row["sha"][:12] + "` | " + row["date"] + " | " + row["status"] + " |")
    payload = "\n".join(text) + "\n"
    encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
    request("PUT", "/contents/" + LOG, {
        "message": "docs: record verified stale branch cleanup results",
        "content": encoded,
        "branch": "main",
    })

def main():
    if not TOKEN:
        raise RuntimeError("GH_TOKEN missing")
    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    expected = {item["name"]: item["sha"] for item in snapshot["branches"]}
    branches = pages("/branches")
    open_prs = pages("/pulls?state=open")
    protected = PROTECTED | {
        p["head"]["ref"] for p in open_prs
        if p.get("head", {}).get("repo", {}).get("full_name") == REPO
    }
    changes = []
    for entry in branches:
        name, sha = entry["name"], entry["commit"]["sha"]
        if name not in expected:
            continue   # never touch branches created since the inventory
        if sha != expected[name]:
            continue   # never touch a branch that changed since the inventory
        if name in protected or entry.get("protected"):
            continue
        changes.append((name, sha))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        dates = list(pool.map(lambda item: commit_date(item[1]), changes))
    statuses = {"Eliminati": [], "Conservati e archiviati": [], "Saltati": [], "Errori": []}
    rows = []
    for (name, sha), date in zip(changes, dates):
        utc = date.astimezone(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        status = ""
        if date >= CUTOFF:
            status = "Conservato: recente"
        else:
            try:
                tag = ensure_archive(name, sha) if name in ARCHIVE else ""
                if tag:
                    statuses["Conservati e archiviati"].append(f"- `{name}` => `{tag}` (`{sha}`)")
                # Confirm the ref still points to the snapshot SHA before DELETE.
                current = request("GET", "/git/ref/heads/" + urllib.parse.quote(name, safe="/"))
                if current.get("object", {}).get("sha") != sha:
                    status = "Saltato: SHA cambiato"
                else:
                    request("DELETE", "/git/refs/heads/" + urllib.parse.quote(name, safe="/"))
                    status = "Eliminato" + (" (tag: " + tag + ")" if tag else "")
                    statuses["Eliminati"].append(f"- `{name}` — `{sha}`")
            except Exception as exc:
                status = "Errore: " + str(exc).replace("|", "/")
                statuses["Errori"].append(f"- `{name}`: {status}")
        if status.startswith("Conservato") or status.startswith("Saltato"):
            statuses["Saltati"].append(f"- `{name}`: {status}")
        rows.append({"name": name, "sha": sha, "date": utc, "status": status})
        print(name, "=>", status, flush=True)
    write_log(rows, statuses)
    print("Total examined:", len(rows), "deleted:", len(statuses["Eliminati"]), "errors:", len(statuses["Errori"]))
    if statuses["Errori"]:
        sys.exit(1)

if __name__ == "__main__":
    main()
