import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/pages/dashboard_page.dart';
import 'package:mewmew/pages/memory_graph_page.dart';
import 'package:mewmew/pages/memory_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

Widget _host(AppState state, Widget page) {
  return MaterialApp(
    theme: AppTheme.lightTheme(),
    home: ChangeNotifierProvider<AppState>.value(value: state, child: page),
  );
}

Future<AppState> buildState() async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final state = AppState(storage);
  await state.load();
  return state;
}

/// 图谱页画布上带 painter 的 CustomPaint（painter 为私有类，走 dynamic 访问）
CustomPaint _graphPaint(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((c) => c.painter != null)
    .last;

Matrix4 _matrixOf(WidgetTester tester) =>
    (_graphPaint(tester).painter as dynamic).matrix as Matrix4;

/// 画布 RenderBox：局部坐标 → 全局坐标转换用（tapAt 接收全局坐标）
RenderBox _graphBox(WidgetTester tester) => tester.renderObject<RenderBox>(
  find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null),
);

Map<String, List<double>> _positionsOf(WidgetTester tester) =>
    (_graphPaint(tester).painter as dynamic).positions
        as Map<String, List<double>>;

/// 离所有节点最远的画布点（保证点在空白处）
Offset _blankPoint(WidgetTester tester, Size size) {
  final matrix = _matrixOf(tester);
  final scale = matrix.getMaxScaleOnAxis();
  final tx = matrix.storage[12];
  final ty = matrix.storage[13];
  final nodes = _positionsOf(
    tester,
  ).values.map((p) => Offset(p[0] * scale + tx, p[1] * scale + ty)).toList();
  Offset best = Offset.zero;
  var bestDistance = -1.0;
  for (final candidate in [
    Offset(size.width * 0.06, size.height * 0.08),
    Offset(size.width * 0.94, size.height * 0.08),
    Offset(size.width * 0.06, size.height * 0.9),
    Offset(size.width * 0.5, size.height * 0.95),
  ]) {
    final nearest = nodes
        .map((n) => (n - candidate).distance)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    if (nearest > bestDistance) {
      bestDistance = nearest;
      best = candidate;
    }
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('记忆图谱交互', () {
    testWidgets('点击节点立即弹出详情且画布矩阵不变（无点击延迟、无位移）', (tester) async {
      final state = await buildState();
      await state.addMemory('张三喜欢的食物是火锅', sessionId: 's1');
      await tester.pumpWidget(_host(state, const MemoryGraphPage()));
      await tester.pumpAndSettle();
      // 布局在 compute isolate 中计算，完成回调走真实事件循环
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      final matrix = _matrixOf(tester);
      final scale = matrix.getMaxScaleOnAxis();
      final p = _positionsOf(tester).values.first;
      final nodeLocal = Offset(
        p[0] * scale + matrix.storage[12],
        p[1] * scale + matrix.storage[13],
      );
      final nodeScreen = _graphBox(tester).localToGlobal(nodeLocal);

      await tester.tapAt(nodeScreen);
      // 单击立即生效：单帧内详情弹层已出现
      await tester.pump();
      expect(find.textContaining('条记忆'), findsOneWidget);
      // 画布位置保持不动
      expect(_matrixOf(tester).storage, matrix.storage);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('双击空白围绕点击点缓动放大，动画收敛后到位', (tester) async {
      final state = await buildState();
      await state.addMemory('张三喜欢的食物是火锅', sessionId: 's1');
      await tester.pumpWidget(_host(state, const MemoryGraphPage()));
      await tester.pumpAndSettle();
      // 布局在 compute isolate 中计算，完成回调走真实事件循环
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      final before = _matrixOf(tester).getMaxScaleOnAxis();
      final blankLocal = _blankPoint(tester, _graphBox(tester).size);
      final blank = _graphBox(tester).localToGlobal(blankLocal);

      await tester.tapAt(blank);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(blank);
      // 动画需要先 pump 起始帧再推进
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final mid = _matrixOf(tester).getMaxScaleOnAxis();
      expect(mid, greaterThan(before));
      expect(mid, lessThan(before * 1.8));

      await tester.pumpAndSettle();
      expect(
        _matrixOf(tester).getMaxScaleOnAxis(),
        closeTo(before * 1.8, 0.001),
      );

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('按钮缩放走缓动动画，可被连续点击打断重设目标', (tester) async {
      final state = await buildState();
      await state.addMemory('张三喜欢的食物是火锅', sessionId: 's1');
      await tester.pumpWidget(_host(state, const MemoryGraphPage()));
      await tester.pumpAndSettle();
      // 布局在 compute isolate 中计算，完成回调走真实事件循环
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      final before = _matrixOf(tester).getMaxScaleOnAxis();

      // 第一次放大动画进行中再次点放大 → 从当前矩阵重新出发
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await tester.tap(find.byTooltip('放大'));
      await tester.pumpAndSettle();
      final afterTwo = _matrixOf(tester).getMaxScaleOnAxis();
      expect(afterTwo, greaterThan(before * 1.3));
      expect(afterTwo, lessThan(before * 1.3 * 1.3 * 1.05));

      // 缩小一次再适配全图，动画收敛回适配缩放
      await tester.tap(find.byTooltip('缩小'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('适配全图'));
      await tester.pumpAndSettle();
      expect(_matrixOf(tester).getMaxScaleOnAxis(), closeTo(before, 0.001));

      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('编辑记忆弹窗主题芯片', () {
    testWidgets('回车与分隔符输入生成芯片、可删除、保存无需手动分隔', (tester) async {
      final state = await buildState();
      // 全局模式：AppBar 常驻「添加记忆」按钮（隔离模式下需先选中人物）
      state.memorySettings = state.memorySettings.copyWith(
        memoryScopeMode: 'global',
      );
      await tester.pumpWidget(_host(state, const MemoryPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('添加记忆'));
      await tester.pumpAndSettle();

      // 弹窗内输入框：内容(0)、主题(1)、关键事实(2)
      // （页面背后还有搜索框，必须限定 Dialog 范围）
      final dialogFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '张三喜欢火锅');
      // 主题：输入后点「添加」按钮
      await tester.enterText(dialogFields.at(1), '宠物');
      await tester.tap(find.byTooltip('添加'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('宠物'), findsOneWidget);

      // 输入含「、」的文本自动拆成两个芯片
      await tester.enterText(dialogFields.at(1), '饮食、偏好');
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(3));
      expect(find.text('饮食'), findsOneWidget);
      expect(find.text('偏好'), findsOneWidget);

      // 删除「宠物」芯片
      await tester.tap(
        find
            .descendant(
              of: find.byType(InputChip),
              matching: find.byIcon(Icons.close),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));

      // 保存：主题以芯片列表写入，无需分隔符
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(state.memories.first.content, '张三喜欢火锅');
      expect(state.memories.first.topics, ['饮食', '偏好']);

      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('仪表盘记忆卡片', () {
    testWidgets('渲染重要性柱状图与原子类型堆叠条，整理面板已移除', (tester) async {
      final state = await buildState();
      for (var i = 0; i < 6; i++) {
        final m = await state.addMemory('记忆条目$i：张三喜欢示例内容$i号');
        if (m != null) m.importance = 0.15 * i;
      }
      await tester.pumpWidget(_host(state, const DashboardPage()));
      await tester.pumpAndSettle();
      // 记忆卡片在懒加载 Sliver 深处，滚动到可见
      await tester.dragUntilVisible(
        find.text('重要性分布'),
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('重要性分布'), findsOneWidget);
      expect(find.text('原子类型分布'), findsOneWidget);
      // 柱状图档位标签（0-1 … 9-10）
      expect(find.text('0-1'), findsOneWidget);
      expect(find.text('9-10'), findsOneWidget);

      // 可跳转统计框带右上角跳转符号（总记忆/活跃/已归档/图谱节点）
      expect(find.byIcon(Icons.north_east_rounded), findsNWidgets(4));

      // 柱体几何：至少一根柱子宽高都 > 0（防止无 child 组件收缩为 0 不可见）
      final barSizes = find
          .byWidgetPredicate(
            (w) => w is FractionallySizedBox && w.heightFactor != null,
          )
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size)
          .toList();
      expect(barSizes, isNotEmpty);
      expect(
        barSizes.any((s) => s.width > 0 && s.height > 0),
        isTrue,
        reason: '重要性柱状图的柱体没有被渲染出来',
      );

      // 堆叠比例条几何：分段高度为条高 14、宽度 > 0
      final segmentSizes = find
          .byType(ColoredBox)
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size)
          .where((s) => s.height == 14)
          .toList();
      expect(segmentSizes, isNotEmpty);
      expect(
        segmentSizes.any((s) => s.width > 0),
        isTrue,
        reason: '原子类型堆叠条的分段没有被渲染出来',
      );

      // 原子类型图例：至少出现一种类型标签
      expect(state.memoryAtoms, isNotEmpty);
      expect(
        [
          '事实',
          '情节',
          '关系',
          '偏好',
          '计划',
          '未分类',
        ].any((l) => find.textContaining(l).evaluate().isNotEmpty),
        isTrue,
      );
      // 整理面板已删除
      expect(find.textContaining('自动整理'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
    });
  });
}
