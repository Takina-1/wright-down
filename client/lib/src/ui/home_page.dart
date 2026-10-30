import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/entry.dart';
import '../domain/export/file_gateway.dart';
import '../domain/local_entry_repository.dart';
import 'entry_editor_controller.dart';
import 'local_data_page.dart';
import 'timeline_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository, this.fileGateway});
  final LocalEntryRepository repository;

  /// 文件出口。默认用系统实现，测试可以注入替身。
  final FileGateway? fileGateway;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final EntryEditorController _editor;
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _tab = 0;
  var _revision = 0;
  var _transitioning = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor = EntryEditorController(
      repository: widget.repository,
      idGenerator: const Uuid().v4,
      now: DateTime.now,
    )..addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_text.text != _editor.content) {
      _text.value = TextEditingValue(
        text: _editor.content,
        selection: TextSelection.collapsed(offset: _editor.content.length),
      );
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_editor.flush());
    }
  }

  Future<void> _selectTab(int tab) async {
    if (_transitioning || tab == _tab) return;
    setState(() {
      _transitioning = true;
    });
    final saved = await _editor.flush();
    if (!mounted) return;
    setState(() {
      _transitioning = false;
      if (saved) {
        _tab = tab;
        _revision++;
      }
    });
    if (saved) {
      if (tab != 0) {
        _focus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }
  }

  Future<void> _nextEntry() async {
    if (_transitioning) return;
    setState(() {
      _transitioning = true;
    });
    await _editor.newEntry();
    if (!mounted) return;
    setState(() {
      _transitioning = false;
    });
    _focus.requestFocus();
  }

  Future<void> _edit(Entry entry) async {
    if (_transitioning) return;
    setState(() {
      _transitioning = true;
    });
    final opened = await _editor.edit(entry);
    if (!mounted) return;
    setState(() {
      _transitioning = false;
      if (opened) _tab = 0;
    });
    if (opened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// 删除当前编辑的条目。确认后条目移入回收站，编辑器复位。
  Future<void> _deleteCurrentEntry() async {
    if (_transitioning) return;
    // 删除成功后编辑器会复位，ID 会被清空，先记下来给撤销用。
    final id = _editor.currentEntryId;
    if (id == null) return;
    final content = _editor.content;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(_deleteDialogBody(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('composer-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // SnackBar 挂在 app 级的 ScaffoldMessenger 上，可能比这个页面活得久
    // （切 Tab 会重建页面）。把仓储取到局部变量，撤销回调就不依赖可能
    // 已卸载的 State，也不会在 State defunct 后再碰 widget。
    final repository = widget.repository;
    setState(() {
      _transitioning = true;
    });
    final deleted = await _editor.deleteCurrent();
    if (!mounted) return;
    setState(() {
      _transitioning = false;
    });
    if (!deleted) {
      // 删除失败要给出最贴近真实原因的那条文案：
      // deleteCurrent() 在正文有改动时会先落盘，若这次保存失败，
      // 它提前返回 false 且不设删除错误——此时只有保存错误说明问题。
      // 反过来，删除本身失败时保存错误是 null，落到删除错误上。
      final reason = _editor.error ?? _editor.deleteError ?? '删除失败，这条记录仍在';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_undoDelete(id, repository)),
        ),
      ),
    );
  }

  /// 撤销删除：把条目从回收站恢复回来。
  ///
  /// 仓储由调用方传入而不是从 `widget` 取：撤销入口挂在 app 级的
  /// ScaffoldMessenger 上，页面此时可能已经卸载，State defunct 后再碰
  /// `widget` 不可靠。
  Future<void> _undoDelete(String id, LocalEntryRepository repository) async {
    try {
      await repository.restore(id);
    } catch (error) {
      debugPrint('恢复失败：$error');
      // 恢复失败必须让用户看见：只 debugPrint 的话，用户点了撤销却看不到
      // 条目回来，以为撤销没生效。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复失败，请到回收站重试')),
      );
    }
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

  Future<void> _exit() async {
    if (_transitioning) return;
    setState(() {
      _transitioning = true;
    });
    final saved = await _editor.flush();
    if (!mounted) return;
    if (saved) {
      await SystemNavigator.pop();
    } else {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('还有未保存的内容'),
          content: const Text('退出会丢失这次未保存的修改，已保存的记录仍会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改并退出'),
            ),
          ],
        ),
      );
      if (discard == true) await SystemNavigator.pop();
    }
    if (mounted) {
      setState(() {
        _transitioning = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor.removeListener(_changed);
    _editor.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_exit());
    },
    child: Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => _composer(context),
          1 => TimelinePage(
            key: ValueKey(_revision),
            repository: widget.repository,
            onEdit: _edit,
            onStart: () => _selectTab(0),
          ),
          _ => LocalDataPage(
            repository: widget.repository,
            fileGateway: widget.fileGateway,
          ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _transitioning ? null : _selectTab,
        destinations: const [
          NavigationDestination(
            key: Key('tab-write'),
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: '记录',
          ),
          NavigationDestination(
            key: Key('tab-review'),
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '回顾',
          ),
          NavigationDestination(
            key: Key('tab-mine'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    ),
  );
  Widget _composer(BuildContext context) {
    final today = DateTime.now();
    final statusText = switch (_editor.status) {
      SaveStatus.empty => '随手写下，自动保存',
      SaveStatus.editing => '等待保存…',
      SaveStatus.saving => '保存中…',
      SaveStatus.saved => '已保存',
      SaveStatus.error => '保存失败',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${today.year} 年 ${today.month} 月 ${today.day} 日',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '留住这一刻',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                Icons.spa_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: const Key('entry-content'),
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              expands: true,
              minLines: null,
              maxLines: null,
              readOnly: _transitioning,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 18, height: 1.8),
              decoration: const InputDecoration(
                hintText: '今天想记点什么？',
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
              onChanged: _editor.updateContent,
            ),
          ),
          if (_editor.error != null) ...[
            Text(
              _editor.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _transitioning ? null : () => _editor.flush(),
              child: const Text('重试保存'),
            ),
          ],
          Row(
            children: [
              Icon(
                _editor.status == SaveStatus.saved
                    ? Icons.check_circle_outline
                    : Icons.edit_note,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_editor.canDelete)
                TextButton(
                  key: const Key('composer-delete'),
                  onPressed: _transitioning ? null : _deleteCurrentEntry,
                  child: const Text('删除这条'),
                ),
              TextButton.icon(
                onPressed: _transitioning ? null : _nextEntry,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('下一条'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
