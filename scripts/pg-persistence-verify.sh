#!/usr/bin/env bash
# T-06 持久化验证：注册 → push → pull → 重启服务 → login → pull 仍在。
# FakeSyncStore 时代重启即丢；PG 时代必须存活。
set -u
B=http://127.0.0.1:8080
EMAIL="pg-persist-$(date +%s)@local.test"

R=$(curl -s -X POST $B/auth/register -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"pw-123\"}")
echo "register: $R"
TOKEN=$(echo "$R" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "token=${TOKEN:0:8}..."

NOW=$(date +%s%3N)
echo "push:"
curl -s -X POST $B/sync/batch -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d "{\"patches\":[{\"id\":\"p-1\",\"createdAt\":$NOW,\"fields\":{\"content\":{\"v\":\"persist-check\",\"t\":$NOW}}}]}"
echo
echo "pull before restart:"
curl -s "$B/sync?cursor=0" -H "authorization: Bearer $TOKEN"
echo

echo "== restart service =="
systemctl restart diary-sync
sleep 3

R2=$(curl -s -X POST $B/auth/login -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"pw-123\"}")
NEWT=$(echo "$R2" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "login after restart token=${NEWT:0:8}... (body: $R2)"
echo "pull after restart:"
curl -s "$B/sync?cursor=0" -H "authorization: Bearer $NEWT"
echo
