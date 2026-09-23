import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../widgets/persona_avatar.dart';
import 'dashboard_page.dart';
import 'memory_graph_page.dart';

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
    final isGlobal = state.memorySettings.memoryScopeMode == 'global';
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
    // 归档记忆不混排在主列表，折叠到末尾分区
    final visible = filtered.where((m) => m.status == 'active').toList();
    final archived = filtered.where((m) => m.status != 'active').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('查看记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: '记忆图谱',
            onPressed: () {
              Navigator.push(
                context,
                FastRoute(builder: (_) => const MemoryGraphPage()),
              );
            },
          ),
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
                      itemCount: visible.length + (archived.isEmpty ? 0 : 1),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i >= visible.length) {
                          return _ArchivedSection(
                            memories: archived,
                            keyword: _keyword.trim(),
                            labelFor: (m) => _globalSessionLabelFor(state, m),
                            onTap: (m) => _showEditDialog(
                              context,
                              persona: state.personaById(m.personaId),
                              memory: m,
                            ),
                            onDelete: (m) =>
                                context.read<AppState>().deleteMemory(m.id),
                          );
                        }
                        final m = visible[i];
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
    // 归档记忆折叠分区
    final visible = filtered.where((m) => m.status == 'active').toList();
    final archived = filtered.where((m) => m.status != 'active').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('查看记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: '记忆图谱',
            onPressed: () {
              Navigator.push(
                context,
                FastRoute(builder: (_) => const MemoryGraphPage()),
              );
            },
          ),
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
                  if (state.memorySettings.memoryScopeMode == 'persona')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        '人物隔离：这个人物在所有会话里共用同一份记忆',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
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
                            itemCount:
                                visible.length + (archived.isEmpty ? 0 : 1),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              if (i >= visible.length) {
                                return _ArchivedSection(
                                  memories: archived,
                                  keyword: _keyword.trim(),
                                  labelFor: (m) => _sessionLabelFor(
                                    state,
                                    m,
                                    sessions,
                                    selectedPersona?.name,
                                  ),
                                  onTap: (m) => _showEditDialog(
                                    context,
                                    persona: selectedPersona,
                                    memory: m,
                                  ),
                                  onDelete: (m) => context
                                      .read<AppState>()
                                      .deleteMemory(m.id),
                                );
                              }
                              final m = visible[i];
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
      bool matches(MemoryEntry m) {
        if (m.content.toLowerCase().contains(kw)) return true;
        if (m.personaSummary.toLowerCase().contains(kw)) return true;
        if (m.topics.any((t) => t.toLowerCase().contains(kw))) return true;
        if (m.keyFacts.any((f) => f.toLowerCase().contains(kw))) return true;
        if (m.participants.any((p) => p.toLowerCase().contains(kw))) {
          return true;
        }
        return false;
      }

      list = list.where(matches).toList();
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
    final isArchived = memory?.status == 'archived';
    final contentCtrl = TextEditingController(text: memory?.content ?? '');
    final factsCtrl = TextEditingController(
      text: memory?.keyFacts.join('\n') ?? '',
    );
    var topics = memory?.topics.toList() ?? <String>[];
    var importance = memory?.importance ?? 0.5;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 32,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                  child: Row(
                    children: [
                      Text(
                        memory == null
                            ? (persona != null
                                  ? '为「${persona.name}」添加记忆'
                                  : '添加通用记忆')
                            : '编辑记忆',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('记忆内容', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextField(
                          controller: contentCtrl,
                          minLines: 4,
                          maxLines: 8,
                          autofocus: memory == null,
                          decoration: const InputDecoration(
                            hintText: '如：用户喜欢猫，讨厌香菜',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('主题', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        _TopicsEditor(
                          initial: memory?.topics ?? const [],
                          onChanged: (list) => topics = list,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '关键事实（每行一条，用于生成记忆原子）',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: factsCtrl,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: '如：\n用户养了一只猫\n用户不吃香菜',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              '重要性',
                              style: Theme.of(ctx).textTheme.labelLarge,
                            ),
                            Expanded(
                              child: Slider(
                                value: importance,
                                min: 0,
                                max: 1,
                                divisions: 20,
                                label: importance.toStringAsFixed(2),
                                onChanged: (v) =>
                                    setDialogState(() => importance = v),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                importance.toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                  child: Row(
                    children: [
                      if (memory != null)
                        TextButton.icon(
                          onPressed: () {
                            context.read<AppState>().setMemoryArchived(
                              memory.id,
                              !isArchived,
                            );
                            Navigator.pop(ctx);
                          },
                          icon: Icon(
                            isArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                            size: 18,
                          ),
                          label: Text(isArchived ? '恢复' : '归档'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () async {
                          final appState = context.read<AppState>();
                          final text = contentCtrl.text.trim();
                          final facts = factsCtrl.text
                              .split('\n')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                          if (memory == null) {
                            if (text.isNotEmpty) {
                              final created = await appState.addMemory(
                                text,
                                personaId: persona?.id,
                              );
                              if (created != null) {
                                await appState.updateMemoryFull(
                                  created.id,
                                  topics: topics,
                                  keyFacts: facts,
                                  importance: importance,
                                );
                              }
                            }
                          } else {
                            await appState.updateMemoryFull(
                              memory.id,
                              content: text,
                              topics: topics,
                              keyFacts: facts,
                              importance: importance,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 主题芯片编辑器
// ──────────────────────────────────────────────

/// 主题以芯片呈现，输入框回车或点 ➕ 添加；
/// 输入/粘贴含「、,，」分隔符的文本时自动拆成多个芯片，天然去重。
class _TopicsEditor extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  const _TopicsEditor({required this.initial, required this.onChanged});

  @override
  State<_TopicsEditor> createState() => _TopicsEditorState();
}

class _TopicsEditorState extends State<_TopicsEditor> {
  late final List<String> _topics = List.from(widget.initial);
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parts = raw
        .split(RegExp(r'[、,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_topics.contains(e))
        .toList();
    _ctrl.clear();
    if (parts.isEmpty) return;
    setState(() => _topics.addAll(parts));
    widget.onChanged(List.of(_topics));
  }

  void _remove(String topic) {
    setState(() => _topics.remove(topic));
    widget.onChanged(List.of(_topics));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_topics.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in _topics)
                  InputChip(
                    label: Text(topic),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _remove(topic),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: _commit,
          // 打分隔符（或粘贴带分隔符的文本）立即拆成芯片
          onChanged: (v) {
            if (v.contains(RegExp(r'[、,，]'))) _commit(v);
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: _topics.isEmpty ? '如：宠物、饮食偏好（回车添加）' : '添加主题…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(Icons.add_circle_outline, size: 20, color: cs.primary),
              tooltip: '添加',
              onPressed: () {
                if (_ctrl.text.trim().isEmpty) return;
                _commit(_ctrl.text);
                _focus.requestFocus();
              },
            ),
          ),
        ),
      ],
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
// 已归档记忆折叠分区
// ──────────────────────────────────────────────

class _ArchivedSection extends StatefulWidget {
  final List<MemoryEntry> memories;
  final String keyword;
  final String? Function(MemoryEntry m) labelFor;
  final void Function(MemoryEntry m) onTap;
  final void Function(MemoryEntry m) onDelete;

  const _ArchivedSection({
    required this.memories,
    required this.keyword,
    required this.labelFor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends State<_ArchivedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        leading: Icon(Icons.archive_outlined, size: 20, color: cs.outline),
        title: Text(
          '已归档记忆',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${widget.memories.length}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        children: _expanded
            ? [
                for (final m in widget.memories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MemoryCard(
                      memory: m,
                      sessionLabel: widget.labelFor(m),
                      keyword: widget.keyword,
                      onTap: () => widget.onTap(m),
                      onDelete: () => widget.onDelete(m),
                    ),
                  ),
              ]
            : const [],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 记忆卡片
// ──────────────────────────────────────────────

/// 单条记忆卡片（重写版）：正文是主角——
/// 顶行「来源徽章 + 会话 + 时间」、正文（关键词高亮，最多 4 行）、
/// 主题芯片行、底行「重要性条 + 热度 + 合并溯源 + 删除」。
/// 去掉了旧版塞满十来个裸图标标签的信息 Wrap，信息分层呈现。
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
    final sourceLabel = isAuto ? 'AI' : isSummary ? '总结' : '手动';
    final isArchived = memory.status == 'archived';
    final isMerged = memory.consolidatedFrom.isNotEmpty;
    final showTopics = memory.topics.take(3).toList();

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 顶行：来源徽章 · 会话 · 时间 ——
              Row(
                children: [
                  _Badge(
                    icon: isAuto
                        ? Icons.auto_awesome
                        : isSummary
                        ? Icons.summarize_outlined
                        : Icons.edit_note,
                    text: sourceLabel,
                    color: sourceColor,
                  ),
                  if (isArchived) ...[
                    const SizedBox(width: 6),
                    _Badge(
                      icon: Icons.archive_outlined,
                      text: '已归档',
                      color: cs.outline,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionLabel ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MM-dd HH:mm').format(memory.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // —— 正文（关键词高亮） ——
              _HighlightedText(
                text: memory.displayContent,
                keyword: keyword,
                baseStyle: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: isArchived
                      ? cs.onSurface.withValues(alpha: 0.5)
                      : cs.onSurface,
                ),
                maxLines: 4,
              ),
              // —— 关键事实（最多 2 条，帮助一眼看懂这条记住了什么） ——
              if (!isArchived && memory.keyFacts.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final fact in memory.keyFacts.take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6.5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.outline.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            fact,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              // —— 主题芯片行 ——
              if (showTopics.isNotEmpty || memory.sentiment != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final topic in showTopics)
                      _TopicChip(text: topic, color: cs.tertiary),
                    if (memory.topics.length > showTopics.length)
                      Text(
                        '+${memory.topics.length - showTopics.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    if (memory.sentiment != null &&
                        memory.sentiment != 'neutral')
                      _Badge(
                        icon: memory.sentiment == 'positive'
                            ? Icons.sentiment_satisfied_alt
                            : Icons.sentiment_dissatisfied,
                        text: memory.sentiment == 'positive' ? '积极' : '消极',
                        color: memory.sentiment == 'positive'
                            ? const Color(0xFF43A047)
                            : const Color(0xFFE53935),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // —— 底行：重要性条 · 热度 · 溯源 · 删除 ——
              Row(
                children: [
                  _ImportanceBar(importance: memory.importance),
                  const SizedBox(width: 12),
                  if (memory.accessCount > 0) ...[
                    Icon(
                      Icons.local_fire_department_outlined,
                      size: 12,
                      color: memory.accessCount >= 5
                          ? Colors.orange
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${memory.accessCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (isMerged) ...[
                    Icon(
                      Icons.merge_type_outlined,
                      size: 12,
                      color: cs.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '合并 ${memory.consolidatedFrom.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.primary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 带底色的小徽章：图标 + 文字的着色胶囊
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Badge({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 主题芯片
class _TopicChip extends StatelessWidget {
  final String text;
  final Color color;

  const _TopicChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tag, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 重要性：迷你进度条 + 数值，颜色随档位变化
class _ImportanceBar extends StatelessWidget {
  final double importance;
  const _ImportanceBar({required this.importance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color;
    if (importance >= 0.75) {
      color = const Color(0xFFE53935); // 红色：高重要性
    } else if (importance >= 0.5) {
      color = const Color(0xFFFFA726); // 琥珀色：中高
    } else if (importance >= 0.25) {
      color = const Color(0xFF42A5F5); // 蓝色：中
    } else {
      color = cs.onSurfaceVariant.withValues(alpha: 0.5);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 56,
            height: 4,
            child: Stack(
              children: [
                ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: const SizedBox.expand(),
                ),
                // 首次出现时从 0 生长到目标值（一次性动画）
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: importance.clamp(0.04, 1.0)),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => FractionallySizedBox(
                    widthFactor: value,
                    child: ColoredBox(
                      color: color,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          importance.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
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
  final int? maxLines;

  const _HighlightedText({
    required this.text,
    required this.keyword,
    required this.baseStyle,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines);
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
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
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
