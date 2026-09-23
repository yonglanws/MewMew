import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    return state;
  }

  MemoryEntry memory(
    String id, {
    String content = '内容',
    String status = 'active',
    String? sessionId,
  }) => MemoryEntry(
    id: id,
    content: content,
    createdAt: DateTime(2025, 11, 19),
    personaId: null,
    sessionId: sessionId,
    status: status,
  );

  group('记忆图谱页', () {
    testWidgets('空图谱显示占位提示', (tester) async {
      final state = await buildState();
      await tester.pumpWidget(_host(state, const MemoryGraphPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无图谱数据'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('有图谱数据时渲染节点画布并统计', (tester) async {
      final state = await buildState();
      state.memories.add(memory('m1', content: '张三喜欢的食物是火锅'));
      state.memorySettings = state.memorySettings.copyWith(graphEnabled: true);
      await state.addMemory('张三喜欢的食物是火锅', sessionId: 's1');
      await tester.pumpWidget(_host(state, const MemoryGraphPage()));
      await tester.pumpAndSettle();
      // addMemory 会生成原子并入图（statBox 中节点数 > 0）
      expect(state.graphStore.nodeCount, greaterThan(0));
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('记忆页归档分区', () {
    testWidgets('归档记忆折叠展示，展开后可见', (tester) async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(
        useSessionFiltering: false,
      );
      state.memories.addAll([
        memory('active-1', content: '活跃记忆甲'),
        memory('archived-1', content: '归档记忆乙', status: 'archived'),
      ]);
      await tester.pumpWidget(_host(state, const MemoryPage()));
      await tester.pumpAndSettle();

      // 活跃记忆直接可见；归档分区折叠存在但内容不可见
      expect(find.textContaining('活跃记忆甲'), findsOneWidget);
      expect(find.text('已归档记忆'), findsOneWidget);
      expect(find.textContaining('归档记忆乙'), findsNothing);

      // 展开后归档内容可见
      await tester.tap(find.text('已归档记忆'));
      await tester.pumpAndSettle();
      expect(find.textContaining('归档记忆乙'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('记忆卡片（重写版）', () {
    testWidgets('正文为主：来源徽章、重要性条、时间分层呈现', (tester) async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(
        useSessionFiltering: false,
      );
      final m = memory('m1', content: '张三喜欢的食物是火锅')..importance = 0.62;
      m.accessCount = 6;
      m.topics = ['饮食', '偏好'];
      state.memories.add(m);
      await tester.pumpWidget(_host(state, const MemoryPage()));
      await tester.pumpAndSettle();

      // 来源徽章（手动记忆）+ 重要性数值 + 热度 + 主题芯片
      expect(find.textContaining('张三喜欢的食物是火锅'), findsOneWidget);
      expect(find.text('手动'), findsOneWidget);
      expect(find.text('0.62'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('饮食'), findsOneWidget);
      expect(find.text('偏好'), findsOneWidget);

      // 重要性迷你进度条几何：56x4，且填充段宽高均大于 0
      final bars = find
          .byWidgetPredicate(
            (w) =>
                w is FractionallySizedBox &&
                w.widthFactor != null &&
                w.heightFactor == null,
          )
          .evaluate()
          .map((e) => (e.renderObject! as RenderBox).size)
          .where((s) => s.height == 4)
          .toList();
      expect(bars, isNotEmpty);
      expect(
        bars.any((s) => s.width > 0),
        isTrue,
        reason: '重要性进度条没有被渲染出来',
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('正文超长时最多显示 4 行并省略，不撑爆卡片', (tester) async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(
        useSessionFiltering: false,
      );
      state.memories.add(
        memory('long-1', content: '这是一条很长的记忆，' * 30),
      );
      await tester.pumpWidget(_host(state, const MemoryPage()));
      await tester.pumpAndSettle();

      final richTexts = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((r) => (r.text as TextSpan).text!.contains('这是一条很长的记忆'))
          .toList();
      expect(richTexts, isNotEmpty);
      expect(richTexts.first.maxLines, 4);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
