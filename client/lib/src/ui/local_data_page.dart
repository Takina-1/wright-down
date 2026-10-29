import 'package:flutter/material.dart';

import '../domain/export/file_gateway.dart';
import '../domain/local_entry_repository.dart';
import '../platform/saf_file_gateway.dart';
import 'export_page.dart';

class LocalDataPage extends StatelessWidget {
  const LocalDataPage({
    super.key,
    required this.repository,
    this.fileGateway = const SafFileGateway(),
  });
  final LocalEntryRepository repository;

  /// 文件出口。默认用系统实现，测试可以注入替身。
  final FileGateway fileGateway;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        '我的',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 24),
      const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.phone_android_outlined),
              SizedBox(height: 12),
              Text(
                '本地模式',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('无需账号，离线也能记录。'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.archive_outlined),
        title: const Text('导出与备份'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                ExportPage(repository: repository, fileGateway: fileGateway),
          ),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('本地数据说明'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('本地数据说明')),
              body: const SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Text(
                  key: Key('local-data-note'),
                  '当前版本保存日记正文和记录时间，使用应用内的本地数据库。\n\n'
                  '本版本不包含账号、应用内云同步、广告或行为统计，也不会申请麦克风、相机和相册权限。\n\n'
                  '看到“已保存”表示内容已写入本地数据库；尚未保存时强制终止应用可能丢失最近输入。\n\n'
                  '在「导出与备份」里可以手动导出备份文件和 Markdown 文件，'
                  '两者都是明文、不做加密，任何文本编辑器都能打开，请自行保管。'
                  '应用不会自动备份，卸载应用或清除数据仍会丢失未导出的记录。',
                  style: TextStyle(fontSize: 16, height: 1.8),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('本地日记 · 开发预览版', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
