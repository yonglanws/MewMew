import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../utils/large_app_bar_title.dart';
import 'api_config_page.dart';
import 'memory_settings_page.dart';
import 'message_debounce_settings_page.dart';
import 'persona_page.dart';
import 'segmented_send_settings_page.dart';
import 'sticker_management_page.dart';
import 'tools_page.dart';

/// 设置页：按功能分组的列表
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
            title: Text('设置', style: _largeAppBarTitleStyle(context)),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '外观',
              children: [
                _SettingTile(
                  icon: Icons.palette_outlined,
                  iconColor: cs.primary,
                  title: '颜色模式',
                  subtitle: '选择应用的显示主题',
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                      ),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (s) =>
                        context.read<AppState>().setThemeMode(s.first),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '模型与服务',
              children: [
                _SettingTile(
                  icon: Icons.cloud_outlined,
                  iconColor: cs.primary,
                  title: 'API 配置',
                  subtitle: '管理对话模型与接口配置',
                  onTap: () => _push(context, const ApiConfigPage()),
                ),
                _SettingTile(
                  icon: Icons.memory_outlined,
                  iconColor: cs.tertiary,
                  title: '嵌入 API 配置',
                  subtitle: '配置记忆检索使用的嵌入模型',
                  onTap: () => _showEmbeddingApiSheet(context),
                ),
                _SettingTile(
                  icon: Icons.extension_outlined,
                  iconColor: cs.secondary,
                  title: '工具调用',
                  subtitle: '管理可供 AI 使用的工具',
                  onTap: () => _push(context, const ToolsPage()),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '角色与对话',
              children: [
                _SettingTile(
                  icon: Icons.face_outlined,
                  iconColor: cs.tertiary,
                  title: '人格设定',
                  subtitle: '创建和编辑对话人格',
                  onTap: () => _push(context, const PersonaPage()),
                ),
                _SettingTile(
                  icon: Icons.stream_outlined,
                  iconColor: cs.primary,
                  title: '流式输出',
                  subtitle: '控制 AI 回复的实时显示方式',
                  trailing: Switch(
                    value: state.streamOutputEnabled,
                    onChanged: (v) =>
                        context.read<AppState>().setStreamOutputEnabled(v),
                  ),
                ),
                _SettingTile(
                  icon: Icons.splitscreen_outlined,
                  iconColor: cs.secondary,
                  title: '对话分段发送',
                  subtitle: '将较长回复切分为多段发送',
                  onTap: () =>
                      _push(context, const SegmentedSendSettingsPage()),
                ),
                _SettingTile(
                  icon: Icons.emoji_emotions_outlined,
                  iconColor: cs.tertiary,
                  title: '表情包',
                  subtitle: '管理表情包资源与人格偏好',
                  onTap: () => _push(context, const StickerManagementPage()),
                ),
                _SettingTile(
                  icon: Icons.merge_type_outlined,
                  iconColor: cs.secondary,
                  title: '消息防抖动',
                  subtitle: '管理连续消息与打字防抖策略',
                  onTap: () =>
                      _push(context, const MessageDebounceSettingsPage()),
                ),
                _SettingTile(
                  icon: Icons.psychology_outlined,
                  iconColor: cs.tertiary,
                  title: '记忆系统',
                  subtitle: '管理跨会话记忆与自动总结',
                  onTap: () => _push(context, const MemorySettingsPage()),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '数据',
              children: [
                _SettingTile(
                  icon: Icons.delete_sweep_outlined,
                  iconColor: cs.error,
                  title: '清空聊天记录',
                  subtitle: '删除所有会话，此操作不可撤销',
                  onTap: () => _confirmClearSessions(context),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '关于',
              children: [
                const _SettingTile(
                  icon: Icons.pets_outlined,
                  iconColor: Color(0xFF6B66C2),
                  title: 'MewMew AI',
                  subtitle: '角色扮演 Agent 对话平台',
                  trailing: SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  static void _confirmClearSessions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定删除所有会话吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              context.read<AppState>().clearSessions();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已清空所有会话')));
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.push(context, FastRoute(builder: (_) => page));
  }

  static void _showEmbeddingApiSheet(BuildContext context) {
    MemorySettingsPage.showEmbeddingApiSheet(context);
  }
}

TextStyle _largeAppBarTitleStyle(BuildContext context) =>
    largeAppBarTitleStyle(context);

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visuallyDisabled = onTap == null && trailing == null;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      enabled: onTap != null || trailing != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (visuallyDisabled ? cs.outline : iconColor).withAlpha(
            (0.15 * 255).toInt(),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: visuallyDisabled ? cs.outline : iconColor,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: visuallyDisabled ? cs.outline : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: visuallyDisabled ? cs.outline : null),
      ),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
      onTap: onTap,
    );
  }
}
