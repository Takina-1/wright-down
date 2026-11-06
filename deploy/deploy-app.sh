#!/usr/bin/env bash
# 在服务器上部署 F013 同步服务：拉代码 → 装依赖 → 静态检查 → 测试 → 编译 → 装服务 → 启动。
# 幂等：重复执行安全。
#
# 用法：bash deploy-app.sh [仓库地址] [分支]
set -euo pipefail

REPO="${1:-https://github.com/Takina-1/wright-down.git}"
BRANCH="${2:-feat/F013-cloud-sync}"

APP_DIR=/opt/diary-sync
SRC_DIR="${APP_DIR}/src"
RUN_USER=diary

log() { printf '\n==> %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "必须以 root 运行" >&2; exit 1; }

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=/opt/dart-sdk/bin:$PATH

log "拉取代码（${BRANCH}）"
if [[ -d "${SRC_DIR}/.git" ]]; then
    git -C "${SRC_DIR}" fetch --all --prune
    git -C "${SRC_DIR}" checkout "${BRANCH}"
    git -C "${SRC_DIR}" pull --ff-only origin "${BRANCH}"
else
    mkdir -p "${APP_DIR}"
    git clone --branch "${BRANCH}" "${REPO}" "${SRC_DIR}"
fi

log "安装依赖"
cd "${SRC_DIR}/packages/server"
dart pub get

log "静态检查"
dart analyze

log "跑测试"
dart test

log "编译可执行文件"
mkdir -p "${APP_DIR}/bin"
dart compile exe bin/server.dart -o "${APP_DIR}/bin/server"
chown -R "${RUN_USER}:${RUN_USER}" "${APP_DIR}"

log "安装 systemd 单元"
install -m 644 "${SRC_DIR}/deploy/diary-sync.service" /etc/systemd/system/diary-sync.service
install -d -m 755 /etc/diary-sync
[[ -f /etc/diary-sync/server.env ]] || echo "PORT=8080" > /etc/diary-sync/server.env
chmod 644 /etc/diary-sync/server.env
systemctl daemon-reload
systemctl enable diary-sync
systemctl restart diary-sync

log "健康检查"
sleep 3
curl -sS -o /dev/null -w "本机 8080 返回 %{http_code}\n" "http://127.0.0.1:8080/sync?cursor=0"
systemctl is-active --quiet diary-sync && echo "diary-sync 运行中" || { echo "diary-sync 未运行" >&2; exit 1; }

log "完成"
