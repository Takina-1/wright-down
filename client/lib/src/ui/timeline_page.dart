import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';
import '../domain/mood.dart';
import '../domain/random_entry.dart';
import '../domain/streak.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.repository,
    required this.onEdit,
    required this.onStart,
    this.onDelete,
    this.today,
    this.onRandomShow,
    this.randomSeed,
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

  /// 点随机一篇卡片时回调，携带抽中的条目，由调用方跳详情。
  ///
  /// 不传则卡片不响应点击（与连续天数卡片本期不响应点击的口径一致）。
  final ValueChanged<Entry>? onRandomShow;

  /// 随机抽取用的种子。仅用于组件测试固定结果，生产不传取系统随机源。
  final int? randomSeed;
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _entries = <Entry>[];
  final _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  Entry? _randomEntry;
  String? _activeTag;

  /// 当前已加载条目里出现过的标签（保序去重），供筛选栏使用。
  List<String> get _availableTags {
    final seen = <String>{};
    final result = <String>[];
    for (final e in _entries) {
      for (final t in e.tags) {
        if (seen.add(t)) result.add(t);
      }
    }
    return result;
  }
  int _randomSeq = -1;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 250 && !_failed) _load();
    });
    _load();
    _pickRandom();
  }

  /// 随机抽一篇用于顶部「随便看看」卡片。
  ///
  /// 从全部条目里过滤掉已删除的，再抽一条；无存活条目时清空卡片。
  /// 抽取失败（理论上不会发生，纯内存运算）不抛异常，保持卡片为空。
  ///
  /// 种子策略：首次生产用系统随机源、测试用固定 seed（可复现）；之后每次
  /// 「换一篇」把种子 +1 走 Random(seed)，保证换到不同条目且测试可复现——
  /// 避免用系统随机时「换一篇」可能抽到同一条，让组件测试断言碰运气。
  Random _nextRandom() {
    if (_randomSeq < 0) {
      if (widget.randomSeed == null) return Random();
      _randomSeq = widget.randomSeed!;
      return Random(_randomSeq);
    }
    _randomSeq++;
    return Random(_randomSeq);
  }

  Future<void> _pickRandom() async {
    try {
      final all = await widget.repository.exportAll();
      // 首次（_randomSeq < 0）不排除；「换一篇」时排除当前展示的那条，
      // 保证必然换到不同条目（AC-03）。按 ID 排除而非引用：exportAll
      // 每次返回新实例，引用比较会失效。
      final excludeId = _randomSeq < 0 ? null : _randomEntry?.id;
      final picked = pickRandomEntry(
        all,
        random: _nextRandom(),
        excludeId: excludeId,
      );
      if (!mounted) return;
      setState(() => _randomEntry = picked);
    } catch (_) {
      // 读取失败不影响时间轴主流程，卡片留空即可。
    }
  }

  /// 按标签筛选：清空已加载条目并重新从第一页加载带该标签的条目。
  ///
  /// 标签来自已加载条目的 tags，故切换标签必须重置 [_entries] 与游标，
  /// 否则会把上一个标签的结果混进来。
  Future<void> _filterByTag(String tag) async {
    if (tag == _activeTag) return;
    if (_loading) return;
    setState(() {
      _entries.clear();
      _activeTag = tag;
      _hasMore = true;
      _failed = false;
      _loading = true;
    });
    await _loadPage();
  }

  /// 清除筛选，回到全部条目。
  Future<void> _clearTagFilter() => _filterByTag('');

  /// 加载一页（不判 _loading/_hasMore，由调用方控制）。
  Future<void> _loadPage() async {
    try {
      final page = await widget.repository.list(
        before: null,
        tag: _activeTag != null && _activeTag!.isNotEmpty ? _activeTag : null,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == 30;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
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
        tag: _activeTag,
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

  /// 随机一篇卡片：从存活条目里随机抽一篇展示摘要。
  ///
  /// 点卡片正文回调 [TimelinePage.onRandomShow] 跳详情；点「换一篇」重新抽。
  /// 无任何存活条目时显示空状态引导，与连续天数卡片的空文案区分。
  Widget _randomCard(BuildContext context) {
    final picked = _randomEntry;
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
                  const Text('🎲', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '随便看看',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              picked == null
                  ? const Text('翻开第一页，开始记录')
                  : InkWell(
                      key: const Key('random-card-body'),
                      onTap: widget.onRandomShow == null
                          ? null
                          : () => widget.onRandomShow!(picked),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _snippet(picked.content),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _dayKeyOf(picked),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
              if (picked != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('random-show-another'),
                    onPressed: _pickRandom,
                    child: const Text('换一篇'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 回顾页页眉：标题 + 副标题。
  Widget _header(BuildContext context) => Padding(
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
  );

  /// 标签筛选栏：列出已加载条目里出现过的标签，点某标签筛选，点「全部」清除。
  ///
  /// 只有已加载条目里出现过的标签才会显示在筛选栏（分页加载的旧条目标签
  /// 不会进入筛选栏，本期可接受）。筛选时时间轴只显示带该标签的未删除条目。
  Widget _tagFilterBar(BuildContext context) {
    final tags = _availableTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _filterChip('全部', _activeTag == null, () => _clearTagFilter()),
          for (final tag in tags)
            _filterChip(
              tag,
              _activeTag == tag,
              () => _filterByTag(tag),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        color: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
      ),
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerLowest,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 整页一个滚动 ListView：页眉 + 标签筛选栏 + 随机一篇卡片 + 连续天数
    // 卡片 + 时间轴全部随滚动一起移动。之前页眉与两张卡片固定在 Expanded
    // 之上，两张卡片撑高后把时间轴第一条推到屏幕外（小屏真机上同样看不到
    // 首条），且固定高度在测试视口里触发 RenderFlex 溢出。合并成单列表后
    // 两者都消失。筛选栏只有带标签时才出现，故 itemCount 动态计算。
    final hasFilterBar = _availableTags.isNotEmpty;
    final fixedCount = 3 + (hasFilterBar ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      // 前 fixedCount 项是页眉、筛选栏（如有）与两张卡片，之后是时间轴条目
      // 或空状态。
      itemCount: fixedCount + _entries.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _header(context);
        if (hasFilterBar && index == 1) return _tagFilterBar(context);
        // 有筛选栏时卡片从 index 2 开始，否则从 index 1 开始。
        final cardOffset = hasFilterBar ? 2 : 1;
        if (index == cardOffset) return _randomCard(context);
        if (index == cardOffset + 1) return _streakCard(context);
        // 条目从 cardOffset + 2 开始；末尾留一项做加载更多/空状态/结束语。
        final entryStart = cardOffset + 2;
        final entryIndex = index - entryStart;
        if (entryIndex == _entries.length) {
          if (_failed) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _retry(),
            );
          }
          if (_entries.isEmpty) {
            return Padding(
              padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 64,
                      color: Colors.grey,
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
              ),
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
        final entry = _entries[entryIndex];
        final month = _monthOf(entry);
        final showMonth =
            entryIndex == 0 || _monthOf(_entries[entryIndex - 1]) != month;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_dayKeyOf(entry)}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      ),
                      if (entry.tags.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            for (final tag in entry.tags)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.primary
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                onTap: () => widget.onEdit(entry),
                onLongPress: () => _showEntryActions(entry),
              ),
            ),
          ],
        );
      },
    );
  }
}
