/// 一次恢复实际改动条目的统计。
class ImportSummary {
  const ImportSummary({
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final int inserted;
  final int updated;
  final int skipped;

  int get total => inserted + updated + skipped;
}
