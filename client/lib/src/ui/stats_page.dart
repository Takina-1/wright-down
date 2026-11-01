import 'package:flutter/material.dart';

import '../domain/heatmap.dart';
import '../domain/local_entry_repository.dart';

/// 统计页：日历热力图。
///
/// 从仓储取全部条目（含已删除），过滤合法 dayKey 后用 [buildHeatmap]
/// 生成网格，按当天条数着色。空数据时显示空状态。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.repository});
  final LocalEntryRepository repository;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<List<HeatmapCell>> _grid = const [];
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repository.exportAll();
      final dayKeys = all.map((e) => e.dayKey).toList();
      if (!mounted) return;
      setState(() {
        _grid = buildHeatmap(dayKeys);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 按强度等级取背景色（条数越多越深）。
  Color _cellColor(BuildContext context, int level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      0 => scheme.surfaceContainerHighest,
      1 => scheme.primary.withValues(alpha: 0.2),
      2 => scheme.primary.withValues(alpha: 0.35),
      3 => scheme.primary.withValues(alpha: 0.55),
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记录热力图')),
    body: _loaded
        ? _grid.isEmpty || _grid.every((r) => r.every((c) => c.count == 0))
            ? _emptyState(context)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _weekdayHeader(context),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        for (final row in _grid)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(width: 28),
                              for (final cell in row)
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      right: 4,
                                      bottom: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _cellColor(context, cell.level),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${cell.count}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: cell.count == 0
                                              ? Colors.transparent
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              )
        : _failed
            ? const Center(child: Text('读取失败，请重试'))
            : const Center(child: Text('正在读取…')),
  );

  Widget _weekdayHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 16, 4),
    child: Row(
      children: [
        const SizedBox(width: 28),
        for (final label in ['一', '二', '三', '四', '五', '六', '日'])
          SizedBox(
            width: 36,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
  );

  Widget _emptyState(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.grid_view,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        const Text('还没有记录'),
        const SizedBox(height: 8),
        const Text('写下第一条，开始看到你的记录节奏'),
      ],
    ),
  );
}
