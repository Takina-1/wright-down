import 'package:flutter/material.dart';

import '../domain/export/file_gateway.dart';
import '../domain/local_entry_repository.dart';
import 'export_controller.dart';

/// 「我的 → 导出与备份」二级页。
class ExportPage extends StatefulWidget {
  const ExportPage({
    super.key,
    required this.repository,
    required this.fileGateway,
  });

  final LocalEntryRepository repository;
  final FileGateway fileGateway;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final ExportController _controller = ExportController(
    repository: widget.repository,
    fileGateway: widget.fileGateway,
  )..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final preview = await _controller.pickBackup();
    if (!mounted || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复这份备份'),
        content: Text(
          '备份里共有 ${preview.total} 条记录。\n'
          '新增 ${preview.inserted} 条，更新 ${preview.updated} 条，'
          '跳过 ${preview.skipped} 条。\n'
          '本机较新的记录不会被覆盖。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final document = _controller.pendingDocument;
    if (document == null) return;
    await _controller.confirmRestore(document);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _controller.status == ExportStatus.working;
    return Scaffold(
      appBar: AppBar(title: const Text('导出与备份')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                key: const Key('export-plaintext-note'),
                '备份文件和 Markdown 文件都是明文，不做加密，'
                '内容可以用任何文本编辑器打开。'
                '请存放在你自己信任的位置，并注意分享给他人时同样会被看到。',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const Key('export-backup'),
            leading: const Icon(Icons.archive_outlined),
            title: const Text('导出备份（可恢复）'),
            subtitle: const Text('包含全部记录，可从文件恢复'),
            enabled: !busy,
            onTap: busy ? null : _controller.exportBackup,
          ),
          ListTile(
            key: const Key('export-markdown'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('导出 Markdown（可阅读）'),
            subtitle: const Text('按日期分组，适合阅读与打印'),
            enabled: !busy,
            onTap: busy ? null : _controller.exportMarkdown,
          ),
          ListTile(
            key: const Key('restore-backup'),
            leading: const Icon(Icons.restore),
            title: const Text('从备份恢复'),
            subtitle: const Text('选择备份文件，按修改时间合并'),
            enabled: !busy,
            onTap: busy ? null : _restore,
          ),
          if (_controller.canShare)
            ListTile(
              key: const Key('share-export'),
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              subtitle: const Text('把刚导出的文件发送到其他应用'),
              enabled: !busy,
              onTap: busy ? null : _controller.shareLastExport,
            ),
          const SizedBox(height: 24),
          if (_controller.status == ExportStatus.working)
            const LinearProgressIndicator(),
          if (_controller.message != null) ...[
            const SizedBox(height: 12),
            Text(
              _controller.message!,
              style: TextStyle(
                color: _controller.status == ExportStatus.failure
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
