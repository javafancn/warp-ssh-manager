#!/usr/bin/env bash
# End-to-end JSON IPC test with an isolated fake HOME/config.
# Real ssh settings and the user's databases are never touched.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: native-ui-bridge-smoke.sh /path/to/wsm' >&2; exit 2; }
wsm="$1"
[[ -x "$wsm" ]] || { echo "Missing Rust bridge: $wsm" >&2; exit 1; }
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export WSM_HOME="$fixture/data"
export WSM_SSH_CONFIG="$fixture/.ssh/config"
export WSM_WARP_CONFIG_DIR="$fixture/warp"
mkdir -p "$fixture/.ssh"
"$wsm" ui init >/dev/null
"$wsm" ui add-group '生产环境' >/dev/null
group_id="$("$wsm" ui snapshot | python3 -c 'import json,sys;print(json.load(sys.stdin)["groups"][0]["id"])')"
child_id="$("$wsm" ui add-group '业务服务' --parent "$group_id" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
grandchild_id="$("$wsm" ui add-group '应用接口' --parent "$child_id" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
# Nested groups must survive CLI JSON round trips; reject parent cycles.
if "$wsm" ui update-group "$group_id" '生产环境' --parent "$grandchild_id" >/dev/null 2>&1; then
  echo "FAILED: group cycle was accepted" >&2; exit 1
fi
if "$wsm" ui add-group '业务服务' --parent "$group_id" >/dev/null 2>&1; then
  echo "FAILED: duplicate sibling name was accepted" >&2; exit 1
fi
"$wsm" ui update-group "$child_id" '后端服务' --parent "$group_id"
"$wsm" ui snapshot | python3 -c 'import json,sys;d=json.load(sys.stdin);assert any(g["name"]=="后端服务" and g["parent_id"] is not None for g in d["groups"])'
cat <<JSON | "$wsm" ui save > "$fixture/saved.json"
{"id":null,"name":"vas-app-2","alias":"vas-app-2","hostname":"example.com","username":"ubuntu","port":1622,"identity_file":null,"proxy_jump":null,"group_id":"$child_id","favorite":false,"tags":"api,production","notes":"SSH metadata smoke"}
JSON
id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$fixture/saved.json")"
"$wsm" ui favorite "$id" true
"$wsm" ui snapshot > "$fixture/snapshot.json"
python3 - "$fixture/snapshot.json" "$id" "$child_id" "$group_id" "$grandchild_id" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
id,group,root,grandchild=sys.argv[2:]
groups={g['id']:g for g in data['groups']}
assert groups[group]['parent_id']==root
assert groups[grandchild]['parent_id']==group
assert groups[root]['parent_id'] is None
assert len(data['hosts'])==1
h=data['hosts'][0]
assert h['id']==id and h['port']==1622
assert h['hostname']=='example.com' and h['favorite'] is True
assert h['notes']=='SSH metadata smoke' and h['tags']=='api,production'
assert h['group_id']==group and h['source']=='Managed'
assert data['include_enabled'] is True
print('PASS: JSON host, nested parent IDs, 1622 port, tags, notes, favorite')
PY
"$wsm" ui delete "$id"
"$wsm" ui snapshot | python3 -c 'import sys,json;assert not json.load(sys.stdin)["hosts"]'
echo 'PASS: Delete does not leave stale host state'
if "$wsm" ui delete-group "$group_id" >/dev/null 2>&1; then
  echo "FAILED: deletion of parent with child groups was accepted" >&2; exit 1
fi
"$wsm" ui delete-group "$grandchild_id"
"$wsm" ui delete-group "$child_id"
"$wsm" ui delete-group "$group_id"
echo 'PASS: nested group deletion protection and cleanup'

python3 - "$wsm" <<'PY'
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys

wsm = sys.argv[1]
config = Path(os.environ["WSM_SSH_CONFIG"])
managed = config.parent / "config.d" / "warp-ssh-manager.conf"
warp = Path(os.environ["WSM_WARP_CONFIG_DIR"])

def run(*args, payload=None):
    return subprocess.run(
        [wsm, *args], input=None if payload is None else json.dumps(payload),
        text=True, capture_output=True, check=True,
    )

def ui(*args, payload=None):
    output = run("ui", *args, payload=payload).stdout
    return json.loads(output) if output else None

def preview():
    result = ui("import-preview")
    assert result["config_path"] == str(config)
    return {row["alias"]: row for row in result["candidates"]}

def apply(*rows):
    return ui("import-apply", payload={"candidates": rows})

def hosts():
    return {host["alias"]: host for host in ui("snapshot")["hosts"]}

run("add", "--name", "Managed", "--alias", "wsm-managed", "--hostname", "managed.example.test", "--user", "tester")
group = ui("add-group", "Imported Hosts")["id"]
includes = config.parent / "included files"
includes.mkdir()
child = includes / "child.conf"
nested = includes / "nested.conf"
config.write_text(config.read_text() + f'\nInclude "{child}"\n')
child.write_text(f"Include '{nested}'\nHost MIX mix\nHost *\n")

def write_hosts(port):
    nested.write_text(
        f'Host "import-first"\n HostName first.example.test\n User alice\n Port {port}\n'
        'Host import-first\n HostName ignored.example.test\n'
        'Host=import-second\n HostName second.example.test\n User bob\n'
        'Host import-third\n HostName third.example.test\n User carol\n'
    )

write_hosts(2222)
initial = hosts()
first_preview = preview()
assert {alias: row["status"] for alias, row in first_preview.items()} == {
    "import-first": "new", "import-second": "new", "import-third": "new",
    "MIX": "conflict", "mix": "conflict", "wsm-managed": "managed",
}
assert first_preview["import-first"]["after"]["hostname"] == "first.example.test"
assert first_preview["import-first"]["after"]["username"] == "alice"
assert first_preview["import-first"]["after"]["port"] == 2222
dry_run = run("import", "--dry-run", "--alias", "IMPORT-FIRST", "--alias", "missing")
assert "new\timport-first" in dry_run.stdout and "error\tmissing" in dry_run.stdout
assert "import-second" not in dry_run.stdout
assert hosts() == initial

assert apply(first_preview["import-first"]) == {"added": 1, "updated": 0, "stale_aliases": []}
assert set(hosts()) == {"wsm-managed", "import-first"}
assert preview()["import-first"]["status"] == "unchanged"
host = hosts()["import-first"]
host.update(name="Renamed", group_id=group, favorite=True, auth_mode="password", tags="prod,api", notes="Imported metadata")
ui("save", payload=host)
database = Path(os.environ["WSM_HOME"]) / "hosts.sqlite3"
with sqlite3.connect(database) as db:
    db.execute("UPDATE hosts SET last_connected = 12345 WHERE id = ?", [host["id"]])
    db.commit()
before = hosts()["import-first"]

write_hosts(2223)
changed = preview()
assert changed["import-first"]["status"] == "update"
assert changed["import-first"]["before"]["port"] == 2222
assert changed["import-first"]["after"]["port"] == 2223
write_hosts(2224)
assert apply(changed["import-first"], changed["import-second"]) == {
    "added": 0, "updated": 0, "stale_aliases": ["import-first"],
}
assert hosts()["import-first"] == before and "import-second" not in hosts()

files = [config, managed, child, nested]
contents = [path.read_bytes() for path in files]
changed = preview()
with sqlite3.connect(database) as db:
    db.execute("""
        CREATE TRIGGER fail_import_for_smoke BEFORE UPDATE OF port ON hosts
        WHEN OLD.alias = 'import-first'
        BEGIN SELECT RAISE(ABORT, 'import smoke rollback'); END
    """)
try:
    apply(changed["import-second"], changed["import-first"])
except subprocess.CalledProcessError as failure:
    assert "import smoke rollback" in failure.stderr
else:
    raise AssertionError("expected injected import failure")
finally:
    with sqlite3.connect(database) as db:
        db.execute("DROP TRIGGER fail_import_for_smoke")
assert hosts()["import-first"] == before and "import-second" not in hosts()

assert apply(changed["import-first"]) == {"added": 0, "updated": 1, "stale_aliases": []}
assert hosts()["import-first"] == {**before, "port": 2224}
assert [path.read_bytes() for path in files] == contents
assert not list(warp.glob("*.toml"))

run("import", "--alias", "import-second")
assert apply(changed["import-second"], changed["import-third"]) == {
    "added": 0, "updated": 0, "stale_aliases": ["import-second"],
}
assert "import-third" not in hosts()
repeated = run("import", "--alias", "import-second")
assert "Imported 0 new, updated 0 existing hosts" in repeated.stdout
legacy = run("import")
assert "Imported 1 new, updated 0 existing hosts" in legacy.stdout
assert set(hosts()) == {"wsm-managed", "import-first", "import-second", "import-third"}

nested.write_text(nested.read_text() + "InvalidSmokeTestOption yes\n")
failure = preview()["import-first"]
assert failure["status"] == "error" and "InvalidSmokeTestOption".lower() in failure["detail"].lower()
assert hosts()["import-first"]["port"] == 2224
print("PASS: SSH import preview, selection, staleness, metadata, and CLI compatibility")
PY
