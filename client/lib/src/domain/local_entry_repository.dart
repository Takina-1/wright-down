import 'entry.dart';
import 'export/import_summary.dart';

abstract interface class LocalEntryRepository {
  Future<void> save(Entry entry);

  /// 时间轴列表：只含未删除条目，按创建时间倒序。
  Future<List<Entry>> list({EntryCursor? before, int limit = 30});

  /// 导出用：一次取出全部条目（含已删除条目），按创建时间倒序排列，不受分页限制。
  /// 含已删除条目是为了让备份携带删除标记，恢复时不会把已删条目复活。
  Future<List<Entry>> exportAll();

  /// 回收站列表：只含已删除条目，按删除时间倒序。
  Future<List<Entry>> listDeleted({int limit = 30});

  /// 软删除：标记删除时间。条目从时间轴消失，但数据保留，可在回收站找回。
  Future<void> softDelete(String id);

  /// 从回收站恢复：清除删除标记，条目回到时间轴，创建时间与正文不变。
  Future<void> restore(String id);

  /// 彻底删除：物理移除该条目，不可再恢复。
  Future<void> purge(String id);

  /// 清空回收站：物理移除所有已删除条目，返回移除条数。
  Future<int> purgeAll();

  /// 恢复用：按条目 ID 合并导入。备份较新才覆盖，本地较新一律跳过；
  /// 本地已删除的条目不会被未删除的备份复活。
  /// 整个导入在一个事务内完成，失败时整体回滚。
  Future<ImportSummary> importAll(List<Entry> entries);

  Future<void> close();
}
