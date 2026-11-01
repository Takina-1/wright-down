import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/domain/heatmap.dart';

void main() {
  // 固定「今天」为 2026-10-31（周六），避免午夜抖动。
  final today = DateTime(2026, 10, 31);

  test('AC-07: levelOf 分级正确', () {
    expect(levelOf(0), 0);
    expect(levelOf(1), 1);
    expect(levelOf(2), 2);
    expect(levelOf(3), 2);
    expect(levelOf(4), 3);
    expect(levelOf(6), 3);
    expect(levelOf(7), 4);
    expect(levelOf(10), 4);
  });

  test('AC-07: 空集合 → 全 0 强度，行数 ≥ weeks', () {
    final grid = buildHeatmap([], weeks: 4, today: today);
    // 网格延伸到本周，行数 = weeks（整周）+ 本周（若本周非整周）。
    expect(grid.length, greaterThanOrEqualTo(4));
    for (final row in grid) {
      expect(row, hasLength(7));
      for (final cell in row) {
        expect(cell.count, 0);
        expect(cell.level, 0);
      }
    }
  });

  test('AC-07: 单天多条 → 条数累加、强度正确', () {
    // 2026-10-31 写 3 条 → level 2。
    final grid = buildHeatmap(
      ['2026-10-31', '2026-10-31', '2026-10-31'],
      weeks: 2,
      today: today,
    );
    final todayCell = _find(grid, '2026-10-31');
    expect(todayCell.count, 3);
    expect(todayCell.level, 2);
  });

  test('AC-07: 跨月网格连续、月份边界正确', () {
    // 在 2026-09-30 和 2026-10-01 各写 1 条，验证跨月格子都在网格里。
    final grid = buildHeatmap(
      ['2026-09-30', '2026-10-01'],
      weeks: 8,
      today: today,
    );
    final sep30 = _find(grid, '2026-09-30');
    final oct01 = _find(grid, '2026-10-01');
    expect(sep30.count, 1);
    expect(oct01.count, 1);
  });

  test('AC-07: 非法 dayKey 跳过，不让网格崩', () {
    final grid = buildHeatmap(
      ['2026-10-31', 'not-a-date', '2026', '', '2026-13-40'],
      weeks: 2,
      today: today,
    );
    // 合法值正常计入，非法值不影响。
    final cell = _find(grid, '2026-10-31');
    expect(cell.count, 1);
  });

  test('AC-07: 网格从周一排列，覆盖到今天所在的周', () {
    // 2026-10-31 是周六，本周一 2026-10-26，往前 2 周（14 天）= 2026-10-12（周一）。
    // 网格延伸到本周（含今天 10-31），故 2 个整周 + 本周 = 3 行。
    final grid = buildHeatmap([], weeks: 2, today: today);
    expect(grid.length, greaterThanOrEqualTo(3));
    expect(grid[0], hasLength(7));
    expect(grid[0].first.dayKey, '2026-10-12'); // 周一
    expect(DateTime.parse('2026-10-12').weekday, 1);
    // 今天的格子一定在网格里。
    expect(grid.any((r) => r.any((c) => c.dayKey == '2026-10-31')), isTrue);
  });

  test('AC-07: 强度 4 需要 7 条以上', () {
    final grid = buildHeatmap(
      List.filled(8, '2026-10-31'),
      weeks: 1,
      today: today,
    );
    final cell = _find(grid, '2026-10-31');
    expect(cell.count, 8);
    expect(cell.level, 4);
  });
}

/// 在网格里找指定 dayKey 的格子。
HeatmapCell _find(List<List<HeatmapCell>> grid, String key) {
  for (final row in grid) {
    for (final cell in row) {
      if (cell.dayKey == key) return cell;
    }
  }
  throw StateError('cell $key not in grid');
}
