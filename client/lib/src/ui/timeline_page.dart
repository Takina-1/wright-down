import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';
import '../domain/mood.dart';
import '../domain/streak.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.repository,
    required this.onEdit,
    required this.onStart,
    this.onDelete,
    this.today,
  });
  final LocalEntryRepository repository;
  final ValueChanged<Entry> onEdit;
  final VoidCallback onStart;

  /// 删除成功后回调，让调用方知道哪条记录进了回收站。
  ///
  /// 不传就是 null，保持现有调用方兼容。
  final ValueChanged<Entry>? onDelete;

  /// 连续天数的「今天」基准。不传取当前本地日期。
  ///
  /// 仅用于让组件测试固定日期，生产调用方无需传。
  final DateTime? today;
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

  /// 长按条目弹出的操作菜单。
  Future<void> _showEntryActions(Entry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('timeline-action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              key: const Key('timeline-action-delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      widget.onEdit(entry);
    } else if (action == 'delete') {
      await _deleteEntry(entry);
    }
  }

  /// 删除一条记录：确认后软删除，并给出撤销入口。
  Future<void> _deleteEntry(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(_deleteDialogBody(entry.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('timeline-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // SnackBar 挂在 app 级的 ScaffoldMessenger 上，可能比这个页面活得久
    // （切 Tab 会重建 TimelinePage）。把仓储取到局部变量，撤销回调就不依赖
    // 可能已卸载的 State，也不会在 State defunct 后再碰 widget。
    final repository = widget.repository;
    try {
      await repository.softDelete(entry.id);
    } catch (error) {
      debugPrint('删除失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，这条记录仍在')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
    // 通知调用方这条记录进了回收站：调用方可能正编辑着它，得把编辑器复位，
    // 否则界面会继续显示「已保存」，而记录在回顾页里已经看不见了。
    widget.onDelete?.call(entry);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_restoreEntry(entry, repository)),
        ),
      ),
    );
  }

  /// 撤销删除：把条目放回列表。
  ///
  /// 仓储由调用方传入而不是从 `widget` 取：撤销入口挂在 app 级的
  /// ScaffoldMessenger 上，页面此时可能已经卸载，State defunct 后再碰
  /// `widget` 不可靠。页面已卸载时只恢复数据库，界面刷新交给用户重新
  /// 进入回顾页，数据不会丢。
  Future<void> _restoreEntry(
    Entry entry,
    LocalEntryRepository repository,
  ) async {
    try {
      await repository.restore(entry.id);
    } catch (error) {
      debugPrint('恢复失败：$error');
      // 恢复失败必须让用户看见：只 debugPrint 的话，用户点了撤销却看不到
      // 条目回来，以为撤销没生效。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复失败，请到回收站重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.insert(_insertPosition(entry), entry);
    });
  }

  /// 条目在列表中的插入位置：按创建时间倒序、同刻按 ID 倒序。
  ///
  /// 时间比较用毫秒 epoch，与仓储层 [LocalEntryRepository.list] 的排序口径一致，
  /// 避免微秒精度差异把条目插到错误的位置。
  int _insertPosition(Entry entry) {
    final target = entry.createdAt.millisecondsSinceEpoch;
    var index = 0;
    while (index < _entries.length) {
      final current = _entries[index];
      final time = current.createdAt.millisecondsSinceEpoch.compareTo(target);
      if (time == 0) {
        if (current.id.compareTo(entry.id) <= 0) break;
      } else if (time < 0) {
        break;
      }
      index++;
    }
    return index;
  }

  /// 确认对话框的正文：内容摘要 + 回收站提示。
  ///
  /// 摘要为空时不写摘要，也就不留前导空行，否则对话框正文会以两个
  /// 空行开头。
  String _deleteDialogBody(String content) {
    final snippet = _snippet(content);
    const hint = '删除后可在回收站找回。';
    return snippet.isEmpty ? hint : '$snippet\n\n$hint';
  }

  /// 确认对话框里的内容摘要。
  String _snippet(String content) {
    final flat = content.replaceAll('\n', ' ').trim();
    return flat.length <= 20 ? flat : '${flat.substring(0, 20)}…';
  }

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

  /// 连续天数卡片：显示截止昨天的连续天数。
  ///
  /// 口径为「昨天为界」（见 [computeStreak]）：今天还没写时数字不含今天，
  /// 午夜后不跳号。今天已记时追加「今天已记」一句；今天未记给「去写一条」
  /// 行动按钮，跳到记录页。无任何记录时显示空状态引导。
  Widget _streakCard(BuildContext context) {
    final dayKeys = _entries.map((e) => _dayKeyOf(e)).toList();
    final streak = computeStreak(dayKeys, today: widget.today);
    final hasAny = dayKeys.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasAny ? '连续 ${streak.display} 天' : '等待你的第一篇日记',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!hasAny)
                const Text('开启你的第一条记录')
              else if (!streak.hasEntryToday)
                Row(
                  children: [
                    Expanded(
                      child: Text('今天还没记，去写一条',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    TextButton(
                      key: const Key('streak-write-today'),
                      onPressed: widget.onStart,
                      child: const Text('写一条'),
                    ),
                  ],
                )
              else
                const Text('今天已记，继续保持',
                    style: TextStyle(color: Colors.green, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
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
      _streakCard(context),
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
                  final emoji = emojiOf(entry.mood);
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
                          leading: emoji.isEmpty ? null : Text(emoji),
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
                          onLongPress: () => _showEntryActions(entry),
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
