import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/character_prompt.dart';
import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/settings_section.dart';
import '../widgets/template_placeholder_bar.dart';

/// 提示词注入设置页（设置-提示词-提示词注入）
///
/// 参考酒馆（SillyTavern）的预设与深度注入机制。没有开关，注入内容完全由用户
/// 自定义：实时状态模板、私聊注入、群聊注入留空时使用内置拟人默认文案，
/// 编辑后即注入用户自己的内容；生成风格是完全自由的自定义文本。
class PromptInjectionPage extends StatelessWidget {
  const PromptInjectionPage({super.key});

  /// 实时状态模板的占位符芯片数据（与 CharacterPrompt 保持一致）
  static List<({String token, String label, String description})
  > get _contextPlaceholders => CharacterPrompt.contextPlaceholderList;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final s = state.promptInjectionSettings;
    final style = state.generationStyleSettings;
    final isDepth = s.mode == 'depth';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('提示词注入', style: largeAppBarTitleStyle(context)),
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '实时状态',
              children: [
                SettingsTile(
                  icon: Icons.location_on_outlined,
                  iconColor: cs.tertiary,
                  title: '实时状态模板',
                  subtitle: _slotSubtitle(
                    custom: s.contextPrompt,
                    fallback: CharacterPrompt.defaultContextTemplate,
                  ),
                  onTap: () => _editText(
                    context,
                    title: '实时状态模板',
                    current: s.contextPrompt,
                    fallback: CharacterPrompt.defaultContextTemplate,
                    hint: '点按下方占位符芯片可插入到光标处，注入时替换为真实信息。',
                    placeholders: _contextPlaceholders,
                    onSave: (text) =>
                        _update(context, s.copyWith(contextPrompt: text)),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '生成风格',
              children: [
                SettingsTile(
                  icon: Icons.auto_awesome_outlined,
                  iconColor: cs.secondary,
                  title: '生成风格',
                  subtitle: _slotSubtitle(
                    custom: style.stylePrompt,
                    fallback: '',
                    emptyLabel: '未设置（留空不注入）',
                  ),
                  onTap: () => _editText(
                    context,
                    title: '生成风格',
                    current: style.stylePrompt,
                    fallback: '',
                    hint: '用你自己的话描述回复的文本形态，写什么就注入什么；'
                        '角色卡里也可为单个角色设置专属风格（优先于这里）。',
                    allowRestore: false,
                    saveEmptyAsDefault: false,
                    onSave: (text) {
                      context.read<AppState>().updateGenerationStyleSettings(
                            style.copyWith(stylePrompt: text),
                          );
                    },
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '场景注入',
              children: [
                SettingsTile(
                  icon: Icons.person_outline,
                  iconColor: cs.secondary,
                  title: '私聊注入',
                  subtitle: _slotSubtitle(
                    custom: s.privatePrompt,
                    fallback: CharacterPrompt.defaultPrivateInjection,
                  ),
                  onTap: () => _editText(
                    context,
                    title: '私聊注入文案',
                    current: s.privatePrompt,
                    fallback: CharacterPrompt.defaultPrivateInjection,
                    hint: '描述私聊场景下角色的说话方式与心态，只在 1对1 私聊中注入。',
                    onSave: (text) =>
                        _update(context, s.copyWith(privatePrompt: text)),
                  ),
                ),
                SettingsTile(
                  icon: Icons.group_outlined,
                  iconColor: cs.secondary,
                  title: '群聊注入',
                  subtitle: _slotSubtitle(
                    custom: s.groupPrompt,
                    fallback: CharacterPrompt.defaultGroupInjection,
                  ),
                  onTap: () => _editText(
                    context,
                    title: '群聊注入文案',
                    current: s.groupPrompt,
                    fallback: CharacterPrompt.defaultGroupInjection,
                    hint: '描述群聊场景下角色的说话方式与心态，只在群聊中注入。',
                    onSave: (text) =>
                        _update(context, s.copyWith(groupPrompt: text)),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '模式注入',
              children: [
                SettingsTile(
                  icon: Icons.low_priority_outlined,
                  iconColor: cs.primary,
                  title: '注入方式',
                  subtitle: isDepth ? '聊天记录深处 @Depth' : '系统提示词末尾',
                  onTap: () => _pickMode(context, s),
                ),
                if (isDepth)
                  SettingsTile(
                    icon: Icons.format_list_numbered_outlined,
                    iconColor: cs.primary,
                    title: '注入深度',
                    subtitle: s.depth == 0
                        ? '@Depth 0（最末尾，紧邻最新消息）'
                        : '@Depth ${s.depth}（倒数第 ${s.depth + 1} 条附近）',
                    onTap: () => _pickDepth(context, s),
                  ),
                if (isDepth)
                  SettingsTile(
                    icon: Icons.alternate_email_outlined,
                    iconColor: cs.primary,
                    title: '注入角色',
                    subtitle: _roleLabel(s.role),
                    onTap: () => _pickRole(context, s),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: Text(
                '实时状态与场景注入留空时使用内置的拟人默认文案；点击任意条目即可改写成你自己的内容。'
                '实时状态（时间等易变信息）会自动注入在聊天记录末尾附近、紧邻最新消息，'
                '系统提示词保持逐字稳定，AI 的"当前时间感知"不受影响，同时服务商的提示词缓存不会失效。'
                '生成风格完全由你定义，留空则不注入。模式注入的"聊天记录深处 @Depth"会把注入文本'
                '伪装成一条聊天消息插进上下文，更贴近对话本身；不同服务商对 system 角色的兼容性有差异。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 槽位副标题：显示当前生效内容的第一行
  static String _slotSubtitle({
    required String custom,
    required String fallback,
    String emptyLabel = '默认',
  }) {
    final text = custom.trim().isNotEmpty ? custom.trim() : fallback.trim();
    if (text.isEmpty) return emptyLabel;
    final firstLine = text.split('\n').first;
    return firstLine.length > 30 ? '${firstLine.substring(0, 30)}…' : firstLine;
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'user':
        return 'user（伪装成用户消息）';
      case 'assistant':
        return 'assistant（伪装成角色发言）';
      default:
        return 'system（系统消息，推荐）';
    }
  }

  static void _update(BuildContext context, PromptInjectionSettings next) {
    context.read<AppState>().updatePromptInjectionSettings(next);
  }

  /// 通用内容编辑底部弹层：预填当前生效内容，保存时与默认一致则视为默认（存空）。
  /// [fallback] 为空表示"留空 = 不注入"，此时没有"恢复默认"按钮、只有"清空"。
  /// [placeholders] 非空时在输入框上方展示占位符芯片，点按插入到光标处。
  static void _editText(
    BuildContext context, {
    required String title,
    required String current,
    required String fallback,
    required String hint,
    required ValueChanged<String> onSave,
    bool allowRestore = true,
    bool saveEmptyAsDefault = true,
    List<({String token, String label, String description})>
    placeholders = const [],
  }) {
    final controller = TextEditingController(
      text: current.trim().isNotEmpty ? current : fallback,
    );
    showModalBottomSheet(
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
                Text(title, style: Theme.of(sheetCtx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 12,
                  minLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                if (placeholders.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TemplatePlaceholderBar(
                    placeholders: [
                      for (final p in placeholders)
                        TemplatePlaceholder(p.token, p.label, p.description),
                    ],
                    controller: controller,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (allowRestore)
                      TextButton.icon(
                        onPressed: () => controller.text = fallback,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('恢复默认'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => controller.clear(),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清空'),
                      ),
                    FilledButton(
                      onPressed: () {
                        final text = controller.text.trim();
                        onSave(
                          saveEmptyAsDefault && text == fallback.trim()
                              ? ''
                              : text,
                        );
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _pickMode(BuildContext context, PromptInjectionSettings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注入方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'system',
              groupValue: s.mode,
              title: const Text('系统提示词'),
              subtitle: const Text('附加在系统提示词末尾，兼容性最好'),
              onChanged: (v) {
                if (v != null) {
                  _update(context, s.copyWith(mode: v));
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<String>(
              value: 'depth',
              groupValue: s.mode,
              title: const Text('聊天记录深处 @Depth'),
              subtitle: const Text('伪装成一条聊天消息插入上下文，贴近对话'),
              onChanged: (v) {
                if (v != null) {
                  _update(context, s.copyWith(mode: v));
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
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

  static void _pickDepth(BuildContext context, PromptInjectionSettings s) {
    var current = s.depth;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('注入深度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '@Depth $current',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: current.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                onChanged: (v) => setState(() => current = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                _update(context, s.copyWith(depth: current));
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _pickRole(BuildContext context, PromptInjectionSettings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注入角色'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in const ['system', 'user', 'assistant'])
              RadioListTile<String>(
                value: role,
                groupValue: s.role,
                title: Text(_roleLabel(role)),
                onChanged: (v) {
                  if (v != null) {
                    _update(context, s.copyWith(role: v));
                    Navigator.pop(ctx);
                  }
                },
              ),
          ],
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
}
