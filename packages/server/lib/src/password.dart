import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'dart:convert';

/// sha256(salt + password)。非 bcrypt——最小里程碑取舍，生产应换 bcrypt/argon2。
String hashPassword(String password, String salt) {
  final h = sha256.convert(utf8.encode('$salt$password'));
  return h.toString();
}

/// 随机 salt（hex）。
String newSalt() => _hex(_randomBytes(16));

/// 随机 token（hex）。
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
