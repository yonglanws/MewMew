import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/persona_avatar.dart';

const _uuid = Uuid();

/// 群聊设置页面
class GroupSettingsPage extends StatefulWidget {
  final GroupChat group;
  const GroupSettingsPage({super.key, required this.group});

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.group.name,
  );
  late String _avatarPath = widget.group.avatarPath;
  late final List<String> _personaIds = List<String>.from(
    widget.group.personaIds,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (img == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${dir.path}/avatars');
    await avatarsDir.create(recursive: true);
    final dot = img.path.lastIndexOf('.');
    final ext = dot >= 0 ? img.path.substring(dot) : '.jpg';
    final saved = await File(
      img.path,
    ).copy('${avatarsDir.path}/${_uuid.v4()}$ext');
    if (!mounted) return;
    setState(() => _avatarPath = saved.path);
  }

  void _persist({List<String>? ids}) {
    final name = _name.text.trim();
    final updated = GroupChat(
      id: widget.group.id,
      name: name.isEmpty ? widget.group.name : name,
      avatarPath: _avatarPath,
      personaIds: ids ?? List<String>.from(_personaIds),
    );
    context.read<AppState>().addOrUpdateGroupChat(updated);
  }

  void _removeMember(String personaId) {
    setState(() => _personaIds.remove(personaId));
    _persist(ids: _personaIds);
  }

  Future<void> _addMember() async {
    final state = context.read<AppState>();
    final available = state.personas
        .where((p) => !_personaIds.contains(p.id))
        .toList();
    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可添加的角色了')));
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: available.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = available[i];
              return ListTile(
                leading: PersonaAvatar(persona: p, radius: 20),
                title: Text(p.name),
                subtitle: p.personality.isEmpty
                    ? null
                    : Text(
                        p.personality,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.pop(ctx, p.id),
              );
            },
          ),
        );
      },
    );
    if (selected == null) return;
    setState(() => _personaIds.add(selected));
    _persist(ids: _personaIds);
  }

  void _confirmDissolve() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: Text('确定解散群聊「${widget.group.name}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppState>().deleteGroupChat(widget.group.id);
              Navigator.of(context).pop();
            },
            child: const Text('解散'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final members = _personaIds
        .map((id) => state.personaById(id))
        .whereType<Persona>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('群聊设置'),
        actions: [
          FilledButton.tonal(
            onPressed: () => _persist(),
            child: const Text('保存'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32).copyWith(bottom: 32),
        children: [
          // 头像
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child:
                          _avatarPath.isNotEmpty &&
                              File(_avatarPath).existsSync()
                          ? CircleAvatar(
                              radius: 44,
                              backgroundImage: FileImage(File(_avatarPath)),
                            )
                          : CircleAvatar(
                              radius: 44,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                Icons.group,
                                size: 44,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: cs.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _pickAvatar,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.photo_camera_outlined,
                              size: 16,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _pickAvatar,
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('上传群头像'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 群名称
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '群名称',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.group_outlined),
            ),
          ),
          const SizedBox(height: 24),
          // 成员列表标题
          Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '群成员',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${members.length + 1}',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addMember,
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (members.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '当前成员：${state.userProfile.name}，点击「添加」邀请角色加入',
                  style: TextStyle(color: cs.outline),
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              color: cs.surfaceContainerLow,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: _UserAvatarSmall(
                      path: state.userProfile.avatarPath,
                      name: state.userProfile.name,
                    ),
                    title: Text(state.userProfile.name),
                    subtitle: const Text('我'),
                  ),
                  for (int i = 0; i < members.length; i++)
                    ListTile(
                      leading: PersonaAvatar(persona: members[i], radius: 20),
                      title: Text(members[i].name),
                      subtitle: members[i].personality.isEmpty
                          ? null
                          : Text(
                              members[i].personality,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: IconButton(
                        tooltip: '移除成员',
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: cs.error,
                          size: 22,
                        ),
                        onPressed: () => _removeMember(members[i].id),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          // 解散群聊
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
            ),
            onPressed: _confirmDissolve,
            icon: const Icon(Icons.delete_outline),
            label: const Text('解散群聊'),
          ),
        ],
      ),
    );
  }
}

class _UserAvatarSmall extends StatelessWidget {
  final String path;
  final String name;

  const _UserAvatarSmall({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (path.isNotEmpty && File(path).existsSync()) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: scheme.secondaryContainer,
        backgroundImage: FileImage(File(path)),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        name.isEmpty ? '我' : name.characters.first,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
