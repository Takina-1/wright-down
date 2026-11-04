#!/usr/bin/env bash
#
# F013 云同步服务端 · Alinux 3 环境初始化
#
# 幂等：重复执行安全（已装则跳过，配置项按需改写）。
# 用法：bash provision-alinux3.sh
#
# 可覆盖的环境变量：
#   PG_DB      数据库名        默认 diary_sync
#   PG_USER    数据库用户      默认 diary
#   PG_PORT    数据库端口      默认 5432
#   DART_VERSION  Dart SDK 版本 默认 3.13.7（须满足 packages/*/pubspec.yaml 的 sdk: ^3.13.7）
#   SWAP_SIZE_MB swap 大小     默认 2048
#   APP_DIR    应用目录        默认 /opt/diary-sync
#   APP_USER   运行用户        默认 diary

set -euo pipefail

PG_DB="${PG_DB:-diary_sync}"
PG_USER="${PG_USER:-diary}"
PG_PORT="${PG_PORT:-5432}"
DART_VERSION="${DART_VERSION:-3.13.7}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"
APP_DIR="${APP_DIR:-/opt/diary-sync}"
APP_USER="${APP_USER:-diary}"
DART_SDK_DIR="/opt/dart-sdk"
PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
# Dart SDK 下载镜像，按顺序尝试。国内到官方源实测仅 ~115 KB/s。
DART_MIRRORS="${DART_MIRRORS:-https://storage.flutter-io.cn/dart-archive https://storage.googleapis.com/dart-archive}"

CRED_FILE="/root/.diary-sync-pg-credentials"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[fail] %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "必须以 root 运行"
command -v dnf >/dev/null || die "没有 dnf，这不是 Alinux 3 / RHEL 系"

# ---------------------------------------------------------------- 0. 系统校验
log "0/7 系统信息"
cat /etc/os-release | grep -E '^(NAME|VERSION_ID)='
if ! grep -qiE 'alinux' /etc/os-release; then
    warn "当前系统不是 Alinux。本脚本按 Alinux 3 / RHEL 8 系编写，继续执行但不保证。"
fi

# ---------------------------------------------------------------- 1. swap
log "1/7 swap"
if swapon --show=NAME --noheadings | grep -q .; then
    echo "已有 swap，跳过"
else
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap defaults 0 0' >> /etc/fstab
    echo "已启用 ${SWAP_SIZE_MB}M swap"
fi
free -h | sed -n '1,3p'

# ---------------------------------------------------------------- 2. 系统包
log "2/7 安装系统包"
# firewalld 不装：只在它本来就运行时才配置，缺失就靠安全组兜底
dnf -y install \
    postgresql-server postgresql-contrib \
    nginx git gcc make unzip tar \
    policycoreutils policycoreutils-python-utils

echo "postgres: $(rpm -q postgresql-server 2>/dev/null || echo '?')"
echo "nginx:    $(rpm -q nginx 2>/dev/null || echo '?')"

# ---------------------------------------------------------------- 3. Postgres
log "3/7 初始化 PostgreSQL"
PGDATA="/var/lib/pgsql/data"

if [[ ! -f "${PGDATA}/PG_VERSION" ]]; then
    # RHEL8 系是 `postgresql-setup --initdb`，RHEL9 系（Alinux 4）改成了
    # `postgresql-setup initdb`，两种形式都试，再不行就手动调 initdb 兜底。
    INIT_OK=0
    for form in "--initdb" "initdb"; do
        if postgresql-setup ${form} >/tmp/pg-initdb.log 2>&1 && [[ -f "${PGDATA}/PG_VERSION" ]]; then
            INIT_OK=1
            break
        fi
    done
    if [[ "${INIT_OK}" != "1" ]]; then
        echo "postgresql-setup 两种形式都失败，改用 initdb 手动初始化"
        mkdir -p "${PGDATA}"
        chown postgres:postgres "${PGDATA}"
        chmod 700 "${PGDATA}"
        su - postgres -c "/usr/bin/initdb -D ${PGDATA}" || {
            tail -20 /tmp/pg-initdb.log 2>/dev/null
            die "initdb 失败"
        }
    fi
else
    echo "数据目录已初始化，跳过 initdb"
fi

systemctl enable --now postgresql

# 内存参数：按小规格实例保守设置，4G 机器也安全
# 注意：conf.d 必须属主为 postgres，否则 postmaster 拒绝启动
# （"data directory ... has invalid permissions/ownership"）。
# 用 install -d 建目录会留下 root:root 属主，必须显式 -o/-g。
install -d -m 700 -o postgres -g postgres "${PGDATA}/conf.d"
cat > "${PGDATA}/conf.d/99-sync.conf" <<EOF
# F013 同步服务调优 —— 由 provision-alinux4.sh 生成
# 只监听本地回环：应用经 127.0.0.1 连库，数据库不对外暴露。
# pg_hba 也只放行 127.0.0.1/::1，这里再收一层，少一个监听面。
listen_addresses = 'localhost'
port = ${PG_PORT}
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
max_connections = 50
timezone = 'Asia/Shanghai'
log_timezone = 'Asia/Shanghai'
# 必须与 pg_hba.conf 的 host 行方法一致，否则建账号时存成 md5 哈希、
# 认证时按 scram 校验会直接失败。
password_encryption = 'scram-sha-256'
EOF

# 只认「生效行」：发行版默认写的是注释掉的 #include_dir = 'conf.d'
# （PG10 是 #include_dir = '...'），用无锚点的 grep 会误判成已配置而跳过追加，
# 导致 conf.d 里的调优参数根本没被加载。
if ! grep -qE "^[[:space:]]*include_dir" "${PGDATA}/postgresql.conf"; then
    echo "include_dir = 'conf.d'" >> "${PGDATA}/postgresql.conf"
fi

# 重启后 password_encryption 才生效，才能保证下面建账号时存的是 scram 哈希
systemctl restart postgresql

# pg_hba：本地 socket 走 peer/scram；非本地连接只允许 127.0.0.1，
# 避免数据库直接暴露在公网（外部统一走 nginx）
PGHBA="${PGDATA}/pg_hba.conf"
cp -f "${PGHBA}" "${PGHBA}.bak.$(date +%s)"
cat > "${PGHBA}" <<EOF
# TYPE  DATABASE  USER  ADDRESS        METHOD
local   all       all                  peer
host    all       all   127.0.0.1/32   scram-sha-256
host    all       all   ::1/128        scram-sha-256
EOF
systemctl reload postgresql

# 数据库与账号
PG_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
# 角色已存在时也必须重设密码：否则凭证文件里的随机密码与库里实际密码对不上，
# 脚本第二次跑就会在 psql 连库时认证失败。
if su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'\"" | grep -q 1; then
    su - postgres -c "psql -c \"ALTER ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}'\""
else
    su - postgres -c "psql -c \"CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}'\""
fi
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${PG_DB}'\"" | grep -q 1 || \
    su - postgres -c "psql -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USER}\""

cat > "${CRED_FILE}" <<EOF
# F013 同步服务数据库凭证（0600，勿提交）
PG_HOST=127.0.0.1
PG_PORT=${PG_PORT}
PG_DB=${PG_DB}
PG_USER=${PG_USER}
PG_PASSWORD=${PG_PASSWORD}
EOF
chmod 600 "${CRED_FILE}"
echo "凭证已写入 ${CRED_FILE}（0600）"

# ---------------------------------------------------------------- 4. 建表
log "4/7 应用库表结构"
SCHEMA_SRC=""
for candidate in "${SCRIPT_DIR}/sql/schema.sql" "${SCRIPT_DIR}/schema.sql" "/tmp/schema.sql"; do
    if [[ -f "${candidate}" ]]; then SCHEMA_SRC="${candidate}"; break; fi
done
if [[ -n "${SCHEMA_SRC}" ]]; then
    echo "使用 ${SCHEMA_SRC}"
    PGPASSWORD="${PG_PASSWORD}" psql -h 127.0.0.1 -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" -v ON_ERROR_STOP=1 -f "${SCHEMA_SRC}"
else
    warn "未找到 schema.sql（试过 ${SCRIPT_DIR}/sql/schema.sql、${SCRIPT_DIR}/schema.sql、/tmp/schema.sql），跳过建表"
fi

# ---------------------------------------------------------------- 5. Dart SDK
log "5/7 安装 Dart SDK ${DART_VERSION}"
if command -v dart >/dev/null && [[ "$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" == "${DART_VERSION}" ]]; then
    echo "Dart ${DART_VERSION} 已安装，跳过"
else
    TMP_DIR="$(mktemp -d)"
    TMP_ZIP="${TMP_DIR}/dartsdk.zip"
    REL="channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-x64-release.zip"
    OFFICIAL="https://storage.googleapis.com/dart-archive"

    # 期望哈希始终取自官方源，字节允许从任一镜像取。
    # 官方源到国内实测吞吐只有 ~115 KB/s（227MB 要半小时），
    # storage.flutter-io.cn 实测 ~1.1 MB/s，两者文件内容一致。
    EXPECTED="$(curl -fsSL --max-time 30 "${OFFICIAL}/${REL}.sha256sum" | awk '{print $1}')"
    [[ -n "${EXPECTED}" ]] || die "无法从官方源取得 ${DART_VERSION} 的 sha256"

    DOWNLOADED=""
    for base in ${DART_MIRRORS}; do
        echo "尝试下载 ${base}/${REL}"
        if curl -fSL --retry 3 --connect-timeout 15 -o "${TMP_ZIP}" "${base}/${REL}"; then
            DOWNLOADED="${base}"
            break
        fi
        warn "从 ${base} 下载失败，尝试下一个镜像"
    done
    [[ -n "${DOWNLOADED}" ]] || die "所有镜像均下载失败"

    ACTUAL="$(sha256sum "${TMP_ZIP}" | awk '{print $1}')"
    [[ "${EXPECTED}" == "${ACTUAL}" ]] || die "Dart SDK 校验失败：期望 ${EXPECTED}，实际 ${ACTUAL}"
    echo "sha256 校验通过（官方哈希）：${ACTUAL}"

    rm -rf "${DART_SDK_DIR}"
    mkdir -p "$(dirname "${DART_SDK_DIR}")"
    unzip -q "${TMP_ZIP}" -d "$(dirname "${DART_SDK_DIR}")"
    ln -sf "${DART_SDK_DIR}/bin/dart" /usr/local/bin/dart
    rm -rf "${TMP_DIR}"
fi

cat > /etc/profile.d/dart.sh <<EOF
export DART_SDK="${DART_SDK_DIR}"
export PATH="\${DART_SDK}/bin:\${PATH}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL}"
EOF
chmod 644 /etc/profile.d/dart.sh
dart --version 2>&1

# ---------------------------------------------------------------- 6. 应用用户与目录
log "6/7 应用用户与目录"
id "${APP_USER}" >/dev/null 2>&1 || useradd -r -m -d "/home/${APP_USER}" -s /sbin/nologin "${APP_USER}"
install -d -m 755 -o "${APP_USER}" -g "${APP_USER}" "${APP_DIR}"
install -d -m 750 -o "${APP_USER}" -g "${APP_USER}" /var/lib/diary-sync
install -d -m 755 /etc/diary-sync
install -m 600 -o "${APP_USER}" -g "${APP_USER}" "${CRED_FILE}" /etc/diary-sync/pg.env
echo "应用目录 ${APP_DIR}，凭证 /etc/diary-sync/pg.env"

# SELinux：Alinux 3 默认 enforcing，给应用目录和端口打标签
if command -v getenforce >/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    log "6b SELinux 打标签（当前 $(getenforce)）"
    semanage fcontext -a -t bin_t "${APP_DIR}(/.*)?" 2>/dev/null || true
    semanage fcontext -a -t var_lib_t "/var/lib/diary-sync(/.*)?" 2>/dev/null || true
    semanage port -a -t http_port_t -p tcp 8080 2>/dev/null || true
    restorecon -Rv "${APP_DIR}" /var/lib/diary-sync 2>/dev/null || true
fi

# ---------------------------------------------------------------- 7. 防火墙
log "7/7 防火墙"
if systemctl is-active --quiet firewalld; then
    echo "firewalld 运行中：放行 ssh 与 nginx 的 80/443；应用端口 8080 不对外开放"
    firewall-cmd --permanent --add-service=ssh >/dev/null
    firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
    firewall-cmd --list-all | sed -n '/^  ports:/,/^$/p'
else
    warn "firewalld 未运行；系统层无防火墙，务必用阿里云安全组限制端口"
fi

# ---------------------------------------------------------------- 汇总
log "完成"
PG_VER="$(su - postgres -c "psql -tAc 'SHOW server_version'" 2>/dev/null | tr -d '[:space:]')"
SWAP_LIST="$(swapon --show=NAME --noheadings | tr -d ' ' | tr '\n' ' ')"
DART_VER="$(dart --version 2>&1)"
cat <<EOF
PostgreSQL : ${PG_VER}  端口 ${PG_PORT}
数据库     : ${PG_DB}（用户 ${PG_USER}）
库表       : 已建（凭证 ${CRED_FILE}）
Dart       : ${DART_VER}
swap       : ${SWAP_LIST}
应用用户   : ${APP_USER}
应用目录   : ${APP_DIR}
启用仓库   : $(yum repolist --enabled 2>/dev/null | tail -n +2 | awk '{printf "%s ", $1}')

下一步：
  1. 部署代码到 ${APP_DIR} 并 dart compile exe 出可执行文件
  2. 装 systemd 单元并启动（deploy/diary-sync.service）
  3. 配 nginx 反代 + HTTPS
EOF
