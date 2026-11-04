import 'package:flutter/material.dart';

import '../../data/sync/sync_engine.dart';

/// 同步状态指示器：按 [SyncState] 显示图标 + 文案。
///
/// - [SyncState.syncing] → ⟳ 「同步中」
/// - [SyncState.synced]  → ✓ 「已同步」
/// - [SyncState.failed]  → ⚠ 「同步失败」
/// - [SyncState.idle]    → 本地模式（未登录/未启动同步）
///
/// 无状态、纯展示：订阅由调用方负责（如 [StreamBuilder] 订阅
/// [SyncEngine.stateChanged]），便于在 composer 顶部与账号卡复用。
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, color) = switch (state) {
      SyncState.syncing => (
        Icons.sync,
        '同步中',
        theme.colorScheme.primary,
      ),
      SyncState.synced => (
        Icons.check_circle,
        '已同步',
        const Color(0xFF2E7D32),
      ),
      SyncState.failed => (
        Icons.warning_amber,
        '同步失败',
        theme.colorScheme.error,
      ),
      SyncState.idle => (
        Icons.cloud_off_outlined,
        '本地模式',
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
