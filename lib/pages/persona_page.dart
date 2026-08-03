import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../widgets/persona_avatar.dart';

const _uuid = Uuid();

/// 人格管理页面
class PersonaPage extends StatelessWidget {
  const PersonaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('人格设定')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('创建角色'),
      ),
      body: state.personas.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              cacheExtent: 500,
              itemCount: state.personas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = state.personas[i];
                final isActive = state.activePersonaId == p.id;
                return RepaintBoundary(
                  child: _PersonaCard(
                    persona: p,
                    isActive: isActive,
                    onTap: () => _openEditor(context, persona: p),
                    onEdit: () => _openEditor(context, persona: p),
                    onDelete: () => _confirmDelete(context, p),
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, Persona p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定删除「${p.name}」吗？相关记忆和会话记录也将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () {
              context.read<AppState>().deletePersona(p.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, {Persona? persona}) {
    Navigator.push(
      context,
      FastRoute(builder: (_) => PersonaEditorPage(persona: persona)),
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
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.face_retouching_natural_rounded,
                size: 44,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '还没有角色',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '创建一个角色，设定性格与风格\n即可开始专属对话',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色卡片
class _PersonaCard extends StatelessWidget {
  final Persona persona;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PersonaCard({
    required this.persona,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = persona;
    final preview = p.useRawPrompt
        ? (p.rawPrompt.isEmpty ? '（未设置提示词）' : p.rawPrompt)
        : (p.personality.isEmpty ? '（未设置性格特征）' : p.personality);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头像（激活态加角标）
              Stack(
                children: [
                  PersonaAvatar(persona: p, radius: 28),
                  if (isActive)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isActive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '使用中',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.useRawPrompt
                                ? cs.tertiaryContainer
                                : cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.useRawPrompt ? '完整提示词' : '结构化',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: p.useRawPrompt
                                  ? cs.onTertiaryContainer
                                  : cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    if (p.greeting.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.format_quote_rounded,
                              size: 12,
                              color: cs.outline,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                p.greeting,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // 右侧菜单按钮（独立点击，不触发卡片点击）
              PopupMenuButton<String>(
                iconSize: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
                onSelected: (v) {
                  if (v == 'edit') {
                    onEdit();
                  } else if (v == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 人格编辑页面
class PersonaEditorPage extends StatefulWidget {
  final Persona? persona;
  const PersonaEditorPage({super.key, this.persona});

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late bool _useRawPrompt = widget.persona?.useRawPrompt ?? false;
  late String _avatarPath = widget.persona?.avatarPath ?? '';
  late final _name = TextEditingController(text: widget.persona?.name ?? '');
  late final _emoji = TextEditingController(
    text: widget.persona?.emoji ?? '🤖',
  );
  late final _personality = TextEditingController(
    text: widget.persona?.personality ?? '',
  );
  late final _languageStyle = TextEditingController(
    text: widget.persona?.languageStyle ?? '',
  );
  late final _backstory = TextEditingController(
    text: widget.persona?.backstory ?? '',
  );
  late final _greeting = TextEditingController(
    text: widget.persona?.greeting ?? '',
  );
  late final _rawPrompt = TextEditingController(
    text: widget.persona?.rawPrompt ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _personality.dispose();
    _languageStyle.dispose();
    _backstory.dispose();
    _greeting.dispose();
    _rawPrompt.dispose();
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

  void _removeAvatar() => setState(() => _avatarPath = '');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.persona == null ? '创建角色' : '编辑角色')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('保存'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: [
            // —— 头像区 ——
            _SectionCard(
              icon: Icons.account_circle_outlined,
              title: '头像与名称',
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        _avatarPath.isNotEmpty && File(_avatarPath).existsSync()
                            ? CircleAvatar(
                                radius: 40,
                                backgroundImage: FileImage(File(_avatarPath)),
                              )
                            : CircleAvatar(
                                radius: 40,
                                backgroundColor: cs.primaryContainer,
                                child: Text(
                                  _emoji.text.trim().isEmpty
                                      ? '🤖'
                                      : _emoji.text.trim(),
                                  style: const TextStyle(fontSize: 36),
                                ),
                              ),
                        Positioned(
                          right: -2,
                          bottom: -2,
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
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _pickAvatar,
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: const Text('上传图片'),
                      ),
                      if (_avatarPath.isNotEmpty)
                        TextButton.icon(
                          onPressed: _removeAvatar,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('移除'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '角色名称 *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入角色名称' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // —— 设定模式 ——
            _SectionCard(
              icon: Icons.tune_rounded,
              title: '设定模式',
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined),
                        label: Text('结构化设定'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.notes_outlined),
                        label: Text('完整提示词'),
                      ),
                    ],
                    selected: {_useRawPrompt},
                    onSelectionChanged: (s) =>
                        setState(() => _useRawPrompt = s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _useRawPrompt
                        ? '直接编写发送给模型的完整系统提示词，拥有最大自由度。'
                        : '分字段填写角色设定，应用会自动组合成系统提示词。',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // —— 角色设定 ——
            _SectionCard(
              icon: _useRawPrompt
                  ? Icons.description_outlined
                  : Icons.psychology_outlined,
              title: _useRawPrompt ? '系统提示词' : '角色设定',
              child: _useRawPrompt
                  ? _buildRawPromptFields()
                  : _buildStructuredFields(),
            ),
            const SizedBox(height: 12),

            // —— 开场白 ——
            _SectionCard(
              icon: Icons.waving_hand_outlined,
              title: '开场白',
              child: TextFormField(
                controller: _greeting,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '新对话开始时角色说的第一句话',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _personality,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '性格特征',
            hintText: '如：温柔体贴、幽默风趣、高冷傲娇……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _languageStyle,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '语言风格',
            hintText: '如：古风文言、网络热梗、简洁专业……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _backstory,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '背景故事',
            hintText: '角色的身世、经历、世界观设定……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildRawPromptFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _rawPrompt,
          maxLines: 14,
          minLines: 8,
          decoration: const InputDecoration(
            labelText: '系统提示词 *',
            hintText: '例如：\n你是「XX」，一位……\n\n## 角色设定\n……\n\n## 行为准则\n……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          validator: (v) {
            if (!_useRawPrompt) return null;
            return (v == null || v.trim().isEmpty) ? '请输入系统提示词' : null;
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _importFromStructured,
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: const Text('从结构化设定生成'),
          ),
        ),
      ],
    );
  }

  void _importFromStructured() {
    final tmp = Persona(
      id: 'tmp',
      name: _name.text.trim().isEmpty ? '未命名角色' : _name.text.trim(),
      personality: _personality.text.trim(),
      languageStyle: _languageStyle.text.trim(),
      backstory: _backstory.text.trim(),
    );
    _rawPrompt.text = tmp.buildSystemPrompt();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final persona = Persona(
      id: widget.persona?.id ?? _uuid.v4(),
      name: _name.text.trim(),
      emoji: _emoji.text.trim().isEmpty ? '🤖' : _emoji.text.trim(),
      avatarPath: _avatarPath,
      personality: _personality.text.trim(),
      languageStyle: _languageStyle.text.trim(),
      backstory: _backstory.text.trim(),
      greeting: _greeting.text.trim(),
      useRawPrompt: _useRawPrompt,
      rawPrompt: _rawPrompt.text.trim(),
    );
    context.read<AppState>().addOrUpdatePersona(persona);
    Navigator.pop(context);
  }
}

/// 分区卡片容器
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
