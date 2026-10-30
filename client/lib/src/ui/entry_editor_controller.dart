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

  String get content => _content;
  SaveStatus get status => _status;
  String? get error => _error;
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
    _status = SaveStatus.saved;
    _notify();
    return true;
  }

  /// 当前是否正在编辑一条已保存的条目。新记录没有可删除的对象。
  bool get canDelete => _persisted && _id != null;

  /// 当前编辑的条目 ID；编辑新记录时为 null。
  String? get currentEntryId => _id;

  /// 删除当前编辑的条目。
  ///
  /// 先把未保存的修改落盘再删除，删除成功后编辑器复位为空白的新记录。
  /// 返回 true 表示删除成功；不是已保存的条目或删除失败时返回 false。
  Future<bool> deleteCurrent() async {
    if (_disposed) return false;
    final id = _id;
    if (id == null || !_persisted) return false;
    // 有未保存的修改时先落盘，免得删除把刚写的内容一起丢掉。
    if (!await flush()) return false;
    try {
      await repository.softDelete(id);
    } catch (error) {
      debugPrint('删除失败：$error');
      _status = SaveStatus.error;
      _error = '删除失败，这条记录仍在。';
      _notify();
      return false;
    }
    _timer?.cancel();
    _content = _savedContent = '';
    _id = _dayKey = null;
    _createdAt = null;
    _persisted = false;
    _error = null;
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
