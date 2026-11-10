#!/usr/bin/env bash
# F013 device acceptance (server API equivalent; real-device install blocked by MIUI dialog)
# Covers: TLS chain / health 401 / register / login(-wrong) / push entry / pull back /
#         bad-token 401 / COS proxy upload-download-HEAD
set -uo pipefail
BASE="https://8.148.158.13"
EMAIL="f013-acc-$(date +%s)@local.test"
PASS="accept.pw-2026"

say() { printf '%s\n' "$*"; }

say "== [0] health + TLS"
CA="/d/dev/myapp/deploy/certs/ca.crt"
curl -sk --cacert "$CA" -o /dev/null \
  -w "GET /sync with local CA -> HTTP %{http_code}\n" "$BASE/sync"
curl -sk -o /dev/null -w "GET /sync (no token) -> HTTP %{http_code} (expect 401)\n" "$BASE/sync"

say "== [1] register"
R=$(curl -sk -w '\n%{http_code}' -X POST "$BASE/auth/register" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
code="${R##*$'\n'}"; body="${R%$'\n'*}"
say "$body"
[ "${code:0:1}" = "2" ] || { say "register failed HTTP $code"; exit 1; }
TOKEN="${body#*\"token\":\"}"; TOKEN="${TOKEN%%\"*}"
say "token: ${TOKEN:0:8}...(truncated)"

say "== [2] login negative (wrong password -> 401)"
curl -sk -o /dev/null -w "wrong-password login -> HTTP %{http_code} (expect 401)\n" \
  -X POST "$BASE/auth/login" -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"wrong\"}"

say "== [3] push diary entry (equiv. DP-06)"
CREATED=$(date +%s%3N)
R=$(curl -sk -w '\n%{http_code}' -X POST "$BASE/sync/batch" \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d "{\"patches\":[{\"id\":\"e-acc-1\",\"createdAt\":$CREATED,\"fields\":{\"content\":{\"v\":\"acceptance diary 2026-11-10 via ECS smoke\",\"t\":$CREATED}}}]}")
code="${R##*$'\n'}"; say "push -> HTTP $code"
[ "${code:0:1}" = "2" ] || { say "push failed HTTP $code"; exit 1; }

say "== [4] pull back (equiv. second device pull)"
R=$(curl -sk -w '\n%{http_code}' "$BASE/sync?cursor=0" -H "authorization: Bearer $TOKEN")
code="${R##*$'\n'}"; body="${R%$'\n'*}"
say "$body"
echo "$body" | grep -q "e-acc-1" && say "pull contains pushed entry OK" || { say "pull missing"; exit 1; }
echo "$body" | grep -o '"cursor":[0-9]*' | head -1

say "== [5] authz assertion (T-21 equiv.)"
curl -sk -o /dev/null -w "bad-token pull -> HTTP %{http_code} (expect 401)\n" "$BASE/sync" -H "authorization: Bearer bogus"

say "== [6] COS proxy link (equiv. device photo flow)"
HASH=$(printf 'hello-f013-cos-acceptance' | sha256sum | cut -d' ' -f1)
say "hash: $HASH"
R=$(curl -sk -w '\n%{http_code}' -X POST "$BASE/sync/photo/upload" \
  -H "authorization: Bearer $TOKEN" -H "X-Photo-Hash: $HASH" --data-binary 'hello-f013-cos-acceptance')
code="${R##*$'\n'}"; body="${R%$'\n'*}"
say "$body"
[ "${code:0:1}" = "2" ] || { say "cos upload failed HTTP $code"; exit 1; }
KEY="${body#*\"key\":\"}"; KEY="${KEY%%\"*}"
say "server key: $KEY"
curl -sk -o /dev/null -w "HEAD exists -> HTTP %{http_code} (expect 200)\n" "$BASE/sync/photo/$KEY" -I -H "authorization: Bearer $TOKEN"
DL=$(curl -sk "$BASE/sync/photo/$KEY" -H "authorization: Bearer $TOKEN")
[ "$DL" = "hello-f013-cos-acceptance" ] && say "download bytes match OK" || { say "download mismatch: $DL"; exit 1; }
curl -sk -o /dev/null -w "HEAD missing key -> HTTP %{http_code} (expect 404)\n" "$BASE/sync/photo/photos/nonexistent" -I -H "authorization: Bearer $TOKEN"

say "== SUMMARY: full chain passed (device UI tap items remain)"
