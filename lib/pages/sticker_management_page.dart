import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/fast_route.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/persona_avatar.dart';

class StickerManagementPage extends StatelessWidget {
  const StickerManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('表情包管理', style: largeAppBarTitleStyle(context)),
          ),
          SliverToBoxAdapter(
            child: _StickerOverviewCard(
              groupCount: state.stickerGroups.length,
              folderCount: state.stickerFolders.length,
              stickerCount: state.stickers.length,
            ),
          ),
          SliverToBoxAdapter(
            child: _StickerSection(
              title: '资源管理',
              children: [
                _StickerEntry(
                  icon: Icons.collections_bookmark_outlined,
                  iconColor: cs.primary,
                  title: '表情包组',
                  subtitle: Text(
                    '${state.stickerGroups.length} 个组 · ${state.stickerFolders.length} 个情绪文件夹 · ${state.stickers.length} 个表情包',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    FastRoute(builder: (_) => const StickerGroupListPage()),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _StickerSection(
              title: '使用关系',
              children: [
                _StickerEntry(
                  icon: Icons.people_outline,
                  iconColor: cs.tertiary,
                  title: '人格绑定',
                  subtitle: Text(
                    '${state.personas.length} 个人格 · ${state.personaStickerBindings.length} 条绑定关系',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    FastRoute(
                      builder: (_) => const PersonaStickerBindingPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class _StickerOverviewCard extends StatelessWidget {
  final int groupCount;
  final int folderCount;
  final int stickerCount;

  const _StickerOverviewCard({
    required this.groupCount,
    required this.folderCount,
    required this.stickerCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '表情包概览',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '按组和情绪文件夹整理资源，聊天时会按人格绑定结果使用。',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StickerStat(
                icon: Icons.collections_bookmark_outlined,
                label: '表情包组',
                value: groupCount,
              ),
              _StickerStat(
                icon: Icons.folder_outlined,
                label: '情绪文件夹',
                value: folderCount,
              ),
              _StickerStat(
                icon: Icons.emoji_emotions_outlined,
                label: '表情包',
                value: stickerCount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StickerStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _StickerStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 82, maxWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _StickerSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    ),
  );
}

class _StickerEntry extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;
  const _StickerEntry({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading:
        leading ??
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withAlpha((0.15 * 255).toInt()),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: subtitle,
    trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

class _StickerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StickerEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}

class _StickerThumbnail extends StatelessWidget {
  final String? filePath;
  final IconData fallbackIcon;

  const _StickerThumbnail({required this.filePath, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final path = filePath?.trim() ?? '';
    final fallback = Icon(
      fallbackIcon,
      color: Theme.of(context).colorScheme.tertiary,
      size: 22,
    );
    if (path.isEmpty) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 160,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _StickerThumbnailBox extends StatelessWidget {
  final String? filePath;
  final IconData fallbackIcon;

  const _StickerThumbnailBox({
    required this.filePath,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: _StickerThumbnail(filePath: filePath, fallbackIcon: fallbackIcon),
    ),
  );
}

class StickerGroupListPage extends StatelessWidget {
  const StickerGroupListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('表情包组')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => StickerGroupListPage._createGroup(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建表情包组'),
      ),
      body: state.stickerGroups.isEmpty
          ? const _EmptyGroups()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: Column(
                    children: [
                      for (final group in state.stickerGroups)
                        Builder(
                          builder: (context) {
                            final thumbnailPath = state
                                .stickerFoldersForGroup(group.id)
                                .expand(
                                  (folder) =>
                                      state.stickersForFolder(folder.id),
                                )
                                .map((sticker) => sticker.filePath.trim())
                                .where((path) => path.isNotEmpty)
                                .firstOrNull;
                            return _StickerEntry(
                              icon: Icons.collections_bookmark_outlined,
                              iconColor: Theme.of(context).colorScheme.primary,
                              leading: _StickerThumbnailBox(
                                filePath: thumbnailPath,
                                fallbackIcon:
                                    Icons.collections_bookmark_outlined,
                              ),
                              title: group.name,
                              subtitle: const Text('表情包组'),
                              onTap: () => Navigator.push(
                                context,
                                FastRoute(
                                  builder: (_) =>
                                      StickerGroupPage(group: group),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static Future<void> _createGroup(BuildContext context) async {
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建表情包组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '表情包组名称'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      await context.read<AppState>().addStickerGroup(name: name.text);
    }
    name.dispose();
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => _StickerEmptyState(
    icon: Icons.emoji_emotions_outlined,
    title: '还没有表情包组',
    description: '创建一个表情包组，再按情绪文件夹整理图片。',
    actionLabel: null,
    onAction: null,
  );
}

class StickerGroupPage extends StatelessWidget {
  final StickerGroup group;
  const StickerGroupPage({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentGroup =
        state.stickerGroups.where((item) => item.id == group.id).firstOrNull ??
        group;
    final folders = state.stickerFoldersForGroup(currentGroup.id);
    return Scaffold(
      appBar: AppBar(title: Text(currentGroup.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showActions(context, currentGroup),
        icon: const Icon(Icons.tune_rounded),
        label: const Text('管理表情包组'),
      ),
      body: folders.isEmpty
          ? const _EmptyFolders()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
              children: [
                Card(
                  child: Column(
                    children: [
                      for (final folder in folders)
                        Builder(
                          builder: (context) {
                            final count = state
                                .stickersForFolder(folder.id)
                                .length;
                            final thumbnailPath = state
                                .stickersForFolder(folder.id)
                                .map((sticker) => sticker.filePath.trim())
                                .where((path) => path.isNotEmpty)
                                .firstOrNull;
                            return _StickerEntry(
                              icon: Icons.folder_outlined,
                              iconColor: Theme.of(context).colorScheme.tertiary,
                              leading: _StickerThumbnailBox(
                                filePath: thumbnailPath,
                                fallbackIcon: Icons.folder_outlined,
                              ),
                              title: folder.name,
                              subtitle: Text(
                                folder.description.isEmpty
                                    ? '$count 个表情包'
                                    : '${folder.description} · $count 个表情包',
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: '更多操作',
                                onSelected: (value) async {
                                  if (value == 'delete') {
                                    await state.removeStickerFolder(folder.id);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除文件夹'),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.push(
                                context,
                                FastRoute(
                                  builder: (_) =>
                                      StickerFolderPage(folder: folder),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static void _showActions(BuildContext context, StickerGroup group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '表情包组操作',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑组名'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editGroup(context, group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建文件夹'),
              onTap: () {
                Navigator.pop(sheetContext);
                _createFolder(context, group);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _editGroup(
    BuildContext context,
    StickerGroup group,
  ) async {
    final updatedName = await showDialog<String>(
      context: context,
      builder: (_) => _EditStickerGroupDialog(initialName: group.name),
    );
    if (updatedName != null && context.mounted) {
      await context.read<AppState>().updateStickerGroup(
        StickerGroup(
          id: group.id,
          name: updatedName,
          createdAt: group.createdAt,
        ),
      );
    }
  }

  static Future<void> _createFolder(
    BuildContext context,
    StickerGroup group,
  ) async {
    final draft = await showDialog<_StickerFolderDraft>(
      context: context,
      builder: (_) => const _CreateStickerFolderDialog(),
    );
    if (draft != null && context.mounted) {
      await context.read<AppState>().addStickerFolder(
        groupId: group.id,
        name: draft.name,
        description: draft.description,
      );
    }
  }
}

class _EditStickerGroupDialog extends StatefulWidget {
  const _EditStickerGroupDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditStickerGroupDialog> createState() =>
      _EditStickerGroupDialogState();
}

class _EditStickerGroupDialogState extends State<_EditStickerGroupDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑表情包组'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: '表情包组名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final updatedName = _nameController.text.trim();
            if (updatedName.isNotEmpty) {
              Navigator.pop(context, updatedName);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _StickerFolderDraft {
  const _StickerFolderDraft({required this.name, required this.description});

  final String name;
  final String description;
}

class _CreateStickerFolderDialog extends StatefulWidget {
  const _CreateStickerFolderDialog();

  @override
  State<_CreateStickerFolderDialog> createState() =>
      _CreateStickerFolderDialogState();
}

class _CreateStickerFolderDialogState
    extends State<_CreateStickerFolderDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建表情文件夹'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: '文件夹名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: '使用场景描述'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _StickerFolderDraft(
              name: _nameController.text,
              description: _descriptionController.text,
            ),
          ),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class PersonaStickerBindingPage extends StatelessWidget {
  const PersonaStickerBindingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('人格绑定')),
      body: Column(
        children: [
          _InfoCard(
            icon: Icons.info_outline_rounded,
            title: '绑定说明',
            text: '每个人格可以选择多个表情包组。绑定后，该人格在聊天中会合并使用这些组内的表情包。',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Card(
                  child: Column(
                    children: [
                      for (final persona in state.personas)
                        Builder(
                          builder: (context) {
                            final groupIds = state.personaStickerBindings
                                .where(
                                  (binding) => binding.personaId == persona.id,
                                )
                                .map((binding) => binding.groupId)
                                .toSet();
                            final groups = state.stickerGroups
                                .where((group) => groupIds.contains(group.id))
                                .toList();
                            final subtitle = groups.isEmpty
                                ? Text(
                                    '未绑定表情包组',
                                    style: TextStyle(color: cs.outline),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${groups.length} 个表情包组'),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final group in groups)
                                            Chip(
                                              label: Text(group.name),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                        ],
                                      ),
                                    ],
                                  );
                            return _StickerEntry(
                              icon: Icons.person_outline,
                              iconColor: cs.tertiary,
                              leading: PersonaAvatar(
                                persona: persona,
                                radius: 20,
                              ),
                              title: persona.name,
                              subtitle: subtitle,
                              onTap: () => _showGroups(context, persona.id),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _showGroups(BuildContext context, String personaId) {
    final state = context.read<AppState>();
    final selected = state.personaStickerBindings
        .where((binding) => binding.personaId == personaId)
        .map((binding) => binding.groupId)
        .toSet();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text('选择表情包组（已选 ${selected.length} 个）'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final group in state.stickerGroups)
                  CheckboxListTile(
                    value: selected.contains(group.id),
                    title: Text(group.name),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selected.add(group.id);
                      } else {
                        selected.remove(group.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await state.setPersonaStickerGroups(
                  personaId: personaId,
                  groupIds: selected,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders();

  @override
  Widget build(BuildContext context) => _StickerEmptyState(
    icon: Icons.folder_outlined,
    title: '这个表情包组还没有文件夹',
    description: '创建情绪文件夹，为表情包补充清晰的使用场景。',
    actionLabel: null,
    onAction: null,
  );
}

class StickerFolderPage extends StatelessWidget {
  final StickerFolder folder;
  const StickerFolderPage({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stickers = state.stickersForFolder(folder.id);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importSticker(context),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('导入表情包'),
      ),
      body: stickers.isEmpty
          ? const _EmptyStickers()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: stickers.length,
              itemBuilder: (_, index) {
                final sticker = stickers[index];
                return Material(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onLongPress: () => _deleteSticker(context, sticker),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(sticker.filePath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 360,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: PopupMenuButton<String>(
                          tooltip: '更多操作',
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deleteSticker(context, sticker);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除表情包'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _importSticker(BuildContext context) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !context.mounted) return;
    final state = context.read<AppState>();
    final baseName = image.name.split('.').first.replaceAll('_', ' ').trim();
    var name = baseName.isEmpty ? '表情包' : baseName;
    var suffix = 2;
    while (state.stickers.any(
      (sticker) => sticker.folderId == folder.id && sticker.name == name,
    )) {
      name = '$baseName $suffix';
      suffix++;
    }
    await state.addSticker(
      folderId: folder.id,
      name: name,
      description: folder.description,
      sourcePath: image.path,
    );
  }

  Future<void> _deleteSticker(BuildContext context, StickerItem sticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除表情包'),
        content: const Text('确定删除这张表情包吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppState>().removeSticker(sticker.id);
    }
  }
}

class _EmptyStickers extends StatelessWidget {
  const _EmptyStickers();

  @override
  Widget build(BuildContext context) => _StickerEmptyState(
    icon: Icons.add_photo_alternate_outlined,
    title: '还没有表情包',
    description: '导入图片后会显示在这里。',
    actionLabel: null,
    onAction: null,
  );
}
