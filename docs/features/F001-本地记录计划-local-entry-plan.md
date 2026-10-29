# F001 本地文字记录开发计划

执行方式：使用 writing-plans 制定计划，executing-plans 在当前会话实施，test-driven-development 验证核心行为；沿用项目指定文档路径。

目标：实现 F001 本地文字记录与回顾闭环。
架构：纯 Dart Domain 接口；SQLite LocalRepo；UI 控制器协调串行保存与界面状态。
技术：Flutter stable、Dart、sqflite、path、uuid；sqflite_common_ffi 用于宿主数据库测试。
需求：[F001 本地记录](F001-本地记录-local-entry.md)。

## 全局约束与复核重点

- 停输 1 秒保存；成功落库后才显示已保存；不用网络与账户。
- Domain 不引入 Flutter 或数据库 SDK；所有写入通过 LocalRepo。
- 特别验证：保存中继续输入、保存失败后导航、同时间分页、重启持久化、空白编辑。
- 当前不是 Git 仓库，按项目约定原地执行；不要求用户重复批准已授权的本地闭环。进度以本文记录替代依赖 Git 的技能辅助脚本。

## 任务 1：工程与本地仓储

文件：`client/pubspec.yaml`、`client/lib/src/domain/entry.dart`、`client/lib/src/domain/local_entry_repository.dart`、`client/lib/src/data/local/sqlite_entry_repository.dart`、`client/test/data/sqlite_entry_repository_test.dart`。

接口：`Entry(id, content, createdAt, updatedAt, dayKey)`；`EntryCursor(createdAt, id)`；`LocalEntryRepository.save(Entry)`、`list({EntryCursor? before, int limit = 30})`、`close()`；SQLite 实现通过数据库工厂与路径注入支持真实文件测试。

- [x] 安装可用 SDK，生成 Android Flutter 工程，配置依赖。
- [x] 写仓储行为测试与接口骨架，运行并观察未实现断言失败。
- [x] 实现 schema v1、事务 upsert、dayKey 索引、创建时间/ID 索引、WAL 和 busy_timeout。
- [x] 运行 `flutter test test/data/sqlite_entry_repository_test.dart`，预期数据库重开、更新与分页通过。

## 任务 2：自动保存与导航保护

文件：`client/lib/src/ui/entry_editor_controller.dart`、`client/test/ui/entry_editor_controller_test.dart`。

接口：`EntryEditorController(repository, idGenerator, now)`；`updateContent(String)`、`Future<bool> flush()`、`Future<bool> newEntry()`、`Future<bool> edit(Entry)`；状态含正文、保存状态、错误及是否有待保存输入。

- [x] 先写停输延迟、失败重试、下一条保护及慢写入竞态测试，观察失败。
- [x] 实现 1 秒 debounce、串行持久化、基于版本的保存状态和失败保留。
- [x] 运行 `flutter test test/ui/entry_editor_controller_test.dart`，预期所有行为断言通过。

## 任务 3：界面闭环与交付

文件：`client/lib/main.dart`、`client/lib/app.dart`、`client/lib/src/ui/home_page.dart`、`client/lib/src/ui/timeline_page.dart`、`client/test/ui/app_test.dart`，必要的初始化与说明页面分离文件。

- [x] 写组件测试验证输入→保存→列表→编辑及空状态，观察失败。
- [x] 实现记录、回顾、我的、加载与重试状态；处理生命周期 flush 和返回失败保护。
- [x] 执行 `dart format`、`flutter analyze`、`flutter test`，预期格式、分析与测试通过。
- [x] 执行 `flutter build apk --debug` 并记录真实构建结果；有可用设备则运行闭环，否则标记设备验收未执行。
- [x] 进行最终代码审查，修复关键问题并重跑相关检查。
- [x] 更新 README 实际命令、功能台账与测试报告，保留未完成项。

## 执行记录

- 2026-10-28：已核对需求与环境。Flutter 官方发布索引确认 stable 3.47.8，准备下载并校验 SHA256。初始环境没有 Android 开发工具。

- 2026-10-28：任务 1、2 已完成，任务 3 功能及组件测试完成。慢写入新增内容遗留定时器问题经失败测试定位后修复；现有 17 项测试通过，flutter analyze 无问题。独立只读审查未发现确定阻塞缺陷；设备行为与极长正文边界保留待验证。
- 决策：无 Git 基线，使用当前文档记录进度；不伪造提交。Android APK 首次构建仍在处理依赖，设备验收待连接设备。
- 次要建议暂缓：busy_timeout 可直接使用 rawQuery；锁定的 sqflite_android 2.4.5 已处理 PRAGMA 返回行，因此当前未认定为故障。

- 2026-10-28 最终结果：17 项测试、静态分析、APK 构建通过，产物和 SHA256 已记录在测试报告。构建问题通过 SQLite hook 分平台配置、Gradle 与 Maven HTTPS 镜像解决。Android 设备未连接，真机验收仍待执行，功能台账保持待测试。
- 目录整理限制：自动审批策略拒绝删除旧空目录；占位文件已移除，旧 client/src 和 client/tests 空目录保留，不作为源码入口。
