/// 连续天数：纯日历日计数。
///
/// 计数口径为「昨天为界」：`current` 是截止到**昨天**的连续天数，
/// `hasEntryToday` 是今天是否已写。今天还没写时 `current` 不含今天，
/// 这样午夜之后数字不会因为「今天还没写」而虚增或跳号。
library;

import 'entry.dart';

/// 连续天数计算结果。
class StreakSummary {
  const StreakSummary({required this.current, required this.hasEntryToday});

  /// 截止到昨天的连续天数。昨天没有任何记录时为 0。
  final int current;

  /// 今天是否已写至少一条。
  final bool hasEntryToday;

  /// 展示用的连续天数：把「已记今天」单独并入，仅用于 UI 文案，
  /// 不改变 [current] 的口径（避免午夜跳号）。
  int get display => current + (hasEntryToday ? 1 : 0);
}

/// 把 `YYYY-MM-DD` 解析成 naive 本地日期。
///
/// [isValidDayKey] 已保证各字段在合法范围（含闰日），
/// 这里 `DateTime(y, m, d)` 构造不会抛异常。
DateTime _parseNaive(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// naive 日期格式化回 `YYYY-MM-DD`（零填充）。
String _formatKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 由一组 `dayKey` 计算连续天数。
///
/// [dayKeys] 为本地日历日字符串（`YYYY-MM-DD`），内部去重；
/// 非法值跳过（不让脏数据让回顾页崩溃），与 F004 对 `dayKey` 的校验口径一致。
/// [today] 为「今天」，默认取当前本地日期。
///
/// 从 [today] 的昨天开始逐日往前找连续命中，命中天数即 [StreakSummary.current]；
/// [today] 本身命中则 [StreakSummary.hasEntryToday] 为 true。
StreakSummary computeStreak(Iterable<String> dayKeys, {DateTime? today}) {
  final reference = (today ?? DateTime.now()).toLocal();
  final valid = <DateTime>{};
  for (final key in dayKeys) {
    if (isValidDayKey(key)) valid.add(_parseNaive(key));
  }

  final todayKey = _formatKey(reference);
  final hasEntryToday = valid.contains(_parseNaive(todayKey));

  // 从昨天开始往前数连续日历日。
  var day = reference.subtract(const Duration(days: 1));
  var count = 0;
  for (var i = 0; i < valid.length; i++) {
    if (valid.contains(day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return StreakSummary(current: count, hasEntryToday: hasEntryToday);
}
