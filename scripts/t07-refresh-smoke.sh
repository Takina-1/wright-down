#!/usr/bin/env bash
# T-07/T-08 冒烟：register → pull → refresh → pull → 过期 → refresh 重试。
set -u
B=http://127.0.0.1:8080
EMAIL="pg-refresh-smoke-$(date +%s)@local.test"

R=$(curl -s -X POST $B/auth/register -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"pw-123\"}")
echo "register: $R"
ACCESS=$(echo "$R" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
REFRESH=$(echo "$R" | grep -o '"refreshToken":"[^"]*"' | cut -d'"' -f4)
echo "access=${ACCESS:0:8}... refresh=${REFRESH:0:8}..."

echo "pull with access:"
curl -s "$B/sync?cursor=0" -H "authorization: Bearer $ACCESS" | head -c 120; echo

echo "refresh:"
R2=$(curl -s -X POST $B/auth/refresh -H 'content-type: application/json' \
  -d "{\"refreshToken\":\"$REFRESH\"}")
echo "$R2"
NEW_ACCESS=$(echo "$R2" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
NEW_REFRESH=$(echo "$R2" | grep -o '"refreshToken":"[^"]*"' | cut -d'"' -f4)
echo "new-access=${NEW_ACCESS:0:8}... new-refresh=${NEW_REFRESH:0:8}..."

echo "pull with new access:"
curl -s "$B/sync?cursor=0" -H "authorization: Bearer $NEW_ACCESS" | head -c 120; echo

echo "old refresh token 作废（应 401）:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST $B/auth/refresh \
  -H 'content-type: application/json' -d "{\"refreshToken\":\"$REFRESH\"}"

echo "== 过期测试：把 access expires_at 设为过去 =="
set -a; . /etc/diary-sync/pg.env; set +a; export PGPASSWORD=$PG_PASSWORD
psql -h 127.0.0.1 -U diary -d diary_sync -c \
  "UPDATE tokens SET expires_at = now() - interval '1 day' WHERE token = '$NEW_ACCESS';" > /dev/null 2>&1
echo "过期 access pull（应 401）:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$B/sync?cursor=0" -H "authorization: Bearer $NEW_ACCESS"
echo "过期 access refresh 重试（用新 refresh 换新 access）:"
R3=$(curl -s -X POST $B/auth/refresh -H 'content-type: application/json' \
  -d "{\"refreshToken\":\"$NEW_REFRESH\"}")
echo "$R3" | head -c 120; echo
FINAL=$(echo "$R3" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "pull with refreshed access:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$B/sync?cursor=0" -H "authorization: Bearer $FINAL"

echo "== 冒烟完成 =="
