import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/logger_service.dart';
import '../services/world_book_import.dart';
import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';
import '../widgets/settings_section.dart';

const _uuid = Uuid();

/// 世界书页面（设置-提示词-世界书）
///
/// 参考酒馆（SillyTavern）World Info / Lorebook：
/// 条目携带主/次触发关键词，主关键词出现在最近聊天中时把该条设定注入提示词
/// （次级关键词为 AND 逻辑）；常驻条目无视关键词始终注入；支持扫描深度、
/// 字符预算、递归扫描与 @Depth 注入位置；可导入酒馆 World Info JSON。
class WorldBookPage extends StatelessWidget {
  const WorldBookPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final wb = state.worldBookSettings;
    final isDepth = wb.injectionPosition == 'depth';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('世界书', style: largeAppBarTitleStyle(context)),
            actions: [
              IconButton(
                tooltip: '导出条目',
                icon: const Icon(Icons.ios_share_outlined),
                onPressed: () => _exportEntries(context),
              ),
              IconButton(
                tooltip: '导入条目',
                icon: const Icon(Icons.file_open_outlined),
                onPressed: () => _importEntries(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '全局设置',
              children: [
                SettingsTile(
                  icon: Icons.auto_stories_outlined,
                  iconColor: cs.primary,
                  title: '启用世界书',
                  subtitle: '关键词命中时把背景设定注入提示词',
                  trailing: Switch(
                    value: wb.enabled,
                    onChanged: (v) => _update(context, wb.copyWith(enabled: v)),
                  ),
                ),
                SettingsTile(
                  icon: Icons.history_outlined,
                  iconColor: cs.primary,
                  title: '扫描深度',
                  subtitle: '检查最近 ${wb.scanDepth} 条消息的关键词',
                  onTap: wb.enabled ? () => _pickScanDepth(context, wb) : null,
                ),
                SettingsTile(
                  icon: Icons.data_object_outlined,
                  iconColor: cs.primary,
                  title: '字符预算',
                  subtitle: '单次最多注入 ${wb.maxChars} 字符，超出按顺序截断',
                  onTap: wb.enabled ? () => _pickMaxChars(context, wb) : null,
                ),
                SettingsTile(
                  icon: Icons.all_inclusive_outlined,
                  iconColor: cs.primary,
                  title: '递归扫描',
                  subtitle: '已激活条目的内容可以继续触发其它条目',
                  trailing: Switch(
                    value: wb.recursiveScanning,
                    onChanged: wb.enabled
                        ? (v) =>
                              _update(context, wb.copyWith(recursiveScanning: v))
                        : null,
                  ),
                ),
                SettingsTile(
                  icon: Icons.low_priority_outlined,
                  iconColor: cs.primary,
                  title: '注入位置',
                  subtitle: isDepth ? '聊天记录深处 @Depth' : '系统提示词内',
                  onTap: wb.enabled ? () => _pickPosition(context, wb) : null,
                ),
                if (isDepth) ...[
                  SettingsTile(
                    icon: Icons.format_list_numbered_outlined,
                    iconColor: cs.primary,
                    title: '注入深度',
                    subtitle: '@Depth ${wb.injectionDepth}',
                    onTap: wb.enabled
                        ? () => _pickInjectionDepth(context, wb)
                        : null,
                  ),
                  SettingsTile(
                    icon: Icons.alternate_email_outlined,
                    iconColor: cs.primary,
                    title: '注入角色',
                    subtitle: _roleLabel(wb.injectionRole),
                    onTap: wb.enabled ? () => _pickRole(context, wb) : null,
                  ),
                ],
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSection(
              title: '条目（${wb.entries.length}）',
              children: wb.entries.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '还没有条目。点击右下角"添加条目"创建，或用右上角导入'
                          '酒馆（SillyTavern）World Info JSON 文件。聊天中出现关键词时，'
                          '对应设定会被自动注入。',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ]
                  : wb.entries
                        .map((entry) => _EntryTile(entry: entry))
                        .toList(),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEntry(context, entry: null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加条目'),
      ),
    );
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

  static void _update(BuildContext context, WorldBookSettings next) {
    context.read<AppState>().updateWorldBookSettings(next);
  }

  // ------------------------------------------------------------------
  // 导入 / 导出
  // ------------------------------------------------------------------

  /// 从 JSON 文件导入条目（兼容酒馆 World Info 格式与本应用格式），追加到现有条目
  static Future<void> _importEntries(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      final raw = file.bytes != null
          ? String.fromCharCodes(file.bytes!)
          : null;
      if (raw == null || raw.trim().isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('文件为空')));
        return;
      }
      final entries = parseWorldBookJson(raw);
      final wb = state.worldBookSettings;
      wb.entries.addAll(entries);
      wb.enabled = true;
      await state.updateWorldBookSettings(wb);
      messenger.showSnackBar(
        SnackBar(content: Text('已导入 ${entries.length} 个条目并启用世界书')),
      );
      Log.i('worldbook', '导入条目成功：${entries.length} 个（${file.name}）');
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  /// 导出当前条目为 JSON 并复制到剪贴板（可再次导入）
  static void _exportEntries(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final wb = context.read<AppState>().worldBookSettings;
    if (wb.entries.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('还没有条目可导出')));
      return;
    }
    Clipboard.setData(
      ClipboardData(text: exportWorldBookJson(wb.entries)),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('已复制 ${wb.entries.length} 个条目的 JSON 到剪贴板')),
    );
  }

  // ------------------------------------------------------------------
  // 全局参数
  // ------------------------------------------------------------------

  static void _pickScanDepth(BuildContext context, WorldBookSettings wb) {
    var current = wb.scanDepth;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('扫描深度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$current 条',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: current.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
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
                _update(context, wb.copyWith(scanDepth: current));
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _pickMaxChars(BuildContext context, WorldBookSettings wb) {
    var current = wb.maxChars;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('字符预算'),
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
                min: 200,
                max: 4000,
                divisions: 38,
                onChanged: (v) =>
                    setState(() => current = (v / 100).round() * 100),
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
                _update(context, wb.copyWith(maxChars: current));
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _pickPosition(BuildContext context, WorldBookSettings wb) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注入位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'system',
              groupValue: wb.injectionPosition,
              title: const Text('系统提示词内'),
              subtitle: const Text('作为背景设定挂在角色设定之后；条目动态激活会使提示词缓存失效'),
              onChanged: (v) {
                if (v != null) {
                  _update(context, wb.copyWith(injectionPosition: v));
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<String>(
              value: 'depth',
              groupValue: wb.injectionPosition,
              title: const Text('聊天记录深处 @Depth'),
              subtitle: const Text('伪装成一条消息插入上下文末尾（默认，推荐：贴近对话且不影响缓存）'),
              onChanged: (v) {
                if (v != null) {
                  _update(context, wb.copyWith(injectionPosition: v));
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

  static void _pickInjectionDepth(BuildContext context, WorldBookSettings wb) {
    var current = wb.injectionDepth;
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
                _update(context, wb.copyWith(injectionDepth: current));
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  static void _pickRole(BuildContext context, WorldBookSettings wb) {
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
                groupValue: wb.injectionRole,
                title: Text(_roleLabel(role)),
                onChanged: (v) {
                  if (v != null) {
                    _update(context, wb.copyWith(injectionRole: v));
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

  /// 条目编辑底部弹层（新增与编辑共用）
  static void _editEntry(
    BuildContext context, {
    required WorldBookEntry? entry,
  }) {
    final titleCtrl = TextEditingController(text: entry?.title ?? '');
    final keywordsCtrl = TextEditingController(
      text: (entry?.keywords ?? const []).join('，'),
    );
    final secondaryCtrl = TextEditingController(
      text: (entry?.secondaryKeywords ?? const []).join('，'),
    );
    final contentCtrl = TextEditingController(text: entry?.content ?? '');
    var constant = entry?.constant ?? false;
    var order = entry?.order ?? 100;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
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
                  Text(
                    entry == null ? '添加条目' : '编辑条目',
                    style: Theme.of(sheetCtx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '条目名称',
                      hintText: '仅用于管理，如"月见高中"',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keywordsCtrl,
                    decoration: const InputDecoration(
                      labelText: '触发关键词',
                      hintText: '多个关键词用逗号分隔，如：月见,高中,校园',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secondaryCtrl,
                    decoration: const InputDecoration(
                      labelText: '次级关键词（可选）',
                      hintText: '填了则需同时命中才会注入（AND 逻辑），如：祭典,运动会',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 8,
                    minLines: 4,
                    decoration: const InputDecoration(
                      labelText: '设定内容',
                      hintText: '关键词命中时注入提示词的背景资料',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('常驻条目'),
                    subtitle: const Text('无视关键词，始终注入'),
                    value: constant,
                    onChanged: (v) => setSheetState(() => constant = v),
                  ),
                  Row(
                    children: [
                      Text(
                        '插入顺序 $order',
                        style: Theme.of(sheetCtx).textTheme.bodySmall,
                      ),
                      Expanded(
                        child: Slider(
                          value: order.toDouble(),
                          min: 0,
                          max: 200,
                          divisions: 20,
                          label: '$order',
                          onChanged: (v) =>
                              setSheetState(() => order = v.round()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          List<String> parseKeywords(String raw) => raw
                              .split(RegExp(r'[,，;；\n]'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                          final next = WorldBookEntry(
                            id: entry?.id ?? _uuid.v4(),
                            title: titleCtrl.text.trim(),
                            keywords: parseKeywords(keywordsCtrl.text),
                            secondaryKeywords: parseKeywords(secondaryCtrl.text),
                            content: contentCtrl.text.trim(),
                            enabled: entry?.enabled ?? true,
                            constant: constant,
                            order: order,
                          );
                          final state = context.read<AppState>();
                          final wb = state.worldBookSettings;
                          final idx = wb.entries.indexWhere(
                            (e) => e.id == next.id,
                          );
                          if (idx >= 0) {
                            wb.entries[idx] = next;
                          } else {
                            wb.entries.add(next);
                          }
                          _update(context, wb);
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
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final WorldBookEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final wb = state.worldBookSettings;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.title.trim().isEmpty ? '（未命名条目）' : entry.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (entry.constant) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '常驻',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ),
          ],
          if (entry.secondaryKeywords.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'AND',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        entry.keywords.isEmpty
            ? (entry.constant ? '始终注入' : '无关键词（不会被触发）')
        : entry.secondaryKeywords.isNotEmpty
        ? '${entry.keywords.join('，')} 且 ${entry.secondaryKeywords.join('，')}'
        : entry.keywords.join('，'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: entry.enabled,
            onChanged: (v) {
              entry.enabled = v;
              WorldBookPage._update(context, wb);
            },
          ),
          PopupMenuButton<String>(
            iconSize: 18,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
            onSelected: (v) {
              if (v == 'edit') {
                WorldBookPage._editEntry(context, entry: entry);
              } else if (v == 'delete') {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除条目'),
                    content: Text(
                      '确定删除「${entry.title.isEmpty ? '未命名条目' : entry.title}」吗？',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(ctx).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(ctx).colorScheme.onErrorContainer,
                        ),
                        onPressed: () {
                          wb.entries.removeWhere((e) => e.id == entry.id);
                          WorldBookPage._update(context, wb);
                          Navigator.pop(ctx);
                        },
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      onTap: () => WorldBookPage._editEntry(context, entry: entry),
    );
  }
}
