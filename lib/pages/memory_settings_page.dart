import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/logger_service.dart';
import '../services/memory/memory_transfer.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../utils/large_app_bar_title.dart';
import 'dashboard_page.dart';
import 'memory_graph_page.dart';
import 'memory_page.dart';

/// 记忆系统设置页（独立页面）
class MemorySettingsPage extends StatelessWidget {
  const MemorySettingsPage({super.key});

  static void showEmbeddingApiSheet(BuildContext context) {
    _showEmbeddingApiSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final embeddingValid = state.embeddingApiConfig.isValid;
    // 嵌入 API 不再是硬门槛：未配置时关键词与图谱检索仍可用
    final isMemoryEnabled = state.injectMemories;
    final memoryDisabled = !isMemoryEnabled;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('记忆系统', style: largeAppBarTitleStyle(context)),
          ),
          // 嵌入未配置时显示信息性提示（非硬门槛）
          if (!embeddingValid)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: cs.tertiary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '未配置嵌入 API',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '关键词检索与图谱检索仍可正常工作；配置嵌入 API 后可启用语义向量检索，召回更准确。',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 嵌入 API 配置与总开关
          SliverToBoxAdapter(
            child: _Section(
              title: '核心配置',
              children: [
                _SettingTile(
                  icon: Icons.power_settings_new_rounded,
                  iconColor: cs.tertiary,
                  title: '记忆系统总开关',
                  subtitle: state.injectMemories
                      ? '已开启：对话中自动检索并注入长期记忆'
                      : '已关闭：暂不注入长期记忆',
                  trailing: Switch(
                    value: state.injectMemories,
                    onChanged: (v) =>
                        context.read<AppState>().setInjectMemories(v),
                  ),
                ),
              ],
            ),
          ),
          // 记忆查看与仪表盘快捷入口
          SliverToBoxAdapter(
            child: _Section(
              title: '记忆管理',
              children: [
                _SettingTile(
                  icon: Icons.dashboard_outlined,
                  iconColor: cs.secondary,
                  title: '记忆系统仪表盘',
                  subtitle: '查看记忆统计、分析与趋势分布',
                  onTap: memoryDisabled
                      ? null
                      : () => _push(
                          context,
                          const DashboardPage(scrollToMemory: true),
                        ),
                ),
                _SettingTile(
                  icon: Icons.account_tree_outlined,
                  iconColor: cs.tertiary,
                  title: '记忆图谱',
                  subtitle:
                      '节点 ${state.graphStore.nodeCount} · 边 ${state.graphStore.edgeCount}',
                  onTap: memoryDisabled
                      ? null
                      : () => _push(context, const MemoryGraphPage()),
                ),
                _SettingTile(
                  icon: Icons.psychology_outlined,
                  iconColor: cs.primary,
                  title: '查看记忆',
                  subtitle: '按人格查看和管理，共 ${state.memories.length} 条',
                  onTap: memoryDisabled
                      ? null
                      : () => _push(context, const MemoryPage()),
                ),
              ],
            ),
          ),
          // 记忆系统参数
          SliverToBoxAdapter(
            child: _Section(
              title: '参数设置',
              children: [
                _SettingTile(
                  icon: Icons.filter_alt_outlined,
                  iconColor: cs.tertiary,
                  title: '记忆隔离模式',
                  subtitle: switch (state.memorySettings.memoryScopeMode) {
                    'persona' => '人物隔离：同一人物的不同会话共用记忆',
                    'global' => '全局共享：所有会话共用一个记忆池',
                    _ => '会话隔离：每个会话拥有独立记忆空间',
                  },
                  onTap: memoryDisabled
                      ? null
                      : () => _showSessionFilterDialog(context),
                ),
                _SettingTile(
                  icon: Icons.format_list_numbered_outlined,
                  iconColor: cs.tertiary,
                  title: '总结轮数阈值',
                  subtitle:
                      '达到 ${state.memorySettings.summaryThreshold} 轮对话后触发总结',
                  onTap: memoryDisabled
                      ? null
                      : () => _showIntDialog(
                          context,
                          title: '总结轮数阈值',
                          value: state.memorySettings.summaryThreshold,
                          min: 1,
                          max: 20,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(
                                  summaryThreshold: v,
                                ),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.model_training_outlined,
                  iconColor: cs.tertiary,
                  title: '总结模型',
                  subtitle: state.memorySettings.summaryModel.isEmpty
                      ? '使用当前 API 主模型'
                      : state.memorySettings.summaryModel,
                  onTap: memoryDisabled
                      ? null
                      : () => _showModelPicker(
                          context,
                          title: '选择总结模型',
                          current: state.memorySettings.summaryModel,
                          allowEmpty: true,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(summaryModel: v),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.memory_outlined,
                  iconColor: cs.primary,
                  title: '检索记忆数量',
                  subtitle: '注入 ${state.memorySettings.retrievalCount} 条最相关记忆',
                  onTap: memoryDisabled
                      ? null
                      : () => _showIntDialog(
                          context,
                          title: '检索记忆数量',
                          value: state.memorySettings.retrievalCount,
                          min: 1,
                          max: 20,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(
                                  retrievalCount: v,
                                ),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.swap_vert_outlined,
                  iconColor: cs.secondary,
                  title: '记忆注入位置',
                  subtitle: state.memorySettings.injectionPosition == 'prepend'
                      ? '前置（prepend）：记忆在消息之前'
                      : '后置（append）：记忆在消息之后',
                  onTap: memoryDisabled
                      ? null
                      : () => _showChoiceDialog(
                          context,
                          title: '记忆注入位置',
                          value: state.memorySettings.injectionPosition,
                          options: const {
                            'prepend': '前置（prepend）',
                            'append': '后置（append）',
                          },
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(
                                  injectionPosition: v,
                                ),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.trending_down_outlined,
                  iconColor: cs.tertiary,
                  title: '每日衰减率',
                  subtitle: state.memorySettings.decayRate == 0
                      ? '已禁用（旧记忆不衰减）'
                      : '每天降低 ${(state.memorySettings.decayRate * 100).toStringAsFixed(1)}%，'
                            '随时间降低旧记忆权重',
                  onTap: memoryDisabled
                      ? null
                      : () => _showDoubleDialog(
                          context,
                          title: '每日衰减率',
                          value: state.memorySettings.decayRate,
                          min: 0,
                          max: 0.1,
                          divisions: 20,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(decayRate: v),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.shield_outlined,
                  iconColor: cs.primary,
                  title: '重要记忆保护阈值',
                  subtitle:
                      '重要性 ≥ ${(state.memorySettings.protectionThreshold * 100).toStringAsFixed(0)}% 的记忆不参与衰减',
                  onTap: memoryDisabled
                      ? null
                      : () => _showDoubleDialog(
                          context,
                          title: '重要记忆保护阈值',
                          value: state.memorySettings.protectionThreshold,
                          min: 0,
                          max: 1,
                          divisions: 20,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(
                                  protectionThreshold: v,
                                ),
                              ),
                        ),
                ),
                _SettingTile(
                  icon: Icons.trending_up_outlined,
                  iconColor: cs.secondary,
                  title: '访问强化次数上限',
                  subtitle:
                      '被检索 ${state.memorySettings.maxAccessBoost} 次后获得最大衰减保护，超出不再增强',
                  onTap: memoryDisabled
                      ? null
                      : () => _showIntDialog(
                          context,
                          title: '访问强化次数上限',
                          value: state.memorySettings.maxAccessBoost,
                          min: 1,
                          max: 50,
                          onConfirm: (v) =>
                              context.read<AppState>().updateMemorySettings(
                                state.memorySettings.copyWith(
                                  maxAccessBoost: v,
                                ),
                              ),
                        ),
                ),
              ],
            ),
          ),
          // 记忆整理
          SliverToBoxAdapter(
            child: _Section(
              title: '记忆整理',
              children: [
                _SettingTile(
                  icon: Icons.merge_type_outlined,
                  iconColor: cs.primary,
                  title: '自动整理合并',
                  subtitle: state.memorySettings.consolidationEnabled
                      ? '已开启：同一会话的零散旧记忆自动合并，原件归档'
                      : '已关闭：保持每条记忆独立',
                  trailing: Switch(
                    value: state.memorySettings.consolidationEnabled,
                    onChanged: memoryDisabled
                        ? null
                        : (v) => context.read<AppState>().updateMemorySettings(
                            state.memorySettings.copyWith(
                              consolidationEnabled: v,
                            ),
                          ),
                  ),
                ),
                _SettingTile(
                  icon: Icons.bolt_outlined,
                  iconColor: cs.secondary,
                  title: '立即整理',
                  subtitle: '手动触发一轮整理合并（不受冷却限制）',
                  onTap:
                      memoryDisabled ||
                          !state.memorySettings.consolidationEnabled
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('整理进行中…')),
                          );
                          await context
                              .read<AppState>()
                              .runConsolidationManually();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('整理完成')),
                          );
                        },
                ),
              ],
            ),
          ),
          // 维护与数据
          SliverToBoxAdapter(
            child: _Section(
              title: '维护与数据',
              children: [
                _SettingTile(
                  icon: Icons.health_and_safety_outlined,
                  iconColor: cs.primary,
                  title: '立即维护',
                  subtitle: '执行衰减、原子清扫与旧记忆清理',
                  onTap: memoryDisabled
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await context.read<AppState>().runMemoryMaintenance();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('记忆维护完成')),
                          );
                        },
                ),
                _SettingTile(
                  icon: Icons.ios_share_outlined,
                  iconColor: cs.secondary,
                  title: '导出记忆',
                  subtitle: '用系统文件选择器保存 JSON',
                  onTap: memoryDisabled ? null : () => _exportMemories(context),
                ),
                _SettingTile(
                  icon: Icons.download_outlined,
                  iconColor: cs.tertiary,
                  title: '导入记忆',
                  subtitle: '从系统文件选择器读取 JSON',
                  onTap: memoryDisabled ? null : () => _importMemories(context),
                ),
              ],
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  static Future<void> _exportMemories(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final json = exportMemoriesJson(
      memories: state.memories,
      atoms: state.memoryAtoms,
    );
    final now = DateTime.now();
    final name =
        'mewmew-memories-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    try {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出记忆',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: utf8.encode(json),
      );
      if (saved == null) return;
      messenger.showSnackBar(const SnackBar(content: Text('记忆已导出')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  static Future<void> _importMemories(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '导入记忆',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final String raw;
      if (file.bytes != null) {
        raw = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
        return;
      }
      final report = importMemoriesJson(raw, existingMemories: state.memories);
      final imported = await state.importMemoryEntries(report.newMemories);
      messenger.showSnackBar(
        SnackBar(content: Text('导入 $imported 条，跳过 ${report.skipped} 条')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  static void _push(BuildContext context, Widget page) {
    Navigator.push(context, FastRoute(builder: (_) => page));
  }

  static void _showEmbeddingApiSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmbeddingApiSheet(),
    );
  }

  static void _showModelPicker(
    BuildContext context, {
    required String title,
    required String current,
    bool allowEmpty = false,
    required ValueChanged<String> onConfirm,
  }) {
    // 使用已配置 API 的模型（不再联网拉取 /models）
    final state = context.read<AppState>();
    final modelSources = <String, Set<String>>{};
    for (final api in state.apiConfigs) {
      // 供应商-模型两级：列出每个供应商下的全部模型档位
      final models = api.models.isNotEmpty
          ? api.models.map((m) => m.model)
          : [if (api.model.trim().isNotEmpty) api.model];
      for (final model in models) {
        if (model.trim().isEmpty) continue;
        (modelSources[model] ??= {}).add(api.name);
      }
    }
    if (modelSources.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在 API 配置中添加至少一个模型')));
      return;
    }
    final entries =
        modelSources.entries
            .map((e) => (model: e.key, sources: e.value.toList()..sort()))
            .toList()
          ..sort((a, b) => a.model.compareTo(b.model));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ModelPickerSheet(
        title: title,
        current: current,
        allowEmpty: allowEmpty,
        entries: entries,
        onConfirm: onConfirm,
      ),
    );
  }

  static void _showSessionFilterDialog(BuildContext context) {
    final state = context.read<AppState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记忆隔离模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              ('session', '会话隔离', '每个会话拥有独立的记忆空间'),
              ('persona', '人物隔离', '同一人物的不同会话共用记忆，人物之间互不混用'),
              ('global', '全局共享', '所有会话共用同一个记忆池'),
            ])
              RadioListTile<String>(
                value: option.$1,
                groupValue: state.memorySettings.memoryScopeMode,
                title: Text(option.$2),
                subtitle: Text(option.$3),
                onChanged: (v) {
                  if (v == null) return;
                  context.read<AppState>().updateMemorySettings(
                    state.memorySettings.copyWith(
                      memoryScopeMode: v,
                      useSessionFiltering: v == 'session',
                    ),
                  );
                  Navigator.pop(ctx);
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
                '$current',
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

  static void _showDoubleDialog(
    BuildContext context, {
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
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
                current == 0 ? '已禁用' : '${(current * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: current,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: (v) => setState(() => current = v),
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

  static void _showChoiceDialog(
    BuildContext context, {
    required String title,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries.map((e) {
            return RadioListTile<String>(
              value: e.key,
              groupValue: value,
              title: Text(e.value),
              onChanged: (v) {
                if (v != null) {
                  onConfirm(v);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
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

/// 模型选择底部弹窗：列出已配置 API 的模型
class _ModelPickerSheet extends StatefulWidget {
  final String title;
  final String current;
  final bool allowEmpty; // 是否允许"留空"选项
  final List<({String model, List<String> sources})> entries;
  final ValueChanged<String> onConfirm;

  const _ModelPickerSheet({
    required this.title,
    required this.current,
    required this.entries,
    required this.onConfirm,
    this.allowEmpty = false,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _query.isEmpty
        ? widget.entries
        : widget.entries
              .where(
                (e) =>
                    e.model.toLowerCase().contains(_query) ||
                    e.sources.any((s) => s.toLowerCase().contains(_query)),
              )
              .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                Text(
                  '${widget.title}（${widget.entries.length}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          if (widget.allowEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                leading: Icon(
                  widget.current.isEmpty ? Icons.check_circle : Icons.memory,
                  color: widget.current.isEmpty ? cs.primary : null,
                ),
                title: const Text('使用当前 API 主模型'),
                dense: true,
                onTap: () {
                  widget.onConfirm('');
                  Navigator.pop(context);
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '搜索模型或 API 名称…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final entry = filtered[i];
                final selected = entry.model == widget.current;
                return ListTile(
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.memory,
                    color: selected ? cs.primary : null,
                  ),
                  title: Text(
                    entry.model,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    entry.sources.join('、'),
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                  dense: true,
                  onTap: () {
                    widget.onConfirm(entry.model);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddingApiSheet extends StatefulWidget {
  const _EmbeddingApiSheet();

  @override
  State<_EmbeddingApiSheet> createState() => _EmbeddingApiSheetState();
}

class _EmbeddingApiSheetState extends State<_EmbeddingApiSheet> {
  final _scrollController = ScrollController();
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  bool _obscureKey = true;
  bool _loadingModels = false;
  bool _testing = false;
  // 测试结果（内联展示）
  bool? _testSuccess;
  String? _testMessage;
  String? _testDetail;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().embeddingApiConfig;
    _baseUrl = TextEditingController(text: cfg.baseUrl);
    _apiKey = TextEditingController(text: cfg.apiKey);
    _model = TextEditingController(text: cfg.model);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 测试完成后自动滚动到结果位置
  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrl.text.trim();
    final apiKey = _apiKey.text.trim();
    if (!baseUrl.startsWith('http') || apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写 Base URL 和 API Key')));
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final models = await AiService.listModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      if (models.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该接口未返回任何模型')));
      } else {
        _showModelPicker(models);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取失败：$e')));
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  /// 测试嵌入 API 连接：获取一个词的嵌入向量验证可用性
  Future<void> _testConnection() async {
    final baseUrl = _baseUrl.text.trim();
    final apiKey = _apiKey.text.trim();
    final model = _model.text.trim();
    if (!baseUrl.startsWith('http') || apiKey.isEmpty || model.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = '请先填写 Base URL、API Key 和模型名称';
        _testDetail = null;
      });
      _scrollToResult();
      return;
    }
    // 清除旧结果，开始测试
    setState(() {
      _testing = true;
      _testSuccess = null;
      _testMessage = null;
      _testDetail = null;
    });
    debugPrint('[嵌入测试] 开始测试: baseUrl=$baseUrl, model=$model');
    Log.i('memory', '嵌入 API 测试开始：baseUrl=$baseUrl, model=$model');
    try {
      final start = DateTime.now();
      final result = await AiService.getEmbedding(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        text: 'test',
      ).timeout(const Duration(seconds: 30));
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[嵌入测试] 成功: ${elapsed}ms, dim=${result.embedding.length}');
      Log.i('memory', '嵌入 API 测试成功：${elapsed}ms 维度=${result.embedding.length}');
      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testMessage =
            '耗时 ${elapsed}ms · 向量维度 ${result.embedding.length} · 输入 token ${result.inputTokens}';
        _testDetail = null;
      });
      _scrollToResult();
    } catch (e) {
      debugPrint('[嵌入测试] 失败: $e');
      Log.e('memory', '嵌入 API 测试失败', error: e);
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testMessage = '连接失败';
        _testDetail = e.toString();
      });
      _scrollToResult();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 构建测试结果卡片（内联展示，避免 Dialog 被 BottomSheet 遮挡）
  Widget _buildTestResult() {
    final cs = Theme.of(context).colorScheme;
    final success = _testSuccess ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: success
              ? cs.primary.withValues(alpha: 0.4)
              : cs.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.cancel,
                color: success ? Colors.green : cs.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success ? '连接成功' : '连接失败',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: success ? cs.primary : cs.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_testMessage!, style: const TextStyle(fontSize: 13)),
          if (_testDetail != null && _testDetail!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _testDetail!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showModelPicker(List<String> models) {
    final current = _model.text.trim();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final query = ValueNotifier('');
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  children: [
                    Text(
                      '选择嵌入模型（${models.length}）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: '搜索模型…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => query.value = v,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, q, __) {
                    final filtered = q.isEmpty
                        ? models
                        : models
                              .where(
                                (m) =>
                                    m.toLowerCase().contains(q.toLowerCase()),
                              )
                              .toList();
                    return ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final m = filtered[i];
                        final selected = m == current;
                        return ListTile(
                          leading: Icon(
                            selected ? Icons.check_circle : Icons.memory,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            m,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          dense: true,
                          onTap: () {
                            _model.text = m;
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('嵌入 API 配置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '可选：为记忆系统提供语义向量检索，可指向不同于对话 API 的服务商；'
              '未配置时关键词与图谱检索仍可正常使用',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKey,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              decoration: InputDecoration(
                labelText: '嵌入模型名称',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _loadingModels ? null : _fetchModels,
                  icon: Icon(
                    _loadingModels ? null : Icons.cloud_download_outlined,
                    size: 18,
                  ),
                  label: Text(_loadingModels ? '获取中…' : '获取模型列表'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_testing ? '测试中…' : '测试连接'),
                ),
              ],
            ),
            // 测试结果内联展示（避免 Dialog 被 BottomSheet 遮挡）
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              _buildTestResult(),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final config = EmbeddingApiConfig(
                  baseUrl: _baseUrl.text.trim().isNotEmpty
                      ? _baseUrl.text.trim()
                      : '',
                  apiKey: _apiKey.text.trim(),
                  model: _model.text.trim().isNotEmpty
                      ? _model.text.trim()
                      : '',
                );
                context.read<AppState>().updateEmbeddingApi(config);
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

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
    // 只有“既不能点、也没有开关”的项才算禁用。
    // 仅带 Switch 的项以前会被误判成灰色。
    final disabled = onTap == null && trailing == null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (disabled ? Theme.of(context).colorScheme.outline : iconColor)
              .withAlpha((0.15 * 255).toInt()),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: disabled ? Theme.of(context).colorScheme.outline : iconColor,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: disabled ? Theme.of(context).colorScheme.outline : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: disabled ? Theme.of(context).colorScheme.outline : null,
        ),
      ),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
      onTap: onTap,
    );
  }
}
