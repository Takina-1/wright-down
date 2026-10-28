import 'package:flutter/material.dart';

import 'src/domain/local_entry_repository.dart';
import 'src/ui/home_page.dart';

class JournalApp extends StatelessWidget {
  const JournalApp({super.key, required this.repository});
  final LocalEntryRepository repository;
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
    home: HomePage(repository: repository),
  );
}
