import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../widgets/persona_avatar.dart';
import 'dashboard_page.dart';

/// 记忆管理页面
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

const _legacyPersonaId = '__legacy__';

enum _SortBy { timeDesc, timeAsc, importanceDesc, importanceAsc, hotDesc }

class _MemoryPageState extends State<MemoryPage> {
  String? _personaId;
  String? _sessionId;
  // 全局模式下的会话过滤：null=全部, '__private__'=私聊, '__general__'=通用, groupId=群聊
  String? _globalSessionFilter;
  String _keyword = '';
  final _searchCtrl = TextEditingController();
  _SortBy _sortBy = _SortBy.timeDesc;

  // 会话/群聊索引：每次 build 更新（O(n) 构建），供各方法 O(1) 查找，
  // 替换原先 O(n²) 的 state.sessions.where((s)=>s.id==...).firstOrNull
  Map<String, ChatSession> _sessionById = const {};
  Map<String, GroupChat> _groupById = const {};
  Set<String> _privateSessionIds = const {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // 构建索引（O(n)），替换方法内 O(n²) 的 where().firstOrNull 查找
    _sessionById = {for (final s in state.sessions) s.id: s};
    _groupById = {for (final g in state.groupChats) g.id: g};
    _privateSessionIds = {
      for (final s in state.sessions)
        if (s.personaId != null && s.groupChatId == null) s.id,
    };
    final isGlobal = !state.memorySettings.useSessionFiltering;
    final hasLegacyMemories = state.memories.any((m) => m.personaId == null);

    if (isGlobal) {
      return _buildGlobalView(state, hasLegacyMemories);
    }
    return _buildIsolatedView(state, hasLegacyMemories);
  }

  // ──────────────────────────────────────────────
  // 全局模式：支持按群聊/私聊筛选
  // ──────────────────────────────────────────────
  Widget _buildGlobalView(AppState state, bool hasLegacyMemories) {
    // 构建会话筛选选项
    final sessionOptions = _buildGlobalSessionOptions(state);
    final filtered = _filterAndSortGlobal(state.memories.toList(), state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('查看记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: '记忆系统仪表盘',
            onPressed: () {
              Navigator.push(
                context,
                FastRoute(
                  builder: (_) => const DashboardPage(scrollToMemory: true),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加记忆',
            onPressed: () => _showEditDialog(context, persona: null),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 会话筛选栏（全部/私聊/群聊...）
            if (sessionOptions.length > 1)
              _GlobalSessionFilterBar(
                options: sessionOptions,
                selected: _globalSessionFilter,
                onSelect: (id) => setState(
                  () => _globalSessionFilter = _globalSessionFilter == id
                      ? null
                      : id,
                ),
              ),
            _SearchAndSort(
              controller: _searchCtrl,
              sortBy: _sortBy,
              onSearch: (v) => setState(() => _keyword = v),
              onSort: (s) => setState(() => _sortBy = s),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const _MemoryEmpty(personaName: null)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                      cacheExtent: 500,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        final sessionLabel = _globalSessionLabelFor(state, m);
                        return RepaintBoundary(
                          child: _MemoryCard(
                            memory: m,
                            sessionLabel: sessionLabel,
                            keyword: _keyword.trim(),
                            onTap: () => _showEditDialog(
                              context,
                              persona: state.personaById(m.personaId),
                              memory: m,
                            ),
                            onDelete: () =>
                                context.read<AppState>().deleteMemory(m.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建全局模式下的会话筛选选项
  List<_SessionOption> _buildGlobalSessionOptions(AppState state) {
    final result = <_SessionOption>[];
    final memories = state.memories;

    // 全部
    result.add(
      _SessionOption(
        id: null,
        label: '全部',
        icon: Icons.layers_outlined,
        count: memories.length,
      ),
    );

    // 统计各类会话的记忆数
    final privateSessionIds = <String>{};
    final groupSessionIds = <String>{};
    int generalCount = 0;

    for (final m in memories) {
      if (m.sessionId == null) {
        generalCount++;
        continue;
      }
      // O(1) 索引查找，替代 O(n) 的 where().firstOrNull
      final session = _sessionById[m.sessionId];
      if (session == null) continue;
      if (session.groupChatId != null) {
        groupSessionIds.add(session.id);
      } else if (session.personaId != null) {
        privateSessionIds.add(session.id);
      }
    }

    // 私聊
    if (privateSessionIds.isNotEmpty) {
      final count = memories
          .where(
            (m) =>
                m.sessionId != null && privateSessionIds.contains(m.sessionId),
          )
          .length;
      result.add(
        _SessionOption(
          id: '__private__',
          label: '私聊',
          icon: Icons.person_outline,
          count: count,
        ),
      );
    }

    // 通用记忆
    if (generalCount > 0) {
      result.add(
        _SessionOption(
          id: '__general__',
          label: '通用',
          icon: Icons.bookmark_outline,
          count: generalCount,
        ),
      );
    }

    // 各群聊
    for (final g in state.groupChats) {
      final session = state.findSessionWithGroup(g.id);
      if (session == null) continue;
      final count = memories.where((m) => m.sessionId == session.id).length;
      if (count > 0) {
        result.add(
          _SessionOption(
            id: g.id,
            label: g.name,
            icon: Icons.group_outlined,
            count: count,
            isGroup: true,
          ),
        );
      }
    }

    return result;
  }

  /// 全局模式下过滤记忆
  List<MemoryEntry> _filterAndSortGlobal(
    List<MemoryEntry> list,
    AppState state,
  ) {
    if (_globalSessionFilter != null) {
      final filter = _globalSessionFilter!;
      if (filter == '__general__') {
        list = list.where((m) => m.sessionId == null).toList();
      } else if (filter == '__private__') {
        // 用 build 中预构建的 _privateSessionIds，避免每次过滤都遍历 sessions
        list = list
            .where(
              (m) =>
                  m.sessionId != null &&
                  _privateSessionIds.contains(m.sessionId!),
            )
            .toList();
      } else {
        // 群聊 ID
        final session = state.findSessionWithGroup(filter);
        if (session != null) {
          list = list.where((m) => m.sessionId == session.id).toList();
        }
      }
    }
    return _applyKeywordAndSort(list);
  }

  /// 获取全局模式下记忆的会话标签
  String? _globalSessionLabelFor(AppState state, MemoryEntry m) {
    if (m.sessionId == null) return '通用记忆';
    // O(1) 索引查找
    final session = _sessionById[m.sessionId];
    if (session == null) return null;
    if (session.groupChatId != null) {
      return _groupById[session.groupChatId]?.name;
    }
    if (session.personaId != null) {
      final persona = state.personaById(session.personaId);
      return persona?.name != null ? '私聊·${persona!.name}' : '私聊';
    }
    return null;
  }

  // ──────────────────────────────────────────────
  // 会话隔离模式
  // ──────────────────────────────────────────────
  Widget _buildIsolatedView(AppState state, bool hasLegacyMemories) {
    final selectedId =
        _personaId != null &&
            (state.personas.any((p) => p.id == _personaId) ||
                (_personaId == _legacyPersonaId && hasLegacyMemories))
        ? _personaId
        : (state.personas.isNotEmpty
              ? state.personas.first.id
              : (hasLegacyMemories ? _legacyPersonaId : null));

    final selectedPersona = state.personaById(selectedId);
    final sessions = _findSessionsForPersona(state, selectedId);
    final rawMemories = state.memories.where((m) {
      if (selectedId == _legacyPersonaId) return m.personaId == null;
      if (m.personaId != selectedId) return false;
      if (_sessionId == null) return true;
      if (_sessionId == '__general__') return m.sessionId == null;
      return m.sessionId == _sessionId;
    }).toList();
    final filtered = _applyKeywordAndSort(rawMemories);

    return Scaffold(
      appBar: AppBar(
        title: const Text('查看记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: '记忆系统仪表盘',
            onPressed: () {
              Navigator.push(
                context,
                FastRoute(
                  builder: (_) => const DashboardPage(scrollToMemory: true),
                ),
              );
            },
          ),
          if (selectedPersona != null)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: '添加记忆',
              onPressed: () =>
                  _showEditDialog(context, persona: selectedPersona),
            ),
        ],
      ),
      body: SafeArea(
        child: state.personas.isEmpty && !hasLegacyMemories
            ? const _EmptyState()
            : Column(
                children: [
                  // 角色选择器
                  _PersonaSelector(
                    personas: state.personas,
                    hasLegacy: hasLegacyMemories,
                    selectedId: selectedId,
                    onSelect: (id) => setState(() {
                      _personaId = id;
                      _sessionId = null;
                    }),
                  ),
                  // 会话过滤（包含群聊）
                  if (sessions.isNotEmpty ||
                      _hasGeneralMemories(state, selectedId))
                    _SessionFilterBar(
                      sessions: sessions,
                      generalCount: _generalMemoryCount(state, selectedId),
                      selected: _sessionId,
                      onSelect: (id) => setState(
                        () => _sessionId = _sessionId == id ? null : id,
                      ),
                    ),
                  // 搜索 + 排序
                  _SearchAndSort(
                    controller: _searchCtrl,
                    sortBy: _sortBy,
                    onSearch: (v) => setState(() => _keyword = v),
                    onSort: (s) => setState(() => _sortBy = s),
                  ),
                  // 记忆列表
                  Expanded(
                    child: filtered.isEmpty
                        ? _MemoryEmpty(personaName: selectedPersona?.name)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                            cacheExtent: 500,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final m = filtered[i];
                              final sessionLabel = _sessionLabelFor(
                                state,
                                m,
                                sessions,
                                selectedPersona?.name,
                              );
                              return RepaintBoundary(
                                child: _MemoryCard(
                                  memory: m,
                                  sessionLabel: sessionLabel,
                                  keyword: _keyword.trim(),
                                  onTap: () => _showEditDialog(
                                    context,
                                    persona: selectedPersona,
                                    memory: m,
                                  ),
                                  onDelete: () => context
                                      .read<AppState>()
                                      .deleteMemory(m.id),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  List<MemoryEntry> _applyKeywordAndSort(List<MemoryEntry> list) {
    if (_keyword.trim().isNotEmpty) {
      final kw = _keyword.trim().toLowerCase();
      list = list.where((m) => m.content.toLowerCase().contains(kw)).toList();
    }
    switch (_sortBy) {
      case _SortBy.timeDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortBy.timeAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _SortBy.importanceDesc:
        list.sort((a, b) => b.importance.compareTo(a.importance));
      case _SortBy.importanceAsc:
        list.sort((a, b) => a.importance.compareTo(b.importance));
      case _SortBy.hotDesc:
        list.sort((a, b) => b.accessCount.compareTo(a.accessCount));
    }
    return list;
  }

  List<_SessionInfo> _findSessionsForPersona(
    AppState state,
    String? personaId,
  ) {
    if (personaId == null || personaId == _legacyPersonaId) return [];
    final result = <_SessionInfo>[];
    final privateSession = state.findSessionWithPersona(personaId);
    if (privateSession != null) {
      final count = state.memories
          .where(
            (m) => m.personaId == personaId && m.sessionId == privateSession.id,
          )
          .length;
      if (count > 0) {
        result.add(
          _SessionInfo(
            id: privateSession.id,
            label: '私聊',
            icon: Icons.person_outline,
            memoryCount: count,
          ),
        );
      }
    }
    for (final g in state.groupChats) {
      if (!g.personaIds.contains(personaId)) continue;
      final session = state.findSessionWithGroup(g.id);
      if (session == null) continue;
      final count = state.memories
          .where((m) => m.personaId == personaId && m.sessionId == session.id)
          .length;
      if (count > 0) {
        result.add(
          _SessionInfo(
            id: session.id,
            label: g.name,
            icon: Icons.group_outlined,
            memoryCount: count,
          ),
        );
      }
    }
    return result;
  }

  bool _hasGeneralMemories(AppState state, String? personaId) {
    if (personaId == null || personaId == _legacyPersonaId) return false;
    return state.memories.any(
      (m) => m.personaId == personaId && m.sessionId == null,
    );
  }

  int _generalMemoryCount(AppState state, String? personaId) {
    if (personaId == null || personaId == _legacyPersonaId) return 0;
    return state.memories
        .where((m) => m.personaId == personaId && m.sessionId == null)
        .length;
  }

  String? _sessionLabelFor(
    AppState state,
    MemoryEntry m,
    List<_SessionInfo> sessions,
    String? personaName,
  ) {
    if (m.sessionId == null) return '通用记忆';
    return sessions.where((s) => s.id == m.sessionId).firstOrNull?.label;
  }

  void _showEditDialog(
    BuildContext context, {
    Persona? persona,
    MemoryEntry? memory,
  }) {
    final controller = TextEditingController(text: memory?.content ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          memory == null
              ? (persona != null ? '为「${persona.name}」添加记忆' : '添加通用记忆')
              : '编辑记忆',
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：用户喜欢猫，讨厌香菜',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final appState = context.read<AppState>();
                if (memory == null) {
                  appState.addMemory(text, personaId: persona?.id);
                } else {
                  appState.updateMemory(memory.id, text);
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 数据类
// ──────────────────────────────────────────────

class _SessionInfo {
  final String id;
  final String label;
  final IconData icon;
  final int memoryCount;
  _SessionInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.memoryCount,
  });
}

class _SessionOption {
  final String? id;
  final String label;
  final IconData icon;
  final int count;
  final bool isGroup;
  _SessionOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.count,
    this.isGroup = false,
  });
}

// ──────────────────────────────────────────────
// 全局模式会话筛选栏
// ──────────────────────────────────────────────

class _GlobalSessionFilterBar extends StatelessWidget {
  final List<_SessionOption> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _GlobalSessionFilterBar({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final opt = options[i];
          final isSelected =
              selected == opt.id || (selected == null && opt.id == null);
          return _SessionFilterChip(
            label: opt.label,
            icon: opt.icon,
            count: opt.count,
            selected: isSelected,
            isGroup: opt.isGroup,
            onTap: () => onSelect(opt.id),
          );
        },
      ),
    );
  }
}

class _SessionFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final bool isGroup;
  final VoidCallback onTap;

  const _SessionFilterChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    this.isGroup = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected
                  ? cs.onPrimary
                  : isGroup
                  ? cs.tertiary
                  : cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(label),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? cs.onPrimary.withValues(alpha: 0.75)
                    : cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: isGroup
            ? cs.tertiary.withValues(alpha: 0.2)
            : cs.primary.withValues(alpha: 0.15),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        side: BorderSide(
          color: selected
              ? (isGroup ? cs.tertiary : cs.primary).withValues(alpha: 0.5)
              : cs.outlineVariant.withValues(alpha: 0.4),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? (isGroup ? cs.tertiary : cs.primary)
              : cs.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 角色选择器
// ──────────────────────────────────────────────

class _PersonaSelector extends StatelessWidget {
  final List<Persona> personas;
  final bool hasLegacy;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  const _PersonaSelector({
    required this.personas,
    required this.hasLegacy,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: personas.length + (hasLegacy ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i < personas.length) {
            final p = personas[i];
            final selected = p.id == selectedId;
            return _PersonaAvatarItem(
              persona: p,
              selected: selected,
              onTap: () => onSelect(p.id),
            );
          }
          final selected = _legacyPersonaId == selectedId;
          return _LegacyAvatar(
            selected: selected,
            onTap: () => onSelect(_legacyPersonaId),
          );
        },
      ),
    );
  }
}

class _PersonaAvatarItem extends StatelessWidget {
  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  const _PersonaAvatarItem({
    required this.persona,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withValues(alpha: 0.25) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                PersonaAvatar(persona: persona, radius: 22),
                if (selected)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(Icons.check, size: 10, color: cs.onPrimary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              persona.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyAvatar extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _LegacyAvatar({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withValues(alpha: 0.25) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.surfaceContainerHigh,
              child: Icon(Icons.help_outline, size: 22, color: cs.outline),
            ),
            const SizedBox(height: 5),
            Text(
              '旧记忆',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 会话隔离模式的会话过滤栏
// ──────────────────────────────────────────────

class _SessionFilterBar extends StatelessWidget {
  final List<_SessionInfo> sessions;
  final int generalCount;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _SessionFilterBar({
    required this.sessions,
    required this.generalCount,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = sessions.fold(
      generalCount,
      (sum, s) => sum + s.memoryCount,
    );

    final chips = <Widget>[
      _SessionFilterChip(
        label: '全部',
        icon: Icons.layers_outlined,
        count: totalCount,
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
    ];

    if (generalCount > 0) {
      chips.add(
        _SessionFilterChip(
          label: '通用',
          icon: Icons.bookmark_outline,
          count: generalCount,
          selected: selected == '__general__',
          onTap: () => onSelect('__general__'),
        ),
      );
    }

    for (final s in sessions) {
      chips.add(
        _SessionFilterChip(
          label: s.label,
          icon: s.icon,
          count: s.memoryCount,
          selected: selected == s.id,
          isGroup: s.icon == Icons.group_outlined,
          onTap: () => onSelect(s.id),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 搜索 + 排序
// ──────────────────────────────────────────────

class _SearchAndSort extends StatefulWidget {
  final TextEditingController controller;
  final _SortBy sortBy;
  final ValueChanged<String> onSearch;
  final ValueChanged<_SortBy> onSort;

  const _SearchAndSort({
    required this.controller,
    required this.sortBy,
    required this.onSearch,
    required this.onSort,
  });

  @override
  State<_SearchAndSort> createState() => _SearchAndSortState();
}

class _SearchAndSortState extends State<_SearchAndSort> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onFocusChange: (f) => setState(() => _focused = f),
              child: TextField(
                controller: widget.controller,
                onChanged: widget.onSearch,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: widget.controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            widget.controller.clear();
                            widget.onSearch('');
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                  hintText: '搜索记忆…',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: _focused
                      ? cs.primaryContainer.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SortButton(sortBy: widget.sortBy, onChanged: widget.onSort),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final _SortBy sortBy;
  final ValueChanged<_SortBy> onChanged;

  const _SortButton({required this.sortBy, required this.onChanged});

  String get _label => switch (sortBy) {
    _SortBy.timeDesc => '最新',
    _SortBy.timeAsc => '最早',
    _SortBy.importanceDesc => '权重高',
    _SortBy.importanceAsc => '权重低',
    _SortBy.hotDesc => '热度',
  };

  IconData get _icon => switch (sortBy) {
    _SortBy.timeDesc || _SortBy.timeAsc => Icons.schedule_outlined,
    _SortBy.importanceDesc || _SortBy.importanceAsc => Icons.bar_chart_outlined,
    _SortBy.hotDesc => Icons.local_fire_department_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<_SortBy>(
      onSelected: onChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        _sortItem(_SortBy.timeDesc, '最新优先', Icons.schedule_outlined),
        _sortItem(_SortBy.timeAsc, '最早优先', Icons.schedule_outlined),
        _sortItem(_SortBy.importanceDesc, '权重从高到低', Icons.bar_chart_outlined),
        _sortItem(_SortBy.importanceAsc, '权重从低到高', Icons.bar_chart_outlined),
        _sortItem(
          _SortBy.hotDesc,
          '热度优先',
          Icons.local_fire_department_outlined,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_SortBy> _sortItem(_SortBy value, String text, IconData icon) {
    final selected = sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: selected ? Colors.blue : Colors.grey),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.blue : null,
            ),
          ),
          const Spacer(),
          if (selected) const Icon(Icons.check, size: 16, color: Colors.blue),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 记忆卡片
// ──────────────────────────────────────────────

class _MemoryCard extends StatelessWidget {
  final MemoryEntry memory;
  final String? sessionLabel;
  final String keyword;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MemoryCard({
    required this.memory,
    this.sessionLabel,
    required this.keyword,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAuto = memory.source == 'auto';
    final isSummary = memory.source == 'summary';
    final sourceColor = isAuto
        ? cs.primary
        : isSummary
        ? cs.tertiary
        : cs.secondary;
    final sourceLabel = isAuto
        ? 'AI'
        : isSummary
        ? '总结'
        : '手动';

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(width: 3, color: sourceColor),
              top: BorderSide(
                width: 1,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
              right: BorderSide(
                width: 1,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
              bottom: BorderSide(
                width: 1,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 内容
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 内容文本（支持关键词高亮）
                      _HighlightedText(
                        text: memory.content,
                        keyword: keyword,
                        baseStyle: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 元信息行
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MetaTag(
                            icon: isAuto
                                ? Icons.auto_awesome
                                : isSummary
                                ? Icons.summarize_outlined
                                : Icons.edit_note,
                            text: sourceLabel,
                            color: sourceColor,
                          ),
                          if (sessionLabel != null)
                            _MetaTag(
                              icon: Icons.bookmark_outline,
                              text: sessionLabel!,
                              color: cs.onSurfaceVariant,
                            ),
                          // 重要性（权重）
                          _ImportanceTag(importance: memory.importance),
                          // 热度（检索次数）
                          if (memory.accessCount > 0)
                            _MetaTag(
                              icon: Icons.local_fire_department_outlined,
                              text: '${memory.accessCount}',
                              color: memory.accessCount >= 5
                                  ? Colors.orange
                                  : cs.onSurfaceVariant,
                            ),
                          _MetaTag(
                            icon: Icons.schedule,
                            text: DateFormat(
                              'MM-dd HH:mm',
                            ).format(memory.createdAt),
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 右侧删除按钮
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaTag({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

/// 重要性标签：显示权重数值 + 颜色编码
class _ImportanceTag extends StatelessWidget {
  final double importance;
  const _ImportanceTag({required this.importance});

  @override
  Widget build(BuildContext context) {
    // 根据重要性等级着色
    final Color color;
    final IconData icon;
    if (importance >= 0.75) {
      color = const Color(0xFFE53935); // 红色：高重要性
      icon = Icons.priority_high_rounded;
    } else if (importance >= 0.5) {
      color = const Color(0xFFFFA726); // 琥珀色：中高
      icon = Icons.fitness_center_rounded;
    } else if (importance >= 0.25) {
      color = const Color(0xFF42A5F5); // 蓝色：中
      icon = Icons.fitness_center_rounded;
    } else {
      color = Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
      icon = Icons.fitness_center_outlined;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          importance.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 带关键词高亮的文本
class _HighlightedText extends StatelessWidget {
  final String text;
  final String keyword;
  final TextStyle baseStyle;

  const _HighlightedText({
    required this.text,
    required this.keyword,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return Text(text, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerKw = kw.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    final highlightStyle = TextStyle(
      color: Theme.of(context).colorScheme.error,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.4),
      fontWeight: FontWeight.w700,
    );

    while (start < text.length) {
      final idx = lowerText.indexOf(lowerKw, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: baseStyle.merge(highlightStyle),
        ),
      );
      start = idx + kw.length;
    }

    return RichText(
      text: TextSpan(children: spans, style: baseStyle),
    );
  }
}

// ──────────────────────────────────────────────
// 空状态
// ──────────────────────────────────────────────

class _MemoryEmpty extends StatelessWidget {
  final String? personaName;
  const _MemoryEmpty({this.personaName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_outlined,
                size: 40,
                color: cs.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              personaName != null ? '「$personaName」暂无记忆' : '暂无记忆记录',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'AI 会自动记录对话中的关键信息\n也可以点击右上角手动添加',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_outlined,
                size: 40,
                color: cs.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '请先创建角色',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '创建角色后，即可为其添加记忆\nAI 也会在对话中自动记录关键信息',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
