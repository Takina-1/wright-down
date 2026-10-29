import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.repository,
    required this.onEdit,
    required this.onStart,
  });
  final LocalEntryRepository repository;
  final ValueChanged<Entry> onEdit;
  final VoidCallback onStart;
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _entries = <Entry>[];
  final _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 250 && !_failed) _load();
    });
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final last = _entries.lastOrNull;
      final page = await widget.repository.list(
        before: last == null ? null : EntryCursor(last.createdAt, last.id),
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == 30;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _retry() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('读取失败，请重试'),
      TextButton(onPressed: _load, child: const Text('重新加载')),
    ],
  );

  /// 取条目所属月份，格式固定为 `YYYY-MM`。
  ///
  /// 防止历史脏数据打崩时间轴：早期版本或手工改过的备份可能留下
  /// 长度不足的 dayKey，直接 `substring` 会抛 RangeError 让整页打不开。
  /// 遇到这种数据就退回用创建时间的本地年月，条目本身仍然显示。
  String _monthOf(Entry entry) => _dayKeyOf(entry).substring(0, 7);

  /// 取可安全显示的日期键，格式固定为 `YYYY-MM-DD`。
  ///
  /// dayKey 不合法时退回用创建时间的本地日期。
  String _dayKeyOf(Entry entry) {
    if (isValidDayKey(entry.dayKey)) return entry.dayKey;
    final local = entry.createdAt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '生活的片段',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('每一件小事，都值得被记住。'),
          ],
        ),
      ),
      Expanded(
        child: _entries.isEmpty
            ? _loading
                  ? ListView(
                      children: List.generate(
                        3,
                        (_) => Container(
                          height: 100,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: _failed
                          ? _retry()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                const Text('还没有记录'),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: widget.onStart,
                                  child: const Text('写下第一条'),
                                ),
                              ],
                            ),
                    )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _entries.length + 1,
                itemBuilder: (context, index) {
                  if (index == _entries.length) {
                    if (_failed) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: _retry(),
                      );
                    }
                    if (_hasMore) {
                      return TextButton(
                        onPressed: _loading ? null : _load,
                        child: Text(_loading ? '正在读取…' : '查看更多'),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('这些片段，都属于你。')),
                    );
                  }
                  final entry = _entries[index];
                  final month = _monthOf(entry);
                  final showMonth =
                      index == 0 || _monthOf(_entries[index - 1]) != month;
                  final time = entry.createdAt.toLocal();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showMonth)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                          child: Text(
                            '${month.substring(0, 4)} 年 ${month.substring(5)} 月',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      Card(
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            entry.content,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.6),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              '${_dayKeyOf(entry)}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                          onTap: () => widget.onEdit(entry),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    ],
  );
}
