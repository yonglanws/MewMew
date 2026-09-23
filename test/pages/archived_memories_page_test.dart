import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/archived_memories_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

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

  testWidgets('归档卡片元信息与按钮不溢出（窄屏回归）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.memories.add(
      MemoryEntry(
        id: 'arch-1',
        content: '用户喜欢在深夜聊关于动画制作流程的话题',
        createdAt: DateTime(2026, 9, 20, 23, 58),
        status: 'archived',
        importance: 0.72,
      ),
    );
    // 窄屏：旧版"元信息 + Spacer + 两个按钮"会 RenderFlex 溢出
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const ArchivedMemoriesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 溢出会以异常形式抛出，能走到这里说明布局无溢出
    expect(tester.takeException(), isNull);
    expect(find.textContaining('归档于 2026-09-20'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 恢复按钮仍可用
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(state.memories.first.status, 'active');
    await tester.pump(const Duration(seconds: 2));
  });
}
