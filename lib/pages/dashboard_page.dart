import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/large_app_bar_title.dart';

/// 全局仪表盘页面
class DashboardPage extends StatefulWidget {
  final bool scrollToMemory;
  const DashboardPage({super.key, this.scrollToMemory = false});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _scrollController = ScrollController();
  final _memoryCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToMemory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _memoryCardKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar.large(
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('仪表盘',
                style: largeAppBarTitleStyle(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _QuickStatsRow(),
                const SizedBox(height: 12),
                const _HeatMapCard(),
                const SizedBox(height: 12),
                const _TokenStatsCard(),
                const SizedBox(height: 12),
                _MemoryDashboardCard(key: _memoryCardKey),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 热力图
// ──────────────────────────────────────────────

/// 热力图共享配置：所有尺寸/颜色常量集中管理，避免多处重复定义
class _HeatMapConfig {
  static const double cellSize = 11.0;
  static const double gap = 3.0;
  static const double radius = 2.0;
  static const int weeksToShow = 53;
  static const int weekdays = 7;
  static double get cellStep => cellSize + gap;
  static double get gridWidth => weeksToShow * cellStep;
  static double get gridHeight => weekdays * cellStep;

  /// 按消息数量映射到 0-4 级别
  static int levelOf(int count, int maxCount) {
    if (count == 0 || maxCount == 0) return 0;
    return (count / maxCount * 4).ceil().clamp(0, 4);
  }

  /// 级别到颜色插值系数（0=空，1-4=由浅到深）
  static double tOf(int level) => switch (level) {
        0 => 0.0,
        1 => 0.28,
        2 => 0.5,
        3 => 0.72,
        _ => 0.95,
      };

  /// 由级别生成颜色
  static Color colorOf(ColorScheme cs, int level) {
    if (level == 0) return cs.surfaceContainerHigh;
    return Color.lerp(cs.surfaceContainerHigh, cs.primary, tOf(level))!;
  }
}

class _HeatMapCard extends StatelessWidget {
  const _HeatMapCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final heatData = _buildHeatMapData(state.sessions);
    final maxCount = heatData.values.fold<int>(0, (m, v) => v > m ? v : m);

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    // 今天所在周的周一，确保最后一周包含今天
    final todayWeekStart =
        todayDate.subtract(Duration(days: todayDate.weekday - 1));
    // 网格起始：从今天所在周往回数 (weeksToShow-1) 周
    final adjustedStart = todayWeekStart
        .subtract(Duration(days: (_HeatMapConfig.weeksToShow - 1) * 7));

    // 统计摘要
    final stats = _computeStats(heatData, adjustedStart, todayDate);

    return _Card(
      title: '聊天热力图',
      icon: Icons.calendar_view_week_rounded,
      color: cs.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部统计摘要行
          _StatsRow(stats: stats),
          const SizedBox(height: 14),
          // 热力图网格（横向滚动，默认显示最近）
          SizedBox(
            height: _HeatMapConfig.gridHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: _HeatMapGrid(
                startDate: adjustedStart,
                heatData: heatData,
                maxCount: maxCount,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例：左侧"今天"说明，右侧颜色梯度
          Row(
            children: [
              // 今天标记说明
              Container(
                width: _HeatMapConfig.cellSize,
                height: _HeatMapConfig.cellSize,
                decoration: BoxDecoration(
                  color: Color.lerp(
                      cs.surfaceContainerHigh, cs.primary, 0.15),
                  borderRadius:
                      BorderRadius.circular(_HeatMapConfig.radius),
                  border: Border.all(color: cs.primary, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text('今天', style: TextStyle(fontSize: 11, color: cs.outline)),
              const Spacer(),
              Text('少', style: TextStyle(fontSize: 11, color: cs.outline)),
              const SizedBox(width: 4),
              for (int i = 0; i <= 4; i++)
                Container(
                  width: _HeatMapConfig.cellSize,
                  height: _HeatMapConfig.cellSize,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: _HeatMapConfig.colorOf(cs, i),
                    borderRadius:
                        BorderRadius.circular(_HeatMapConfig.radius),
                  ),
                ),
              const SizedBox(width: 2),
              Text('多', style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ),
        ],
      ),
    );
  }

  /// 计算热力图统计摘要
  _HeatMapStats _computeStats(
    Map<DateTime, int> heatData,
    DateTime startDate,
    DateTime todayDate,
  ) {
    int totalMessages = 0;
    int activeDays = 0;
    int longestStreak = 0;
    int currentStreak = 0;
    int thisWeekMessages = 0;

    final todayWeekStart =
        todayDate.subtract(Duration(days: todayDate.weekday - 1));

    // 按日期排序遍历，计算连续天数
    final sortedDates = heatData.keys.toList()..sort();
    for (final date in sortedDates) {
      final count = heatData[date]!;
      if (count > 0) {
        totalMessages += count;
        activeDays++;
        // 本周消息
        if (!date.isBefore(todayWeekStart) &&
            !date.isAfter(todayDate)) {
          thisWeekMessages += count;
        }
      }
    }

    // 计算最长连续天数（从 startDate 到今天逐日检查）
    DateTime cursor = startDate;
    while (!cursor.isAfter(todayDate)) {
      if ((heatData[cursor] ?? 0) > 0) {
        currentStreak++;
        if (currentStreak > longestStreak) {
          longestStreak = currentStreak;
        }
      } else {
        currentStreak = 0;
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    return _HeatMapStats(
      totalMessages: totalMessages,
      activeDays: activeDays,
      longestStreak: longestStreak,
      thisWeekMessages: thisWeekMessages,
    );
  }

  Map<DateTime, int> _buildHeatMapData(List sessions) {
    final data = <DateTime, int>{};
    for (final session in sessions) {
      for (final msg in session.messages) {
        final date = DateTime(
          msg.timestamp.year,
          msg.timestamp.month,
          msg.timestamp.day,
        );
        data[date] = (data[date] ?? 0) + 1;
      }
    }
    return data;
  }
}

/// 热力图统计摘要
class _HeatMapStats {
  final int totalMessages;
  final int activeDays;
  final int longestStreak;
  final int thisWeekMessages;

  const _HeatMapStats({
    required this.totalMessages,
    required this.activeDays,
    required this.longestStreak,
    required this.thisWeekMessages,
  });
}

/// 顶部统计行：四个关键指标横排
class _StatsRow extends StatelessWidget {
  final _HeatMapStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      _StatItem(
        icon: Icons.calendar_today_rounded,
        label: '活跃天',
        value: '${stats.activeDays}',
        color: cs.tertiary,
      ),
      _StatItem(
        icon: Icons.local_fire_department_rounded,
        label: '最长连续',
        value: '${stats.longestStreak}天',
        color: cs.error,
      ),
      _StatItem(
        icon: Icons.date_range_rounded,
        label: '本周',
        value: _formatNum(stats.thisWeekMessages),
        color: cs.secondary,
      ),
    ];
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

/// 单个统计项
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.outline,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeatMapGrid extends StatelessWidget {
  final DateTime startDate;
  final Map<DateTime, int> heatData;
  final int maxCount;

  const _HeatMapGrid({
    required this.startDate,
    required this.heatData,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return CustomPaint(
      size: Size(
        _HeatMapConfig.gridWidth,
        _HeatMapConfig.gridHeight,
      ),
      painter: _HeatMapPainter(
        startDate: startDate,
        heatData: heatData,
        maxCount: maxCount,
        baseColor: cs.primary,
        emptyColor: cs.surfaceContainerHigh,
        today: today,
      ),
    );
  }
}

/// 热力图绘制器：一次性绘制所有格子，避免大量独立 widget
class _HeatMapPainter extends CustomPainter {
  final DateTime startDate;
  final Map<DateTime, int> heatData;
  final int maxCount;
  final Color baseColor;
  final Color emptyColor;
  final DateTime today;

  _HeatMapPainter({
    required this.startDate,
    required this.heatData,
    required this.maxCount,
    required this.baseColor,
    required this.emptyColor,
    required this.today,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellPaint = Paint()..style = PaintingStyle.fill;
    final todayDate = DateTime(today.year, today.month, today.day);
    final cellStep = _HeatMapConfig.cellStep;
    final cellSize = _HeatMapConfig.cellSize;
    final radius = Radius.circular(_HeatMapConfig.radius);

    for (int w = 0; w < _HeatMapConfig.weeksToShow; w++) {
      for (int d = 0; d < 7; d++) {
        final date = startDate.add(Duration(days: w * 7 + d));
        final dateOnly = DateTime(date.year, date.month, date.day);
        final count = heatData[dateOnly] ?? 0;
        final x = w * cellStep;
        final y = d * cellStep;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          radius,
        );

        final level = _HeatMapConfig.levelOf(count, maxCount);
        final isToday = dateOnly == todayDate;

        if (level == 0) {
          cellPaint.color = emptyColor;
        } else {
          cellPaint.color =
              Color.lerp(emptyColor, baseColor, _HeatMapConfig.tOf(level))!;
        }
        canvas.drawRRect(rect, cellPaint);

        // 今天的高亮边框（加粗 + 深色，确保可见）
        if (isToday) {
          final borderPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = baseColor;
          canvas.drawRRect(rect.deflate(0.75), borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatMapPainter oldDelegate) =>
      oldDelegate.startDate != startDate ||
      oldDelegate.maxCount != maxCount ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.today != today ||
      !_mapEquals(oldDelegate.heatData, heatData);

  // 浅比较 Map 键值，避免每次都重绘
  static bool _mapEquals(Map<DateTime, int> a, Map<DateTime, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }
}

// ──────────────────────────────────────────────
// 快速统计横排
// ──────────────────────────────────────────────
class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    final totalSessions = state.sessions.length;
    final totalMessages = state.sessions.fold<int>(
        0, (sum, s) => sum + s.messages.length);
    final totalPersonas = state.personas.length;
    final totalGroups = state.groupChats.length;

    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            icon: Icons.chat_bubble_outline_rounded,
            color: cs.primary,
            value: '$totalSessions',
            label: '对话',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStat(
            icon: Icons.message_outlined,
            color: cs.tertiary,
            value: '$totalMessages',
            label: '消息',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStat(
            icon: Icons.face_outlined,
            color: cs.secondary,
            value: '$totalPersonas',
            label: '人格',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStat(
            icon: Icons.group_outlined,
            color: cs.primary,
            value: '$totalGroups',
            label: '群聊',
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Token 统计（柱状图 + 文字说明）
// ──────────────────────────────────────────────
class _TokenStatsCard extends StatelessWidget {
  const _TokenStatsCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    final input = state.tokenUsage.inputTokens;
    final output = state.tokenUsage.outputTokens;
    final cached = state.tokenUsage.cachedTokens;
    final total = input + output;

    // 近7天数据
    final dailyData = _buildLast7Days(state.tokenUsage.dailyRecords);

    return _Card(
      title: 'Token 使用',
      icon: Icons.token_outlined,
      color: cs.tertiary,
      trailing: Text(
        _formatTokens(total),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.tertiary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 柱状图（点击查看详细信息）
          GestureDetector(
            onTap: () => _showDailyDetail(context, dailyData),
            child: SizedBox(
              height: 140,
              child: CustomPaint(
              painter: _TokenBarChartPainter(
                data: dailyData,
                inputColor: cs.primary,
                outputColor: cs.tertiary,
                cachedColor: cs.secondary,
                gridColor: cs.outlineVariant.withValues(alpha: 0.35),
                textColor: cs.outline,
              ),
                size: const Size(double.infinity, 140),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例与数值
          Row(
            children: [
              _LegendDot(color: cs.primary, label: '输入'),
              const SizedBox(width: 16),
              _LegendDot(color: cs.secondary, label: '缓存'),
              const SizedBox(width: 16),
              _LegendDot(color: cs.tertiary, label: '输出'),
            ],
          ),
          const SizedBox(height: 10),
          // 详细数值
          Row(
            children: [
              Expanded(
                child: _TokenValueLine(
                  label: '输入',
                  value: input,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TokenValueLine(
                  label: '缓存',
                  value: cached,
                  color: cs.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TokenValueLine(
                  label: '输出',
                  value: output,
                  color: cs.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.functions_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '累计 Token ${_formatTokens(total)}',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.rocket_launch_outlined, size: 16, color: cs.outline),
              const SizedBox(width: 6),
              Text(
                '累计调用 ${state.appLaunchCount} 次',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 点击柱状图弹出近7天每日详细信息
  void _showDailyDetail(BuildContext context, List<_DayTokenData> data) {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.token_outlined, color: cs.tertiary, size: 22),
              const SizedBox(width: 8),
              const Text(
                '近7天 Token 详情',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in data)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            d.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.outline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _DetailChip(
                                label: '输入',
                                value: _formatTokens(d.input),
                                color: cs.primary,
                              ),
                              _DetailChip(
                                label: '缓存',
                                value: _formatTokens(d.cached),
                                color: cs.secondary,
                              ),
                              _DetailChip(
                                label: '输出',
                                value: _formatTokens(d.output),
                                color: cs.tertiary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '合计',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.outline,
                      ),
                    ),
                    Text(
                      _formatTokens(data.fold<int>(
                          0, (sum, d) => sum + d.total)),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 生成近7天数据（含空日期补0）
  List<_DayTokenData> _buildLast7Days(List<DailyTokenUsage> records) {
    final result = <_DayTokenData>[];
    final today = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final key =
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final match = records.firstWhere(
        (r) => r.date ==
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        orElse: () => DailyTokenUsage(date: key),
      );
      result.add(_DayTokenData(
        label: key,
        input: match.inputTokens,
        output: match.outputTokens,
        cached: match.cachedTokens,
      ));
    }
    return result;
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(2)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }
}

class _DayTokenData {
  final String label;
  final int input; // 含缓存的输入（即 prompt_tokens）
  final int output;
  final int cached; // 缓存命中的部分（已包含在 input 中）
  _DayTokenData({
    required this.label,
    this.input = 0,
    this.output = 0,
    this.cached = 0,
  });
  // 柱子总高度只按 input + output 计算，避免缓存被重复计算
  int get total => input + output;
  // 实际新输入 = input - cached
  int get freshInput => (input - cached).clamp(0, input);
}

/// Token 柱状图绘制器
class _TokenBarChartPainter extends CustomPainter {
  final List<_DayTokenData> data;
  final Color inputColor;
  final Color outputColor;
  final Color cachedColor;
  final Color gridColor;
  final Color textColor;

  _TokenBarChartPainter({
    required this.data,
    required this.inputColor,
    required this.outputColor,
    required this.cachedColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.map((d) => d.total).reduce((a, b) => a > b ? a : b);
    final chartH = size.height - 20; // 底部留 20 给日期
    final barW = (size.width - (data.length + 1) * 8) / data.length;
    final barGap = 8.0;

    final paint = Paint()..style = PaintingStyle.fill;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    // 画3条水平网格线
    for (int i = 1; i <= 3; i++) {
      final y = chartH * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (maxVal == 0) {
      // 从未做过 Token 使用时：显示空网格和 7 天日期基准
      for (int i = 0; i < data.length; i++) {
        final d = data[i];
        final x = barGap + i * (barW + barGap);
        paint.color = gridColor.withValues(alpha: 0.15);
        canvas.drawRect(
          Rect.fromLTWH(x, chartH - 2, barW, 2),
          paint,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: d.label,
            style: TextStyle(fontSize: 9, color: textColor),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(
          canvas,
          Offset(x + (barW - tp.width) / 2, chartH + 4),
        );
      }
      return;
    }

    // 画每天柱子（三段：底部缓存、中间新输入、顶部输出）
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final x = barGap + i * (barW + barGap);

      if (d.total == 0) {
        paint.color = gridColor.withValues(alpha: 0.3);
        canvas.drawRect(
          Rect.fromLTWH(x, chartH - 4, barW, 4),
          paint,
        );
      } else {
        final barH = (d.total / maxVal) * (chartH - 4);
        // 缓存是输入的子集，不重复计算：输入段拆为 freshInput + cached
        final cachedH = (d.cached / d.total) * barH;
        final freshH = (d.freshInput / d.total) * barH;
        final outputH = barH - freshH - cachedH;
        var top = chartH - barH;

        // 缓存段（最底部）
        if (cachedH > 0) {
          paint.color = cachedColor;
          canvas.drawRect(
            Rect.fromLTWH(x, top + freshH + outputH, barW, cachedH),
            paint,
          );
        }
        // 新输入段（中间）
        if (freshH > 0) {
          paint.color = inputColor;
          canvas.drawRect(
            Rect.fromLTWH(x, top + outputH, barW, freshH),
            paint,
          );
        }
        // 输出段（顶部）
        if (outputH > 0) {
          paint.color = outputColor;
          canvas.drawRect(
            Rect.fromLTWH(x, top, barW, outputH),
            paint,
          );
        }
      }

      // 日期标签
      final tp = TextPainter(
        text: TextSpan(
          text: d.label,
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(x + (barW - tp.width) / 2, chartH + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TokenBarChartPainter old) =>
      old.data != data;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _TokenValueLine extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _TokenValueLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        Text(
          _formatTokens(value),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(2)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return '$tokens';
  }
}

/// 详情弹窗中的带色小标签
class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DetailChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 记忆系统仪表盘
// ──────────────────────────────────────────────
class _MemoryDashboardCard extends StatelessWidget {
  const _MemoryDashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    final isMemoryEnabled =
        state.injectMemories && state.embeddingApiConfig.isValid;

    final total = state.memories.length;
    final manual = state.memories.where((m) => m.source == 'manual').length;
    final auto = state.memories.where((m) => m.source == 'auto').length;
    final summary = state.memories.where((m) => m.source == 'summary').length;

    // 1. 今日新增记忆
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayCount = state.memories
        .where((m) => !m.createdAt.isBefore(todayStart))
        .length;

    // 2. 每会话平均记忆数（计算有记忆或存在的会话数）
    final sessionIdsWithMemory = state.memories
        .map((m) => m.sessionId)
        .whereType<String>()
        .toSet();
    final activeSessionCount = sessionIdsWithMemory.isNotEmpty
        ? sessionIdsWithMemory.length
        : (state.sessions.isNotEmpty ? state.sessions.length : 1);
    final avgPerSession = (total / activeSessionCount).toStringAsFixed(1);

    // 3. 最活跃的会话 (Top 10)
    final top10Sessions = _getTop10Sessions(state);

    // 4. 近7天每日记忆新增趋势
    final dailyTrend = _getDailyMemoryTrend(state.memories);

    return _Card(
      title: '记忆系统',
      icon: Icons.psychology_outlined,
      color: cs.primary,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isMemoryEnabled
              ? cs.primaryContainer
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          isMemoryEnabled ? '总计 $total 条' : '未开启',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isMemoryEnabled ? cs.onPrimaryContainer : cs.outline,
          ),
        ),
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: isMemoryEnabled
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        firstChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 4大核心指标卡片网络
            Row(
              children: [
                Expanded(
                  child: _MemoryStatBox(
                    label: '总记忆数',
                    value: '$total',
                    icon: Icons.psychology_outlined,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MemoryStatBox(
                    label: '今日新增',
                    value: '+$todayCount',
                    icon: Icons.today_rounded,
                    color: cs.tertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MemoryStatBox(
                    label: '每会话平均',
                    value: avgPerSession,
                    icon: Icons.auto_awesome_motion_rounded,
                    color: cs.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 近7天记忆增长趋势图 (折线图 - 缩窄对齐上方的柱状图)
            Text(
              '近7天记忆增长趋势',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 110,
                child: CustomPaint(
                  size: const Size(double.infinity, 110),
                  painter: _MemoryTrendPainter(
                    data: dailyTrend,
                    lineColor: cs.primary,
                    dotColor: cs.tertiary,
                    textColor: cs.outline,
                    gridColor: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 最活跃会话 (Top 10 记忆分布)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最活跃会话 (Top 10)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (top10Sessions.isNotEmpty)
                  Text(
                    '包含 ${top10Sessions.length} 个活跃会话',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (top10Sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '暂无会话记忆关联数据',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < top10Sessions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _TopSessionRow(
                        rank: i + 1,
                        name: top10Sessions[i].name,
                        count: top10Sessions[i].count,
                        maxCount: top10Sessions.first.count,
                        isGroup: top10Sessions[i].isGroup,
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 来源分布条
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      _barSegment(cs.primary, manual / total),
                      _barSegment(cs.tertiary, auto / total),
                      _barSegment(cs.secondary, summary / total),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // 图例
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _Legend(color: cs.primary, label: '手动 $manual'),
                _Legend(color: cs.tertiary, label: 'AI自动 $auto'),
                _Legend(color: cs.secondary, label: '总结 $summary'),
              ],
            ),
            const SizedBox(height: 14),
            // 配置信息
            _InfoRow(
              icon: Icons.filter_alt_outlined,
              label: '会话过滤',
              value:
                  state.memorySettings.useSessionFiltering ? '会话隔离' : '全局共享',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.summarize_outlined,
              label: '自动总结阈值',
              value: '${state.memorySettings.summaryThreshold} 轮',
            ),
          ],
        ),
        secondChild: const SizedBox.shrink(),
      ),
    );
  }

  Widget _barSegment(Color color, double ratio) {
    return Flexible(
      flex: (ratio * 1000).round().clamp(1, 1000),
      child: Container(color: color),
    );
  }

  /// 获取记忆最多的 Top 10 会话列表
  List<_TopSessionItem> _getTop10Sessions(AppState state) {
    final sessionCountMap = <String, int>{};
    for (final m in state.memories) {
      if (m.sessionId != null) {
        sessionCountMap[m.sessionId!] =
            (sessionCountMap[m.sessionId!] ?? 0) + 1;
      }
    }

    if (sessionCountMap.isEmpty) return [];

    final sessionById = {for (final s in state.sessions) s.id: s};
    final groupById = {for (final g in state.groupChats) g.id: g};

    final items = <_TopSessionItem>[];
    sessionCountMap.forEach((sessionId, count) {
      final session = sessionById[sessionId];
      String name = '未知会话';
      bool isGroup = false;

      if (session != null) {
        if (session.groupChatId != null) {
          name = groupById[session.groupChatId]?.name ?? '群聊';
          isGroup = true;
        } else if (session.personaId != null) {
          final persona = state.personaById(session.personaId);
          name = persona != null ? '与 ${persona.name}' : '私聊';
        }
      }

      items.add(_TopSessionItem(name: name, count: count, isGroup: isGroup));
    });

    items.sort((a, b) => b.count.compareTo(a.count));
    return items.take(10).toList();
  }

  /// 获取近7天每日新增记忆数
  List<_DailyMemoryPoint> _getDailyMemoryTrend(List<MemoryEntry> memories) {
    final result = <_DailyMemoryPoint>[];
    final today = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));

      final count = memories
          .where(
            (m) =>
                !m.createdAt.isBefore(dateStart) &&
                m.createdAt.isBefore(dateEnd),
          )
          .length;

      final label =
          '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      result.add(_DailyMemoryPoint(label: label, count: count));
    }

    return result;
  }
}

class _TopSessionItem {
  final String name;
  final int count;
  final bool isGroup;
  _TopSessionItem({
    required this.name,
    required this.count,
    required this.isGroup,
  });
}

class _DailyMemoryPoint {
  final String label;
  final int count;
  _DailyMemoryPoint({required this.label, required this.count});
}

/// 记忆小指标框
class _MemoryStatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MemoryStatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top 10 会话条目行
class _TopSessionRow extends StatelessWidget {
  final int rank;
  final String name;
  final int count;
  final int maxCount;
  final bool isGroup;

  const _TopSessionRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.maxCount,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: rank <= 3 ? cs.primary : cs.outline,
            ),
          ),
        ),
        Icon(
          isGroup ? Icons.group_outlined : Icons.person_outline,
          size: 13,
          color: isGroup ? cs.tertiary : cs.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: isGroup ? cs.tertiary : cs.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '$count条',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 每日记忆趋势折线/点图绘制器
class _MemoryTrendPainter extends CustomPainter {
  final List<_DailyMemoryPoint> data;
  final Color lineColor;
  final Color dotColor;
  final Color textColor;
  final Color gridColor;

  _MemoryTrendPainter({
    required this.data,
    required this.lineColor,
    required this.dotColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    final chartH = size.height - 22;
    final stepX = size.width / (data.length - 1);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    // 画网格背景
    for (int i = 1; i <= 2; i++) {
      final y = chartH * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = maxVal == 0
          ? chartH
          : chartH - (data[i].count / maxVal) * (chartH - 12);
      points.add(Offset(x, y));

      // X 轴日期
      final tp = TextPainter(
        text: TextSpan(
          text: data[i].label,
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartH + 6));
    }

    // 绘制趋势折线
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);

    // 绘制数据圆点及数值
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 3.0, dotPaint);

      if (data[i].count > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${data[i].count}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: lineColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MemoryTrendPainter old) =>
      old.data != data || old.lineColor != lineColor;
}

// ──────────────────────────────────────────────
// 通用组件
// ──────────────────────────────────────────────
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.color,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.outline),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
