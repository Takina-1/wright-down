import 'entry.dart';

abstract interface class LocalEntryRepository {
  Future<void> save(Entry entry);
  Future<List<Entry>> list({EntryCursor? before, int limit = 30});
  Future<void> close();
}
