/// 心情的稳定标记与显示映射。
///
/// mood 字段存稳定标记字符串（如 `happy`），不存 emoji。
/// emoji 与文字只用于显示，改表情或加种类只动这张表，不动数据模型与备份格式。
library;

enum Mood {
  happy,
  good,
  neutral,
  plain,
  sad;
}

/// 全部心情，弹层按此顺序展示。
const List<Mood> allMoods = [
  Mood.happy,
  Mood.good,
  Mood.neutral,
  Mood.plain,
  Mood.sad,
];

/// 标记 → emoji。
const Map<String, String> _emoji = {
  'happy': '😄',
  'good': '😊',
  'neutral': '🙂',
  'plain': '😐',
  'sad': '😢',
};

/// 标记 → 中文文字。
const Map<String, String> _label = {
  'happy': '开心',
  'good': '不错',
  'neutral': '一般',
  'plain': '平淡',
  'sad': '难过',
};

/// 解析存储值到 [Mood]。非法值、null、空串一律返回 null。
/// 大小写敏感：`Happy` 不等于 `happy`，避免不同来源的拼写漂移。
Mood? parseMood(String? value) {
  if (value == null) return null;
  for (final m in Mood.values) {
    if (m.name == value) return m;
  }
  return null;
}

/// 取 emoji；mood 为 null 或非法标记时返回空串。
String emojiOf(String? mood) => _emoji[mood] ?? '';

/// 取文字；mood 为 null 或非法标记时返回空串。
String labelOf(String? mood) => _label[mood] ?? '';
