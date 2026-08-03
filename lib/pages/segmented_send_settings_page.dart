import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';

/// 对话分段发送设置独立页面
///
/// 视觉规范与 MemorySettingsPage / SettingsPage 一致：使用 `_Section` +
/// `_SettingTile`（40×40 圆角色块图标 + 标题 + 副标题 + trailing）。
class SegmentedSendSettingsPage extends StatelessWidget {
  const SegmentedSendSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.segmentedSendSettings;
    final cs = Theme.of(context).colorScheme;
    final e = s.enabled;
    final streamEnabled = state.streamOutputEnabled;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('对话分段发送'),
          ),
          // ---- 基础设置 ----
          SliverToBoxAdapter(
            child: streamEnabled
                ? Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: cs.error,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '当前已开启流式输出。分段发送与流式输出互斥，关闭流式输出后才能启用分段发送。',
                            style: TextStyle(
                              color: cs.onErrorContainer,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: '基础设置',
              children: [
                _SettingTile(
                  icon: Icons.splitscreen_outlined,
                  iconColor: cs.primary,
                  title: '启用分段发送',
                  subtitle: e ? '已开启：流式结束后将长回复按标点智能拆为多段' : '已关闭：AI 整段回复作为一条消息',
                  trailing: Switch(
                    value: e,
                    onChanged: streamEnabled
                        ? null
                        : (v) => _update(context, s.copyWith(enabled: v)),
                  ),
                ),
                _SettingTile(
                  icon: Icons.short_text,
                  iconColor: cs.tertiary,
                  title: '最短触发字数',
                  subtitle: '回复短于 ${s.minTriggerLength} 字时保持单段，不拆分',
                  trailing: _ValueLabel('${s.minTriggerLength} 字', e, cs),
                  onTap: e && !streamEnabled
                      ? () => _showIntDialog(
                          context,
                          title: '最短触发字数',
                          value: s.minTriggerLength,
                          min: 5,
                          max: 200,
                          unit: '字',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(minTriggerLength: v)),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.format_align_left,
                  iconColor: cs.tertiary,
                  title: '最长处理字数',
                  subtitle: '回复超过 ${s.maxProcessLength} 字时截断后再分段（0 = 不限制）',
                  trailing: _ValueLabel(
                    s.maxProcessLength == 0 ? '不限制' : '${s.maxProcessLength} 字',
                    e,
                    cs,
                  ),
                  onTap: e && !streamEnabled
                      ? () => _showIntDialog(
                          context,
                          title: '最长处理字数（0=不限制）',
                          value: s.maxProcessLength,
                          min: 0,
                          max: 500,
                          unit: '字',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(maxProcessLength: v)),
                        )
                      : null,
                ),
              ],
            ),
          ),
          // ---- 均分算法 ----
          SliverToBoxAdapter(
            child: _Section(
              title: '均分算法',
              children: [
                _SettingTile(
                  icon: Icons.layers_outlined,
                  iconColor: cs.secondary,
                  title: '最大段数',
                  subtitle: '最多拆分为 ${s.maxSegments} 段',
                  trailing: _ValueLabel('${s.maxSegments} 段', e, cs),
                  onTap: e && !streamEnabled
                      ? () => _showIntDialog(
                          context,
                          title: '最大段数',
                          value: s.maxSegments,
                          min: 2,
                          max: 20,
                          unit: '段',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(maxSegments: v)),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.vertical_align_bottom_outlined,
                  iconColor: cs.secondary,
                  title: '最小段长',
                  subtitle: '均分模式避免切出短于 ${s.minSegmentLength} 字的碎片',
                  trailing: _ValueLabel('${s.minSegmentLength} 字', e, cs),
                  onTap: e && !streamEnabled
                      ? () => _showIntDialog(
                          context,
                          title: '最小段长',
                          value: s.minSegmentLength,
                          min: 5,
                          max: 300,
                          unit: '字',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(minSegmentLength: v)),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.trending_down,
                  iconColor: cs.secondary,
                  title: '均分下限比',
                  subtitle:
                      '低于理想长度 ${(s.balanceLowerRatio * 100).round()}% 时不切分（合并入相邻段）',
                  trailing: _ValueLabel(
                    '${(s.balanceLowerRatio * 100).round()}%',
                    e,
                    cs,
                  ),
                  onTap: e && !streamEnabled
                      ? () => _showDoubleDialog(
                          context,
                          title: '均分下限比',
                          value: s.balanceLowerRatio,
                          min: 0.1,
                          max: 0.95,
                          onConfirm: (v) => _update(
                            context,
                            s.copyWith(balanceLowerRatio: v),
                          ),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.trending_up,
                  iconColor: cs.secondary,
                  title: '均分上限比',
                  subtitle:
                      '高于理想长度 ${(s.balanceUpperRatio * 100).round()}% 时降级使用次级标点（，、,; 等）补切',
                  trailing: _ValueLabel(
                    '${(s.balanceUpperRatio * 100).round()}%',
                    e,
                    cs,
                  ),
                  onTap: e && !streamEnabled
                      ? () => _showDoubleDialog(
                          context,
                          title: '均分上限比',
                          value: s.balanceUpperRatio,
                          min: 0.5,
                          max: 1.0,
                          onConfirm: (v) => _update(
                            context,
                            s.copyWith(balanceUpperRatio: v),
                          ),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: cs.secondary,
                  title: '清理首尾空行',
                  subtitle: s.trimBlankLines
                      ? '已开启：仅清理每段两端空行，不影响段内换行'
                      : '已关闭：保留每段两端空行',
                  trailing: Switch(
                    value: s.trimBlankLines,
                    onChanged: !e || streamEnabled
                        ? null
                        : (v) =>
                              _update(context, s.copyWith(trimBlankLines: v)),
                  ),
                  disabled: !e || streamEnabled,
                ),
              ],
            ),
          ),
          // ---- 线性延迟算法 ----
          SliverToBoxAdapter(
            child: _Section(
              title: '线性延迟算法',
              children: [
                _SettingTile(
                  icon: Icons.timer_outlined,
                  iconColor: cs.tertiary,
                  title: '线性基础值（秒）',
                  subtitle: '段落之间固定的等待基准：${s.linearBase} 秒',
                  trailing: _ValueLabel('${s.linearBase} s', e, cs),
                  onTap: e && !streamEnabled
                      ? () => _showDoubleDialog(
                          context,
                          title: '线性基础值（秒）',
                          value: s.linearBase,
                          min: 0.0,
                          max: 5.0,
                          onConfirm: (v) =>
                              _update(context, s.copyWith(linearBase: v)),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.functions,
                  iconColor: cs.tertiary,
                  title: '线性字数系数',
                  subtitle: '每多一个字追加 ${s.linearCharFactor} 秒',
                  trailing: _ValueLabel('${s.linearCharFactor}', e, cs),
                  onTap: e && !streamEnabled
                      ? () => _showDoubleDialog(
                          context,
                          title: '线性字数系数',
                          value: s.linearCharFactor,
                          min: 0.0,
                          max: 0.3,
                          onConfirm: (v) =>
                              _update(context, s.copyWith(linearCharFactor: v)),
                        )
                      : null,
                ),
              ],
            ),
          ),
          // ---- 文本清理 ----
          SliverToBoxAdapter(
            child: _Section(
              title: '文本清理',
              children: [
                _SettingTile(
                  icon: Icons.input_outlined,
                  iconColor: cs.primary,
                  title: '前置清理正则',
                  subtitle:
                      '分段前对全文匹配并删除\n当前：${s.preCleanRegex.isEmpty ? "空" : "「${s.preCleanRegex}\""}',
                  onTap: e && !streamEnabled
                      ? () => _showRegexDialog(
                          context,
                          title: '前置清理正则',
                          value: s.preCleanRegex,
                          hint: '对全文匹配并删除，留空禁用',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(preCleanRegex: v)),
                        )
                      : null,
                ),
                _SettingTile(
                  icon: Icons.output_outlined,
                  iconColor: cs.primary,
                  title: '后置清理正则',
                  subtitle:
                      '每段切分后对该段匹配并删除（默认去首尾空白）\n当前：${s.postCleanRegex.isEmpty ? "空" : "「${s.postCleanRegex}\""}',
                  onTap: e && !streamEnabled
                      ? () => _showRegexDialog(
                          context,
                          title: '后置清理正则',
                          value: s.postCleanRegex,
                          hint: '对每段匹配并删除，留空禁用',
                          onConfirm: (v) =>
                              _update(context, s.copyWith(postCleanRegex: v)),
                        )
                      : null,
                ),
              ],
            ),
          ),
          // ---- 替换规则（条目在上，反向替换开关在下） ----
          SliverToBoxAdapter(
            child: _Section(
              title: '替换规则',
              children: [
                for (int i = 0; i < s.replaceRules.length; i++)
                  _ReplaceRuleTile(
                    enabled: e,
                    rule: s.replaceRules[i],
                    index: i,
                    onChanged: (newRule) {
                      final list = List<SegmentedReplaceRule>.from(
                        s.replaceRules,
                      );
                      list[i] = newRule;
                      _update(context, s.copyWith(replaceRules: list));
                    },
                    onDelete: () {
                      final list = List<SegmentedReplaceRule>.from(
                        s.replaceRules,
                      );
                      list.removeAt(i);
                      _update(context, s.copyWith(replaceRules: list));
                    },
                  ),
                _SettingTile(
                  icon: Icons.add,
                  iconColor: cs.primary,
                  title: '新增替换条目',
                  subtitle: '新建一条查找→替换规则，保存后可在上条中编辑',
                  onTap: e
                      ? () {
                          final list = List<SegmentedReplaceRule>.from(
                            s.replaceRules,
                          );
                          list.add(SegmentedReplaceRule(find: '', replace: ''));
                          _update(context, s.copyWith(replaceRules: list));
                        }
                      : null,
                ),
                _SettingTile(
                  icon: Icons.sync_alt,
                  iconColor: cs.secondary,
                  title: '反向替换',
                  subtitle: s.reverseReplace
                      ? '替换规则同时反向作用于用户输入。'
                      : '替换规则仅作用于 AI 回复',
                  trailing: Switch(
                    value: s.reverseReplace,
                    onChanged: !e || streamEnabled
                        ? null
                        : (v) =>
                              _update(context, s.copyWith(reverseReplace: v)),
                  ),
                  disabled: !e || streamEnabled,
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  static void _update(BuildContext context, SegmentedSendSettings next) {
    context.read<AppState>().setSegmentedSendSettings(next);
  }

  // ---------- 对话框 ----------

  static void _showIntDialog(
    BuildContext context, {
    required String title,
    required int value,
    required int min,
    required int max,
    String unit = '',
    required ValueChanged<int> onConfirm,
  }) {
    var current = value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$current $unit',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: current.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                onChanged: (v) => setState(() => current = v.round()),
              ),
              Text('范围 $min ~ $max', style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onConfirm(current);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _showDoubleDialog(
    BuildContext context, {
    required String title,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onConfirm,
  }) {
    var current = value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: current,
                min: min,
                max: max,
                divisions: ((max - min) * 100).round(),
                onChanged: (v) => setState(() {
                  current = (v * 100).round() / 100;
                }),
              ),
              Text(
                '范围 ${min.toStringAsFixed(2)} ~ ${max.toStringAsFixed(2)}',
                style: Theme.of(ctx).textTheme.bodySmall,
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
                onConfirm(current);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _showRegexDialog(
    BuildContext context, {
    required String title,
    required String value,
    required String hint,
    required ValueChanged<String> onConfirm,
  }) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入正则表达式，留空禁用',
              ),
              maxLines: 2,
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
              onConfirm(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// ---------- 通用组件（与 MemorySettingsPage 风格一致） ----------

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
  final bool disabled;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final visuallyDisabled = disabled || (onTap == null && trailing is! Switch);
    final cs = Theme.of(context).colorScheme;
    // 当本项有 Switch trailing（无视 disabled）时，需要让 Switch 仍可点击；
    // Switch 变化由其自身 onChanged 控制， tapping tile 不动作。
    return ListTile(
      enabled: !disabled && (onTap != null || trailing is Switch),
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

/// 右侧数值标签
class _ValueLabel extends StatelessWidget {
  final String label;
  final bool enabled;
  final ColorScheme cs;
  const _ValueLabel(this.label, this.enabled, this.cs);
  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(color: enabled ? cs.primary : cs.outline));
}

class _ReplaceRuleTile extends StatelessWidget {
  final bool enabled;
  final SegmentedReplaceRule rule;
  final int index;
  final ValueChanged<SegmentedReplaceRule> onChanged;
  final VoidCallback onDelete;
  const _ReplaceRuleTile({
    required this.enabled,
    required this.rule,
    required this.index,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.secondary.withAlpha((0.15 * 255).toInt()),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.swap_horiz,
          color: enabled ? cs.secondary : cs.outline,
          size: 22,
        ),
      ),
      title: Text(
        rule.find.isEmpty && rule.replace.isEmpty
            ? '条目 ${index + 1}（未设置）'
            : '条目 ${index + 1}：${rule.find.isEmpty ? "空" : rule.find} → ${rule.replace.isEmpty ? "空" : rule.replace}',
        style: TextStyle(color: enabled ? null : cs.outline),
      ),
      subtitle: const Text('点击编辑查找/替换内容'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        tooltip: '删除条目',
        onPressed: !enabled ? null : onDelete,
      ),
      onTap: !enabled ? null : () => _showEditDialog(context),
    );
  }

  void _showEditDialog(BuildContext context) {
    final findController = TextEditingController(text: rule.find);
    final replaceController = TextEditingController(text: rule.replace);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑替换条目 ${index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('AI 回复中（正向）查找下列文本并将其替换为「替换为」'),
            const SizedBox(height: 12),
            TextField(
              controller: findController,
              decoration: const InputDecoration(
                labelText: '查找文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: replaceController,
              decoration: const InputDecoration(
                labelText: '替换为',
                border: OutlineInputBorder(),
              ),
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
              onChanged(
                SegmentedReplaceRule(
                  find: findController.text,
                  replace: replaceController.text,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
