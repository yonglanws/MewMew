import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/settings_switch_action.dart';

/// 消息防抖动设置独立页面
class MessageDebounceSettingsPage extends StatelessWidget {
  const MessageDebounceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: SettingsSwitchFab(
        icon: Icons.tune_rounded,
        label: '防抖开关',
        onPressed: () => _showSwitches(context),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('消息防抖动', style: largeAppBarTitleStyle(context)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                child: Column(
                  children: [
                    ListTile(
                      enabled: state.messageMergeEnabled,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.timer_outlined,
                          color: state.messageMergeEnabled
                              ? cs.primary
                              : cs.outline,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        '合并防抖时间',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: state.messageMergeEnabled ? null : cs.outline,
                        ),
                      ),
                      subtitle: Text(
                        '等待 ${state.messageMergeDebounce} 秒无新发送消息后合并触发 AI 回复',
                        style: TextStyle(
                          color: state.messageMergeEnabled ? null : cs.outline,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: state.messageMergeEnabled ? null : cs.outline,
                      ),
                      onTap: !state.messageMergeEnabled
                          ? null
                          : () => _showIntDialog(
                              context,
                              title: '合并防抖时间（秒）',
                              value: state.messageMergeDebounce,
                              min: 1,
                              max: 15,
                              onConfirm: (v) => context
                                  .read<AppState>()
                                  .setMessageMergeDebounce(v),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 104)),
        ],
      ),
    );
  }

  static void _showSwitches(BuildContext context) {
    showSettingsSwitchSheet(
      context,
      title: '防抖开关',
      builder: (sheetContext) {
        final state = sheetContext.watch<AppState>();
        final cs = Theme.of(sheetContext).colorScheme;
        return Column(
          children: [
            SwitchListTile(
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.merge_type_outlined,
                  color: cs.secondary,
                  size: 22,
                ),
              ),
              title: const Text('消息防抖动'),
              subtitle: Text(
                state.messageMergeEnabled
                    ? '已开启：${state.messageMergeDebounce}s 内连续发出的多条消息合并为一条发送'
                    : '已关闭：每条发送的消息立即独立触发 AI 回复',
              ),
              value: state.messageMergeEnabled,
              onChanged: (v) =>
                  context.read<AppState>().setMessageMergeEnabled(v),
            ),
            SwitchListTile(
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.keyboard_outlined,
                  color: cs.tertiary,
                  size: 22,
                ),
              ),
              title: const Text('打字防抖'),
              subtitle: Text(
                state.typingDebounceEnabled
                    ? '已开启：输入框非空打字时暂停倒计时，停止打字或切出页面后恢复发送'
                    : '已关闭：消息发出后直接开始防抖倒计时',
              ),
              value: state.typingDebounceEnabled,
              onChanged: (v) =>
                  context.read<AppState>().setTypingDebounceEnabled(v),
            ),
          ],
        );
      },
    );
  }

  static void _showIntDialog(
    BuildContext context, {
    required String title,
    required int value,
    required int min,
    required int max,
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
                '$current 秒',
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
}
