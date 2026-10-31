/// 标签规范化：trim、去空、去重（保序）。
///
/// 大小写敏感（"Travel" 与 "travel" 视为不同标签）。空字符串与纯空白
/// 被过滤。返回新列表，不修改入参。
///
/// 这是 domain 层纯函数（零框架依赖，符合 Local-First 三条铁律），
/// 记录页加标签、仓储层存标签、备份编码前都应先过这一道，
/// 避免各处各写一份判断导致存进去的标签形态不一致。
List<String> normalizeTags(List<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in raw) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed)) {
      result.add(trimmed);
    }
  }
  return result;
}
