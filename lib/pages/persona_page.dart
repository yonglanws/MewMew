import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/character_prompt.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/persona_avatar.dart';
import '../widgets/template_placeholder_bar.dart';

const _uuid = Uuid();

/// 角色卡管理页面（升级版单列卡片）
class PersonaPage extends StatelessWidget {
  const PersonaPage({super.key});

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
            title: Text('角色卡', style: largeAppBarTitleStyle(context)),
          ),
          if (state.personas.isEmpty)
            SliverToBoxAdapter(child: const _EmptyState())
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '${state.personas.length} 个角色卡 · 点击卡片编辑设定',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.separated(
                itemCount: state.personas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final p = state.personas[i];
                  final isActive = state.activePersonaId == p.id;
                  return RepaintBoundary(
                    child: _PersonaCard(
                      persona: p,
                      isActive: isActive,
                      onTap: () => _openEditor(context, persona: p),
                      onDelete: () => _confirmDelete(context, p),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('创建角色卡'),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Persona p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除角色卡'),
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

/// 空状态：还没有角色卡
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Center(
        child: Column(
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
              '还没有角色卡',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '创建一张角色卡，设定外貌、性格与对话风格\n即可开始拟真对话',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色卡卡片：头像 + 名称徽章 + 两行设定预览 + 编辑/删除菜单
class _PersonaCard extends StatelessWidget {
  final Persona persona;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PersonaCard({
    required this.persona,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  String get _preview {
    final p = persona;
    if (p.useRawPrompt) {
      return p.rawPrompt.trim().isEmpty ? '（未设置提示词）' : p.rawPrompt;
    }
    if (p.personality.trim().isNotEmpty) return p.personality;
    if (p.backstory.trim().isNotEmpty) return p.backstory;
    return '（未设置性格特质）';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = persona;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? cs.primary.withValues(alpha: 0.55)
                  : cs.outlineVariant.withValues(alpha: 0.4),
              width: isActive ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头像（激活态加角标）
              Stack(
                children: [
                  PersonaAvatar(persona: p, radius: 26),
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
                      _preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
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
                    onTap();
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

/// 角色卡编辑页面
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
  late final _appearance = TextEditingController(
    text: widget.persona?.appearance ?? '',
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
  late final _promptTemplate = TextEditingController(
    text: widget.persona?.promptTemplate ?? '',
  );
  late final _stylePrompt = TextEditingController(
    text: widget.persona?.stylePrompt ?? '',
  );
  late final _rawPrompt = TextEditingController(
    text: widget.persona?.rawPrompt ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _appearance.dispose();
    _personality.dispose();
    _languageStyle.dispose();
    _backstory.dispose();
    _promptTemplate.dispose();
    _stylePrompt.dispose();
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
      appBar: AppBar(
        title: Text(widget.persona == null ? '创建角色卡' : '编辑角色卡'),
        actions: [
          // 完整提示词模式下内容即最终提示词，预览无意义
          if (!_useRawPrompt)
            TextButton.icon(
              onPressed: _previewPrompt,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('预览提示词'),
            ),
          const SizedBox(width: 4),
        ],
      ),
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
                        : '分字段填写角色设定，应用会按拟人模板自动拼接成系统提示词：角色会知道自己在社交软件上聊天、知道当前时间和聊天对象。',
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
          ],
        ),
      ),
    );
  }

  /// 组装当前表单的角色卡（用于预览/生成/保存）
  Persona _buildPersonaFromForm({
    required String id,
    bool? useRawPromptOverride,
  }) {
    return Persona(
      id: id,
      name: _name.text.trim().isEmpty ? '未命名角色' : _name.text.trim(),
      emoji: _emoji.text.trim().isEmpty ? '🤖' : _emoji.text.trim(),
      avatarPath: _avatarPath,
      appearance: _appearance.text.trim(),
      personality: _personality.text.trim(),
      languageStyle: _languageStyle.text.trim(),
      backstory: _backstory.text.trim(),
      promptTemplate: _promptTemplate.text.trim(),
      stylePrompt: _stylePrompt.text.trim(),
      useRawPrompt: useRawPromptOverride ?? _useRawPrompt,
      rawPrompt: _rawPrompt.text.trim(),
    );
  }

  void _previewPrompt() {
    final persona = _buildPersonaFromForm(id: 'preview');
    final prompt = CharacterPrompt.buildCharacterPrompt(persona);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拟人提示词预览'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              prompt,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredFields() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _appearance,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '外貌特征',
            hintText: '如：身高体重、发色发长、穿着习惯、瞳色……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _personality,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '性格特质',
            hintText: '如：慵懒/活泼、温和/傲娇、情绪驱动/理性驱动、有没有耐心……',
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
            hintText: '角色的身世、经历、职业、兴趣爱好、社会关系……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _languageStyle,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '对话风格',
            hintText: '如：口头禅、口癖（句尾加"喵~"）、网络热梗、古风文言、爱用空格代替逗号……',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        Divider(height: 24, color: cs.outlineVariant.withValues(alpha: 0.5)),
        // —— 高级自定义：模板与专属生成风格（行内入口，弹层编辑） ——
        _EditorRow(
          icon: Icons.edit_note_outlined,
          label: '提示词模板',
          value: _promptTemplate.text.trim().isEmpty ? '默认' : '自定义',
          onTap: _editTemplateSheet,
        ),
        _EditorRow(
          icon: Icons.auto_awesome_outlined,
          label: '生成风格',
          value: _stylePrompt.text.trim().isEmpty ? '跟随全局' : '自定义',
          onTap: _editStyleSheet,
        ),
      ],
    );
  }

  /// 角色专属提示词模板弹层：留空用应用默认拟人模板；每个角色可各自定制
  Future<void> _editTemplateSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('提示词模板', style: Theme.of(sheetCtx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '只对本角色生效。点按下方占位符芯片可插入到光标处；留空使用应用默认拟人模板。',
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptTemplate,
                  maxLines: 12,
                  minLines: 6,
                  decoration: const InputDecoration(
                    labelText: '模板内容（留空 = 默认）',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                TemplatePlaceholderBar(
                  placeholders: [
                    for (final p in CharacterPrompt
                        .characterTemplatePlaceholderList)
                      TemplatePlaceholder(p.token, p.label, p.description),
                  ],
                  controller: _promptTemplate,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => _promptTemplate.text =
                          CharacterPrompt.defaultCharacterTemplate,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('载入默认模板'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 角色专属生成风格弹层：留空跟随全局生成风格配置
  Future<void> _editStyleSheet() async {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: _stylePrompt.text);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('生成风格', style: Theme.of(sheetCtx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '只对本角色生效。用你自己的话描述回复的文本形态，留空跟随"设置-提示词-提示词注入"里的生成风格。',
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 4,
                  decoration: const InputDecoration(
                    labelText: '专属生成风格（留空 = 跟随全局）',
                    hintText: '例如：回复要非常简短，多用语气词，允许只回一个问号',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        _stylePrompt.clear();
                        controller.clear();
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('跟随全局'),
                    ),
                    FilledButton(
                      onPressed: () {
                        _stylePrompt.text = controller.text.trim();
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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
    final tmp = _buildPersonaFromForm(id: 'tmp', useRawPromptOverride: false);
    _rawPrompt.text = CharacterPrompt.buildCharacterPrompt(tmp);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final persona = _buildPersonaFromForm(
      id: widget.persona?.id ?? _uuid.v4(),
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

/// 编辑页卡片内的行内入口：图标 + 标签 + 当前值 + 箭头
class _EditorRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _EditorRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: value == '默认' || value == '跟随全局'
                    ? cs.onSurfaceVariant
                    : cs.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
