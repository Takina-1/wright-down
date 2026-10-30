import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';

/// 回收站：已删除的条目先放在这里，可以恢复，也可以彻底删除。
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.repository});

  final LocalEntryRepository repository;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  /// 一页的条数，与 [LocalEntryRepository.listDeleted] 的默认 limit 一致。
  static const _pageSize = 30;

  final _entries = <Entry>[];
  bool _loading = true;
  bool _failed = false;

  /// 读回来的条数打到了 [_pageSize]，说明库里可能还有更早的已删除条目，
  /// 界面得提示用户「只显示最近 N 条」，否则「清空回收站」会删掉看不见的条目。
  bool _mayHaveMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取回收站内容。失败时给出「读取失败」并留一个重新加载的入口。
  Future<void> _load() async {
    try {
      final entries = await widget.repository.listDeleted(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _mayHaveMore = entries.length >= _pageSize;
        _loading = false;
        _failed = false;
      });
    } catch (error) {
      debugPrint('读取回收站失败：$error');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  /// 「重新加载」按钮：先回到加载中，再读一次。
  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    await _load();
  }

  /// 从回收站恢复条目，成功后把它移出列表。
  Future<void> _restore(Entry entry) async {
    final repository = widget.repository;
    try {
      await repository.restore(entry.id);
    } catch (error) {
      debugPrint('恢复失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复失败，请重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复到回顾')),
    );
  }

  /// 彻底删除单条，需要二次确认。
  Future<void> _purge(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('彻底删除这条记录？'),
        content: const Text('彻底删除后不能再恢复，之后导出的备份也不再包含这条记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('trash-purge-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = widget.repository;
    try {
      await repository.purge(entry.id);
    } catch (error) {
      debugPrint('彻底删除失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('彻底删除失败，请重试')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _entries.removeWhere((item) => item.id == entry.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已彻底删除')),
    );
  }

  /// 清空回收站，需要二次确认。
  Future<void> _purgeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('回收站里的所有记录都会被彻底删除，之后导出的备份不再包含它们。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('trash-purge-all-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = widget.repository;
    try {
      final count = await repository.purgeAll();
      if (!mounted) return;
      setState(() {
        _entries.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $count 条')),
      );
    } catch (error) {
      debugPrint('清空失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清空失败，请重试')),
      );
    }
  }

  /// 删除时间戳：年-月-日 时:分，月、日、时、分都补零到两位。
  /// 没有删除时间时给出占位串，避免界面上出现悬空的「删除于 」。
  String _formatDeletedAt(Entry entry) {
    final deletedAt = entry.deletedAt?.toLocal();
    if (deletedAt == null) return '未知时间';
    final month = deletedAt.month.toString().padLeft(2, '0');
    final day = deletedAt.day.toString().padLeft(2, '0');
    final hour = deletedAt.hour.toString().padLeft(2, '0');
    final minute = deletedAt.minute.toString().padLeft(2, '0');
    return '${deletedAt.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('回收站'),
      actions: [
        if (_entries.isNotEmpty)
          TextButton(
            key: const Key('trash-purge-all'),
            onPressed: _purgeAll,
            child: const Text('清空回收站'),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('读取失败，请重试'),
                TextButton(onPressed: _reload, child: const Text('重新加载')),
              ],
            ),
          )
        : _entries.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '回收站是空的。\n删除的记录会先放到这里，可以随时恢复。',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _entries.length + (_mayHaveMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (_mayHaveMore && index == _entries.length) {
                return const _TrashOverflowNotice(count: _pageSize);
              }
              final entry = _entries[index];
              return Card(
                elevation: 0,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    entry.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 操作按钮放在副标题下方单独一行：ListTile 的 trailing 宽度有限，
                  // 两个文字按钮在窄屏上会被裁掉。
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        key: Key('trash-deleted-at-${entry.id}'),
                        '删除于 ${_formatDeletedAt(entry)}',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: Key('trash-restore-${entry.id}'),
                            onPressed: () => _restore(entry),
                            child: const Text('恢复'),
                          ),
                          TextButton(
                            key: Key('trash-purge-${entry.id}'),
                            onPressed: () => _purge(entry),
                            child: const Text('彻底删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

/// 列表底部的提示：当一页显示不下所有已删除条目时，告诉用户还有更早的记录。
class _TrashOverflowNotice extends StatelessWidget {
  const _TrashOverflowNotice({required this.count});

  /// 这一页最多显示多少条。
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      '仅显示最近 $count 条，更早的记录不会出现在这里。',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
