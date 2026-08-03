import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/logger_service.dart';

/// 时间范围筛选
enum _TimeRange { all, today, week }

/// 日志查看页面
///
/// 性能架构（解决进入页面极其卡顿）：
/// 1. 派生数据（filter/counts）缓存到 State，build 方法 O(1) 读缓存
/// 2. 卡片极简化：单 Container + 纯 Text，无 Material/InkWell/Wrap/RichText
/// 3. ListView.builder + addAutomaticKeepAlives:false，减少 item 构建开销
/// 4. 滚动监听不触发 setState，自动滚动仅在日志数变化时触发一次
/// 5. LoggerService 通知合并到下一帧，避免高频重建
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  LogLevel? _levelFilter;
  String? _tagFilter;
  _TimeRange _timeRange = _TimeRange.all;
  String _keyword = '';
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _autoScroll = true;

  // 缓存的派生数据
  List<LogEntry> _filteredList = const [];
  Map<LogLevel, int> _levelCounts = const {};
  Map<String, int> _tagCounts = const {};
  int _totalCount = 0;
  int _lastSeenLogCount = -1; // 用于检测日志数变化以触发自动滚动
  bool _isFirstBuild = true; // 首次进入标记，用于延迟自动滚动
  bool _ready = false; // 首帧完成前禁止 setState，避免 setState during build 死循环
  bool _refreshQueued = false;
  bool _stateUpdateQueued = false;
  bool _initialScrollQueued = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    final logger = LoggerService.instance;
    // 仅同步读缓存，不 setState（initState 期间 setState 会触发
    // "setState() called during build" → FlutterError.onError 记 error
    // → notify → 再次 setState → 疯狂吐 error）
    _syncCacheFromLogger();
    logger.addListener(_onLoggerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ready = true;
      _refreshFromLogger();
    });
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    final maxExtent = _scrollCtrl.position.maxScrollExtent;

    // 自动滚动状态：不触发 setState，仅在需要时改标志位，下次重建自然生效
    final nearBottom = maxExtent - offset <= 200;
    if (_autoScroll != nearBottom) {
      _autoScroll = nearBottom;
      // 仅改 FAB 显隐，用轻量 setState 而非整页重建
      _queueStateUpdate();
    }

  }

  @override
  void dispose() {
    LoggerService.instance.removeListener(_onLoggerChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// LoggerService 通知回调：延迟到下一帧再刷新，避免 build 期间 setState
  void _onLoggerChanged() {
    if (!_ready || !mounted) return;
    if (_refreshQueued) return;
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshQueued = false;
      if (mounted) _refreshFromLogger();
    });
  }

  void _queueStateUpdate() {
    if (_stateUpdateQueued) return;
    _stateUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stateUpdateQueued = false;
      if (mounted) setState(() {});
    });
  }

  /// 仅更新缓存字段，不触发 setState
  void _syncCacheFromLogger() {
    final logger = LoggerService.instance;
    _levelCounts = logger.levelCounts;
    _tagCounts = logger.tagCounts;
    _totalCount = logger.logCount;
    _filteredList = logger.filter(
      level: _levelFilter,
      tag: _tagFilter,
      keyword: _keyword,
      since: _since,
    );
  }

  void _refreshFromLogger() {
    if (!mounted) return;
    _syncCacheFromLogger();
    if (_totalCount != _lastSeenLogCount) {
      _lastSeenLogCount = _totalCount;
      if (_autoScroll) {
        if (_isFirstBuild) {
          _isFirstBuild = false;
          _queueInitialScroll();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_autoScroll &&
                _scrollCtrl.hasClients &&
                _filteredList.isNotEmpty) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }
      }
    }
    if (_ready) setState(() {});
  }

  void _queueInitialScroll() {
    if (_initialScrollQueued) return;
    _initialScrollQueued = true;
    void attempt(int frame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_autoScroll &&
            _scrollCtrl.hasClients &&
            _filteredList.isNotEmpty) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
        if (frame < 3) {
          attempt(frame + 1);
        } else {
          _initialScrollQueued = false;
        }
      });
    }
    attempt(0);
  }

  void _recomputeFilter() {
    _filteredList = LoggerService.instance.filter(
      level: _levelFilter,
      tag: _tagFilter,
      keyword: _keyword,
      since: _since,
    );
    setState(() {});
  }

  DateTime? get _since {
    final now = DateTime.now();
    switch (_timeRange) {
      case _TimeRange.all:
        return null;
      case _TimeRange.today:
        return DateTime(now.year, now.month, now.day);
      case _TimeRange.week:
        return now.subtract(const Duration(days: 7));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _filteredList;
    final logger = LoggerService.instance;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined, size: 20),
            tooltip: '导出',
            onPressed:
                list.isEmpty ? null : () => _showExportMenu(context, logger),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空',
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            RepaintBoundary(
              child: _LevelFilterBar(
                selected: _levelFilter,
                counts: _levelCounts,
                onChanged: (l) {
                  _levelFilter = l;
                  _recomputeFilter();
                },
              ),
            ),
            // 时间 + Tag 过滤 —— RepaintBoundary 隔离
            RepaintBoundary(
              child: _SecondaryFilterBar(
                timeRange: _timeRange,
                selectedTag: _tagFilter,
                tagCounts: _tagCounts,
                onTimeChanged: (t) {
                  _timeRange = t;
                  _recomputeFilter();
                },
                onTagChanged: (t) {
                  _tagFilter = t;
                  _recomputeFilter();
                },
              ),
            ),
            // 搜索框 —— RepaintBoundary 隔离
            RepaintBoundary(
              child: _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) {
                  _keyword = v;
                  _recomputeFilter();
                },
              ),
            ),
            // 日志列表
            Expanded(
              child: list.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      cacheExtent: 800,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: list.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onLongPress: () => _showLogDetail(context, list[i]),
                        child: _LogRow(
                          entry: list[i],
                          keyword: _keyword.trim(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: list.isEmpty || _autoScroll
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                if (_scrollCtrl.hasClients) {
                  _scrollCtrl.animateTo(
                    _scrollCtrl.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: const Icon(Icons.keyboard_double_arrow_down_rounded),
            ),
    );
  }

  void _showLogDetail(BuildContext context, LogEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final color = _levelColor(entry.level);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.level.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '[${entry.tag}]',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                entry.message,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              if (entry.error != null && entry.error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Error:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    entry.error!,
                    style: TextStyle(fontSize: 11, color: cs.error),
                  ),
                ),
              ],
              if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Stack Trace:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    entry.stackTrace!,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text:
                      '${entry.level.label} [${entry.tag}] ${entry.message}\n${entry.error ?? ""}\n${entry.stackTrace ?? ""}',
                ),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制详细日志')),
              );
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定清空所有日志记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await LoggerService.instance.clear();
      log.i('app', '用户手动清空了日志');
    }
  }

  void _showExportMenu(BuildContext context, LoggerService logger) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '导出日志',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        '${logger.logs.length} 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded, size: 22),
                  title: const Text('复制到剪贴板'),
                  subtitle: const Text('全部日志以纯文本形式复制'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyAll(logger);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined, size: 22),
                  title: const Text('导出为 TXT'),
                  subtitle: const Text('纯文本，便于直接查看'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportAndShare(logger, LogExportFormat.text);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined, size: 22),
                  title: const Text('导出为 Markdown'),
                  subtitle: const Text('表格格式，便于归档'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportAndShare(logger, LogExportFormat.markdown);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.data_object, size: 22),
                  title: const Text('导出为 JSON'),
                  subtitle: const Text('结构化数据，便于解析'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportAndShare(logger, LogExportFormat.json);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _copyAll(LoggerService logger) async {
    final text = logger.exportAsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${logger.logs.length} 条日志到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    log.i('app', '复制 ${logger.logs.length} 条日志到剪贴板');
  }

  void _exportAndShare(LoggerService logger, LogExportFormat format) async {
    try {
      final file = await logger.exportToFile(format);
      if (!mounted) return;
      final result = await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'mewmew 运行日志');
      if (result.status == ShareResultStatus.success) {
        log.i('app', '导出 ${logger.logs.length} 条日志（${format.label}）并分享成功');
      }
    } catch (e, s) {
      log.e('app', '导出日志失败', error: e, stackTrace: s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

// ──────────────────────────────────────────────
// 级别过滤栏
// ──────────────────────────────────────────────

class _LevelFilterBar extends StatelessWidget {
  final LogLevel? selected;
  final Map<LogLevel, int> counts;
  final ValueChanged<LogLevel?> onChanged;

  const _LevelFilterBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _LevelChip(
            label: '全部',
            count: total,
            isSelected: selected == null,
            color: null,
            onTap: () => onChanged(null),
          ),
          _LevelChip(
            label: 'DEBUG',
            count: counts[LogLevel.debug] ?? 0,
            isSelected: selected == LogLevel.debug,
            color: _levelColor(LogLevel.debug),
            onTap: () => onChanged(LogLevel.debug),
          ),
          _LevelChip(
            label: 'INFO',
            count: counts[LogLevel.info] ?? 0,
            isSelected: selected == LogLevel.info,
            color: _levelColor(LogLevel.info),
            onTap: () => onChanged(LogLevel.info),
          ),
          _LevelChip(
            label: 'WARN',
            count: counts[LogLevel.warning] ?? 0,
            isSelected: selected == LogLevel.warning,
            color: _levelColor(LogLevel.warning),
            onTap: () => onChanged(LogLevel.warning),
          ),
          _LevelChip(
            label: 'ERROR',
            count: counts[LogLevel.error] ?? 0,
            isSelected: selected == LogLevel.error,
            color: _levelColor(LogLevel.error),
            onTap: () => onChanged(LogLevel.error),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _LevelChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text('$label $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? c : cs.onSurfaceVariant,
            )),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: c.withValues(alpha: 0.15),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        side: BorderSide(
          color: isSelected
              ? c.withValues(alpha: 0.5)
              : cs.outlineVariant.withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 次级过滤栏（时间 + Tag）
// ──────────────────────────────────────────────

class _SecondaryFilterBar extends StatelessWidget {
  final _TimeRange timeRange;
  final String? selectedTag;
  final Map<String, int> tagCounts;
  final ValueChanged<_TimeRange> onTimeChanged;
  final ValueChanged<String?> onTagChanged;

  const _SecondaryFilterBar({
    required this.timeRange,
    required this.selectedTag,
    required this.tagCounts,
    required this.onTimeChanged,
    required this.onTagChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tags = tagCounts.keys.toList();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _MiniChip(
            label: '全部时间',
            isSelected: timeRange == _TimeRange.all,
            onTap: () => onTimeChanged(_TimeRange.all),
          ),
          _MiniChip(
            label: '今天',
            isSelected: timeRange == _TimeRange.today,
            onTap: () => onTimeChanged(_TimeRange.today),
          ),
          _MiniChip(
            label: '近 7 天',
            isSelected: timeRange == _TimeRange.week,
            onTap: () => onTimeChanged(_TimeRange.week),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: VerticalDivider(width: 1),
          ),
          _MiniChip(
            label: '全部标签',
            isSelected: selectedTag == null || selectedTag == '全部',
            onTap: () => onTagChanged(null),
          ),
          for (final t in tags)
            _MiniChip(
              label: '$t ·${tagCounts[t]}',
              isSelected: selectedTag == t,
              onTap: () => onTagChanged(t),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MiniChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isSelected
            ? cs.secondaryContainer.withValues(alpha: 0.7)
            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 搜索框
// ──────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onChanged('');
                      FocusScope.of(context).unfocus();
                    },
                  )
                : null,
            hintText: '搜索日志内容、标签…',
            hintStyle: TextStyle(color: cs.outline, fontSize: 13),
            filled: true,
            fillColor: _focused
                ? cs.primaryContainer.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 日志行（极简单行，性能最优）
//
// 原卡片有 Material+InkWell+DecoratedBox+IntrinsicHeight+Row+Wrap+
// 多个 _MetaTag+_HighlightedText(RichText)，每条卡片 widget 树深、
// 构建开销大，1500 条累积严重掉帧。
// 改为：单 Container（左侧色条 border）+ 两行纯 Text（等宽），
// 无 RichText/Wrap/Material，构建开销极低。
// ──────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final String keyword;

  const _LogRow({required this.entry, required this.keyword});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _levelColor(entry.level);
    final time = _timeFmt.format(entry.timestamp);
    final hasDetail =
        (entry.error?.isNotEmpty ?? false) ||
        (entry.stackTrace?.isNotEmpty ?? false);

    // 元信息行：[级别] [tag] 时间  →  纯文本拼接，避免多个 _MetaTag widget
    final metaLine = '${entry.level.label}  ${entry.tag}  $time';

    // 外层：均匀 Border + borderRadius（合法组合）
    // 色条：Stack + Positioned 拉高，无 IntrinsicHeight、无非均匀 Border
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          width: 1,
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: color),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 7, 10, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metaLine,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Roboto', 'sans-serif'],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface,
                    height: 1.45,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Roboto', 'sans-serif'],
                  ),
                  maxLines: hasDetail ? 8 : 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasDetail)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '长按查看详情',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static final _timeFmt = DateFormat('HH:mm:ss');
}

// ──────────────────────────────────────────────
// 空状态
// ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
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
                Icons.article_outlined,
                size: 44,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '暂无日志记录',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '使用应用功能后将自动记录到这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 级别颜色
// ──────────────────────────────────────────────

Color _levelColor(LogLevel l) => switch (l) {
      LogLevel.debug => const Color(0xFF8B9AAF),
      LogLevel.info => const Color(0xFF3B82F6),
      LogLevel.warning => const Color(0xFFF59E0B),
      LogLevel.error => const Color(0xFFEF4444),
    };
