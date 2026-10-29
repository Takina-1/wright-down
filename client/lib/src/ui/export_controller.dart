import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/entry.dart';
import '../domain/export/backup_codec.dart';
import '../domain/export/backup_document.dart';
import '../domain/export/file_gateway.dart';
import '../domain/export/import_summary.dart';
import '../domain/export/markdown_exporter.dart';
import '../domain/export/restore_preview.dart';
import '../domain/local_entry_repository.dart';

enum ExportStatus { idle, working, success, failure }

/// 导出与恢复的编排：读条目、编码、交给文件出口，并管理界面要显示的状态。
class ExportController extends ChangeNotifier {
  ExportController({
    required this.repository,
    required this.fileGateway,
    this._codec = const BackupCodec(),
    this._markdownExporter = const MarkdownExporter(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LocalEntryRepository repository;
  final FileGateway fileGateway;
  final BackupCodec _codec;
  final MarkdownExporter _markdownExporter;
  final DateTime Function() _now;

  ExportStatus _status = ExportStatus.idle;
  String? _message;
  Uint8List? _lastExportBytes;
  String? _lastExportName;
  BackupDocument? _pendingDocument;
  bool _disposed = false;

  ExportStatus get status => _status;
  String? get message => _message;
  bool get canShare => _lastExportBytes != null;

  /// 最近一次选中、等待用户确认的备份文件。
  /// 每次 [pickBackup] 都会先清空：只有本次真正选中的备份才会留在这里，
  /// 取消或失败后不会残留上一份备份。
  BackupDocument? get pendingDocument => _pendingDocument;

  /// 文件选择器与分享面板都是异步挂起点，控制器可能在挂起期间被销毁。
  /// 销毁后再通知监听器会抛断言错误，所以统一走 [_notify]。
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<bool> exportBackup() => _export(
    extension: 'json',
    mimeType: 'application/json',
    encode: (entries) => _codec.encode(entries, exportedAt: _now()),
  );

  Future<bool> exportMarkdown() => _export(
    extension: 'md',
    mimeType: 'text/markdown',
    encode: (entries) => _markdownExporter.render(entries, exportedAt: _now()),
  );

  Future<bool> _export({
    required String extension,
    required String mimeType,
    required String Function(List<Entry> entries) encode,
  }) async {
    _status = ExportStatus.working;
    _message = null;
    _notify();
    try {
      final entries = await repository.exportAll();
      final bytes = Uint8List.fromList(utf8.encode(encode(entries)));
      final name = '本地日记-${_stamp()}.$extension';
      final saved = await fileGateway.saveFile(
        suggestedName: name,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (saved == null) {
        _status = ExportStatus.idle;
        _notify();
        return false;
      }
      _lastExportBytes = bytes;
      _lastExportName = name;
      _status = ExportStatus.success;
      _message = '已导出 ${entries.length} 条';
      _notify();
      return true;
    } catch (error) {
      debugPrint('导出失败：$error');
      _status = ExportStatus.failure;
      _message = '导出失败，请检查存储空间后重试';
      _notify();
      return false;
    }
  }

  Future<bool> shareLastExport() async {
    final bytes = _lastExportBytes;
    final name = _lastExportName;
    if (bytes == null || name == null) return false;
    _status = ExportStatus.working;
    _notify();
    try {
      await fileGateway.shareFile(
        fileName: name,
        bytes: bytes,
        mimeType: name.endsWith('.md') ? 'text/markdown' : 'application/json',
      );
      _status = ExportStatus.success;
      _message = '已打开分享面板';
      _notify();
      return true;
    } catch (error) {
      debugPrint('分享失败：$error');
      _status = ExportStatus.failure;
      _message = '分享失败，请重试';
      _notify();
      return false;
    }
  }

  Future<RestorePreview?> pickBackup() async {
    // 每次选择都从零开始：取消或失败后不留上一份备份。
    _pendingDocument = null;
    _status = ExportStatus.working;
    _message = null;
    _notify();
    try {
      final bytes = await fileGateway.pickFile(
        mimeType: 'application/json',
        extensions: ['json'],
      );
      if (bytes == null) {
        _status = ExportStatus.idle;
        _notify();
        return null;
      }
      final document = _codec.decode(utf8.decode(bytes));
      if (document.entries.isEmpty) {
        // 空备份没有可恢复的内容：不写待恢复文档，也不动本地数据。
        _status = ExportStatus.success;
        _message = '备份里没有记录';
        _notify();
        return null;
      }
      final local = await repository.exportAll();
      final preview = compareRestore(local, document.entries);
      _pendingDocument = document;
      _status = ExportStatus.success;
      _message = '已选择备份文件';
      _notify();
      return preview;
    } on BackupFormatException catch (error) {
      debugPrint('备份文件无法读取：$error');
      _status = ExportStatus.failure;
      _message = error.reason;
      _notify();
      return null;
    } catch (error) {
      debugPrint('读取所选文件失败：$error');
      _status = ExportStatus.failure;
      _message = '无法读取所选文件';
      _notify();
      return null;
    }
  }

  Future<ImportSummary?> confirmRestore(BackupDocument document) async {
    _status = ExportStatus.working;
    _message = null;
    _notify();
    try {
      final summary = await repository.importAll(document.entries);
      _status = ExportStatus.success;
      _message =
          '恢复完成：新增 ${summary.inserted} 条，更新 ${summary.updated} 条，跳过 ${summary.skipped} 条';
      _notify();
      return summary;
    } catch (error) {
      debugPrint('恢复失败：$error');
      _status = ExportStatus.failure;
      _message = '恢复失败，未导入任何条目';
      _notify();
      return null;
    }
  }

  String _stamp() {
    final local = _now().toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}-$month-$day-$hour-$minute-$second';
  }
}
