import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entry.dart';
import '../domain/local_entry_repository.dart';

enum SaveStatus { empty, editing, saving, saved, error }

class EntryEditorController extends ChangeNotifier {
  EntryEditorController({
    required this.repository,
    required this.idGenerator,
    required this.now,
  });
  final LocalEntryRepository repository;
  final String Function() idGenerator;
  final DateTime Function() now;
  String _content = '';
  String _savedContent = '';
  String? _id;
  DateTime? _createdAt;
  String? _dayKey;
  bool _persisted = false;
  bool _writing = false;
  bool _disposed = false;
  Timer? _timer;
  Future<bool>? _saving;
  SaveStatus _status = SaveStatus.empty;
  String? _error;
  String? _deleteError;

  String get content => _content;
  SaveStatus get status => _status;
  String? get error => _error;

  /// 删除失败时的错误文案。与保存错误（[error]）是两回事：
  /// 删除失败不该把状态显示成「保存失败」，也不该出现「重试保存」按钮。
  String? get deleteError => _deleteError;
  bool get _dirty =>
      _persisted ? _content != _savedContent : _content.trim().isNotEmpty;
  bool get hasPendingChanges => _writing || _dirty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void updateContent(String value) {
    if (_disposed || value == _content) return;
    _content = value;
    _error = null;
    // 开始改字就说明用户已经换了个心思，上一次的删除失败提示不该留着。
    _deleteError = null;
    _timer?.cancel();
    _status = hasPendingChanges
        ? SaveStatus.editing
        : (_persisted ? SaveStatus.saved : SaveStatus.empty);
    if (_dirty) {
      _timer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
    }
    _notify();
  }

  Future<bool> flush() {
    _timer?.cancel();
    if (_disposed) return Future.value(false);
    if (_saving != null) return _saving!;
    if (!_dirty) return Future.value(true);
    return _saving = _saveLoop().whenComplete(() {
      _saving = null;
    });
  }

  Future<bool> _saveLoop() async {
    while (_dirty && !_disposed) {
      if (_content.trim().isEmpty) {
        _status = SaveStatus.error;
        _error = '正文不能为空，原记录仍保留。';
        _notify();
        return false;
      }
      final timestamp = now();
      _id ??= idGenerator();
      _createdAt ??= timestamp;
      final local = _createdAt!.toLocal();
      _dayKey ??=
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      final snapshot = Entry(
        id: _id!,
        content: _content,
        createdAt: _createdAt!,
        updatedAt: timestamp,
        dayKey: _dayKey!,
      );
      _status = SaveStatus.saving;
      _error = null;
      _writing = true;
      _notify();
      try {
        await repository.save(snapshot);
        _persisted = true;
        _savedContent = snapshot.content;
      } catch (_) {
        _timer?.cancel();
        _status = SaveStatus.error;
        _error = '保存失败，文字仍在此处。请检查存储空间后重试。';
        return false;
      } finally {
        _writing = false;
        _notify();
      }
    }
    if (_disposed) return false;
    _timer?.cancel();
    _status = SaveStatus.saved;
    _notify();
    return true;
  }

  Future<bool> newEntry() async {
    if (!await flush() || _disposed) return false;
    _content = _savedContent = '';
    _id = _dayKey = null;
    _createdAt = null;
    _persisted = false;
    _error = null;
    _deleteError = null;
    _status = SaveStatus.empty;
    _notify();
    return true;
  }

  Future<bool> edit(Entry entry) async {
    if (!await flush() || _disposed) return false;
    _content = _savedContent = entry.content;
    _id = entry.id;
    _createdAt = entry.createdAt;
    _dayKey = entry.dayKey;
    _persisted = true;
    _error = null;
    _deleteError = null;
    _status = SaveStatus.saved;
    _notify();
    return true;
  }

  /// 当前是否正在编辑一条已保存的条目。新记录没有可删除的对象。
  bool get canDelete => _persisted && _id != null;

  /// 当前编辑的、且已落库的条目 ID；新记录（或保存失败、从未落库）时为 null。
  String? get currentEntryId => _persisted ? _id : null;

  /// 删除当前编辑的条目。
  ///
  /// 先把未保存的修改落盘再删除，删除成功后编辑器复位为空白的新记录。
  /// 返回 true 表示删除成功；不是已保存的条目或删除失败时返回 false。
  Future<bool> deleteCurrent() async {
    if (_disposed) return false;
    final id = _id;
    if (id == null || !_persisted) return false;
    // 先等在飞行的保存落地：否则迟到的保存会把下面的复位覆盖掉，
    // 让界面显示「原记录仍保留」，而记录其实已经删掉了。
    final pending = _saving;
    if (pending != null) {
      await pending;
    }
    // 正文非空时先落盘，免得删除把刚写的内容一起丢掉。
    // 正文为空时跳过落盘：保存会因为「正文不能为空」失败，
    // 但用户要的是把这条记录删掉，不该被针对保存的规则拦住。
    if (_content.trim().isNotEmpty && !await flush()) return false;
    try {
      await repository.softDelete(id);
    } catch (error) {
      debugPrint('删除失败：$error');
      // 防抖定时器还活着的话，1 秒后会触发 flush()，把「正文不能为空」
      // 这条与删除无关的文案盖上来。这里先把它掐掉。
      _timer?.cancel();
      _timer = null;
      // 删除错误单独走 [deleteError]：不占用保存的状态与错误字段，
      // 否则界面会同时显示「保存失败」和「重试保存」。
      _deleteError = '删除失败，这条记录仍在。';
      _notify();
      return false;
    }
    _timer?.cancel();
    _content = _savedContent = '';
    _id = _dayKey = null;
    _createdAt = null;
    _persisted = false;
    _error = null;
    _deleteError = null;
    _status = SaveStatus.empty;
    _notify();
    return true;
  }

  /// 条目在别处被删除时告知控制器。
  ///
  /// 正在编辑的就是它时，把编辑器复位为空白的新记录——继续编辑一条已经
  /// 在回收站里的记录，界面会显示「已保存」而用户根本看不到它。
  /// 返回 true 表示确实复位了。
  bool markDeleted(String id) {
    if (_disposed || _id != id) return false;
    _timer?.cancel();
    _content = _savedContent = '';
    _id = _dayKey = null;
    _createdAt = null;
    _persisted = false;
    _error = null;
    _deleteError = null;
    _status = SaveStatus.empty;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
