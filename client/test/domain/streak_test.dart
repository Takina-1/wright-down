import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/streak.dart';

void main() {
  final today = DateTime(2026, 10, 31);

  test('AC-04: 空集合 → current 0、今天未记', () {
    final s = computeStreak([], today: today);
    expect(s.current, 0);
    expect(s.hasEntryToday, isFalse);
    expect(s.display, 0);
  });

  test('AC-04: 只有今天的记录 → current 0（今天不算进连续）、今天已记', () {
    // 昨天为界：今天写了，但昨天没写，连续天数从昨天往回数是 0。
    final s = computeStreak(['2026-10-31'], today: today);
    expect(s.current, 0);
    expect(s.hasEntryToday, isTrue);
    expect(s.display, 1);
  });

  test('昨天单条 → current 1、今天未记', () {
    final s = computeStreak(['2026-10-30'], today: today);
    expect(s.current, 1);
    expect(s.hasEntryToday, isFalse);
    expect(s.display, 1);
  });

  test('AC-02: 昨天起连续 3 天、今天未记 → current 3', () {
    final s = computeStreak(
      ['2026-10-30', '2026-10-29', '2026-10-28'],
      today: today,
    );
    expect(s.current, 3);
    expect(s.hasEntryToday, isFalse);
    expect(s.display, 3);
  });

  test('AC-03: 今天已记、昨天起连续 2 天 → current 2、今天已记', () {
    final s = computeStreak(
      ['2026-10-31', '2026-10-30', '2026-10-29'],
      today: today,
    );
    expect(s.current, 2);
    expect(s.hasEntryToday, isTrue);
    expect(s.display, 3);
  });

  test('AC-05: 中间断开 → 只算昨天那 1 天，不跨断口', () {
    // 10-30 有、10-28 有，但 10-29 缺 → 从昨天 10-30 起只有 1 天。
    final s = computeStreak(['2026-10-30', '2026-10-28'], today: today);
    expect(s.current, 1);
    expect(s.hasEntryToday, isFalse);
  });

  test('AC-05: 更早的连续段不计入（昨天断了）', () {
    // 昨天 10-30 没写，10-29/10-28/10-27 连续 → 昨天为界下 current 0。
    final s = computeStreak(
      ['2026-10-29', '2026-10-28', '2026-10-27'],
      today: today,
    );
    expect(s.current, 0);
    expect(s.hasEntryToday, isFalse);
  });

  test('AC-06: 跨月连续（10-31 为今天，10-30/10-29/10-28 连续）', () {
    final s = computeStreak(
      ['2026-10-30', '2026-10-29', '2026-10-28'],
      today: today,
    );
    expect(s.current, 3);
  });

  test('AC-06: 跨月到 9 月（9-30, 10-1 连续，today=10-2）', () {
    final s = computeStreak(
      ['2026-09-30', '2026-10-01'],
      today: DateTime(2026, 10, 2),
    );
    expect(s.current, 2);
  });

  test('AC-07: 跨年连续（today=2026-01-01，昨天 2025-12-31）', () {
    final s = computeStreak(['2025-12-31', '2025-12-30'], today: DateTime(2026, 1, 1));
    expect(s.current, 2);
  });

  test('AC-07: 跨年多段（2024-12-31, 2025-01-01 连续，today=2025-01-02）', () {
    final s = computeStreak(
      ['2024-12-31', '2025-01-01'],
      today: DateTime(2025, 1, 2),
    );
    expect(s.current, 2);
  });

  test('AC-08: 跨闰日（2024-02-28, 29, 03-01 连续，today=03-02）', () {
    final s = computeStreak(
      ['2024-02-28', '2024-02-29', '2024-03-01'],
      today: DateTime(2024, 3, 2),
    );
    expect(s.current, 3);
  });

  test('AC-09: 非法 dayKey 跳过，不影响合法记录', () {
    // 昨天 10-30 连续 2 天，中间夹一个非法串与一个非当天键。
    final s = computeStreak(
      ['2026-10-30', '2026-10-29', 'bad', '2026-13-40', '2026-10-28'],
      today: today,
    );
    // 10-30、10-29、10-28 连续 3 天，非法值被跳过。
    expect(s.current, 3);
  });

  test('AC-09: 重复 dayKey 去重，不放大连续天数', () {
    final s = computeStreak(
      ['2026-10-30', '2026-10-30', '2026-10-30'],
      today: today,
    );
    expect(s.current, 1);
  });

  test('跨月边界：10-01 单独（today=10-02，9-30 无）→ 1 天', () {
    final s = computeStreak(['2026-10-01'], today: DateTime(2026, 10, 2));
    expect(s.current, 1);
  });

  test('全部非法 → current 0、今天未记', () {
    final s = computeStreak(['x', '2026-13-40', '2026-1-1'], today: today);
    expect(s.current, 0);
    expect(s.hasEntryToday, isFalse);
  });

  // 回归：真机 today 来自 DateTime.now()，带时刻（不是午夜）。
  // 计数必须只看日历日，不能被时刻影响。
  test('回归: today 带时刻时连续天数只按日历日算', () {
    final s = computeStreak(
      ['2026-10-31'],
      today: DateTime(2026, 11, 1, 23, 51),
    );
    expect(s.current, 1);
    expect(s.hasEntryToday, isFalse);
    expect(s.display, 1);
  });

  test('回归: today 带时刻时今天已记也算 1 天', () {
    final s = computeStreak(
      ['2026-11-01'],
      today: DateTime(2026, 11, 1, 1, 44),
    );
    expect(s.current, 0);
    expect(s.hasEntryToday, isTrue);
    expect(s.display, 1);
  });

  test('回归: today 带时刻时连续多天不受影响', () {
    final s = computeStreak(
      ['2026-10-31', '2026-10-30', '2026-10-29'],
      today: DateTime(2026, 11, 1, 13, 5),
    );
    expect(s.current, 3);
    expect(s.hasEntryToday, isFalse);
    expect(s.display, 3);
  });

  test('回归: today 带时刻时断口仍只算到断口为止', () {
    final s = computeStreak(
      ['2026-10-31', '2026-10-29'],
      today: DateTime(2026, 11, 1, 8, 30),
    );
    expect(s.current, 1);
  });
}
