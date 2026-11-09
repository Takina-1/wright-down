#!/usr/bin/env bash
# 在服务器上部署 F013 同步服务（仅 Dart 服务本体）：拉代码 → 装依赖 → 静态检查 → 测试 →
# 编译 → 装 systemd 单元 → 启动 → 健康检查。
# 幂等：重复执行安全。
#
# 范围说明：本脚本**不含 TLS 入口**。nginx 配置与证书需另行安装，见
# deploy/阿里云部署-aliyun-deploy.md（证书由开发机签发后上传，CA 私钥永不上服务器）。
#
# 用法：bash deploy-app.sh [仓库地址] [分支]
set -euo pipefail

REPO="${1:-https://github.com/Takina-1/wright-down.git}"
BRANCH="${2:-feat/F013-cloud-sync}"

APP_DIR=/opt/diary-sync
SRC_DIR="${APP_DIR}/src"
RUN_USER=diary
STATE_DIR=/var/lib/diary-sync

log() { printf '\n==> %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "必须以 root 运行" >&2; exit 1; }

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=/opt/dart-sdk/bin:$PATH

log "拉取代码（${BRANCH}）"
# git 仓库归 root 所有（只有 root 跑 git），运行用户 diary 只拿到编译产物与状态目录。
# 若历史版本把整棵树 chown 给了 diary，这里先归位，否则 root 的 git 会因
# "dubious ownership" 直接 fatal，脚本在 fetch 处中止。
if [[ -d "${SRC_DIR}/.git" ]]; then
    chown -R root:root "${SRC_DIR}"
fi
git config --global --add safe.directory "${SRC_DIR}"
if [[ -d "${SRC_DIR}/.git" ]]; then
    git -C "${SRC_DIR}" fetch --all --prune
    git -C "${SRC_DIR}" checkout "${BRANCH}"
    git -C "${SRC_DIR}" pull --ff-only origin "${BRANCH}"
else
    mkdir -p "${APP_DIR}"
    # 默认走 HTTPS 匿名克隆，前提是仓库公开；仓库转私有后需在此配置凭据。
    git clone --branch "${BRANCH}" "${REPO}" "${SRC_DIR}"
    chown -R root:root "${SRC_DIR}"
fi

log "安装依赖"
cd "${SRC_DIR}/packages/server"
dart pub get

log "静态检查"
dart analyze

log "跑测试"
dart test

log "编译可执行文件"
install -d -m 755 "${APP_DIR}"
install -d -m 755 -o "${RUN_USER}" -g "${RUN_USER}" "${APP_DIR}/bin"
dart compile exe bin/server.dart -o "${APP_DIR}/bin/server"
# 只交付二进制给运行用户，源码仓库保持 root（见上方说明）。
chown -R "${RUN_USER}:${RUN_USER}" "${APP_DIR}/bin"
chmod 755 "${APP_DIR}/bin/server"

log "安装 systemd 单元"
install -m 644 "${SRC_DIR}/deploy/diary-sync.service" /etc/systemd/system/diary-sync.service
install -d -m 755 /etc/diary-sync
install -d -m 750 -o "${RUN_USER}" -g "${RUN_USER}" "${STATE_DIR}"
[[ -f /etc/diary-sync/server.env ]] || echo "PORT=8080" > /etc/diary-sync/server.env
chmod 644 /etc/diary-sync/server.env
systemctl daemon-reload
systemctl enable diary-sync
systemctl restart diary-sync

log "健康检查"
sleep 3
# 未带 token 访问 /sync 期望 401（鉴权生效）。curl 失败或状态码不符时先打印诊断再退出，
# 避免 set -e 直接中止、运维看不到服务状态。
if ! code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080/sync?cursor=0"); then
    echo "8080 无响应，服务诊断：" >&2
    systemctl status diary-sync --no-pager >&2 || true
    journalctl -u diary-sync -n 30 --no-pager >&2 || true
    exit 1
fi
if [[ "${code}" != "401" ]]; then
    echo "8080 返回 ${code}（期望 401），服务诊断：" >&2
    systemctl status diary-sync --no-pager >&2 || true
    journalctl -u diary-sync -n 30 --no-pager >&2 || true
    exit 1
fi
echo "本机 8080 返回 401（未带 token，鉴权生效）"
systemctl is-active --quiet diary-sync && echo "diary-sync 运行中" || { echo "diary-sync 未运行" >&2; exit 1; }

log "完成"
