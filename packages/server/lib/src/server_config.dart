/// 服务监听配置。
///
/// 默认只绑回环地址：8080 不对公网暴露，对外由 nginx 走 443 反代。
class ServerConfig {
  const ServerConfig({this.host = defaultHost, this.port = defaultPort});

  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8080;

  final String host;
  final int port;

  /// 从环境变量解析。PORT 缺失或非法时回落默认端口。
  static ServerConfig fromEnv(Map<String, String> env) => ServerConfig(
        host: env['HOST'] ?? defaultHost,
        port: int.tryParse(env['PORT'] ?? '') ?? defaultPort,
      );
}
