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
