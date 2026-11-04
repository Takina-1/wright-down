/// 同步服务端基址。
///
/// 编译期通过 `--dart-define=SYNC_BASE_URL=https://8.148.158.13` 注入；
/// 未注入时回落安卓模拟器访问宿主机的别名（10.0.2.2 映射到本机）。
String syncBaseUrl() => const String.fromEnvironment(
      'SYNC_BASE_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
