import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/entry.dart';
import '../domain/export/file_gateway.dart';
import '../domain/local_entry_repository.dart';
import '../domain/mood.dart';
import '../data/sync/sync_engine.dart';
import 'entry_editor_controller.dart';
import 'local_data_page.dart';
import 'sync/sync_status_indicator.dart';
import 'timeline_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    this.fileGateway,
    this.syncEngine,
  });
  final LocalEntryRepository repository;

  /// 文件出口。默认用系统实现，测试可以注入替身。
  final FileGateway? fileGateway;

  /// 同步引擎。为空时 composer 不显示同步状态、flush 不触发推送、前台不触发拉取。
  final SyncEngine? syncEngine;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final EntryEditorController _editor;
  final _text = TextEditingController();
  final _tagInput = TextEditingController();
  final _focus = FocusNode();
  var _tab = 0;
  var _revision = 0;
  var _transitioning = false;

  /// 刚被删除、还可以撤销的条目 ID。
  ///
  /// 撤销入口就地显示在记录页里，不用 SnackBar：SnackBar 会浮在
  /// Scaffold 底部，正好压住记录页固定在底部的「删除这条」「下一条」，
  /// 用户的点击会落到提示条上而不是按钮上（真机上表现为「下一条」点了没反应，
  /// 或者误触「撤销」把刚删掉的记录又恢复回来）。
  String? _undoableEntryId;

  /// 从 OSS 下载回来的照片字节（photo=null 但 photoKey 存在时用）。
  ///
  /// 编辑一条远端拉下来的条目时，本地 photo BLOB 可能还没缓存（只有
  /// photoKey）。composer 凭 photoKey 向 OSS 下载一份临时字节显示缩略图；
  /// 不写回仓储（写回由 SyncEngine.pullOnce 负责），仅作显示用。
  Uint8List? _remotePhoto;

  /// 已经触发下载的 photoKey。非 null 表示该 key 的下载已发起（在途或完成），
  /// 避免编辑器每次通知都重新触发下载。
  String? _downloadedKey;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor = EntryEditorController(
      repository: widget.repository,
      idGenerator: const Uuid().v4,
      now: DateTime.now,
    )..addListener(_changed);
    _tagInput.addListener(_onTagInputChanged);
  }

  void _onTagInputChanged() {
    // 输入框内容变化时不立即写控制器：标签只在「添加」时落库，
    // 避免每个字符都触发一次 flush 防抖。回车或点「添加」才提交。
  }

  void _changed() {
    if (!mounted) return;
    if (_text.text != _editor.content) {
      _text.value = TextEditingValue(
        text: _editor.content,
        selection: TextSelection.collapsed(offset: _editor.content.length),
      );
    }
    _syncRemotePhoto();
    setState(() {});
  }

  /// 同步「远端照片」下载状态：本地有 BLOB 就用本地；本地没有但 photoKey
  /// 存在就向 OSS 下载一份临时字节显示；都没有就清空。
  ///
  /// 编辑器每次变更都会通知（_changed），这里用 [_downloadedKey] 记住
  /// 已发起下载的 key，避免每个按键都重新下载。
  void _syncRemotePhoto() {
    final photo = _editor.photo;
    final key = _editor.photoKey;
    final engine = widget.syncEngine;
    if (photo != null) {
      // 本地 BLOB 在场：直接用它，不需要远端下载。
      if (_downloadedKey != null || _remotePhoto != null) {
        _downloadedKey = null;
        _remotePhoto = null;
      }
      return;
    }
    if (key == null || engine == null) {
      if (_downloadedKey != null || _remotePhoto != null) {
        _downloadedKey = null;
        _remotePhoto = null;
      }
      return;
    }
    if (_downloadedKey == key) return; // 已在下载中或已完成。
    _downloadedKey = key; // 标记在途，避免重复触发。
    unawaited(_fetchRemotePhoto(key));
  }

  /// 按 photoKey 从 OSS 下载照片字节，下载成功后 setState 显示。
  ///
  /// 下载期间用户可能换了照片或 photoKey：只在本地仍无 BLOB 且 key 未变
  /// 时才显示，避免迟到的下载盖掉用户刚选的新照片。
  Future<void> _fetchRemotePhoto(String key) async {
    try {
      final bytes = await widget.syncEngine!.oss.download(key);
      if (!mounted) return;
      if (_editor.photo != null || _editor.photoKey != key) return;
      setState(() => _remotePhoto = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _remotePhoto = null;
        _downloadedKey = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 退到后台/失焦前落盘，落盘成功后触发一次推送（防抖合并多次写入）。
      unawaited(_flushAndPush());
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台拉一次远端变更；未登录时 triggerPull 内部 _me() 返回 null 提前退出。
      final engine = widget.syncEngine;
      if (engine != null) unawaited(engine.triggerPull());
    }
  }

  /// 落盘并触发推送：flush 成功才 triggerPush（失败的写入不推）。
  ///
  /// triggerPush 自身 30 秒防抖，多次调用会合并为一次往返，故在
  /// _selectTab/_exit/后台落盘三处复用本方法无需额外节流。
  Future<bool> _flushAndPush() async {
    final saved = await _editor.flush();
    if (saved) widget.syncEngine?.triggerPush();
    return saved;
  }

  Future<void> _selectTab(int tab) async {
    if (_transitioning || tab == _tab) return;
    setState(() {
      _transitioning = true;
    });
    final saved = await _flushAndPush();
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

  /// 心情选择弹层：列 5 种心情，已设时额外提供「清除」。
  ///
  /// 清除用空串作哨兵值：弹层返回类型是 [String?]，区分「取消」（null）
  /// 与「清除」（空串），调用方据此决定 setMood(null) 还是 setMood(picked)。
  Future<void> _showMoodSheet() async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...allMoods.map((m) {
              final sel = _editor.mood == m.name;
              return ListTile(
                leading: Text(emojiOf(m.name)),
                title: Text(labelOf(m.name)),
                trailing: sel ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, m.name),
              );
            }),
            if (_editor.mood != null)
              ListTile(
                leading: const Icon(Icons.clear_outlined),
                title: const Text('清除'),
                onTap: () => Navigator.pop(context, ''),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (picked == null) return; // 取消
    _editor.setMood(picked.isEmpty ? null : picked);
  }

  /// 从相册选一张照片。选到非图片文件或取消都不改照片。
  Future<void> _pickPhoto() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    );
    if (!mounted) return;
    final file = files.firstOrNull;
    if (file == null) return; // 取消
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择图片')),
      );
      return;
    }
    _editor.setPhoto(bytes);
  }

  /// 移除当前照片。
  void _removePhoto() => _editor.setPhoto(null);

  /// 添加当前输入框里的标签。回车或点「添加」触发。
  ///
  /// 规范化后若与已有标签重复则不重复添加；空输入忽略。
  void _addTag() {
    final raw = _tagInput.text;
    if (raw.trim().isEmpty) return;
    final next = [..._editor.tags, raw];
    _editor.setTags(next);
    _tagInput.clear();
  }

  /// 移除某个标签。
  void _removeTag(String tag) {
    _editor.setTags(_editor.tags.where((t) => t != tag).toList());
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

  /// 回顾页删除了条目：如果正在编辑它，编辑器复位并提示用户。
  void _entryDeleted(Entry entry) {
    if (!_editor.markDeleted(entry.id)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这条记录已移入回收站')),
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
    final saved = await _flushAndPush();
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
    _tagInput.dispose();
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
            onDelete: _entryDeleted,
          ),
          _ => LocalDataPage(
            repository: widget.repository,
            fileGateway: widget.fileGateway,
            syncEngine: widget.syncEngine,
            auth: widget.syncEngine?.auth,
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
    final thumbBytes = _editor.photo ?? _remotePhoto;
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
              if (widget.syncEngine != null)
                StreamBuilder<SyncState>(
                  stream: widget.syncEngine!.stateChanged,
                  initialData: widget.syncEngine!.state,
                  builder: (context, snapshot) => SyncStatusIndicator(
                    state: snapshot.data ?? SyncState.idle,
                  ),
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
          Row(
            children: [
              IconButton(
                key: const Key('mood-entry'),
                icon: Text(_editor.mood == null ? '😊' : emojiOf(_editor.mood)),
                onPressed: _transitioning ? null : _showMoodSheet,
              ),
              IconButton(
                key: const Key('photo-entry'),
                icon: const Icon(Icons.add_a_photo_outlined),
                onPressed: _transitioning ? null : _pickPhoto,
              ),
            ],
          ),
          if (thumbBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: const Key('photo-thumbnail'),
                onTap: _transitioning ? null : _pickPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                      child: Image.memory(
                        thumbBytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('图片无法显示')),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        key: const Key('photo-remove'),
                        onTap: _transitioning ? null : _removePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_editor.tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _editor.tags)
                  ActionChip(
                    key: Key('tag-chip-$tag'),
                    label: Text(tag),
                    onPressed: _transitioning
                        ? null
                        : () => _removeTag(tag),
                  ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('tag-input'),
                  controller: _tagInput,
                  enabled: !_transitioning,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                  decoration: const InputDecoration(
                    hintText: '加标签，回车确认',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              IconButton(
                key: const Key('tag-add'),
                icon: const Icon(Icons.add, size: 20),
                onPressed: _transitioning ? null : _addTag,
              ),
            ],
          ),
          if (_editor.error != null) ...[
            Text(
              _editor.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _transitioning ? null : () => unawaited(_flushAndPush()),
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
