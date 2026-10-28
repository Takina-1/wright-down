import 'package:flutter/material.dart';

class LocalDataPage extends StatelessWidget {
  const LocalDataPage({super.key});
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
                  '当前版本保存日记正文和记录时间，使用应用内的本地数据库。\n\n'
                  '本版本不包含账号、应用内云同步、广告或行为统计，也不会申请麦克风、相机和相册权限。\n\n'
                  '看到“已保存”表示内容已写入本地数据库；尚未保存时强制终止应用可能丢失最近输入。\n\n'
                  '卸载应用、清除应用数据或设备损坏可能造成记录丢失。当前版本尚未提供导出与备份，请勿将唯一的重要记录保存在这里。',
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
