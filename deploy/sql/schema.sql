-- F013 云同步服务端 · PostgreSQL 库表结构
-- 对齐 packages/server/lib/src/sync_store.dart 的 SyncStore 接口。
--
-- 表名与 docs/superpowers/specs/云同步设计-cloud-sync-design.md 第 5 节一致：
--   users   (id, email UNIQUE, password_hash, created_at)
--   entries (user_id, id, payload JSONB, created_at, seq)
--   tokens  (token, user_id, created_at)      -- FakeSyncStore 有 _tokens，真实库需要
--   sync_seq(id, value)                        -- 全局单调 seq 计数器
--
-- 与设计文档的两处偏差（有意为之，理由见注释）：
--   1. entries 主键用 (user_id, id) 而非单列 id，与 FakeSyncStore 条目按 (userId, id)
--      复合键存储的口径一致（跨用户同 id 不互相覆盖）。
--   2. seq 用 sync_seq 行锁自增而非 BIGSERIAL。序列 nextval 在事务提交前就分配，
--      客户端可能先拉到 seq=6 却漏掉仍未提交的 seq=5，cursor 直接跳过。改用
--      "UPDATE sync_seq SET value = value + 1 ... RETURNING value"，行锁持有到提交，
--      推送事务之间串行化，seq 顺序 == 提交顺序，pull 不会丢条目。

BEGIN;

CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tokens (
    token      TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tokens_user_id_idx ON tokens (user_id);

CREATE TABLE IF NOT EXISTS entries (
    user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    id         TEXT NOT NULL,
    payload    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    seq        BIGINT NOT NULL,
    PRIMARY KEY (user_id, id)
);

-- pull 的查询形态：WHERE user_id = ? AND seq > ? ORDER BY seq
CREATE INDEX IF NOT EXISTS entries_user_seq_idx ON entries (user_id, seq);

-- 全局单调计数器，单行。push 在事务内 UPDATE ... RETURNING 取下一个值。
CREATE TABLE IF NOT EXISTS sync_seq (
    id    INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    value BIGINT NOT NULL DEFAULT 0
);

INSERT INTO sync_seq (id, value) VALUES (1, 0) ON CONFLICT (id) DO NOTHING;

-- T-07：refresh token 机制（AC-08）。
-- access token 过期时间（NULL = 无过期，兼容 T-06 存量 token）；
-- 新 token 由 PostgresSyncStore 写入 now() + interval '7 days'。
ALTER TABLE tokens ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- refresh token 表：30 天过期（NOT NULL——新表无存量）。
-- refresh 端点校验 expires_at > now()，有效则轮换（DELETE 旧 + INSERT 新）。
CREATE TABLE IF NOT EXISTS refresh_tokens (
    token      TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx
    ON refresh_tokens (user_id);

COMMIT;
