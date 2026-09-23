import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/mini_group_avatar.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/persona_avatar.dart';

/// 聊天记录管理页（设置-数据-聊天记录管理）
///
/// 仿 QQ"清理聊天记录"：全宽行列表（选择圆圈 + 头像 + 名称 + 消息数/日期），
/// 点行任意处勾选，支持全选与批量删除。
class ChatHistoryManagerPage extends StatefulWidget {
  const ChatHistoryManagerPage({super.key});

  @override
  State<ChatHistoryManagerPage> createState() =>
      _ChatHistoryManagerPageState();
}

class _ChatHistoryManagerPageState extends State<ChatHistoryManagerPage> {
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  void _toggle(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectAll = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    final state = context.read<AppState>();
    HapticFeedback.selectionClick();
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedIds
          ..clear()
          ..addAll(state.sessions.map((s) => s.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final state = context.read<AppState>();
    final count = _selectedIds.length;
    final isAll = count == state.sessions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除聊天记录'),
        content: Text(
          isAll
              ? '确定删除全部 $count 个会话的聊天记录吗？此操作不可撤销。'
              : '确定删除选中的 $count 个会话的聊天记录吗？此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await state.deleteSessions(_selectedIds.toList());
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectAll = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $count 个会话的聊天记录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final sessions = state.sessions;
    final totalMessages = sessions.fold<int>(
      0,
      (sum, s) => sum + s.messages.length,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('聊天记录管理', style: largeAppBarTitleStyle(context)),
          ),
          if (sessions.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: cs.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有聊天记录',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text(
                  '共 ${sessions.length} 个会话 · $totalMessages 条消息',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 0.5, color: cs.outlineVariant),
              ),
              itemBuilder: (context, i) {
                final session = sessions[i];
                return _SessionRow(
                  session: session,
                  selected: _selectedIds.contains(session.id),
                  onToggle: () => _toggle(session.id),
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
          ],
        ],
      ),
      bottomSheet: sessions.isEmpty
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    top: BorderSide(color: cs.outlineVariant, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 全选
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _toggleSelectAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            _SelectCircle(selected: _selectAll, color: cs),
                            const SizedBox(width: 10),
                            Text(
                              '全选',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 删除
                    AnimatedOpacity(
                      opacity: _selectedIds.isEmpty ? 0.4 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: _selectedIds.isEmpty,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.errorContainer,
                            foregroundColor: cs.onErrorContainer,
                          ),
                          onPressed: _deleteSelected,
                          child: Text(
                            _selectedIds.isEmpty
                                ? '删除'
                                : '删除 (${_selectedIds.length})',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 单个会话行：选择圆圈 + 头像 + 标题 + 消息数/时间
class _SessionRow extends StatelessWidget {
  final ChatSession session;
  final bool selected;
  final VoidCallback onToggle;

  const _SessionRow({
    required this.session,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final persona = state.personaOf(session);
    final group = state.groupOf(session);
    final updatedAt = session.updatedAt;
    final timeLabel = '${updatedAt.year}/${updatedAt.month}/${updatedAt.day}';

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _SelectCircle(selected: selected, color: cs),
            const SizedBox(width: 14),
            _SessionAvatar(session: session, persona: persona, group: group),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${session.messages.length} 条消息 · $timeLabel',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  final ChatSession session;
  final Persona? persona;
  final GroupChat? group;

  const _SessionAvatar({
    required this.session,
    required this.persona,
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    if (session.isGroup) {
      final members = (group?.personaIds ?? const [])
          .map((id) => state.personaById(id))
          .whereType<Persona>()
          .toList();
      return MiniGroupAvatar(members: members, avatarPath: group?.avatarPath);
    }
    if (persona != null) return PersonaAvatar(persona: persona, radius: 22);
    return CircleAvatar(
      radius: 22,
      backgroundColor: cs.primaryContainer,
      child: Icon(
        Icons.chat_bubble_outline_rounded,
        size: 20,
        color: cs.onPrimaryContainer,
      ),
    );
  }
}

/// 选择圆圈：带缩放动画的对勾圈
class _SelectCircle extends StatelessWidget {
  final bool selected;
  final ColorScheme color;

  const _SelectCircle({required this.selected, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color.primary : Colors.transparent,
        border: Border.all(
          color: selected ? color.primary : color.outline,
          width: selected ? 0 : 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: color.onPrimary)
          : null,
    );
  }
}
