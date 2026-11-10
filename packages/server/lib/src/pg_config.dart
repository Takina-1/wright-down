/// PostgreSQL 连接配置。
///
/// 从环境变量解析：PG_HOST / PG_PORT / PG_DB / PG_USER / PG_PASSWORD。
/// 凭证齐全返回配置（缺省使用与 provision 脚本一致的默认值）；
/// 任一缺失返回 null，调用方据此回落 FakeSyncStore。
class PgConfig {
  const PgConfig({
    required this.host,
    required this.port,
    required this.db,
    required this.user,
    required this.password,
    this.timeout = const Duration(seconds: 10),
  });

  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 5432;
  static const String defaultDb = 'diary_sync';
  static const String defaultUser = 'diary';

  final String host;
  final int port;
  final String db;
  final String user;
  final String password;
  final Duration timeout;

  /// 凭证齐全时返回配置；缺 PG_HOST 视为「未配置 PG」（与 provision 脚本
  /// 写入 pg.env 的变量清单一致：PG_HOST 为锚点）。
  static PgConfig? fromEnv(Map<String, String> env) {
    final host = env['PG_HOST'];
    if (host == null || host.isEmpty) return null;
    final password = env['PG_PASSWORD'];
    if (password == null || password.isEmpty) return null;
    return PgConfig(
      host: host,
      port: int.tryParse(env['PG_PORT'] ?? '') ?? defaultPort,
      db: env['PG_DB'] ?? defaultDb,
      user: env['PG_USER'] ?? defaultUser,
      password: password,
    );
  }
}
