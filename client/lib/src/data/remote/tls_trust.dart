import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// TLS 信任锚点：产出信任系统 CA 的 [http.Client]。
///
/// ## 为什么只信任系统 CA
///
/// 云端经 Cloudflare 代理，Cloudflare 用公网 CA（Let's Encrypt）签发证书，
/// 平台系统 CA 信任库已包含该根，`withTrustedRoots: true` 即可信任，
/// **无需再内嵌自签 CA**。
///
/// ## 历史
///
/// F013 早期实现曾内嵌自签 CA（`assets/diary_ca.crt`），用于直连 IP
/// `https://8.148.158.13` 的场景——`dart:io` 不读 network_security_config.xml，
/// 自签 CA 必须在 Dart 侧显式信任，否则真机 TLS 握手在证书校验阶段即中止。
/// 改用 Cloudflare 域名 + 公网证书后，自签 CA 不再需要，本类退化为「信任
/// 系统 CA 的 client 工厂」。详见
/// docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md。
///
/// ## 信任语义
///
/// 仅信任平台系统 CA 信任库，不收窄也不放大既有信任面。
class TlsTrust {
  TlsTrust._();

  static final TlsTrust instance = TlsTrust._();

  /// 缓存的是 Future 而非 client —— 并发首次调用也只构造一次，
  /// 重复调用返回同一实例。
  Future<http.Client>? _cached;

  /// 构造（并缓存）可信 client。重复调用返回同一实例。
  Future<http.Client> client() => _cached ??= _build(const []);

  /// 构造可信 client，除系统 CA 外再追加 [extraPems]（每项是一张 PEM 证书的字节）。
  ///
  /// [extraPems] 供测试注入额外锚点；生产路径传空列表。
  /// 带额外锚点时不走缓存（信任集合不同）。
  Future<http.Client> clientWithTrustedCerts(List<List<int>> extraPems) {
    if (extraPems.isEmpty) return client();
    return _build(extraPems);
  }

  Future<http.Client> _build(List<List<int>> extraPems) async {
    final ctx = SecurityContext(withTrustedRoots: true);
    for (final pem in extraPems) {
      ctx.setTrustedCertificatesBytes(pem);
    }
    return IOClient(HttpClient(context: ctx));
  }
}
