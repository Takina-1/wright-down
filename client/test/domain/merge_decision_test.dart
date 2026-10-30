import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/entry.dart';
import 'package:local_diary/src/domain/export/merge_decision.dart';

void main() {
  Entry entry({
    String id = 'a',
    String content = '正文',
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Entry(
    id: id,
    content: content,
    createdAt: DateTime.utc(2026, 10, 28, 3),
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 28, 3),
    dayKey: '2026-10-28',
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
    final decision = decideMerge(
      local: entry(content: '旧正文'),
      incoming: entry(content: '新正文', updatedAt: DateTime.utc(2026, 11, 1)),
    );
    expect(decision.action, MergeAction.update);
    expect(decision.entry.content, '新正文');
    expect(decision.entry.createdAt, DateTime.utc(2026, 10, 28, 3));
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
    final decision = decideMerge(
      local: entry(updatedAt: DateTime.utc(2026, 11, 1, 0, 0, 0, 500)),
      incoming: entry(updatedAt: DateTime.utc(2026, 11, 1, 0, 0, 0, 500)),
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
