# 测试专用 TLS 夹具 · test tls fixtures

本目录为 **自动化测试专用** 的 CA 与 localhost 服务器证书。

## 为什么需要

Flutter 的 `dart:io` 网络栈**不读** `network_security_config.xml`，只信任 Android
系统 CA 库。生产环境用自签 CA（`CN=Local Diary App CA`）时，客户端必须在 Dart 侧
显式追加信任锚点才能连上 `https://8.148.158.13`。

`tls_trust_test.dart` 用本目录的证书起一个本地 TLS 服务器，真实验证「Dart 侧
信任锚点生效」这条路径 —— 只测 asset 存在是测不出来的。

## 与生产 CA 的关系

**完全无关。** 本目录的 `test_ca.key` 仅用于测试；生产 CA 私钥在
`deploy/certs/ca.key`，已被 `.gitignore` 排除，不入库、不上服务器。

## 安全说明

测试私钥入库是业界常规做法（与「生产私钥入库」性质不同）。任何人拿到本目录的
私钥只能伪造 `localhost` 的测试证书，无法冒充生产服务器
（生产 CA 私钥不在库内）。

## 重新生成

```bash
bash client/test/fixtures/tls/generate.sh
```

Git Bash 下需 `export MSYS_NO_PATHCONV=1`（脚本内部已处理），否则 `openssl -subj`
的 `/CN=` 会被误转成 Windows 路径。
