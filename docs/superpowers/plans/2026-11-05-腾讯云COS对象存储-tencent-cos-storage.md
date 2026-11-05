# 腾讯云 COS 对象存储迁移 · tencent cos storage

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把对象存储从阿里云 OSS 换成腾讯云 COS，并把代码里的 `OSSGateway` / `FakeOSS` 命名统一为 `CosGateway` / `FakeCos`，同时把全部文档中的 OSS 表述替换为 COS、新增 COS 运维文档与 CAM 策略模板。

**Architecture:** 分三层落地。**代码层**是纯机械重命名——`sync_core` 的抽象接口 `OSSGateway`→`CosGateway`、客户端本地文件系统实现 `FakeOSS`→`FakeCos`、`SyncEngine` 的 `oss` 字段与构造参数 `oss:`→`cos:`，行为完全不变，测试数量与结果必须与基线一致。**文档层**把「对象存储 = 阿里云 OSS」的表述改为腾讯云 COS（ECS 侧的事实表述保持不动），并按已确认的 D-07 把数据路径改写为「ECS 代理收发字节」。**运维层**新增 `deploy/腾讯云COS配置-tencent-cos-setup.md` 与 `deploy/cam-policy.json`，承载桶配置、凭证管理、资源包抵扣范围与实测带宽数据。

**Tech Stack:** Dart 3.13.7 / Flutter 3.47.8（Windows 宿主，PowerShell 脚本驱动）、`package:crypto`、shelf + shelf_router（服务端）、Markdown 文档、腾讯云 CAM 策略 JSON。

## Global Constraints

- **分支**：全部改动在 `feat/F013-cloud-sync` 分支上完成。`packages/sync_core` 与客户端同步代码只存在于该分支，`main` 上没有这些文件，**不得从 main 另开分支**。
- **命令前缀**：所有 Dart/Flutter 命令用项目脚本驱动，不直接调 `dart` / `flutter`：
  - Dart 包（`packages/sync_core`、`packages/server`）：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" <args>`
  - Flutter（`client`）：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" <args>`
  - 工作目录：`packages/sync_core`、`packages/server`、`client` 各自目录下执行。
- **测试基线**（2026-11-05 实测，改动前后必须一致）：sync_core **13** 项、server **31** 项、client **442** 项，全部通过。
- **不改动**：`Entry.photoKey` 字段名与 `photo_key` 数据库列名；`deploy/ram-policy.json`（阿里云 ECS 只读策略）；任何 ECS 侧内容（`deploy/` 下的阿里云脚本、`deploy/阿里云部署-aliyun-deploy.md` 正文）；`docs/开发环境-development-environment.md` 里的「阿里云 central HTTPS 镜像」（那是 Maven 镜像）。
- **工作区保护**：`packages/server/lib/src/fake_sync_store.dart`、`packages/server/test/fake_sync_store_sync_test.dart`、`packages/server/tool_bcrypt_probe.dart`（未跟踪）、`deploy/deploy-app.sh`、`*.pubspec.lock` 在本计划开始前已有未提交改动。**不得提交、不得回退、不得修改**这些内容。提交时用 `git add <具体路径>` 逐个添加，禁止 `git add -A` 或 `git add .`。
- **提交信息格式**：`<type>:<中文说明>,<english summary>`，需要标注功能编号时写成 `docs(F013):<中文说明>,<english summary>`。中文说明写清本次改动，英文摘要用祈使句并与中文对应。
- **文档命名**：除 `README.md` / `AGENTS.md` / `CLAUDE.md` 外，Markdown 文件名必须为 `<中文主题>-<english-topic>.md`，英文主题小写连字符。新增文件为 `deploy/腾讯云COS配置-tencent-cos-setup.md`。
- **本计划不实现真机 COS**。建桶、CAM 凭证、服务端代理端点、客户端真机版全部延后，作为 F013 待办 T-05 / T-24。
- **Task 1 与 Task 2 之间，`client/` 处于不可编译状态**：Task 1 把 `OSSGateway` 改成 `CosGateway` 后，`client/lib/src/data/sync/sync_engine.dart`、`client/lib/src/data/sync/fake_oss.dart`、`client/test/ui/home_page_photo_sync_test.dart` 仍引用旧名。这三处由 Task 2 修复，**Task 2 完成后 `client/` 恢复可编译**。因此 Task 1 与 Task 2 之间不要跑 client 的 analyze/test，也不要在这个中间态上做整分支验证。
- **`git add` 旧路径会中止整条命令**：凡是用 `git mv` 重命名的文件，旧路径已被删除记入索引，`git add <旧路径>` 报 `fatal: pathspec ... did not match any files`，且 git 遇到无效 pathspec 时**中止整条命令**——后面的路径一个都不会被暂存。只 add 仍存在的路径。

---

### Task 1: sync_core 抽象接口重命名

**Files:**
- Rename: `packages/sync_core/lib/src/oss_gateway.dart` → `packages/sync_core/lib/src/cos_gateway.dart`
- Modify: `packages/sync_core/lib/sync_core.dart`
- Modify: `packages/sync_core/test/interfaces_test.dart`
- Modify: `packages/sync_core/pubspec.yaml`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `sync_core` 导出 `abstract interface class CosGateway`，方法签名不变：`Future<String> upload(Uint8List bytes)`、`Future<Uint8List> download(String key)`、`Future<String> presign(String key)`。后续 Task 2 的客户端实现与 Task 3 的 `SyncEngine` 依赖这个名字。

- [ ] **Step 1: 记录重命名前的基线**

Run:
```bash
cd packages/sync_core && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" test
```
Expected: `All tests passed!`，计数 **13**。

- [ ] **Step 2: 重命名文件**

Run:
```bash
cd packages/sync_core && git mv lib/src/oss_gateway.dart lib/src/cos_gateway.dart
```
Expected: `R packages/sync_core/lib/src/oss_gateway.dart -> packages/sync_core/lib/src/cos_gateway.dart`

- [ ] **Step 3: 改写 `cos_gateway.dart` 的接口声明**

`packages/sync_core/lib/src/cos_gateway.dart` 全文替换为：

```dart
import 'dart:typed_data';

/// COS 直传抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理 COS
/// 读写（本接口不依赖任何 SDK）。
abstract interface class CosGateway {
  /// 上传字节，返回可持久化的 key（sha256）。
  Future<String> upload(Uint8List bytes);

  /// 按 key 下载字节。
  Future<Uint8List> download(String key);

  /// 生成预签名 URL（真机 COS 用；fake 可返回本地路径）。
  Future<String> presign(String key);
}
```

- [ ] **Step 4: 改写导出路径**

`packages/sync_core/lib/sync_core.dart` 的第 5 行：

```dart
export 'src/oss_gateway.dart';
```
改为：
```dart
export 'src/cos_gateway.dart';
```

- [ ] **Step 5: 改写契约测试**

`packages/sync_core/test/interfaces_test.dart` 中，第 18–26 行的 group 块：

```dart
  group('CosGateway 契约', () {
    test('测试替身可实现 CosGateway', () async {
      final g = _FakeCos();
      final key = await g.upload(Uint8List.fromList([1, 2, 3]));
      expect(key, 'key-1');
      expect((await g.download('key-1')), Uint8List.fromList([1, 2, 3]));
      expect(await g.presign('key-1'), 'fake://key-1');
    });
  });
```

第 42 行的替身类声明：

```dart
class _FakeCos implements CosGateway {
```

- [ ] **Step 6: 改写 pubspec 描述**

`packages/sync_core/pubspec.yaml` 第 2 行：

```yaml
description: "云同步共享纯逻辑包：字段级 LWW 合并、同步协议、鉴权/COS 抽象。"
```

- [ ] **Step 7: 验证**

Run:
```bash
cd packages/sync_core && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" analyze
cd packages/sync_core && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" test
```
Expected: analyze 输出 `No issues found`；test 输出 `All tests passed!`，计数 **13**（与 Step 1 一致）。

- [ ] **Step 8: 提交**

```bash
git add packages/sync_core/lib/src/cos_gateway.dart packages/sync_core/lib/sync_core.dart packages/sync_core/test/interfaces_test.dart packages/sync_core/pubspec.yaml
git commit -m "refactor(F013):重命名同步抽象为CosGateway,rename sync abstraction to CosGateway"
```
Expected: 提交成功。`git status --short` 中不应再出现 `packages/sync_core/lib/src/oss_gateway.dart`。

> ⚠️ **不要 add 旧路径**（`oss_gateway.dart`）。`git mv` 已把删除记入索引，add 旧路径会报 `fatal: pathspec ... did not match any files`，且遇到无效 pathspec 时整条 `git add` 命令中止——后面的路径一个都不会被暂存。只 add 仍存在的路径即可；`git mv` 的重命名记录由索引自动携带。

---

### Task 2: 客户端 FakeCos 实现重命名

**Files:**
- Rename: `client/lib/src/data/sync/fake_oss.dart` → `client/lib/src/data/sync/fake_cos.dart`
- Rename: `client/test/data/sync/fake_oss_test.dart` → `client/test/data/sync/fake_cos_test.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/lib/src/data/sync/sync_engine.dart`（仅类型引用）
- Modify: `client/test/data/sync/fake_cos_test.dart`（重命名后）
- Modify: `client/test/data/sync/sync_engine_photo_test.dart`
- Modify: `client/test/data/sync/sync_engine_runtime_test.dart`
- Modify: `client/test/data/sync/sync_engine_stamps_test.dart`
- Modify: `client/test/data/sync/sync_engine_test.dart`
- Modify: `client/test/ui/home_page_photo_sync_test.dart`（仅类型引用）
- Modify: `client/test/ui/sync/login_page_test.dart`

**Interfaces:**
- Consumes: Task 1 产出的 `CosGateway`（从 `package:sync_core/sync_core.dart` 导入）
- Produces: `client/lib/src/data/sync/fake_cos.dart` 导出 `class FakeCos implements CosGateway`，构造函数 `FakeCos({Directory? root})`，方法 `Future<String> upload(Uint8List bytes)`、`Future<Uint8List> download(String key)`、`Future<String> presign(String key)`、`Future<void> close()`、`Directory get rootForTest`。Task 3 会把 `SyncEngine` 的构造参数改为 `cos:`。

> **本任务必须同时改掉客户端对 `OSSGateway` 的类型引用**，否则 Task 1 完成后客户端无法编译，本任务的 Step 7 验证会失败。字段名 `oss` 的重命名推迟到 Task 3。

- [ ] **Step 1: 记录基线**

Run:
```bash
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" test test/data/sync/fake_oss_test.dart
```
Expected: `All tests passed!`，计数 **4**。

- [ ] **Step 2: 重命名两个文件**

Run:
```bash
cd client && git mv lib/src/data/sync/fake_oss.dart lib/src/data/sync/fake_cos.dart
cd client && git mv test/data/sync/fake_oss_test.dart test/data/sync/fake_cos_test.dart
```
Expected: 两条 `R` 状态记录。

- [ ] **Step 3: 改写 `fake_cos.dart`**

`client/lib/src/data/sync/fake_cos.dart` 全文替换为：

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sync_core/sync_core.dart';

/// 本地文件系统实现 [CosGateway]（开发/测试用）。
///
/// upload 计算字节的 sha256 作为 key，写入 `<root>/<key>`；download 按 key
/// 读取字节；presign 返回 `fake://<root>/<key>` 假 URL。不依赖任何云 SDK。
///
/// [root] 默认在系统临时目录下创建；可通过构造参数注入指定目录（如测试夹具）。
/// [close] 删除底层目录——仅用于开发/测试清理，勿对真实项目目录调用。
class FakeCos implements CosGateway {
  FakeCos({Directory? root})
      : _root = root ?? Directory.systemTemp.createTempSync('fakecos');

  final Directory _root;

  /// 测试夹具：暴露底层目录以便断言 close 后是否被删除。
  Directory get rootForTest => _root;

  @override
  Future<String> upload(Uint8List bytes) async {
    if (!_root.existsSync()) _root.createSync(recursive: true);
    final key = sha256.convert(bytes).toString();
    await File('${_root.path}/$key').writeAsBytes(bytes);
    return key;
  }

  @override
  Future<Uint8List> download(String key) async {
    return Uint8List.fromList(await File('${_root.path}/$key').readAsBytes());
  }

  @override
  Future<String> presign(String key) async => 'fake://${_root.path}/$key';

  /// 删除底层目录。目录不存在时静默返回，可安全重复调用。
  Future<void> close() async {
    if (_root.existsSync()) await _root.delete(recursive: true);
  }
}
```

- [ ] **Step 4: 改写 `fake_cos_test.dart`**

`client/test/data/sync/fake_cos_test.dart` 全文替换为：

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/data/sync/fake_cos.dart';

void main() {
  test('FakeCos 上传后能下载同内容', () async {
    final oss = FakeCos();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final key = await oss.upload(bytes);
    expect(key, isA<String>());
    final back = await oss.download(key);
    expect(back, bytes);
    await oss.close();
  });

  test('presign 返回非空 URL', () async {
    final oss = FakeCos();
    final key = await oss.upload(Uint8List.fromList([1]));
    expect(await oss.presign(key), isA<String>());
    await oss.close();
  });

  test('相同内容上传得到相同 key（sha256 去重）', () async {
    final oss = FakeCos();
    final bytes = Uint8List.fromList([10, 20, 30]);
    final k1 = await oss.upload(bytes);
    final k2 = await oss.upload(Uint8List.fromList([10, 20, 30]));
    expect(k1, k2);
    await oss.close();
  });

  test('close 后目录被删除', () async {
    final oss = FakeCos();
    await oss.upload(Uint8List.fromList([1]));
    final root = oss.rootForTest;
    expect(root.existsSync(), isTrue);
    await oss.close();
    expect(root.existsSync(), isFalse);
  });
}
```

- [ ] **Step 5: 改写 `main.dart`**

`client/lib/main.dart` 第 12 行的 import：

```dart
import 'src/data/sync/fake_oss.dart';
```
改为：
```dart
import 'src/data/sync/fake_cos.dart';
```

第 44–46 行：

```dart
      // FakeOSS 是开发期占位实现（本地临时目录）；真机 OSS 直传网关待后续
      // Part 接入后替换。
      oss: FakeOSS(),
```
改为：
```dart
      // FakeCos 是开发期占位实现（本地临时目录）；真机 COS 网关待后续
      // Part 接入后替换。
      oss: FakeCos(),
```

> 注：`oss:` 参数名在 Task 3 才改为 `cos:`。本任务保持 `oss:` 不变，保证本任务可独立通过编译与测试。

- [ ] **Step 6: 改写客户端对 `OSSGateway` 的类型引用**

`sync_core` 在 Task 1 已把接口改名，客户端必须同步，否则编译不过。

`client/lib/src/data/sync/sync_engine.dart` 第 43 行：
```dart
  final OSSGateway oss;
```
改为：
```dart
  final CosGateway oss;
```

`client/test/ui/home_page_photo_sync_test.dart` 第 46 行：
```dart
class _InMemoryOSS implements OSSGateway {
```
改为：
```dart
class _InMemoryOSS implements CosGateway {
```

> 字段名 `oss` 与类名 `_InMemoryOSS` **本任务不改**——类名在 Task 3 改，字段名在 Task 3 改。

- [ ] **Step 7: 改写其余 5 个测试文件的 import 与类名**

对 `client/test/data/sync/sync_engine_photo_test.dart`、`client/test/data/sync/sync_engine_runtime_test.dart`、`client/test/data/sync/sync_engine_stamps_test.dart`、`client/test/data/sync/sync_engine_test.dart`、`client/test/ui/sync/login_page_test.dart` 这 5 个文件，各做两处替换：

1. import 行
   ```dart
   import 'package:local_diary/src/data/sync/fake_oss.dart';
   ```
   改为
   ```dart
   import 'package:local_diary/src/data/sync/fake_cos.dart';
   ```
2. 构造调用 `FakeOSS()` → `FakeCos()`

逐文件的 `FakeOSS()` 出现次数（用于核对替换完整）：

| 文件 | `FakeOSS()` 次数 |
|---|---|
| `client/test/data/sync/sync_engine_photo_test.dart` | 2 |
| `client/test/data/sync/sync_engine_runtime_test.dart` | 5 |
| `client/test/data/sync/sync_engine_stamps_test.dart` | 1 |
| `client/test/data/sync/sync_engine_test.dart` | 3 |
| `client/test/ui/sync/login_page_test.dart` | 1 |

Run 核对（应无输出）：
```bash
cd client && grep -rn "FakeOSS\|fake_oss\|OSSGateway" test/ lib/
```

- [ ] **Step 8: 验证**

Run:
```bash
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" analyze
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" test test/data/sync/fake_cos_test.dart
```
Expected: analyze 无新增 warning；fake_cos_test 输出 `All tests passed!`，计数 **4**（与 Step 1 一致）。

- [ ] **Step 9: 提交**

```bash
git add client/lib/src/data/sync/fake_cos.dart client/lib/main.dart client/lib/src/data/sync/sync_engine.dart client/test/data/sync/fake_cos_test.dart client/test/data/sync/sync_engine_photo_test.dart client/test/data/sync/sync_engine_runtime_test.dart client/test/data/sync/sync_engine_stamps_test.dart client/test/data/sync/sync_engine_test.dart client/test/ui/home_page_photo_sync_test.dart client/test/ui/sync/login_page_test.dart
git commit -m "refactor(F013):重命名本地存储替身为FakeCos,rename fake storage to FakeCos"
```

> ⚠️ **不要 add 旧路径**（`fake_oss.dart`、`fake_oss_test.dart`）。`git mv` 已把删除记入索引，add 旧路径会报 `fatal: pathspec ... did not match any files`，且遇到无效 pathspec 时整条 `git add` 命令中止——后面的路径一个都不会被暂存。只 add 仍存在的路径即可；`git mv` 的重命名记录由索引自动携带。

---

### Task 3: SyncEngine 与 UI 的 cos 字段重命名

**Files:**
- Modify: `client/lib/src/data/sync/sync_engine.dart`
- Modify: `client/lib/src/ui/home_page.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/test/data/sync/sync_engine_photo_test.dart`
- Modify: `client/test/data/sync/sync_engine_runtime_test.dart`
- Modify: `client/test/data/sync/sync_engine_stamps_test.dart`
- Modify: `client/test/data/sync/sync_engine_test.dart`
- Modify: `client/test/ui/home_page_photo_sync_test.dart`
- Modify: `client/test/ui/sync/login_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `CosGateway`、Task 2 的 `FakeCos`
- Produces: `SyncEngine` 构造函数参数 `cos`（类型 `CosGateway`），实例字段 `cos`。`home_page.dart` 通过 `widget.syncEngine!.cos.download(key)` 取字节。

- [ ] **Step 1: 改写 `sync_engine.dart`**

第 36 行构造参数：
```dart
    required this.oss,
```
改为：
```dart
    required this.cos,
```

第 43 行字段声明：
```dart
  final OSSGateway oss;
```
改为：
```dart
  final CosGateway cos;
```

第 80 行的注释与第 85 行的调用：
```dart
    // 照片上传：photo 有 BLOB 但无 photoKey 的条目，上传 OSS 并设 key。
```
改为：
```dart
    // 照片上传：photo 有 BLOB 但无 photoKey 的条目，上传 COS 并设 key。
```

```dart
        final key = await oss.upload(e.photo!);
```
改为：
```dart
        final key = await cos.upload(e.photo!);
```

第 133 行的注释：
```dart
      // 照片下载：photoKey 有但本地 photo BLOB 缺失，从 OSS 下载缓存。
```
改为：
```dart
      // 照片下载：photoKey 有但本地 photo BLOB 缺失，从 COS 下载缓存。
```

第 136 行的调用：
```dart
        final bytes = await oss.download(merged.photoKey!);
```
改为：
```dart
        final bytes = await cos.download(merged.photoKey!);
```

- [ ] **Step 2: 改写 `home_page.dart`**

第 53 行的注释：
```dart
  /// 从 OSS 下载回来的照片字节（photo=null 但 photoKey 存在时用）。
```
改为：
```dart
  /// 从 COS 下载回来的照片字节（photo=null 但 photoKey 存在时用）。
```

第 56 行的注释：
```dart
  /// photoKey）。composer 凭 photoKey 向 OSS 下载一份临时字节显示缩略图；
```
改为：
```dart
  /// photoKey）。composer 凭 photoKey 向 COS 下载一份临时字节显示缩略图；
```

第 93 行的注释：
```dart
  /// 存在就向 OSS 下载一份临时字节显示；都没有就清空。
```
改为：
```dart
  /// 存在就向 COS 下载一份临时字节显示；都没有就清空。
```

第 121 行的注释：
```dart
  /// 按 photoKey 从 OSS 下载照片字节，下载成功后 setState 显示。
```
改为：
```dart
  /// 按 photoKey 从 COS 下载照片字节，下载成功后 setState 显示。
```

第 127 行的调用：
```dart
      final bytes = await widget.syncEngine!.oss.download(key);
```
改为：
```dart
      final bytes = await widget.syncEngine!.cos.download(key);
```

- [ ] **Step 3: 改写 `main.dart`**

第 46 行的构造调用：
```dart
      oss: FakeCos(),
```
改为：
```dart
      cos: FakeCos(),
```

- [ ] **Step 4: 改写 5 个测试文件的构造调用**

对 `client/test/data/sync/sync_engine_photo_test.dart`、`client/test/data/sync/sync_engine_runtime_test.dart`、`client/test/data/sync/sync_engine_stamps_test.dart`、`client/test/data/sync/sync_engine_test.dart`、`client/test/ui/home_page_photo_sync_test.dart`、`client/test/ui/sync/login_page_test.dart` 这 6 个文件，把 `SyncEngine(...)` 构造里的 `oss:` 改为 `cos:`。

Run 核对（应无输出）：
```bash
cd client && grep -rn "oss:" test/ lib/
```

- [ ] **Step 5: 改写 `home_page_photo_sync_test.dart` 的内存替身**

第 37 行的注释块与第 46 行的类声明（Task 2 已把 `implements OSSGateway` 改成 `implements CosGateway`，本步改类名与注释）：

```dart
/// 内存版 COS 替身：upload 返回递增 key 并记下字节，download 按 key 取回。
///
/// 不用 [FakeCos]（真实文件 I/O）的原因：widget 测试跑在 FakeAsync 上，
/// `File.readAsBytes` 的延续不会在 `pumpAndSettle` 时排空——只有
/// `tester.runAsync` 直接 await 才能拿到结果，而 composer 内部的
/// `cos.download` 是 fire-and-forget，延续永远排不上空。预解析的
/// `Future.value` 走微任务队列，能被 `pumpAndSettle` 排空，行为等价
/// （按 key 返回字节），适合驱动 UI。真实 I/O 路径由 sync_engine 层的
/// `test()` 覆盖（见 sync_engine_photo_test.dart）。
class _InMemoryCos implements CosGateway {
```

该文件里 `_InMemoryOSS` 的 3 处出现全部改掉：
- 第 46 行：类声明（见上）
- 第 154 行：`final oss = _InMemoryOSS();` → `final oss = _InMemoryCos();`
- 第 194 行注释：`// 下载是微任务（_InMemoryOSS 预解析 Future），pumpAndSettle 排空后` → `// 下载是微任务（_InMemoryCos 预解析 Future），pumpAndSettle 排空后`

该文件其余的 `'some-oss-key'` 字面量是测试夹具数据，**保留不动**（与厂商无关）。

- [ ] **Step 6: 验证**

Run:
```bash
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" analyze
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" test
```
Expected: analyze 无新增 warning；test 输出 `All tests passed!`，计数 **442**。

- [ ] **Step 7: 提交**

```bash
git add client/lib/src/data/sync/sync_engine.dart client/lib/src/ui/home_page.dart client/lib/main.dart client/test/data/sync/sync_engine_photo_test.dart client/test/data/sync/sync_engine_runtime_test.dart client/test/data/sync/sync_engine_stamps_test.dart client/test/data/sync/sync_engine_test.dart client/test/ui/home_page_photo_sync_test.dart client/test/ui/sync/login_page_test.dart
git commit -m "refactor(F013):同步引擎改用cos字段,rename sync engine storage field to cos"
```

---

### Task 4: 领域注释与存储键表述统一

**Files:**
- Modify: `packages/sync_core/lib/src/entry_sync.dart`
- Modify: `client/lib/src/domain/entry.dart`
- Modify: `client/lib/src/data/local/sqlite_entry_repository.dart`
- Modify: `client/lib/src/ui/entry_editor_controller.dart`
- Modify: `client/test/support/memory_repository.dart`
- Modify: `client/test/data/sync/sync_engine_photo_test.dart`

**Interfaces:**
- Consumes: 无（纯注释改动）
- Produces: 无接口变化。`photoKey` 字段名与 `photo_key` 列名**不变**，只改注释文字。

- [ ] **Step 1: 改写 `entry_sync.dart` 的注释**

`packages/sync_core/lib/src/entry_sync.dart` 第 9 行：
```dart
/// - photo: String?（OSS key；null 表示无照片）
```
改为：
```dart
/// - photo: String?（COS key；null 表示无照片）
```

- [ ] **Step 2: 改写 `entry.dart` 的注释**

第 22 行：
```dart
    this.photoKey,          // 可选；照片 OSS key（同步字段），BLOB 留本地不同步
```
改为：
```dart
    this.photoKey,          // 可选；照片 COS key（同步字段），BLOB 留本地不同步
```

第 45 行：
```dart
  /// 照片 OSS key（同步字段）。非空表示照片已上传 OSS，其他设备凭此 key
```
改为：
```dart
  /// 照片 COS key（同步字段）。非空表示照片已上传 COS，其他设备凭此 key
```

- [ ] **Step 3: 改写 `sqlite_entry_repository.dart` 的 3 处注释**

第 105 行：
```dart
              // 列可能已在。photo_key 存照片 OSS key（String?），是跨设备同步
```
改为：
```dart
              // 列可能已在。photo_key 存照片 COS key（String?），是跨设备同步
```

第 136 行与第 218 行（两处相同）：
```dart
    // photoKey 存 OSS key（TEXT）：null 即清除已有 key。
```
改为：
```dart
    // photoKey 存 COS key（TEXT）：null 即清除已有 key。
```

第 471 行：
```dart
              // 插入时带上照片 OSS key：存 TEXT，null 即不带 key。
```
改为：
```dart
              // 插入时带上照片 COS key：存 TEXT，null 即不带 key。
```

- [ ] **Step 4: 改写 `memory_repository.dart` 的 2 处注释**

第 191 行：
```dart
      // 照片 OSS key 是同步字段，软删除不碰它：跨设备仍靠 key 下载。
```
改为：
```dart
      // 照片 COS key 是同步字段，软删除不碰它：跨设备仍靠 key 下载。
```

第 215 行：
```dart
      // 恢复不碰照片 OSS key：删除标记清了，key 仍保留供跨设备下载。
```
改为：
```dart
      // 恢复不碰照片 COS key：删除标记清了，key 仍保留供跨设备下载。
```

- [ ] **Step 5: 改写 `entry_editor_controller.dart` 的注释**

第 46 行：
```dart
  /// 照片 OSS key（同步字段）。编辑一条已同步照片的条目时，这个 key 必须
```
改为：
```dart
  /// 照片 COS key（同步字段）。编辑一条已同步照片的条目时，这个 key 必须
```

- [ ] **Step 6: 改写 `sync_engine_photo_test.dart` 的 3 处文案**

第 69 行：
```dart
      // 先上传一份照片到 OSS，拿到 key。
```
改为：
```dart
      // 先上传一份照片到 COS，拿到 key。
```

第 93 行：
```dart
          reason: 'pull 后 photoKey 必须等于远端字段携带的 OSS key');
```
改为：
```dart
          reason: 'pull 后 photoKey 必须等于远端字段携带的 COS key');
```

第 95 行：
```dart
          reason: 'pull 后必须从 OSS 下载 BLOB 落本地 photo');
```
改为：
```dart
          reason: 'pull 后必须从 COS 下载 BLOB 落本地 photo');
```

- [ ] **Step 7: 验证**

Run:
```bash
cd client && grep -rn "OSS" lib/ test/ --include="*.dart"
```
Expected: **无输出**。`grep` 大小写敏感，`'some-oss-key'` 是小写，不匹配本模式——那 6 处测试夹具字面量保留不动是正确的。

Run:
```bash
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" analyze
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" test
```
Expected: analyze 报 3 个 pre-existing issue（`home_page.dart:51` unused_field、`sync_engine_stamps_test.dart:5` 与 `:6` unused import）——**与基线一致，无新增**；test 计数 **442**。

- [ ] **Step 8: 提交**

```bash
git add client/lib/src/domain/entry.dart client/lib/src/data/local/sqlite_entry_repository.dart client/lib/src/ui/entry_editor_controller.dart client/test/support/memory_repository.dart client/test/data/sync/sync_engine_photo_test.dart
git commit -m "docs(F013):照片存储键注释改为COS,update photo key comments to cos"
```

---

### Task 5: 产品设计文档改为腾讯云 COS 与 ECS 代理路径

**Files:**
- Modify: `docs/产品设计-product-design.md`

**Interfaces:**
- Consumes: 设计文档 D-07（ECS 代理收发字节）、§3.2 数据路径表
- Produces: 无接口变化。产品设计是跨功能架构的唯一维护位置，Task 6 的其他文档需与本任务结果一致。

- [ ] **Step 1: 改写 §3 语音链路的存储表述**

第 54 行：
```markdown
- 音频上传 OSS（私有 bucket，预签名 URL）
```
改为：
```markdown
- 音频上传 COS（私有 bucket，服务端代理读写）
```

- [ ] **Step 2: 改写 §4 同步引擎的图片路径**

第 66 行：
```markdown
- 图片：sha256 秒传 → 预签名 URL 直传 OSS → 库里只存 key
```
改为：
```markdown
- 图片：sha256 秒传 → **经服务端代理 COS**（客户端 ↔ ECS ↔ COS）→ 库里只存 key
```

- [ ] **Step 3: 改写 §6 合规要求的存储表述**

第 76 行：
```markdown
- OSS 必须私有 bucket，音频访问单独鉴权（不能拿到日记列表就能拉所有音频）
```
改为：
```markdown
- COS 必须私有 bucket，音频访问单独鉴权（不能拿到日记列表就能拉所有音频）
```

- [ ] **Step 4: 改写 §9 服务端的部署、备份与成本**

第 109 行：
```markdown
- 部署：单机 + Docker Compose（Postgres + API + Nginx），OSS 托管，不上 K8s
```
改为：
```markdown
- 部署：单机 + Docker Compose（Postgres + API + Nginx），COS 托管，不上 K8s
```

第 112 行：
```markdown
- 备份：Postgres 每日 pg_dump → OSS，保留 30 天；每月手动完整导出。⚠️ 备份数据也要境内，注销时含备份一并清除
```
改为：
```markdown
- 备份：Postgres 每日 pg_dump → COS，保留 30 天；每月手动完整导出。⚠️ 备份数据也要境内，注销时含备份一并清除
```

第 114 行：
```markdown
- 成本：轻量 2核4G ~100元/月 + OSS ~50 + 短信 0.04/条 + 域名 ~100/年 ≈ **150 元/月**
```
改为：
```markdown
- 成本：轻量 2核4G ~100元/月 + COS ~50 + 短信 0.04/条 + 域名 ~100/年 ≈ **150 元/月**
```

- [ ] **Step 5: 改写 §里程碑表的图片表述**

第 234 行：
```markdown
| 4 | 账号 + 同步 + 图片直传 OSS | 2 周 |
```
改为：
```markdown
| 4 | 账号 + 同步 + 图片经服务端代理 COS | 2 周 |
```

- [ ] **Step 6: 核对**

Run:
```bash
cd docs && grep -n "OSS" 产品设计-product-design.md
```
Expected: 无输出。（`阿里云/腾讯云 ASR` 那行不含 OSS 字样，保留不动。）

- [ ] **Step 7: 提交**

```bash
git add docs/产品设计-product-design.md
git commit -m "docs(F013):产品设计对象存储改为腾讯云COS,update product design to tencent cos"
```

---

### Task 6: 功能文档与计划文档的 OSS 表述替换

**Files:**
- Modify: `docs/features/F012-语音输入-voice-input.md`
- Modify: `docs/features/F013-待办-todos.md`
- Modify: `docs/features/README.md`
- Modify: `docs/superpowers/specs/云同步设计-cloud-sync-design.md`
- Modify: `docs/superpowers/plans/云同步-照片同步-photo-sync.md`
- Modify: `docs/superpowers/plans/云同步-sync-core共享包-sync-core-package.md`
- Modify: `docs/superpowers/plans/云同步-部署链路-ecs-deploy.md`
- Modify: `docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md`
- Modify: `docs/test-reports/README.md`
- Modify: `docs/OPPO上架清单-oppo-release-checklist.md`
- Modify: `docs/开源仓库-open-source-repositories.md`

**Interfaces:**
- Consumes: Task 5 的产品设计新表述；设计文档 D-07
- Produces: 全部文档中的对象存储表述统一为 COS，命名统一为 `CosGateway` / `FakeCos`。

- [ ] **Step 1: 改写 F012 语音输入**

`docs/features/F012-语音输入-voice-input.md` 第 26 行：
```markdown
  - 音频上传 OSS（私有 bucket，预签名 URL）。
```
改为：
```markdown
  - 音频上传 COS（私有 bucket，服务端代理读写）。
```

第 42 行：
```markdown
- OSS 必须私有 bucket，音频访问单独鉴权（不能拿到日记列表就能拉所有音频）。
```
改为：
```markdown
- COS 必须私有 bucket，音频访问单独鉴权（不能拿到日记列表就能拉所有音频）。
```

第 45 行的 `转写用国内厂商（阿里云/腾讯云 ASR），不用 OpenAI Whisper。` **保留不动**——那是转写供应商，不是存储。

- [ ] **Step 2: 改写 F013 待办登记**

`docs/features/F013-待办-todos.md` 第 15 行：
```markdown
| T-04 | 真机端到端跨设备同步（含照片） | 未执行 | 无真机 + 无真实 OSS | T-01 / T-02 完成后补做 | 设计 AC-03 / AC-06 |
```
改为：
```markdown
| T-04 | 真机端到端跨设备同步（含照片） | 未执行 | 无真机 + 无真实 COS | T-01 / T-02 完成后补做 | 设计 AC-03 / AC-06 |
```

T-05 与 T-24 两行、T-25 行已在本计划的 Task 6 之前由设计阶段写入，**保留现状不动**，只核对内容与 COS 设计一致。

- [ ] **Step 3: 改写功能台账 F013 行**

`docs/features/README.md` 第 21 行中：
```markdown
照片同步(FakeOSS)
```
改为：
```markdown
照片同步(FakeCos)
```

「未完成项共 25 条」已由设计阶段更新，**保留不动**。

- [ ] **Step 4: 改写云同步设计文档**

`docs/superpowers/specs/云同步设计-cloud-sync-design.md`：

第 5 行：
```markdown
- 范围：Phase 4 第一里程碑——最小身份 + 同步引擎 + 照片同步（fake OSS）
```
改为：
```markdown
- 范围：Phase 4 第一里程碑——最小身份 + 同步引擎 + 照片同步（fake COS）
```

第 9 行末尾的 `Phase 4 是账号 + 同步 + 图片直传 OSS。` → `Phase 4 是账号 + 同步 + 图片经服务端代理 COS。`

第 11 行：
```markdown
本里程碑**包含**：邮箱+密码最小身份、同步引擎（文本字段）、照片同步（fake OSS）。
```
改为：
```markdown
本里程碑**包含**：邮箱+密码最小身份、同步引擎（文本字段）、照片同步（fake COS）。
```

第 12 行：
```markdown
本里程碑**不包含**（延后）：SMS/手机号注册、找回密码、设备信任链、真机阿里云 OSS 端到端、推送通知。
```
改为：
```markdown
本里程碑**不包含**（延后）：SMS/手机号注册、找回密码、设备信任链、真机腾讯云 COS 端到端、推送通知。
```

第 18 行：
```markdown
| 里程碑 | 最小身份(邮箱+密码) + 同步引擎 + 照片同步(fake OSS) |
```
改为：
```markdown
| 里程碑 | 最小身份(邮箱+密码) + 同步引擎 + 照片同步(fake COS) |
```

第 22 行：
```markdown
| 照片 | 本次含，fake OSS 开发，真机端到端延后到 bucket 就绪 |
```
改为：
```markdown
| 照片 | 本次含，fake COS 开发，真机端到端延后到 bucket 就绪 |
```

第 38 行：
```markdown
| `oss_gateway.dart` | `OSSGateway` 抽象：`upload/download/presign`——接口共享，实现客户端侧（fake 开发，真机 OSS 时 presign 由服务端生成） |
```
改为：
```markdown
| `cos_gateway.dart` | `CosGateway` 抽象：`upload/download/presign`——接口共享，实现客户端侧（fake 开发，真机 COS 时由服务端代理读写） |
```

第 54 行：
```markdown
- **OSS 客户端**走 `OSSGateway` 抽象，fake 实现开发。
```
改为：
```markdown
- **COS 客户端**走 `CosGateway` 抽象，fake 实现开发。
```

§6 照片同步（第 84–88 行）整段替换为：

```markdown
- `CosGateway` 抽象：`upload(bytes)→key`、`download(key)→bytes`、`presign(key)→url`
- **Fake COS**：本地文件系统模拟（开发/测试用），不依赖云
- 流程：选照片 → 算 sha256 → `CosGateway.upload` 上传（fake 写本地临时区）→ 得 key → `entry.photo = key` → 同步传播 key
- 其他设备拉取 → 见 key → `CosGateway.download`（fake 读本地）
- **真机腾讯云 COS**（私有桶、境内 ap-guangzhou、**经服务端代理读写**）延后到 bucket 就绪，届时替换 fake 实现
- **照片字段 LWW**：照片是引用（key），整字段替换（取 updatedAt 大的），不做 BLOB 合并
```

第 116 行：
```markdown
- 客户端：SyncEngine 用 fake RemoteRepo + fake OSS + `sqflite_common_ffi` 宿主测试（复用现有测试模式）
```
改为：
```markdown
- 客户端：SyncEngine 用 fake RemoteRepo + fake COS + `sqflite_common_ffi` 宿主测试（复用现有测试模式）
```

第 118 行：
```markdown
- 真机端到端：文本同步可真机验证；**照片同步延后到 OSS bucket 就绪**
```
改为：
```markdown
- 真机端到端：文本同步可真机验证；**照片同步延后到 COS bucket 就绪**
```

第 129 行：
```markdown
| AC-06 | 照片同步（fake OSS） | A 拍照 → 同步 → B 拉取可见照片 |
```
改为：
```markdown
| AC-06 | 照片同步（fake COS） | A 拍照 → 同步 → B 拉取可见照片 |
```

第 136 行：
```markdown
- 真机阿里云 OSS 端到端照片同步（bucket 就绪后补）
```
改为：
```markdown
- 真机腾讯云 COS 端到端照片同步（bucket 就绪后补）
```

- [ ] **Step 5: 改写照片同步计划文档**

`docs/superpowers/plans/云同步-照片同步-photo-sync.md` 做全文替换，逐项对应：

| 原 | 新 |
|---|---|
| `Entry 加 photoKey（OSS key，同步字段）` | `Entry 加 photoKey（COS key，同步字段）` |
| `FakeOSS 实现 OSSGateway` | `FakeCos 实现 CosGateway` |
| `走 OSS 直传` | `走 COS 直传` |
| `上传 OSS 得 key` | `上传 COS 得 key` |
| `真机阿里云 OSS 延后` | `真机腾讯云 COS 延后` |
| `sync_core \`OSSGateway\`` | `sync_core \`CosGateway\`` |
| `Entry.photoKey：String?（OSS key，同步字段）` | `Entry.photoKey：String?（COS key，同步字段）` |
| `FakeOSS：本地文件系统实现 OSSGateway` | `FakeCos：本地文件系统实现 CosGateway` |
| `client/lib/src/data/sync/sync_engine.dart       # OSSGateway 注入` | `client/lib/src/data/sync/sync_engine.dart       # CosGateway 注入` |
| `client/lib/src/data/sync/fake_oss.dart           # FakeOSS（本地文件系统）` | `client/lib/src/data/sync/fake_cos.dart           # FakeCos（本地文件系统）` |
| `this.photoKey,   // 新增：OSS key，同步字段` | `this.photoKey,   // 新增：COS key，同步字段` |
| `## Task 2: photo 映射 + FakeOSS` | `## Task 2: photo 映射 + FakeCos` |
| `client/lib/src/data/sync/fake_oss.dart` | `client/lib/src/data/sync/fake_cos.dart` |
| `client/test/data/sync/fake_oss_test.dart` | `client/test/data/sync/fake_cos_test.dart` |
| `Consumes: \`Entry.photoKey\`、\`OSSGateway\`（sync_core）` | `Consumes: \`Entry.photoKey\`、\`CosGateway\`（sync_core）` |
| `Produces: \`FakeOSS implements OSSGateway\`` | `Produces: \`FakeCos implements CosGateway\`` |
| `import 'package:local_diary/src/data/sync/fake_oss.dart';` | `import 'package:local_diary/src/data/sync/fake_cos.dart';` |
| `final oss = FakeOSS();` | `final oss = FakeCos();` |
| `Expected: FAIL —— \`FakeOSS\`/photo 映射未定义。` | `Expected: FAIL —— \`FakeCos\`/photo 映射未定义。` |
| `/// 本地文件系统实现 OSSGateway（开发/测试用）。upload 写临时目录返回 sha256 key；` | `/// 本地文件系统实现 CosGateway（开发/测试用）。upload 写临时目录返回 sha256 key；` |
| `class FakeOSS implements OSSGateway {` | `class FakeCos implements CosGateway {` |
| `_root = dir ?? Directory.systemTemp.createTempSync('fakeoss');` | `_root = dir ?? Directory.systemTemp.createTempSync('fakecos');` |
| `git add client/lib/src/data/sync/fake_oss.dart ...` | `git add client/lib/src/data/sync/fake_cos.dart ...` |
| `git commit -m "feat(F013):FakeOSS与照片映射,add fake oss and photo mapping"` | `git commit -m "feat(F013):FakeCos与照片映射,add fake cos and photo mapping"` |
| `Modify: \`client/lib/src/data/sync/sync_engine.dart\`（注入 OSSGateway；push 上传设 key；pull 下载 BLOB）` | `Modify: \`client/lib/src/data/sync/sync_engine.dart\`（注入 CosGateway；push 上传设 key；pull 下载 BLOB）` |
| `Consumes: \`OSSGateway\`、\`Entry.photo\`/\`photoKey\`、\`FakeOSS\`。` | `Consumes: \`CosGateway\`、\`Entry.photo\`/\`photoKey\`、\`FakeCos\`。` |
| `Produces: \`SyncEngine({required OSSGateway oss, ...})\`` | `Produces: \`SyncEngine({required CosGateway cos, ...})\`` |
| `import 'package:local_diary/src/data/sync/fake_oss.dart';` | `import 'package:local_diary/src/data/sync/fake_cos.dart';` |
| `SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), oss: oss)` | `SyncEngine(repository: repo, remote: remote, auth: _FakeAuth(), cos: oss)` |
| `Expected: FAIL —— SyncEngine 无 oss 参数 / photo 上传下载未实现。` | `Expected: FAIL —— SyncEngine 无 cos 参数 / photo 上传下载未实现。` |
| `- 构造函数加 \`required OSSGateway oss\`。` | `- 构造函数加 \`required CosGateway cos\`。` |
| `final key = await oss.upload(entry.photo!)` | `final key = await cos.upload(entry.photo!)` |
| `final bytes = await oss.download(photoKey)` | `final bytes = await cos.download(photoKey)` |
| `Consumes: \`SyncEngine.oss\`、\`Entry.photo\`/\`photoKey\`。` | `Consumes: \`SyncEngine.cos\`、\`Entry.photo\`/\`photoKey\`。` |
| `测试替身 FakeOSS 注入 SyncEngine。` | `测试替身 FakeCos 注入 SyncEngine。` |
| `触发一次 oss.download 并 setState 显示` | `触发一次 cos.download 并 setState 显示` |
| `composer 内部的 \`oss.download\`` | `composer 内部的 \`cos.download\`` |
| `**Spec 覆盖**：spec 第 6 节（照片走 OSS 直传、sha256 key、预签名）` | `**Spec 覆盖**：spec 第 6 节（照片走 COS 直传、sha256 key、服务端代理）` |
| `**类型一致**：photoKey/photo/OSSGateway/FakeOSS 签名在实现与测试一致。` | `**类型一致**：photoKey/photo/CosGateway/FakeCos 签名在实现与测试一致。` |
| `真机阿里云 OSS（预签名直传、私有 bucket）延后到 bucket 就绪。` | `真机腾讯云 COS（服务端代理读写、私有 bucket）延后到 bucket 就绪。` |

- [ ] **Step 6: 改写 sync_core 计划文档**

`docs/superpowers/plans/云同步-sync-core共享包-sync-core-package.md`：

第 23 行：
```markdown
| **Part 1（本计划）** | sync_core 共享包：字段级 LWW、同步协议、鉴权/OSS 抽象 | 无 |
```
改为：
```markdown
| **Part 1（本计划）** | sync_core 共享包：字段级 LWW、同步协议、鉴权/COS 抽象 | 无 |
```

第 26 行：
```markdown
| Part 4 | 照片同步：fake OSS + 照片上传/传播 | Part 3 |
```
改为：
```markdown
| Part 4 | 照片同步：fake COS + 照片上传/传播 | Part 3 |
```

第 38 行：
```markdown
  lib/src/oss_gateway.dart              # OSSGateway 抽象
```
改为：
```markdown
  lib/src/cos_gateway.dart              # CosGateway 抽象
```

第 45 行：
```markdown
> 说明：EmailPasswordProvider 与 fake OSS 实现放客户端（Part 3/4），不放 sync_core——它们依赖 `http`/文件系统。sync_core 只放抽象与纯逻辑，保持"纯 Dart、无框架"约束。
```
改为：
```markdown
> 说明：EmailPasswordProvider 与 fake COS 实现放客户端（Part 3/4），不放 sync_core——它们依赖 `http`/文件系统。sync_core 只放抽象与纯逻辑，保持"纯 Dart、无框架"约束。
```

第 108 行：
```yaml
description: "云同步共享纯逻辑包：字段级 LWW 合并、同步协议、鉴权/OSS 抽象。"
```
改为：
```yaml
description: "云同步共享纯逻辑包：字段级 LWW 合并、同步协议、鉴权/COS 抽象。"
```

第 130 行：
```markdown
/// - photo: String?（OSS key；null 表示无照片）
```
改为：
```markdown
/// - photo: String?（COS key；null 表示无照片）
```

第 512 行：
```markdown
## Task 4: 鉴权与 OSS 抽象接口
```
改为：
```markdown
## Task 4: 鉴权与 COS 抽象接口
```

第 517 行：
```markdown
- Create: `packages/sync_core/lib/src/oss_gateway.dart`
```
改为：
```markdown
- Create: `packages/sync_core/lib/src/cos_gateway.dart`
```

第 521 行：
```markdown
- Produces: `AuthResult`、`AuthProvider`（抽象）、`OSSGateway`（抽象）。EmailPasswordProvider 与 fake OSS 实现放客户端（Part 3/4），本任务只锁接口契约。
```
改为：
```markdown
- Produces: `AuthResult`、`AuthProvider`（抽象）、`CosGateway`（抽象）。EmailPasswordProvider 与 fake COS 实现放客户端（Part 3/4），本任务只锁接口契约。
```

第 545–546 行：
```dart
  group('OSSGateway 契约', () {
    test('测试替身可实现 OSSGateway', () async {
```
改为：
```dart
  group('CosGateway 契约', () {
    test('测试替身可实现 CosGateway', () async {
```

第 569 行：
```dart
class _FakeOss implements OSSGateway {
```
改为：
```dart
class _FakeCos implements CosGateway {
```

第 583 行：
```markdown
Expected: FAIL —— `AuthProvider` / `OSSGateway` 未定义。
```
改为：
```markdown
Expected: FAIL —— `AuthProvider` / `CosGateway` 未定义。
```

第 608 行：
```markdown
`packages/sync_core/lib/src/oss_gateway.dart`：
```
改为：
```markdown
`packages/sync_core/lib/src/cos_gateway.dart`：
```

第 613–615 行：
```dart
/// OSS 直传抽象。fake 实现开发期用；真机阿里云 OSS 时 presign 由服务端生成、
/// upload/download 由客户端直连 OSS。本接口不依赖任何 SDK。
abstract interface class OSSGateway {
```
改为：
```dart
/// COS 直传抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理读写。
/// 本接口不依赖任何 SDK。
abstract interface class CosGateway {
```

第 622 行：
```dart
  /// 生成预签名 URL（真机 OSS 用；fake 可返回本地路径）。
```
改为：
```dart
  /// 生成预签名 URL（真机 COS 用；fake 可返回本地路径）。
```

第 631 行：
```dart
export 'src/oss_gateway.dart';
```
改为：
```dart
export 'src/cos_gateway.dart';
```

第 665 行：
```markdown
- **Spec 覆盖**：spec 第 3 节 sync_core 的 entry_sync/merge_decision/sync_protocol/auth_provider/oss_gateway 均有对应任务；EmailPasswordProvider 与 fake OSS 实现按 spec 意图放客户端（Part 3/4），已注明。
```
改为：
```markdown
- **Spec 覆盖**：spec 第 3 节 sync_core 的 entry_sync/merge_decision/sync_protocol/auth_provider/cos_gateway 均有对应任务；EmailPasswordProvider 与 fake COS 实现按 spec 意图放客户端（Part 3/4），已注明。
```

- [ ] **Step 7: 改写部署链路计划文档**

`docs/superpowers/plans/云同步-部署链路-ecs-deploy.md`：

第 40 行：
```markdown
| 真机阿里云 OSS | 照片走 FakeOSS（本地文件系统） |
```
改为：
```markdown
| 真机腾讯云 COS | 照片走 FakeCos（本地文件系统） |
```

第 1263 行中的 `真机 OSS` → `真机 COS`。

第 1269 行中的 `真机 OSS` → `真机 COS`。

第 1282 行：
```markdown
- 本轮服务端用 FakeSyncStore（内存），重启丢数据；PostgresSyncStore 与真机 OSS 是下一轮
```
改为：
```markdown
- 本轮服务端用 FakeSyncStore（内存），重启丢数据；PostgresSyncStore 与真机 COS 是下一轮
```

第 1201 行的「阿里云安全组」**保留不动**——那是 ECS 侧的事实。

- [ ] **Step 8: 改写 F013 测试报告**

`docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md`：

第 10 行：`照片同步（FakeOSS）` → `照片同步（FakeCos）`

第 11 行：`照片同步（schema v7 photo_key + FakeOSS + 上传/下载）` → `照片同步（schema v7 photo_key + FakeCos + 上传/下载）`

第 12 行：
```markdown
- 不包含（延后）：PostgresSyncStore（环境无 postgres）、真机阿里云 OSS（环境无 bucket）、SMS/找回、真机端到端验收。
```
改为：
```markdown
- 不包含（延后）：PostgresSyncStore（环境无 postgres）、真机腾讯云 COS（环境无 bucket）、SMS/找回、真机端到端验收。
```

第 22 行：`| sync_core | 13 | 字段级 LWW、协议编解码、鉴权/OSS 抽象契约 |` → `| sync_core | 13 | 字段级 LWW、协议编解码、鉴权/COS 抽象契约 |`

第 47 行：`否则编辑同步的照片条目会清空 OSS key` → `否则编辑同步的照片条目会清空 COS key`

第 58 行：`| AC-06 | 照片同步 | FakeOSS 上传/下载 + SyncEngine 照片测试通过 | 未执行 |` → `| AC-06 | 照片同步 | FakeCos 上传/下载 + SyncEngine 照片测试通过 | 未执行 |`

第 66 行：`无真实服务端 + 无真实 OSS` → `无真实服务端 + 无真实 COS`

第 70 行：`宿主测试用 FakeSyncStore / FakeOSS / 替身覆盖逻辑契约` → `宿主测试用 FakeSyncStore / FakeCos / 替身覆盖逻辑契约`

第 75 行：
```markdown
2. **照片用 FakeOSS（本地文件系统）**：环境无阿里云 OSS bucket。真机 OSS 直传（预签名、私有 bucket、境内 region）延后。OSSGateway 抽象已就位，届时替换实现。
```
改为：
```markdown
2. **照片用 FakeCos（本地文件系统）**：环境无腾讯云 COS bucket。真机 COS（服务端代理读写、私有 bucket、境内 region）延后。CosGateway 抽象已就位，届时替换实现。
```

第 87 行：`无连接设备 + 无真实服务端/OSS` → `无连接设备 + 无真实服务端/COS`

第 89 行：`部署真实服务端/OSS 后补做真机端到端验收；实现 PostgresSyncStore、真机 OSS、bcrypt、token 刷新。` → `部署真实服务端/COS 后补做真机端到端验收；实现 PostgresSyncStore、真机 COS、bcrypt、token 刷新。`

第 94 行：`- \`dart:crypto\` 在本 SDK 缺失，服务端与 FakeOSS 用 \`package:crypto\`。` → `...服务端与 FakeCos 用 \`package:crypto\`。`

第 183 行：`**真机 OSS**、**token 刷新（AC-08）**` → `**真机 COS**、**token 刷新（AC-08）**`

第 188 行：`接入 PostgresSyncStore 后补做 DP-09 落库验证与真机 OSS` → `...与真机 COS`

第 190 行：`接入 PostgresSyncStore 后补做 DP-09 落库验证与真机 OSS；实现 token 刷新（AC-08）。` → `...与真机 COS；...`

第 102 行的「阿里云 ECS \`i-7xv4buzm47fxdask0bgz\`」**保留不动**——那是 ECS 侧的事实。

- [ ] **Step 9: 改写测试报告索引**

`docs/test-reports/README.md` 第 20 行：
```markdown
**真机端到端验收未执行**（无真实服务端/OSS）
```
改为：
```markdown
**真机端到端验收未执行**（无真实服务端/COS）
```

同行的 `PostgresSyncStore/真机 OSS/bcrypt/token 刷新延后` → `PostgresSyncStore/真机 COS/bcrypt/token 刷新延后`

- [ ] **Step 10: 改写 OPPO 上架清单**

`docs/OPPO上架清单-oppo-release-checklist.md` 第 37 行：
```markdown
| 18 | 数据境内存储 | OSS + 数据库全在**中国大陆境内**；转写用阿里云/腾讯云 ASR，**不用 OpenAI Whisper** |
```
改为：
```markdown
| 18 | 数据境内存储 | COS + 数据库全在**中国大陆境内**；转写用阿里云/腾讯云 ASR，**不用 OpenAI Whisper** |
```

- [ ] **Step 11: 改写开源仓库资料**

`docs/开源仓库-open-source-repositories.md` 第 41 行：
```markdown
- StoryPad 的 Google Drive 同步不直接等同于我们计划的国内 OSS + 自建同步 API。
```
改为：
```markdown
- StoryPad 的 Google Drive 同步不直接等同于我们计划的国内对象存储 + 自建同步 API。
```

- [ ] **Step 12: 核对全仓库**

Run:
```bash
cd docs && grep -rn "OSS" . --include="*.md"
```
Expected: 仅剩以下两处**有意的保留**：
1. `docs/superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md` —— 设计文档本身，记录「从阿里云 OSS 改为腾讯云 COS」的来龙去脉。
2. `docs/superpowers/plans/2026-11-05-腾讯云COS对象存储-tencent-cos-storage.md` —— 本计划文档自身。

其余文件不应有大写 `OSS`（`阿里云/腾讯云 ASR` 那类不含 OSS 字样）。

- [ ] **Step 13: 提交**

```bash
git add docs/features/F012-语音输入-voice-input.md docs/features/F013-待办-todos.md docs/features/README.md docs/superpowers/specs/云同步设计-cloud-sync-design.md docs/superpowers/plans/云同步-照片同步-photo-sync.md docs/superpowers/plans/云同步-sync-core共享包-sync-core-package.md docs/superpowers/plans/云同步-部署链路-ecs-deploy.md docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md docs/test-reports/README.md docs/OPPO上架清单-oppo-release-checklist.md docs/开源仓库-open-source-repositories.md
git commit -m "docs(F013):文档对象存储表述统一为腾讯云COS,unify docs to tencent cos"
```

---

### Task 7: 新增 COS 运维文档与 CAM 策略模板

**Files:**
- Create: `deploy/腾讯云COS配置-tencent-cos-setup.md`
- Create: `deploy/cam-policy.json`
- Modify: `docs/README.md`
- Modify: `docs/产品设计-product-design.md`（补充一处架构表述）

**Interfaces:**
- Consumes: 设计文档 §3.1–§3.6 的全部结论
- Produces: 运维文档 `deploy/腾讯云COS配置-tencent-cos-setup.md`（COS 侧唯一维护位置）；CAM 策略模板 `deploy/cam-policy.json`（占位符 `<APPID>` / `<BUCKET>` / `<PREFIX>`）。

- [ ] **Step 1: 创建 CAM 策略模板**

创建 `deploy/cam-policy.json`，内容：

```json
{
  "version": "2.0",
  "statement": [
    {
      "effect": "allow",
      "action": [
        "name/cos:PutObject",
        "name/cos:GetObject"
      ],
      "resource": [
        "qcs::cos:ap-guangzhou:uid/<APPID>:<BUCKET>-<APPID>/<PREFIX>/*"
      ]
    }
  ]
}
```

> 说明：刻意**不授** `name/cos:DeleteObject`——凭据泄露时防止数据被批量删除。`name/cos:` 前缀是 CAM 控制台**用户策略**的写法（桶策略与元素参考文档用 `cos:`，写错不生效）。所有键必须小写。

- [ ] **Step 2: 创建 COS 运维文档**

创建 `deploy/腾讯云COS配置-tencent-cos-setup.md`，内容：

````markdown
# 腾讯云 COS 配置 · tencent cos setup

F013 云同步的对象存储侧配置说明。ECS 服务端部署见 [阿里云部署](阿里云部署-aliyun-deploy.md)。

- 对象存储：**腾讯云 COS**（原设计为阿里云 OSS，2026-11-05 变更）
- 桶地域：**ap-guangzhou**（广州）
- 数据路径：**ECS 代理收发字节**（客户端 ↔ ECS ↔ COS）
- 后端存储：**对象 key**（不是完整 URL）
- 关联：[COS 设计文档](../docs/superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md) · [F013 待办](../docs/features/F013-待办-todos.md)

## 1. 现状

| 项 | 状态 |
|---|---|
| COS 桶 | **未创建**（F013 待办 T-05） |
| CAM 子用户与策略 | 未创建（T-05） |
| 服务端凭证落地 | 未完成（T-05） |
| 服务端代理端点 | 未实现（T-24） |
| 客户端真机版 `CosGateway` | 未实现（T-24） |
| 标准存储容量包 | **已购买**（抵扣标准存储容量费） |
| 外网下行流量包 | 未购买（流量按量付费） |

## 2. 建桶与配置

1. 腾讯云控制台 → 对象存储 COS → 创建存储桶
   - 名称：`<BUCKET>`（**必须带 `-<APPID>` 后缀**，控制台自动补）
   - 所属地域：**广州（ap-guangzhou）**
   - 访问权限：**私有读写**（私有桶，访问单独鉴权）
   - 版本控制：暂不开
   - 服务端加密：暂不开
2. 记录 **APPID**（账号唯一标识，可在 COS 控制台「存储桶信息」里看到，与桶名 `-<APPID>` 后缀是同一个值）。注意资源串里要填**主账号**的 APPID，不是子账号的。
3. 生命周期规则：**暂不配置**。等有真实存储成本数据后再决定是否把老照片沉降到低频/归档——注意归档类型需要另外购买对应的存储容量包，且读取前需解冻（归档约 1 分钟、冷归档 1~12 小时），用户点开老照片会明显变慢。

## 3. 凭证与最小权限

1. 复制 `deploy/cam-policy.json`，把 `<APPID>`、`<BUCKET>`、`<PREFIX>` 替换成真实值。`<PREFIX>` 建议用 `photos`，与客户端的 key 前缀对应。
2. 访问管理 CAM → 策略 → 新建自定义策略 → **按 JSON 语法创建**，粘贴上一步准备好的策略内容（CAM 控制台的 JSON 编辑器不接受注释与尾随逗号）。
3. 访问管理 CAM → 用户 → 新建子用户（编程访问）。
4. 给子用户绑定上一步创建的自定义策略。
5. 拿到 **SecretId / SecretKey**，写入 **ECS 服务端**的环境变量。**绝不下发客户端。**
6. 凭证轮换时同步更新 ECS 环境变量并重启服务。

> 为什么不授 DeleteObject：凭据泄露时，防止数据被批量删除。注销与清理需求走单独的、需人工确认的流程。

## 4. 资源包与计费

腾讯云 COS 的资源包分三类，**互不抵扣**：

| 类别 | 品种 | 抵扣范围 |
|---|---|---|
| 存储容量包 | 标准 / 低频 / 归档 / 深度归档 / 智能分层 | 对应存储类型的**容量费** |
| 流量包 | 外网下行 / CDN 回源 / 全球加速 / 跨地域复制 | 对应的**流量费** |
| 请求包 | 标准 / 低频读写请求包 | **请求次数**费 |

要点：

- 已购的**标准存储容量包**只抵扣标准存储容量费。
- **外网下行流量包未购** → 照片下载流量当前按量付费（单价以腾讯云 COS 定价页为准）。
- 免费额度资源包**只能抵扣标准存储容量**，不能抵扣流量、请求次数、低频/归档容量——「领了免费额度仍欠费」的常见原因。
- 不同存储类型的容量包不能混用；存储容量包暂不支持抵扣多 AZ 存储类型。
- 抵扣顺序：免费额度包 → 自购包（同为自购包时先到期先抵扣）→ 按量计费。
- 存储容量包**每日**按当天平均存储量抵扣；流量包/请求包**每月**重置抵扣额度，当月未用完不累计。
- 资源包**有地域限制**，中国大陆通用包可抵扣 ap-guangzhou 的用量；若买到的是**指定地域**规格的包，则必须与桶所在地域一致才抵扣。**核实已购容量包是哪种规格**——买成境外地域包则不抵扣大陆桶。

## 5. 跨厂商成本与带宽约束

COS 的内网 endpoint 只对**同地域腾讯云 CVM** 免费开放。本项目 ECS 在阿里云，两家之间无内网，因此每一份照片字节都要跨两次公网：

| 段 | 计费方 | 计费项 |
|---|---|---|
| 客户端 → ECS（上传请求体） | 阿里云 | ECS 公网入方向流量（通常免费） |
| ECS → COS（PUT 对象） | 阿里云 | ECS 公网出方向流量（约 0.8 元/GB） |
| ECS → COS（PUT 对象，COS 侧） | 腾讯云 | COS 外网流入（不计费） |
| COS → ECS（GET 对象） | 腾讯云 | COS 外网下行流量（与存储容量包无关） |
| ECS → 客户端（回传响应体） | 阿里云 | ECS 公网出方向流量（约 0.8 元/GB） |

**一份照片的下载付两份流量费**，存储容量包一份都不抵扣。

> 注：`docs/产品设计-product-design.md` §9 的成本估算「COS ~50」沿用原阿里云 OSS 的量级假设。ECS 代理后跨厂商公网中转会产生两次出向流量，实际月成本需在有真实流量数据后复核。

### 实测带宽（2026-11-05，`8.148.158.13`）

| 路径 | 实测速度 | 换算 |
|---|---|---|
| ECS → 客户端（nginx 443 出向） | **428 KB/s** | ≈ 3.4 Mbps |
| ECS → 公网（腾讯云镜像上传） | 390 KB/s | ≈ 3.1 Mbps |
| 公网 → ECS（入向） | 1.1–1.26 MB/s | ≈ 10 Mbps |
| ECS → 阿里云内网镜像 | 19.7 MB/s | 内网，不计费 |

- 4 条并发连接合计仍为 ~1.3 MB/s → **是峰值封顶，不是单连接限速**。
- 同线路本机下载 7 MB/s → 排除测试端网络限制。
- `deploy/阿里云部署-aliyun-deploy.md` 里记的「基础带宽 0.2 Gbit/s」是**内网**带宽，不代表公网。

**换算到体验**（手机照片典型 3–5 MB）：下载 1 张 4 MB 照片 ≈ **10 秒**；两台设备同步 100 张照片 ≈ **16 分钟**。

## 6. nginx 请求体上限

`deploy/nginx/diary-sync.conf` 的配置是 `client_max_body_size 8m`。超过 **8 MB** 的照片经 ECS 上传会被 nginx 拒绝。手机照片常见 3–5 MB，但 HDR / 长焦可能超标——T-24 实现时需一并处理（调大上限，或客户端上传前压缩）。

## 7. 真机实现指引（T-24）

服务端需要能读写 COS。腾讯云的签名算法与阿里云 OSS 不同，不能直接搬。注意点：

- 签名绑定四要素：HTTP 方法、桶、对象键、有效期。
- SDK 默认签名会签入 `Host` header；不签入 Host 可能导致请求失败。
- 单个预签名上传最大支持 5GB。
- **Dart 生态注意**：pub.dev 上**没有纯 Dart 的官方 COS SDK**（不依赖 Flutter 的官方实现）。`tencentcloud_cos_sdk_plugin` 是**腾讯云官方**发布的 Flutter 插件（含 `getPresignedUrl`），面向客户端 Flutter 应用；`tencent_cos_dart`（0.1.x）是**社区包**，非官方。**本项目两者都不采用**——D-07 架构下客户端不集成任何云存储 SDK（凭证只存服务端，客户端走 ECS 代理），服务端是纯 Dart、官方 Flutter 插件不适用。服务端若走 HTTP 直调 COS，可用 `package:crypto` 自行实现签名（`q-sign-algorithm=sha1`），避免引入非官方依赖。

真机验收时注意：**2024-01-01 后创建的桶不支持用默认域名在浏览器直接预览文件**，验收要靠 App 内流程，不能靠浏览器打开默认域名看图。
````

- [ ] **Step 3: 补一句服务端职责的准确表述**

`docs/产品设计-product-design.md` 第 46 行现在是：

```markdown
- 本地库是唯一真相源，服务器只做同步管道
```

ECS 代理方案下，服务端还要代理照片字节收发，不再只是「同步管道」。这一行是跨功能架构的核心表述，需要保持准确。改为：

```markdown
- 本地库是唯一真相源，服务器只做同步管道与照片字节代理（见 §4）
```

> 不要动同段落的另外两条铁律（UI 层不直接碰 RemoteRepo、写入只走 LocalRepo、Domain 层不 import 任何框架/SDK）——它们仍然成立。

- [ ] **Step 4: 修正代码里最后一处「直传」表述**

`packages/sync_core/lib/src/cos_gateway.dart` 第 3–4 行现在是：

```dart
/// COS 直传抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理 COS
/// 读写（本接口不依赖任何 SDK）。
```

「直传」是旧架构（客户端直连对象存储）的说法，与已确定的 ECS 代理架构矛盾——Task 6 已把全部文档里的「直传」改为「经服务端代理」，这里要保持一致。改为：

```dart
/// COS 访问抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理 COS
/// 读写（本接口不依赖任何 SDK）。
```

> 只改这一处注释文字，**不动接口声明、方法签名、方法体**——那些是 Task 1 已评审通过的内容。

- [ ] **Step 5: 更新文档总索引**

`docs/README.md` 的「按问题找文档」表格，在「如何准备 OPPO 上架」那一行之后新增一行：

```markdown
| 如何部署服务端、配置对象存储 | [部署与云资源配置](../deploy/阿里云部署-aliyun-deploy.md) | ECS 实例、nginx、systemd，以及 COS 桶、凭证、资源包 |
```

并在该表下方、「新功能使用的模板」之前，新增一段：

```markdown
## 部署文档

服务端与对象存储的部署配置在 [`deploy/`](../deploy/) 目录：

- [阿里云部署](../deploy/阿里云部署-aliyun-deploy.md)：ECS 实例、镜像选型、初始化脚本、nginx 与 systemd、带宽与变配
- [腾讯云 COS 配置](../deploy/腾讯云COS配置-tencent-cos-setup.md)：存储桶、CAM 凭证与最小权限策略、资源包与抵扣范围、跨厂商成本与实测带宽
```

> 注：`docs/README.md` 里的链接指向 `../deploy/`（仓库根下的 deploy 目录），不是 `docs/deploy/`。

- [ ] **Step 6: 校验 JSON 与链接**

Run:
```bash
python -c "import json;json.load(open('deploy/cam-policy.json'));print('cam-policy.json OK')"
```
Expected: 输出 `cam-policy.json OK`

Run:
```bash
grep -n "腾讯云COS配置-tencent-cos-setup\|阿里云部署-aliyun-deploy" docs/README.md
```
Expected: 两处都能匹配到（索引行 + 部署文档段落）。

Run:
```bash
ls deploy/腾讯云COS配置-tencent-cos-setup.md deploy/cam-policy.json
```
Expected: 两个文件都存在。

- [ ] **Step 7: 提交**

```bash
git add deploy/腾讯云COS配置-tencent-cos-setup.md deploy/cam-policy.json docs/README.md docs/产品设计-product-design.md packages/sync_core/lib/src/cos_gateway.dart
git commit -m "docs(F013):新增腾讯云COS配置文档与CAM策略,add tencent cos setup doc and cam policy"
```

---

### Task 8: 全量验证与最终核对

**Files:**
- Verify only（不修改文件）

**Interfaces:**
- Consumes: Task 1–7 的全部产出
- Produces: 验证结论。发现问题时回到对应 Task 修复，不在本任务直接改代码。

- [ ] **Step 1: 全仓库搜索残留标识符**

Run:
```bash
grep -rn "OSSGateway\|FakeOSS\|oss_gateway\|fake_oss\|_InMemoryOSS\|_FakeOss" client/ packages/ deploy/ docs/ --include="*.dart" --include="*.md" --include="*.yaml" --include="*.json"
```
Expected: 仅命中本计划文档与 COS 设计文档自身（它们记录改名前的旧名）。代码文件（`*.dart`）**零命中**。`deploy/腾讯云COS配置-tencent-cos-setup.md` 里的 `CosGateway` 是**新名**，不匹配本模式。

- [ ] **Step 2: 全仓库搜索残留 OSS 表述**

Run:
```bash
grep -rn "OSS" docs/ deploy/ --include="*.md" --include="*.json" --include="*.sh"
```
Expected: 仅命中**三个有意保留的文件**：

1. `docs/superpowers/plans/2026-11-05-腾讯云COS对象存储-tencent-cos-storage.md` —— 本计划文档自身。
2. `docs/superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md` —— COS 设计文档。
3. `deploy/腾讯云COS配置-tencent-cos-setup.md` —— 新增的运维文档，有 **3 处** OSS 字样，均为**历史或对照说明**：
   - 第 5 行「对象存储：**腾讯云 COS**（原设计为阿里云 OSS，2026-11-05 变更）」——记录变更来龙去脉。
   - 第 78 行「§9 的成本估算「COS ~50」沿用原阿里云 OSS 的量级假设」——说明估算来源。
   - 第 101 行「腾讯云的签名算法与阿里云 OSS 不同，不能直接搬」——技术对照，防移植踩坑。

其余文件零命中——包括 `deploy/阿里云部署-aliyun-deploy.md`、`deploy/ram-policy.json`、`deploy/deploy-app.sh`、`deploy/nginx/diary-sync.conf`（实测这 4 个文件本来就不含 OSS 字样）。

- [ ] **Step 3: 三包静态分析**

Run:
```bash
cd packages/sync_core && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" analyze
cd packages/server && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" analyze
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" analyze
```
Expected: sync_core 与 server 输出 `No issues found`；client 报 **3 个 issue**，与基线完全一致（`home_page.dart:51` 的 `unused_field _undoableEntryId`、`sync_engine_stamps_test.dart:5` 与 `:6` 的 2 个 unused import）。出现任何**新增** issue 即为失败。

- [ ] **Step 4: 三包测试**

Run:
```bash
cd packages/sync_core && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" test
cd packages/server && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\dart.ps1" test
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" test
```
Expected: 三个包全部 `All tests passed!`；计数与基线一致——sync_core **13**、server **31**、client **442**。任何一项失败或计数变化都必须查明原因。

- [ ] **Step 5: 构建 APK**

Run:
```bash
cd client && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\dev\myapp\scripts\flutter.ps1" build apk --debug
```
Expected: 构建成功。

- [ ] **Step 6: 确认工作区未污染**

Run:
```bash
git status --short
```
Expected: 只应看到本计划开始前就存在的未提交改动：

```
 M client/pubspec.lock
 M deploy/deploy-app.sh
 M packages/server/lib/src/fake_sync_store.dart
 M packages/server/pubspec.lock
 M packages/server/test/fake_sync_store_sync_test.dart
 M packages/sync_core/pubspec.lock
?? packages/server/tool_bcrypt_probe.dart
```

`packages/sync_core/pubspec.lock` 的 `M` 是本计划开始前就有的（`pubspec.yaml` 的改动已随 Task 1 提交）。**不应出现任何本计划涉及的新未提交文件。**

- [ ] **Step 7: 提交最终验证记录**

把验证结果追加到 F013 测试报告末尾（新增一节）：

```markdown
## 第三轮：对象存储供应商迁移与命名对齐（2026-11-05）

- 关联设计：[腾讯云 COS 对象存储](../superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md)
- 被测 commit：本轮提交（分支 `feat/F013-cloud-sync`）
- 改动性质：纯机械重命名 + 文档替换，**运行行为不变**

| 检查 | 结果 |
|---|---|
| sync_core 静态分析 | No issues found |
| server 静态分析 | No issues found |
| client 静态分析 | 无新增 warning |
| sync_core 测试 | 13 项全过 |
| server 测试 | 31 项全过 |
| client 测试 | 442 项全过 |
| client 调试 APK 构建 | 成功 |

- 命名：`OSSGateway`→`CosGateway`、`FakeOSS`→`FakeCos`、`oss_gateway.dart`→`cos_gateway.dart`、`fake_oss.dart`→`fake_cos.dart`、`SyncEngine.oss`→`SyncEngine.cos`。
- 文档：产品设计、F012、F013 待办与台账、云同步设计、三份实现计划、测试报告、OPPO 上架清单、开源仓库资料中的对象存储表述统一为腾讯云 COS；ECS 侧事实表述保持不动。
- 新增：`deploy/腾讯云COS配置-tencent-cos-setup.md`、`deploy/cam-policy.json`。
- **未执行**：真机腾讯云 COS 读写（T-05 / T-24）。桶尚未创建，本次不含任何真实 COS 链路的验证证据。
```

Run:
```bash
git add docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md
git commit -m "docs(F013):记录COS迁移轮验证结果,record cos migration verification"
```

- [ ] **Step 8: 汇报**

向用户汇报：

1. 改动了哪些文件（Task 1–7 的产出清单）
2. 三包静态分析与测试结果、APK 构建结果
3. **明确说明真机 COS 未验证**——桶尚未创建，本轮没有任何真实 COS 链路的证据
4. 下一步待办：T-05（建桶 + CAM 凭证）、T-24（真机代理读写实现）、T-25（ECS 带宽限制待缓解）

---

## 附：不在本计划范围

- 建桶、CAM 子用户创建、凭证落地 → F013 待办 T-05
- 服务端 COS 代理读写端点、客户端真机 `CosGateway` → F013 待办 T-24
- ECS 带宽缓解措施（客户端压缩 / 升配 / 回退直连） → F013 待办 T-25 与 COS 设计文档 §9
- 购买外网下行流量包 → 等月流量数据
- 照片生命周期沉降到低频/归档 → 等存储成本数据
- ECS 迁移到腾讯云 → 已决定不做
