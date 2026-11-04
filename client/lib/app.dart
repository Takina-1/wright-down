import 'package:flutter/material.dart';

import 'src/data/sync/sync_engine.dart';
import 'src/domain/export/file_gateway.dart';
import 'src/domain/local_entry_repository.dart';
import 'src/ui/home_page.dart';

class JournalApp extends StatelessWidget {
  const JournalApp({
    super.key,
    required this.repository,
    this.fileGateway,
    this.syncEngine,
  });
  final LocalEntryRepository repository;

  /// 文件出口。默认用系统实现，测试可以注入替身。
  final FileGateway? fileGateway;

  /// 同步引擎。为空时 HomePage 不显示同步状态、不触发推拉（保持纯本地）。
  final SyncEngine? syncEngine;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '本地日记',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF496653),
        surface: const Color(0xFFFAF8F3),
      ),
      scaffoldBackgroundColor: const Color(0xFFFAF8F3),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
      ),
    ),
    home: HomePage(
      repository: repository,
      fileGateway: fileGateway,
      syncEngine: syncEngine,
    ),
  );
}
