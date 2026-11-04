import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sync_core/sync_core.dart';

import '../../data/sync/sync_engine.dart';
import '../../domain/local_entry_repository.dart';
import 'sync_status_indicator.dart';
import 'login_page.dart';

/// 「我的」页顶部的账号卡。
///
/// 启动时调 [AuthProvider.current] 读登录态：
/// - 未登录：显示「登录」按钮，点按推上 [LoginPage]。
/// - 已登录：显示账号标识（AuthResult 只带 userId，没有 email）、
///   [SyncEngine] 同步状态（订阅 [SyncState] 文本）、以及「登出」按钮。
///
/// 登出调 [AuthProvider.signOut] 后刷新登录态。同步状态指示是
/// [SyncStatusIndicator]（Task 4）就绪前的最小占位——Task 4 接入后会
/// 用正式指示器替换本卡里的同步状态行。
class AccountCard extends StatefulWidget {
  const AccountCard({
    super.key,
    required this.auth,
    this.syncEngine,
    this.repository,
  });

  final AuthProvider auth;
  final SyncEngine? syncEngine;

  /// 登录页认领机制需要查询本地条目数；为空时登录页跳过认领。
  final LocalEntryRepository? repository;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  AuthResult? _user;
  SyncState _sync = SyncState.idle;
  StreamSubscription<SyncState>? _syncSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _subscribeSync(widget.syncEngine);
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  void _subscribeSync(SyncEngine? engine) {
    _syncSub?.cancel();
    _syncSub = null;
    if (engine == null) return;
    _sync = engine.state;
    _syncSub = engine.stateChanged.listen(
      (s) {
        if (mounted) setState(() => _sync = s);
      },
      onError: (_) {},
    );
  }

  Future<void> _refresh() async {
    final u = await widget.auth.current();
    if (mounted) setState(() => _user = u);
  }

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginPage(
          auth: widget.auth,
          syncEngine: widget.syncEngine,
          repository: widget.repository,
        ),
      ),
    );
    // 登录页返回后刷新登录态（登录成功或登出都会回到本卡）。
    if (mounted) _refresh();
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _user == null ? _buildGuest(context) : _buildLoggedIn(context),
      ),
    );
  }

  Widget _buildGuest(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cloud_outlined),
        const SizedBox(width: 12),
        const Expanded(child: Text('登录后可同步到云端')),
        TextButton(
          onPressed: () => _openLogin(context),
          child: const Text('登录'),
        ),
      ],
    );
  }

  Widget _buildLoggedIn(BuildContext context) {
    final user = _user!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.cloud_outlined),
            SizedBox(width: 12),
            Text('云同步已开启'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 20),
            const SizedBox(width: 8),
            // AuthResult 没有 email 字段，登录态只带 userId，故显示 userId。
            Text(user.userId),
          ],
        ),
        if (widget.syncEngine != null) ...[
          const SizedBox(height: 8),
          _syncStateRow(context),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _signOut,
          child: const Text('登出'),
        ),
      ],
    );
  }

  Widget _syncStateRow(BuildContext context) {
    return SyncStatusIndicator(state: _sync);
  }
}
