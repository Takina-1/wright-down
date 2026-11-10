#!/usr/bin/env bash
# 生成自签 CA 与服务器证书。CA 私钥只留在本机，不上传服务器。
#
# 用法：
#   bash deploy/make-cert.sh                          # 默认为 8.148.158.13
#   bash deploy/make-cert.sh --ip 1.2.3.4 --cn host  # 指定 IP 与 CN
#
# 产物在 deploy/certs/（已 .gitignore）。

set -euo pipefail

HOST_IP="8.148.158.13"
COMMON_NAME="8.148.158.13"
DAYS=3650

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip) HOST_IP="$2"; COMMON_NAME="$2"; shift 2 ;;
        --cn) COMMON_NAME="$2"; shift 2 ;;
        --days) DAYS="$2"; shift 2 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SCRIPT_DIR}/certs"
mkdir -p "${OUT}"
cd "${OUT}"

# T-20：CA-pair guard 同时检查 ca.key 与 ca.crt——上次签发失败
# 可能只留下 ca.key（无 ca.crt）——此时重新生成整套 CA（覆盖残留）。
if [[ ! -f ca.key || ! -f ca.crt ]]; then
    echo "==> 生成 CA（私钥仅存本机）"
    openssl req -x509 -newkey rsa:4096 -nodes -days "${DAYS}" \
        -keyout ca.key -out ca.crt -subj "/CN=Local Diary App CA"
    chmod 600 ca.key
fi

echo "==> 生成服务器证书（SAN: IP:${HOST_IP}）"
openssl req -newkey rsa:2048 -nodes \
    -keyout server.key -out server.csr -subj "/CN=${COMMON_NAME}"
cat > server.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:${HOST_IP}
EOF
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days "${DAYS}" -extfile server.ext
chmod 600 server.key

echo "==> 校验证书链"
openssl verify -CAfile ca.crt server.crt
openssl x509 -in server.crt -noout -subject -ext subjectAltName

echo
echo "产物在 ${OUT}"
echo "  ca.crt     -> 复制到 client/android/app/src/main/res/raw/diary_ca.crt"
echo "  server.key + server.crt -> 上传到服务器 /etc/nginx/ssl/diary-sync/"
echo "  ca.key     -> 留在本机，不要上传"
