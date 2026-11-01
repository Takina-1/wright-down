import 'entry.dart';

/// 一天的热力格子。
class HeatmapCell {
  const HeatmapCell(this.dayKey, this.count, this.level);

  /// 日期键 `YYYY-MM-DD`。
  final String dayKey;

  /// 当天条数。
  final int count;

  /// 强度等级 0~4，条数越多越大。
  final int level;
}

/// 按条数分档的强度等级。
///
/// 0 条 → 0（无色）；1 条 → 1；2~3 条 → 2；4~6 条 → 3；≥7 条 → 4。
int levelOf(int count) {
  if (count <= 0) return 0;
  if (count == 1) return 1;
  if (count <= 3) return 2;
  if (count <= 6) return 3;
  return 4;
}

/// 把 YYYY-MM-DD 解析成 naive 本地日历日。
DateTime _parseNaive(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// 把 DateTime 格式化成 YYYY-MM-DD。
String _formatKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 由一组 dayKey 生成最近 [weeks] 周（默认 12 周 = 84 天）的热力网格。
///
/// [dayKeys] 可以是含非法值的混合集合：非法值（不匹配 `YYYY-MM-DD`）跳过，
/// 不让统计页崩溃——与 F004/F009 对脏数据的口径一致。
///
/// 网格从「今天往前推 weeks*7 天」的那一天开始，按周一到周日排列（每行 7 格）。
/// 同一天多次出现（多条记录）会累加 count。返回的行数固定为 [weeks]。
///
/// [today] 为「今天」基准，默认取当前本地日期；测试可注入固定日期避免午夜抖动。
List<List<HeatmapCell>> buildHeatmap(
  List<String> dayKeys, {
  int weeks = 12,
  DateTime? today,
}) {
  final reference = (today ?? DateTime.now()).toLocal();
  // 今天归零到当日 00:00（naive 日历日），避免带时刻导致与 dayKey 不相等。
  final todayNaive = DateTime(
    reference.year,
    reference.month,
    reference.day,
  );
  // 统计每条 dayKey 的条数（按日历日聚合，同一天多条累加）。
  final counts = <String, int>{};
  for (final key in dayKeys) {
    if (!isValidDayKey(key)) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  // 网格起点：从「今天所在的这一周的周一」往前推 weeks*7 天，
  // 保证网格第一格正好是某周的周一。
  // 网格始终延伸到「今天所在的这一周」，保证今天的格子一定在网格里——
  // 若今天落在周中，最后一行会多出今天之后到周日的格子（那些格子 count=0，
  // 因为未来还没写；但今天的格子一定可见）。
  final todayWeekday = todayNaive.weekday; // 1=周一 ... 7=周日
  final daysSinceMonday = todayWeekday - 1; // 本周一到今天的天数
  final gridStart = todayNaive
      .subtract(Duration(days: daysSinceMonday)) // 今天回本周一
      .subtract(Duration(days: weeks * 7)); // 再往前推满 weeks 周，落在周一
  final rows = <List<HeatmapCell>>[];
  var w = 0;
  while (true) {
    final row = <HeatmapCell>[];
    for (var d = 0; d < 7; d++) {
      final date = gridStart.add(Duration(days: w * 7 + d));
      final key = _formatKey(date);
      // 未来日期（晚于今天）count=0，避免显示未来已写数据的假象。
      final count = date.isAfter(todayNaive) ? 0 : (counts[key] ?? 0);
      row.add(HeatmapCell(key, count, levelOf(count)));
    }
    rows.add(row);
    // 最后一行到达本周（含今天）即停。
    final rowEnd = gridStart.add(Duration(days: w * 7 + 6));
    if (rowEnd.isAfter(todayNaive)) break;
    w++;
  }
  return rows;
}
