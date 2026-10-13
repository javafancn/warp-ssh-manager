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
cat <<JSON | "$wsm" ui save > "$fixture/saved.json"
{"id":null,"name":"vas-app-2","alias":"vas-app-2","hostname":"example.com","username":"ubuntu","port":1622,"identity_file":null,"proxy_jump":null,"group_id":"$group_id","favorite":false,"tags":"api,production","notes":"SSH metadata smoke"}
JSON
id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$fixture/saved.json")"
"$wsm" ui favorite "$id" true
"$wsm" ui snapshot > "$fixture/snapshot.json"
python3 - "$fixture/snapshot.json" "$id" "$group_id" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
id,group=sys.argv[2:]
assert len(data['hosts'])==1
h=data['hosts'][0]
assert h['id']==id and h['port']==1622
assert h['hostname']=='example.com' and h['favorite'] is True
assert h['notes']=='SSH metadata smoke' and h['tags']=='api,production'
assert h['group_id']==group and h['source']=='Managed'
assert data['include_enabled'] is True
print('PASS: JSON host, group, 1622 port, tags, notes, favorite')
PY
"$wsm" ui delete "$id"
"$wsm" ui snapshot | python3 -c 'import sys,json;assert not json.load(sys.stdin)["hosts"]'
echo 'PASS: Delete does not leave stale host state'
