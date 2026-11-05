# F013 云同步实现计划 · Part 1：sync_core 共享包

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立客户端与服务端共享的纯 Dart 包 `sync_core`，含字段级 LWW 合并、同步协议类型与编解码，作为云同步的"单一真相源"。

**Architecture:** 独立 Dart 包（`packages/sync_core/`），不依赖 flutter/shelf/postgres，宿主可测。客户端 RemoteRepo 与服务端 merge logic 都引用同一份合并规则，冲突解决不漂移。本 Part 只产出纯逻辑与类型，不含 HTTP、不含服务端、不含客户端 UI。

**Tech Stack:** Dart 3.13.7，`dart:convert`/`dart:typed_data`，`dart_test`。无第三方运行时依赖。

## 全局约束

- SDK 约束：`sdk: ^3.13.7`（与 client 一致）。
- 包位置：`packages/sync_core/`，独立 pubspec；client 与未来 server 用 `path` 依赖引用。
- 纯 Dart：不依赖 `flutter`、`shelf`、`postgres`、`http`。仅用 `dart:` 库。
- 命名：Markdown 与提交信息遵循项目约定，中英结合。
- 提交信息格式：`<type>:<中文说明>,<english summary>`，标注 `feat(F013)`。

## 整体拆分（本 Part 是第 1 部分）

| Part | 内容 | 依赖 |
|---|---|---|
| **Part 1（本计划）** | sync_core 共享包：字段级 LWW、同步协议、鉴权/COS 抽象 | 无 |
| Part 2 | 服务端：Dart shelf + postgres，auth + sync API | sync_core |
| Part 3 | 客户端同步引擎：RemoteRepo + SyncEngine + 认领 + 同步状态 UI | sync_core + Part 2 |
| Part 4 | 照片同步：fake COS + 照片上传/传播 | Part 3 |

## 文件结构

```
packages/sync_core/
  pubspec.yaml                          # 独立包，无运行时依赖
  lib/sync_core.dart                    # barrel 导出
  lib/src/entry_sync.dart               # FieldValue, SyncEntry
  lib/src/merge_decision.dart           # 字段级 LWW 纯函数
  lib/src/sync_protocol.dart            # 拉取/推送类型 + SyncCodec
  lib/src/auth_provider.dart            # AuthProvider 抽象 + AuthResult
  lib/src/cos_gateway.dart              # CosGateway 抽象
  test/entry_sync_test.dart
  test/merge_decision_test.dart
  test/sync_protocol_test.dart
  test/interfaces_test.dart             # 抽象契约：测试替身可实现
```

> 说明：EmailPasswordProvider 与 fake COS 实现放客户端（Part 3/4），不放 sync_core——它们依赖 `http`/文件系统。sync_core 只放抽象与纯逻辑，保持"纯 Dart、无框架"约束。

---

## Task 1: sync_core 包骨架 + 字段模型

**Files:**
- Create: `packages/sync_core/pubspec.yaml`
- Create: `packages/sync_core/lib/sync_core.dart`
- Create: `packages/sync_core/lib/src/entry_sync.dart`
- Test: `packages/sync_core/test/entry_sync_test.dart`

**Interfaces:**
- Produces: `FieldValue(Object? v, int t)`、`SyncEntry(String id, int createdAt, Map<String,FieldValue> fields)`，供后续任务与 Part 2/3/4 使用。

- [ ] **Step 1: 写失败测试**

`packages/sync_core/test/entry_sync_test.dart`：

```dart
import 'package:dart_test/dart_test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('FieldValue', () {
    test('相等比较按 v 与 t', () {
      expect(const FieldValue('a', 1), const FieldValue('a', 1));
      expect(const FieldValue('a', 1), isNot(const FieldValue('b', 1)));
      expect(const FieldValue('a', 1), isNot(const FieldValue('a', 2)));
    });

    test('v 可为 null（mood/photo/deletedAt 用）', () {
      expect(const FieldValue(null, 1).v, isNull);
    });
  });

  group('SyncEntry', () {
    test('持有 id、createdAt 与字段映射', () {
      final e = SyncEntry(
        id: 'e1',
        createdAt: 1000,
        fields: const {'content': FieldValue('hi', 2000)},
      );
      expect(e.id, 'e1');
      expect(e.createdAt, 1000);
      expect(e.fields['content']?.v, 'hi');
      expect(e.fields['content']?.t, 2000);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/sync_core && dart test`
Expected: FAIL —— `package:sync_core/sync_core.dart` 不存在。

- [ ] **Step 3: 写实现**

`packages/sync_core/pubspec.yaml`：

```yaml
name: sync_core
description: "云同步共享纯逻辑包：字段级 LWW 合并、同步协议、鉴权/COS 抽象。"
publish_to: 'none'
version: 0.0.1

environment:
  sdk: ^3.13.7

dev_dependencies:
  dart_test: ^1.25.0
```

`packages/sync_core/lib/src/entry_sync.dart`：

```dart
/// 同步字段模型。每个可变字段独立携带版本戳（毫秒），做字段级 LWW。
///
/// 字段取值类型（由 field 名约定，协议层不强制）：
/// - content: String
/// - mood: String?（null 表示无心情）
/// - tags: List<String>
/// - dayKey: String
/// - deletedAt: int?（毫秒；null 表示未删除）
/// - photo: String?（COS key；null 表示无照片）
class FieldValue {
  const FieldValue(this.v, this.t);

  final Object? v;
  final int t;

  @override
  bool operator ==(Object other) =>
      other is FieldValue && other.v == v && other.t == t;

  @override
  int get hashCode => Object.hash(v, t);
}

/// 同步用的条目：不可变的 id 与 createdAt + 字段级可变状态。
class SyncEntry {
  const SyncEntry({
    required this.id,
    required this.createdAt,
    required this.fields,
  });

  final String id;
  final int createdAt; // 毫秒；首次创建确定，同步不修改
  final Map<String, FieldValue> fields;
}
```

`packages/sync_core/lib/sync_core.dart`：

```dart
export 'src/entry_sync.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/sync_core && dart test`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/sync_core
git commit -m "feat(F013):建sync_core字段模型,add sync_core field model"
```

---

## Task 2: 字段级 LWW 合并

**Files:**
- Modify: `packages/sync_core/lib/sync_core.dart`
- Create: `packages/sync_core/lib/src/merge_decision.dart`
- Test: `packages/sync_core/test/merge_decision_test.dart`

**Interfaces:**
- Consumes: `FieldValue`、`SyncEntry`（Task 1）。
- Produces: `FieldValue mergeFieldLww(FieldValue existing, FieldValue incoming)`、`Map<String,FieldValue> mergeSyncEntry(Map<String,FieldValue> local, SyncEntry incoming)`。两端（客户端拉取合并、服务端推送合并）共用同一函数。

- [ ] **Step 1: 写失败测试**

`packages/sync_core/test/merge_decision_test.dart`：

```dart
import 'package:dart_test/dart_test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('mergeFieldLww', () {
    test('incoming 版本戳更大则赢', () {
      final a = const FieldValue('old', 100);
      final b = const FieldValue('new', 200);
      expect(mergeFieldLww(a, b), const FieldValue('new', 200));
    });

    test('incoming 版本戳更小则输', () {
      final a = const FieldValue('new', 200);
      final b = const FieldValue('old', 100);
      expect(mergeFieldLww(a, b), const FieldValue('new', 200));
    });

    test('版本戳相等取 incoming（推送方）', () {
      final a = const FieldValue('local', 200);
      final b = const FieldValue('pushed', 200);
      expect(mergeFieldLww(a, b), const FieldValue('pushed', 200));
    });
  });

  group('mergeSyncEntry', () {
    test('逐字段合并：本地没有的字段直接采用 incoming', () {
      final local = const {'content': FieldValue('a', 100)};
      final incoming = SyncEntry(
        id: 'e1',
        createdAt: 1,
        fields: const {
          'content': FieldValue('b', 200),
          'mood': FieldValue('happy', 200),
        },
      );
      final merged = mergeSyncEntry(local, incoming);
      expect(merged['content'], const FieldValue('b', 200));
      expect(merged['mood'], const FieldValue('happy', 200));
    });

    test('逐字段合并：本地字段更新时不被较旧的 incoming 覆盖', () {
      final local = const {
        'content': FieldValue('local-new', 300),
        'mood': FieldValue('calm', 100),
      };
      final incoming = SyncEntry(
        id: 'e1',
        createdAt: 1,
        fields: const {
          'content': FieldValue('remote-old', 200), // 旧，应被忽略
          'mood': FieldValue('excited', 200),        // 新，应覆盖
        },
      );
      final merged = mergeSyncEntry(local, incoming);
      expect(merged['content'], const FieldValue('local-new', 300));
      expect(merged['mood'], const FieldValue('excited', 200));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/sync_core && dart test test/merge_decision_test.dart`
Expected: FAIL —— `mergeFieldLww` / `mergeSyncEntry` 未定义。

- [ ] **Step 3: 写实现**

`packages/sync_core/lib/src/merge_decision.dart`：

```dart
import 'entry_sync.dart';

/// 字段级 LWW：版本戳大的赢；相等取 incoming（推送方 / 服务端解析态）。
///
/// 客户端拉取合并与服务端推送合并共用本函数，保证两端冲突解决一致。
FieldValue mergeFieldLww(FieldValue existing, FieldValue incoming) {
  return incoming.t >= existing.t ? incoming : existing;
}

/// 把一条 SyncEntry 逐字段合并入本地字段状态，返回合并后的映射。
/// 本地没有的字段直接采用 incoming；已有字段走 [mergeFieldLww]。
Map<String, FieldValue> mergeSyncEntry(
  Map<String, FieldValue> local,
  SyncEntry incoming,
) {
  final merged = <String, FieldValue>{...local};
  for (final e in incoming.fields.entries) {
    final existing = local[e.key];
    merged[e.key] =
        existing == null ? e.value : mergeFieldLww(existing, e.value);
  }
  return merged;
}
```

Modify `packages/sync_core/lib/sync_core.dart`，在末尾追加：

```dart
export 'src/merge_decision.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/sync_core && dart test`
Expected: PASS（含 Task 1 的测试）。

- [ ] **Step 5: 提交**

```bash
git add packages/sync_core
git commit -m "feat(F013):字段级LWW合并,add field-level lww merge"
```

---

## Task 3: 同步协议类型与编解码

**Files:**
- Modify: `packages/sync_core/lib/sync_core.dart`
- Create: `packages/sync_core/lib/src/sync_protocol.dart`
- Test: `packages/sync_core/test/sync_protocol_test.dart`

**Interfaces:**
- Consumes: `FieldValue`、`SyncEntry`（Task 1）。
- Produces: `SyncPullResponse`、`EntryPatch`、`SyncPushBatch`、`SyncCodec`（encode/decode 拉取与推送 JSON）。供 RemoteRepo（客户端）与服务端 handler 共用。

- [ ] **Step 1: 写失败测试**

`packages/sync_core/test/sync_protocol_test.dart`：

```dart
import 'package:dart_test/dart_test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('SyncCodec', () {
    test('拉取响应往返一致', () {
      const codec = SyncCodec();
      final original = SyncPullResponse(
        cursor: 42,
        entries: [
          SyncEntry(
            id: 'e1',
            createdAt: 1000,
            fields: const {
              'content': FieldValue('hello', 2000),
              'mood': FieldValue('happy', 2000),
              'tags': FieldValue(const ['a', 'b'], 2000),
            },
          ),
        ],
      );
      final restored = codec.decodePull(codec.encodePull(original));
      expect(restored.cursor, 42);
      expect(restored.entries.single.id, 'e1');
      expect(restored.entries.single.fields['content'],
          const FieldValue('hello', 2000));
      expect(restored.entries.single.fields['tags']?.v, const ['a', 'b']);
    });

    test('推送批次往返一致', () {
      const codec = SyncCodec();
      final batch = SyncPushBatch(patches: [
        EntryPatch(
          id: 'e1',
          createdAt: 1000,
          fields: const {
            'content': FieldValue('new', 3000),
            'deletedAt': FieldValue(null, 3000),
          },
        ),
      ]);
      final restored = codec.decodePush(codec.encodePush(batch));
      expect(restored.patches.single.id, 'e1');
      expect(restored.patches.single.fields['content'],
          const FieldValue('new', 3000));
      expect(restored.patches.single.fields['deletedAt']?.v, isNull);
    });

    test('空字段映射不崩', () {
      const codec = SyncCodec();
      final batch = SyncPushBatch(patches: [
        EntryPatch(id: 'e1', createdAt: 1, fields: const {}),
      ]);
      final restored = codec.decodePush(codec.encodePush(batch));
      expect(restored.patches.single.fields, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/sync_core && dart test test/sync_protocol_test.dart`
Expected: FAIL —— `SyncPullResponse` / `SyncCodec` 未定义。

- [ ] **Step 3: 写实现**

`packages/sync_core/lib/src/sync_protocol.dart`：

```dart
import 'dart:convert';

import 'entry_sync.dart';

/// 游标：0 表示从最早开始。
typedef Cursor = int;

/// 服务端返回的拉取结果。cursor = 本次结果最大 seq，下次请求带上。
class SyncPullResponse {
  const SyncPullResponse({required this.cursor, required this.entries});
  final int cursor;
  final List<SyncEntry> entries;

  Map<String, dynamic> toJson() => {
        'cursor': cursor,
        'entries': entries.map((e) => _entryToJson(e)).toList(),
      };

  static SyncPullResponse fromJson(Map<String, dynamic> j) => SyncPullResponse(
        cursor: j['cursor'] as int,
        entries: (j['entries'] as List)
            .map((e) => _entryFromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 客户端推送的单条条目变更（仅变更字段，每字段带版本戳）。
class EntryPatch {
  const EntryPatch({
    required this.id,
    required this.createdAt,
    required this.fields,
  });
  final String id;
  final int createdAt;
  final Map<String, FieldValue> fields;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'fields': fields.map((k, v) => MapEntry(k, _fieldToJson(v))),
      };

  static EntryPatch fromJson(Map<String, dynamic> j) => EntryPatch(
        id: j['id'] as String,
        createdAt: j['createdAt'] as int,
        fields: (j['fields'] as Map).map(
            (k, v) => MapEntry(k as String, _fieldFromJson(v as Map<String, dynamic>))),
      );
}

/// 推送批次。
class SyncPushBatch {
  const SyncPushBatch({required this.patches});
  final List<EntryPatch> patches;

  Map<String, dynamic> toJson() =>
      {'patches': patches.map((p) => p.toJson()).toList()};

  static SyncPushBatch fromJson(Map<String, dynamic> j) => SyncPushBatch(
        patches: (j['patches'] as List)
            .map((p) => EntryPatch.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

Map<String, dynamic> _fieldToJson(FieldValue f) => {'v': f.v, 't': f.t};
FieldValue _fieldFromJson(Map<String, dynamic> j) =>
    FieldValue(j['v'], j['t'] as int);
Map<String, dynamic> _entryToJson(SyncEntry e) => {
  'id': e.id,
  'createdAt': e.createdAt,
  'fields': e.fields.map((k, v) => MapEntry(k, _fieldToJson(v))),
};
SyncEntry _entryFromJson(Map<String, dynamic> j) => SyncEntry(
      id: j['id'] as String,
      createdAt: j['createdAt'] as int,
      fields: (j['fields'] as Map).map(
          (k, v) => MapEntry(k as String, _fieldFromJson(v as Map<String, dynamic>))),
    );

/// JSON 编解码入口，供 RemoteRepo 与服务端 handler 共用，宿主测试验证往返。
class SyncCodec {
  const SyncCodec();

  String encodePull(SyncPullResponse r) => jsonEncode(r.toJson());
  SyncPullResponse decodePull(String s) =>
      SyncPullResponse.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String encodePush(SyncPushBatch b) => jsonEncode(b.toJson());
  SyncPushBatch decodePush(String s) =>
      SyncPushBatch.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
```

Modify `packages/sync_core/lib/sync_core.dart`，在末尾追加：

```dart
export 'src/sync_protocol.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/sync_core && dart test`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/sync_core
git commit -m "feat(F013):同步协议与编解码,add sync protocol and codec"
```

---

## Task 4: 鉴权与 COS 抽象接口

**Files:**
- Modify: `packages/sync_core/lib/sync_core.dart`
- Create: `packages/sync_core/lib/src/auth_provider.dart`
- Create: `packages/sync_core/lib/src/cos_gateway.dart`
- Test: `packages/sync_core/test/interfaces_test.dart`

**Interfaces:**
- Produces: `AuthResult`、`AuthProvider`（抽象）、`CosGateway`（抽象）。EmailPasswordProvider 与 fake COS 实现放客户端（Part 3/4），本任务只锁接口契约。

- [ ] **Step 1: 写失败测试**

`packages/sync_core/test/interfaces_test.dart`：

```dart
import 'dart:typed_data';

import 'package:dart_test/dart_test.dart';
import 'package:sync_core/sync_core.dart';

void main() {
  group('AuthProvider 契约', () {
    test('测试替身可实现 AuthProvider', () async {
      final p = _FakeAuth();
      final r = await p.login('a@b.com', 'pw');
      expect(r.userId, 'u1');
      expect(r.token, 'tok');
      expect(await p.current(), isNull);
      await p.signOut();
    });
  });

  group('CosGateway 契约', () {
    test('测试替身可实现 CosGateway', () async {
      final g = _FakeOss();
      final key = await g.upload(Uint8List.fromList([1, 2, 3]));
      expect(key, 'key-1');
      expect((await g.download('key-1')), Uint8List.fromList([1, 2, 3]));
      expect(await g.presign('key-1'), 'fake://key-1');
    });
  });
}

class _FakeAuth implements AuthProvider {
  @override
  Future<AuthResult> register(String email, String password) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult> login(String email, String password) async =>
      AuthResult(userId: 'u1', token: 'tok');
  @override
  Future<AuthResult?> current() async => null;
  @override
  Future<void> signOut() async {}
}

class _FakeCos implements CosGateway {
  @override
  Future<String> upload(Uint8List bytes) async => 'key-1';
  @override
  Future<Uint8List> download(String key) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<String> presign(String key) async => 'fake://$key';
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/sync_core && dart test test/interfaces_test.dart`
Expected: FAIL —— `AuthProvider` / `CosGateway` 未定义。

- [ ] **Step 3: 写实现**

`packages/sync_core/lib/src/auth_provider.dart`：

```dart
/// 登录结果。
class AuthResult {
  const AuthResult({required this.userId, required this.token});
  final String userId;
  final String token;
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
```

`packages/sync_core/lib/src/cos_gateway.dart`：

```dart
import 'dart:typed_data';

/// COS 直传抽象。fake 实现开发期用；真机腾讯云 COS 时由服务端代理读写。
/// 本接口不依赖任何 SDK。
abstract interface class CosGateway {
  /// 上传字节，返回可持久化的 key（sha256）。
  Future<String> upload(Uint8List bytes);

  /// 按 key 下载字节。
  Future<Uint8List> download(String key);

  /// 生成预签名 URL（真机 COS 用；fake 可返回本地路径）。
  Future<String> presign(String key);
}
```

Modify `packages/sync_core/lib/sync_core.dart`，在末尾追加：

```dart
export 'src/auth_provider.dart';
export 'src/cos_gateway.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/sync_core && dart test`
Expected: PASS（全部测试）。

- [ ] **Step 5: 提交并打通 client 引用**

在 `client/pubspec.yaml` 的 `dependencies` 下追加：

```yaml
  sync_core:
    path: ../packages/sync_core
```

Run: `cd client && ../scripts/flutter.ps1 pub get`
Expected: 成功拉取 sync_core，无冲突。

Run: `cd client && ../scripts/flutter.ps1 test`
Expected: 既有 376 项测试仍全过（sync_core 是新增依赖，不影响现有）。

提交：

```bash
git add client/pubspec.yaml client/pubspec.lock
git commit -m "feat(F013):client引用sync_core,link sync_core into client"
```

---

## 自检

- **Spec 覆盖**：spec 第 3 节 sync_core 的 entry_sync/merge_decision/sync_protocol/auth_provider/cos_gateway 均有对应任务；EmailPasswordProvider 与 fake COS 实现按 spec 意图放客户端（Part 3/4），已注明。
- **占位符**：无 TBD/TODO，每步含完整代码与命令。
- **类型一致**：FieldValue/SyncEntry/EntryPatch/SyncPushBatch/SyncPullResponse/SyncCodec 在定义与测试中签名一致；mergeFieldLww 平局取 incoming 与 spec"t 相等取推送方"一致。

## 执行交接

本计划已保存到 `docs/superpowers/plans/云同步-sync-core共享包-sync-core-package.md`。

后续 Part 2（服务端）、Part 3（客户端同步引擎）、Part 4（照片同步）将在 sync_core 完成后依次编写。

**两种执行方式：**

1. **子代理驱动（推荐）** — 每个任务派发独立子代理，任务间两阶段评审，迭代快。
2. **内联执行** — 本会话内按批次执行，带检查点评审。

选哪种？
