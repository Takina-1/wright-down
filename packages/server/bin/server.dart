import 'package:server/server.dart';

/// `dart compile exe bin/server.dart` 的编译入口。
Future<void> main(List<String> args) => serveDiarySync();
