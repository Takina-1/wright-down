#!/usr/bin/env bash
# 生成测试专用 CA 与 localhost 服务器证书。
#
# 用途：tls_trust_test.dart 起一个本地 TLS 服务器，验证客户端的 Dart 侧
# 信任锚点确实生效（dart:io 不读 network_security_config.xml）。
#
# 与生产 CA 完全无关：生产 CA 私钥在 deploy/certs/ca.key（gitignore、
# 不入库、不上服务器）。本目录的私钥仅供自动化测试使用。
#
# 用法：bash client/test/fixtures/tls/generate.sh
set -euo pipefail

# Git Bash 会把 openssl -subj 的 "/CN=..." 误转成 Windows 路径。
export MSYS_NO_PATHCONV=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

rm -f ./*.crt ./*.key ./*.csr ./*.srl ./*.ext

echo "==> 生成测试 CA"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout test_ca.key -out test_ca.crt -subj "/CN=Test Diary CA"

echo "==> 生成 localhost 服务器证书"
openssl req -newkey rsa:2048 -nodes \
    -keyout test_server.key -out test_server.csr -subj "/CN=localhost"
cat > test_server.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EOF
openssl x509 -req -in test_server.csr \
    -CA test_ca.crt -CAkey test_ca.key -CAcreateserial \
    -out test_server.crt -days 3650 -extfile test_server.ext

echo "==> 校验证书链"
openssl verify -CAfile test_ca.crt test_server.crt
openssl x509 -in test_server.crt -noout -subject -ext subjectAltName

rm -f test_server.csr test_server.ext test_ca.srl
echo "==> 完成：${DIR}"
