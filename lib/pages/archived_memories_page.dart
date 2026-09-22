import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';

/// 已归档记忆页面：浏览、恢复或彻底删除归档记忆。
class ArchivedMemoriesPage extends StatelessWidget {
  const ArchivedMemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final archived = state.memories
        .where((m) => m.status == 'archived')
        .toList()
      ..sort((a, b) =>
          (b.archivedAt ?? b.createdAt).compareTo(a.archivedAt ?? a.createdAt));

    return Scaffold(
      appBar: AppBar(title: Text('已归档记忆（${archived.length}）')),
      body: archived.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 48,
                      color: cs.outline.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '没有已归档的记忆',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '在记忆列表的编辑弹窗里选择「归档」，\n或开启自动清理的归档模式后，归档记忆会出现在这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: archived.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = archived[i];
                return _ArchivedCard(memory: m);
              },
            ),
    );
  }
}

class _ArchivedCard extends StatelessWidget {
  final MemoryEntry memory;

  const _ArchivedCard({required this.memory});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final archivedAt = memory.archivedAt ?? memory.createdAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            memory.displayContent,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 12,
                color: cs.outline,
              ),
              const SizedBox(width: 4),
              Text(
                '归档于 ${DateFormat('yyyy-MM-dd HH:mm').format(archivedAt)} · '
                    '重要性 ${memory.importance.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context
                    .read<AppState>()
                    .setMemoryArchived(memory.id, false),
                icon: const Icon(Icons.unarchive_outlined, size: 16),
                label: const Text('恢复'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  final state = context.read<AppState>();
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('彻底删除'),
                      content: const Text(
                        '删除后该记忆及其原子、图谱痕迹将一并移除，无法恢复。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            state.deleteMemory(memory.id);
                            Navigator.pop(ctx);
                          },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                },
                icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                label: Text('删除', style: TextStyle(color: cs.error)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
