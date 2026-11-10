/// 登录结果。
class AuthResult {
  const AuthResult({
    required this.userId,
    required this.token,
    this.refreshToken,
  });
  final String userId;
  final String token;

  /// refresh token（T-07）：access token 过期后用它换新。
  /// 注册/登录/refresh 端点返回；客户端经 TokenStore 持久化。
  final String? refreshToken;
}

/// 鉴权抽象。EmailPasswordProvider 客户端实现；SmsProvider 将后续加入。
/// 本接口不依赖 http/flutter——实现由客户端注入，token 持久化由调用方负责。
abstract interface class AuthProvider {
  Future<AuthResult> register(String email, String password);
  Future<AuthResult> login(String email, String password);
  /// 读取已持久化的登录态；未登录返回 null。
  Future<AuthResult?> current();
  Future<void> signOut();
}
