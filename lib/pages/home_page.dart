import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../widgets/app_drawer.dart';
import '../widgets/persona_avatar.dart';
import 'chat_page.dart';
import 'persona_page.dart';

const _uuid = Uuid();

/// 主页：社交式列表（群聊 + 好友混合按时间排序）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    // 合并群聊和好友，按最近活动时间排序
    final items = <_ListItem>[];
    for (final g in state.groupChats) {
      final session = state.findSessionWithGroup(g.id);
      items.add(
        _ListItem(
          type: _ItemType.group,
          id: g.id,
          name: g.name,
          avatarPath: g.avatarPath,
          group: g,
          lastTime: session?.updatedAt,
          session: session,
        ),
      );
    }
    for (final p in state.personas) {
      final session = state.findSessionWithPersona(p.id);
      items.add(
        _ListItem(
          type: _ItemType.persona,
          id: p.id,
          name: p.name,
          avatarPath: '',
          persona: p,
          lastTime: session?.updatedAt,
          session: session,
        ),
      );
    }
    items.sort((a, b) {
      final ta = a.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });

    // 搜索过滤
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? items
        : items.where((i) => i.name.toLowerCase().contains(q)).toList();
    final messageHits = q.isEmpty
        ? const <_MessageSearchHit>[]
        : _searchMessages(state, q);

    return Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: Colors.black54,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 110,
            toolbarHeight: 52,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            title: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'MewMew',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                  color: scheme.onSurface,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add_rounded),
                tooltip: '新建群聊',
                onPressed: () => _createGroup(context),
              ),
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_rounded),
                tooltip: '新建人格',
                onPressed: () => Navigator.push(
                  context,
                  FastRoute(builder: (_) => const PersonaPage()),
                ),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: _SearchField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 空状态
          if (state.personas.isEmpty && state.groupChats.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                onAdd: () => Navigator.push(
                  context,
                  FastRoute(builder: (_) => const PersonaPage()),
                ),
              ),
            )
          else if (q.isNotEmpty && filtered.isEmpty && messageHits.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _NoResults())
          else if (q.isNotEmpty)
            SliverList(
              delegate: SliverChildListDelegate([
                if (filtered.isNotEmpty) ...[
                  const _SearchSectionTitle(title: '联系人与群聊'),
                  for (final item in filtered)
                    RepaintBoundary(
                      child: _UnifiedTile(
                        item: item,
                        onTap: () => _openItem(context, item),
                      ),
                    ),
                ],
                if (messageHits.isNotEmpty) ...[
                  const _SearchSectionTitle(title: '聊天记录'),
                  for (final hit in messageHits)
                    RepaintBoundary(
                      child: _MessageSearchTile(
                        hit: hit,
                        onTap: () => _openMessageHit(context, hit),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
              ]),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final item = filtered[i];
                  return RepaintBoundary(
                    child: _UnifiedTile(
                      item: item,
                      onTap: () => _openItem(context, item),
                    ),
                  );
                }, childCount: filtered.length),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _openItem(BuildContext context, _ListItem item) {
    if (item.type == _ItemType.group) {
      _openGroup(context, item.id);
    } else {
      _openPersona(context, item.id);
    }
  }

  void _openPersona(BuildContext context, String id) async {
    await context.read<AppState>().openChatWithPersona(id);
    if (!context.mounted) return;
    Navigator.push(context, FastRoute(builder: (_) => const ChatPage()));
  }

  void _openGroup(BuildContext context, String id) async {
    await context.read<AppState>().openChatWithGroup(id);
    if (!context.mounted) return;
    Navigator.push(context, FastRoute(builder: (_) => const ChatPage()));
  }

  void _createGroup(BuildContext context) {
    if (context.read<AppState>().personas.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少需要 2 个角色才能创建群聊')));
      return;
    }
    Navigator.push(
      context,
      FastRoute(builder: (_) => const _CreateGroupPage()),
    );
  }

  void _openMessageHit(BuildContext context, _MessageSearchHit hit) async {
    context.read<AppState>().openSession(hit.session.id);
    if (!context.mounted) return;
    Navigator.push(context, FastRoute(builder: (_) => const ChatPage()));
  }

  List<_MessageSearchHit> _searchMessages(AppState state, String query) {
    final hits = <_MessageSearchHit>[];
    for (final session in state.sessions) {
      for (final message in session.messages.reversed) {
        if (message.role == 'tool' || message.content.trim().isEmpty) continue;
        if (!message.content.toLowerCase().contains(query)) continue;
        hits.add(_MessageSearchHit(session: session, message: message));
        if (hits.length >= 60) return hits;
      }
    }
    return hits;
  }
}

enum _ItemType { group, persona }

class _ListItem {
  final _ItemType type;
  final String id;
  final String name;
  final String avatarPath;
  final Persona? persona;
  final GroupChat? group;
  final ChatSession? session;
  final DateTime? lastTime;

  _ListItem({
    required this.type,
    required this.id,
    required this.name,
    required this.avatarPath,
    this.persona,
    this.group,
    this.session,
    this.lastTime,
  });
}

class _MessageSearchHit {
  final ChatSession session;
  final ChatMessage message;

  const _MessageSearchHit({required this.session, required this.message});
}

class _SearchSectionTitle extends StatelessWidget {
  final String title;

  const _SearchSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          color: scheme.outline,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageSearchTile extends StatelessWidget {
  final _MessageSearchHit hit;
  final VoidCallback onTap;

  const _MessageSearchTile({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final group = hit.session.isGroup ? state.groupOf(hit.session) : null;
    final persona = hit.session.isGroup ? null : state.personaOf(hit.session);
    final title = group?.name ?? persona?.name ?? hit.session.title;
    final sender = hit.message.role == 'user'
        ? '我'
        : (state.personaById(hit.message.speakerId)?.name ?? '对方');
    final avatar = group != null
        ? _GroupAvatar(group: group, size: 46)
        : persona != null
        ? PersonaAvatar(persona: persona, radius: 23)
        : CircleAvatar(
            radius: 23,
            backgroundColor: scheme.surfaceContainerHigh,
            child: Icon(Icons.chat_bubble_outline, color: scheme.outline),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _formatSearchDate(hit.message.timestamp),
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    _highlightSearchText(
                      '$sender：${hit.message.content.replaceAll('\n', ' ')}',
                      context,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
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

String _formatSearchDate(DateTime time) {
  final now = DateTime.now();
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  return '${time.month}月${time.day}日';
}

TextSpan _highlightSearchText(String text, BuildContext context) {
  final query =
      (context.findAncestorStateOfType<_HomePageState>()?._query ?? '').trim();
  if (query.isEmpty) return TextSpan(text: text);
  final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
  final spans = <TextSpan>[];
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > start)
      spans.add(TextSpan(text: text.substring(start, match.start)));
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    start = match.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return TextSpan(children: spans);
}

/// 搜索框
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 15, color: scheme.onSurface),
      decoration: InputDecoration(
        hintText: '搜索好友、群聊',
        hintStyle: TextStyle(color: scheme.outline, fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: scheme.outline),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// 统一列表项
class _UnifiedTile extends StatelessWidget {
  final _ListItem item;
  final VoidCallback onTap;

  const _UnifiedTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget avatar;
    if (item.type == _ItemType.group && item.group != null) {
      avatar = _GroupAvatar(group: item.group!, size: 48);
    } else if (item.persona != null) {
      avatar = PersonaAvatar(persona: item.persona!, radius: 24);
    } else {
      avatar = CircleAvatar(
        radius: 24,
        backgroundColor: scheme.surfaceContainerHigh,
        child: Icon(Icons.person_outline, color: scheme.outline),
      );
    }

    String subtitle;
    if (item.session != null && item.session!.messages.isNotEmpty) {
      final last = item.session!.messages.last;
      final prefix = last.role == 'user' ? '我: ' : '';
      subtitle = last.stickerId != null
          ? '$prefix[表情包]'
          : '$prefix${last.content.replaceAll('\n', ' ')}';
    } else if (item.type == _ItemType.group && item.group != null) {
      final count = item.group!.personaIds.length + 1;
      subtitle = count > 0 ? '$count 位成员' : '暂无成员';
    } else if (item.persona != null) {
      final p = item.persona!;
      subtitle = p.greeting.isNotEmpty
          ? p.greeting
          : (p.useRawPrompt
                ? '完整提示词模式'
                : (p.personality.isEmpty ? '点击开始对话' : p.personality));
    } else {
      subtitle = '点击开始对话';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              if (item.lastTime != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatTime(item.lastTime!),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final date = DateTime(t.year, t.month, t.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final offset = date.difference(today).inDays;
    if (offset == -1) return '昨天';
    if (offset == 0) return '今天';
    if (offset == 1) return '明天';
    return '${t.month}月${t.day}日';
  }
}

/// 群头像
class _GroupAvatar extends StatelessWidget {
  final GroupChat group;
  final double size;
  const _GroupAvatar({required this.group, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final radius = size / 2;

    if (group.avatarPath.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundImage: FileImage(File(group.avatarPath)),
        onForegroundImageError: (_, __) {},
        child: Icon(
          Icons.group_rounded,
          size: radius,
          color: scheme.onPrimaryContainer,
        ),
      );
    }
    final members = group.personaIds
        .map((id) => state.personaById(id))
        .whereType<Persona>()
        .take(3)
        .toList();
    if (members.isEmpty) {
      return _UserGroupAvatar(
        profile: state.userProfile,
        radius: radius,
        borderColor: scheme.surface,
      );
    }
    return _GroupMemberAvatarGrid(
      size: size,
      members: members,
      profile: state.userProfile,
    );
  }
}

class _UserGroupAvatar extends StatelessWidget {
  final UserProfile profile;
  final double radius;
  final Color borderColor;

  const _UserGroupAvatar({
    required this.profile,
    required this.radius,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = profile.avatarPath;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: path.isNotEmpty && File(path).existsSync()
          ? CircleAvatar(radius: radius, backgroundImage: FileImage(File(path)))
          : CircleAvatar(
              radius: radius,
              backgroundColor: scheme.secondaryContainer,
              child: Text(
                profile.name.isEmpty ? '我' : profile.name.characters.first,
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: radius * 0.72,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

class _PersonaGroupAvatar extends StatelessWidget {
  final Persona persona;
  final double radius;
  final Color borderColor;

  const _PersonaGroupAvatar({
    required this.persona,
    required this.radius,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: PersonaAvatar(persona: persona, radius: radius),
    );
  }
}

class _GroupMemberAvatarGrid extends StatelessWidget {
  final double size;
  final List<Persona> members;
  final UserProfile profile;

  const _GroupMemberAvatarGrid({
    required this.size,
    required this.members,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = (members.length + 1).clamp(1, 4).toInt();
    final radius = size * (total == 3 ? 0.19 : 0.18);
    final centers = total == 3
        ? [
            Offset(size * .5, size * .22),
            Offset(size * .25, size * .72),
            Offset(size * .75, size * .72),
          ]
        : [
            Offset(size * .25, size * .25),
            Offset(size * .75, size * .25),
            Offset(size * .25, size * .75),
            Offset(size * .75, size * .75),
          ];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < total; i++)
            Positioned(
              left: centers[i].dx - radius,
              top: centers[i].dy - radius,
              child: i == 0
                  ? _UserGroupAvatar(
                      profile: profile,
                      radius: radius,
                      borderColor: scheme.surface,
                    )
                  : _PersonaGroupAvatar(
                      persona: members[i - 1],
                      radius: radius,
                      borderColor: scheme.surface,
                    ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '开始你的第一次对话',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '先创建一个角色人格作为你的好友',
            style: TextStyle(fontSize: 14, color: scheme.outline),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('创建角色'),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: scheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '未找到匹配的结果',
            style: TextStyle(fontSize: 14, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 创建群聊页面
class _CreateGroupPage extends StatefulWidget {
  const _CreateGroupPage();

  @override
  State<_CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<_CreateGroupPage> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发起群聊'),
        actions: [
          if (_selected.length >= 2)
            FilledButton(
              onPressed: _create,
              child: Text('创建（${_selected.length}）'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.groups_2_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '创建一个多人聊天室',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '选择至少两位人格，创建后你也会作为群成员加入。聊天时可以长按头像快速 @ 某位人格。',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.78,
                            ),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: _UserGroupAvatar(
                      profile: state.userProfile,
                      radius: 12,
                      borderColor: scheme.surface,
                    ),
                    label: Text('${state.userProfile.name}（我）'),
                  ),
                  ..._selected.map((id) {
                    final p = state.personaById(id);
                    if (p == null) return const SizedBox.shrink();
                    return Chip(
                      avatar: PersonaAvatar(persona: p, radius: 12),
                      label: Text(p.name),
                      onDeleted: () => setState(() => _selected.remove(id)),
                    );
                  }),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '选择人格成员（至少 2 人）',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...state.personas.map((p) {
            final selected = _selected.contains(p.id);
            return CheckboxListTile(
              value: selected,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(p.id);
                } else {
                  _selected.remove(p.id);
                }
              }),
              secondary: PersonaAvatar(persona: p, radius: 22),
              title: Text(p.name),
              subtitle: Text(
                p.useRawPrompt
                    ? '完整提示词模式'
                    : (p.personality.isEmpty ? '未设置性格' : p.personality),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          if (_selected.length < 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                '还需要选择 ${2 - _selected.length} 位人格才能创建群聊',
                style: TextStyle(color: scheme.outline, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  void _create() {
    final state = context.read<AppState>();
    final names = _selected
        .map((id) => state.personaById(id)?.name ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final group = GroupChat(
      id: _uuid.v4(),
      name:
          '${names.take(3).join('、')}${names.length > 3 ? '等${names.length}人群' : '群'}',
      personaIds: _selected.toList(),
    );
    state.addOrUpdateGroupChat(group);
    Navigator.pop(context);
  }
}
