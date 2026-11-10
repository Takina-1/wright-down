/// 服务监听配置。
///
/// 默认只绑回环地址：8080 不对公网暴露，对外由 nginx 走 443 反代。
class ServerConfig {
  const ServerConfig({this.host = defaultHost, this.port = defaultPort});

  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8080;

  final String host;
  final int port;

  /// 从环境变量解析。PORT 缺失、非数字或超出合法范围（1–65535）时
  /// 回落默认端口——避免 -1/0/65536 这类可解析但非法的值在 bind 时才失败。
  static ServerConfig fromEnv(Map<String, String> env) {
    final raw = env['PORT'];
    final port = int.tryParse(raw ?? '');
    final valid = port != null && port >= 1 && port <= 65535;
    return ServerConfig(
      host: env['HOST'] ?? defaultHost,
      port: valid ? port : defaultPort,
    );
  }
}
