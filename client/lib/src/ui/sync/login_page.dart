import 'package:flutter/material.dart';
import 'package:sync_core/sync_core.dart';

import '../../data/sync/sync_engine.dart';
import '../../domain/local_entry_repository.dart';

/// 邮箱密码登录/注册页。
///
/// 邮箱 + 密码两个输入框，「登录」「注册」两个按钮。登录调
/// [AuthProvider.login]，注册调 [AuthProvider.register]；失败显示错误文案。
/// 成功后弹出本页（带 [AuthResult]）并触发认领：查本地条目数，>0 则弹
/// 「要把本机 N 条日记同步到云端吗？」，点「是」调 [SyncEngine.triggerPush]。
///
/// [repository] 为空时跳过认领（认领只对有本地数据的账号有意义）。
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.auth,
    this.syncEngine,
    this.repository,
  });

  final AuthProvider auth;
  final SyncEngine? syncEngine;
  final LocalEntryRepository? repository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(bool register) async {
    if (_busy) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final result = register
          ? await widget.auth.register(_email.text, _password.text)
          : await widget.auth.login(_email.text, _password.text);
      await _claim();
      if (mounted) setState(() => _busy = false);
      // 本页在真实 App 里由 AccountCard push 上来，故能 pop 回。
      // 测试直接把本页当 home 时 canPop 为 false，不 pop 也不会抛错。
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context, result);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = register ? '注册失败，请重试' : '登录失败，请重试';
          _busy = false;
        });
      }
    }
  }

  /// 登录/注册成功后的认领：本机有未同步条目时询问是否推送到云端。
  Future<void> _claim() async {
    final repo = widget.repository;
    if (repo == null) return;
    final entries = await repo.exportAll();
    if (!mounted) return;
    if (entries.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步本机日记'),
        content: Text('要把本机 ${entries.length} 条日记同步到云端吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('是'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.syncEngine?.triggerPush();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录与注册')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '登录后日记可同步到云端',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            key: const Key('login-email'),
            controller: _email,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('login-password'),
            controller: _password,
            autofillHints: const [AutofillHints.password],
            keyboardType: TextInputType.visiblePassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _submit(false),
                  child: const Text('登录'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _submit(true),
                  child: const Text('注册'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
