import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sync_core/sync_core.dart';
import 'sync_store.dart';

Future<Map<String, dynamic>> _json(Request req) async =>
    jsonDecode(await req.readAsString()) as Map<String, dynamic>;

String? _bearer(Request req) {
  final h = req.headers['authorization'];
  if (h is! String) return null;
  final m = RegExp(r'^Bearer (.+)$').firstMatch(h);
  return m?.group(1);
}

Response _okJson(Object body) =>
    Response.ok(jsonEncode(body),
        headers: {'content-type': 'application/json'});

Response _err(int status, String msg) =>
    Response(status, body: msg);

Handler registerHandler(SyncStore store) => (req) async {
  final j = await _json(req);
  final email = j['email'] as String;
  final password = j['password'] as String;
  try {
    final r = await store.register(email, password);
    return _okJson({'userId': r.userId, 'token': r.token});
  } on StateError catch (_) {
    return _err(409, 'email already registered');
  }
};

Handler loginHandler(SyncStore store) => (req) async {
  final j = await _json(req);
  final email = j['email'] as String;
  final password = j['password'] as String;
  final r = await store.login(email, password);
  if (r == null) return _err(401, 'invalid credentials');
  return _okJson({'userId': r.userId, 'token': r.token});
};

Handler pullHandler(SyncStore store) => (req) async {
  final token = _bearer(req);
  if (token == null) return _err(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _err(401, 'invalid token');
  final cursor = int.tryParse(req.requestedUri.queryParameters['cursor'] ?? '0') ?? 0;
  final result = await store.pull(userId, cursor);
  return _okJson(result.toJson());
};

Handler pushHandler(SyncStore store) => (req) async {
  final token = _bearer(req);
  if (token == null) return _err(401, 'missing token');
  final userId = await store.userIdForToken(token);
  if (userId == null) return _err(401, 'invalid token');
  final j = await _json(req);
  final batch = SyncPushBatch.fromJson(j);
  await store.push(userId, batch);
  return _okJson({'ok': true});
};
