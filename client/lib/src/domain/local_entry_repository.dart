import 'entry.dart';
import 'export/import_summary.dart';

abstract interface class LocalEntryRepository {
  Future<void> save(Entry entry);
  Future<List<Entry>> list({EntryCursor? before, int limit = 30});

  /// 导出用：一次取出全部条目，按创建时间倒序排列，不受分页限制。
  Future<List<Entry>> exportAll();

  /// 恢复用：按条目 ID 合并导入。备份较新才覆盖，本地较新一律跳过。
  /// 整个导入在一个事务内完成，失败时整体回滚。
  Future<ImportSummary> importAll(List<Entry> entries);

  Future<void> close();
}
