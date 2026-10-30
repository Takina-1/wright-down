import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/merge_decision.dart';

void main() {
  Entry entry({
    String id = 'a',
    String content = '正文',
    DateTime? createdAt,
    DateTime? updatedAt,
    String? dayKey,
    DateTime? deletedAt,
  }) => Entry(
    id: id,
    content: content,
    // 创建时属性默认可传，测试里要能故意让本地与备份不同。
    createdAt: createdAt ?? DateTime.utc(2026, 10, 28, 3),
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 28, 3),
    dayKey: dayKey ?? '2026-10-28',
    deletedAt: deletedAt,
  );

  test('本地没有这条时插入', () {
    final decision = decideMerge(local: null, incoming: entry());
    expect(decision.action, MergeAction.insert);
    expect(decision.entry.id, 'a');
  });

  test('本地已删除而备份未删除时跳过，不复活', () {
    final decision = decideMerge(
      local: entry(deletedAt: DateTime.utc(2026, 10, 30, 1)),
      incoming: entry(updatedAt: DateTime.utc(2026, 11, 1)),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('备份更新时更新正文，创建时间以本地为准', () {
    // 本地与备份的创建时属性故意不同：这样断言「以本地为准」才真的能区分，
    // 写错成 incoming 的值时这条用例会变红。
    final decision = decideMerge(
      local: entry(
        content: '旧正文',
        createdAt: DateTime.utc(2026, 10, 28),
        dayKey: '2026-10-28',
      ),
      incoming: entry(
        content: '新正文',
        createdAt: DateTime.utc(2026, 9, 1),
        dayKey: '2026-09-01',
        updatedAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.content, '新正文');
    expect(decision.entry.createdAt, DateTime.utc(2026, 10, 28));
    expect(decision.entry.dayKey, '2026-10-28');
  });

  test('备份更新且带删除标记时，本地条目变为已删除', () {
    final decision = decideMerge(
      local: entry(),
      incoming: entry(
        updatedAt: DateTime.utc(2026, 11, 1),
        deletedAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.deletedAt, DateTime.utc(2026, 11, 1));
  });

  test('备份不比本地新时跳过', () {
    final decision = decideMerge(
      local: entry(updatedAt: DateTime.utc(2026, 11, 1)),
      incoming: entry(updatedAt: DateTime.utc(2026, 10, 1)),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('毫秒精度比较：同一毫秒内不更新', () {
    // 两个时间戳完全相同，落在同一毫秒内：无论怎么比都不该更新。
    final stamp = DateTime.utc(2026, 11, 1, 0, 0, 0, 0, 500);
    final decision = decideMerge(
      local: entry(updatedAt: stamp),
      incoming: entry(updatedAt: stamp),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('毫秒精度比较：备份比本地晚 500 微秒也不算更新', () {
    // 备份在微秒精度上确实更晚，但两者的毫秒数相同：
    // 按毫秒比较应判定为「不比本地新」而跳过。
    // 若把比较改回 isAfter，这条用例会变红。
    final local = DateTime.utc(2026, 11, 1, 0, 0, 0, 0, 0);
    final incoming = DateTime.utc(2026, 11, 1, 0, 0, 0, 0, 500);
    expect(incoming.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    final decision = decideMerge(
      local: entry(updatedAt: local),
      incoming: entry(updatedAt: incoming),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('毫秒精度比较：备份比本地早 500 微秒也不算更新', () {
    final local = DateTime.utc(2026, 11, 1, 0, 0, 0, 0, 500);
    final incoming = DateTime.utc(2026, 11, 1, 0, 0, 0, 0, 0);
    expect(incoming.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    final decision = decideMerge(
      local: entry(updatedAt: local),
      incoming: entry(updatedAt: incoming),
    );
    expect(decision.action, MergeAction.skip);
  });

  test('插入时保留备份里的删除标记', () {
    final decision = decideMerge(
      local: null,
      incoming: entry(deletedAt: DateTime.utc(2026, 10, 30, 1)),
    );
    expect(decision.action, MergeAction.insert);
    expect(decision.entry.deletedAt, DateTime.utc(2026, 10, 30, 1));
  });

  test('本地已删除而备份也带删除标记时按时间比较更新', () {
    final decision = decideMerge(
      local: entry(deletedAt: DateTime.utc(2026, 10, 30, 1)),
      incoming: entry(
        updatedAt: DateTime.utc(2026, 11, 1),
        deletedAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.deletedAt, DateTime.utc(2026, 11, 1));
  });

  test('更新时删除标记以备份为准', () {
    final decision = decideMerge(
      local: entry(),
      incoming: entry(updatedAt: DateTime.utc(2026, 11, 1)),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.deletedAt, isNull);
  });
}
