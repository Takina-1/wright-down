import 'dart:math';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';

/// bcrypt 计算强度。实测目标机（2 vCPU）单次 106 ms，登录接口可接受。
const int kBcryptLogRounds = 10;

/// bcrypt 前缀。用 `$2b` 而非默认的 `$2a`——`$2a` 存在高位字符符号扩展缺陷。
const String kBcryptPrefix = r'$2b';

/// 口令最大字节数。bcrypt 只取前 72 字节，超过则拒绝而非静默截断。
const int kMaxPasswordBytes = 72;

/// 生成 bcrypt 哈希。salt 内嵌于返回值（`$2b$10$<salt><hash>`）。
///
/// 抛 [ArgumentError] 当口令超过 72 字节。
String hashPassword(String password) => BCrypt.hashpw(
    password,
    BCrypt.gensalt(prefix: kBcryptPrefix, logRounds: kBcryptLogRounds));

/// 校验口令与哈希。哈希格式非法时返回 false，不抛异常。
///
/// T-19：收窄捕获——只吞 [ArgumentError]（bcrypt 对超长口令抛的）。
/// 调用方（login handler）已做长度预检，其他异常不会触发——
/// 收窄避免宽捕获吞掉本应暴露的编程错误。
bool verifyPassword(String password, String hash) {
  try {
    return BCrypt.checkpw(password, hash);
  } on ArgumentError {
    return false;
  }
}

/// 随机 token（hex，48 字符）。
String newToken() => _hex(_randomBytes(24));

Uint8List _randomBytes(int n) {
  final rng = Random.secure();
  final bytes = Uint8List(n);
  for (var i = 0; i < n; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return bytes;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
