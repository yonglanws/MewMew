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
    home: ChangeNotifierProvider<AppState>.value(
      value: state,
      child: page,
    ),
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
  }) =>
      MemoryEntry(
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
      state.memorySettings =
          state.memorySettings.copyWith(graphEnabled: true);
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
      state.memorySettings =
          state.memorySettings.copyWith(useSessionFiltering: false);
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
}
