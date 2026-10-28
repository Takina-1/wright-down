class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String dayKey;
}

class EntryCursor {
  const EntryCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final String id;
}
