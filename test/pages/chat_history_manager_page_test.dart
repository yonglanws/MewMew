import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/chat_history_manager_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  Future<AppState> buildStateWithSessions() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    final now = DateTime(2026, 9, 23);
    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.sessions = [
      ChatSession(
        id: 's1',
        title: '和小林的私聊',
        personaId: 'p1',
        messages: [
          ChatMessage(
            id: 'u1',
            role: 'user',
            content: '早上好',
            timestamp: now,
          ),
          ChatMessage(
            id: 'a1',
            role: 'assistant',
            content: '早哇',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      ChatSession(
        id: 's2',
        title: '摸鱼群',
        groupChatId: 'g1',
        messages: [],
        createdAt: now,
        updatedAt: now,
      ),
      ChatSession(
        id: 's3',
        title: '另一个会话',
        personaId: 'p1',
        messages: [
          ChatMessage(
            id: 'u2',
            role: 'user',
            content: '在吗',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
    state.groupChats = [GroupChat(id: 'g1', name: '摸鱼群', personaIds: [])];
    return state;
  }

  Widget host(AppState state) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const ChatHistoryManagerPage(),
    ),
  );

  testWidgets('按会话列出聊天记录：标题、消息数、最后时间', (tester) async {
    final state = await buildStateWithSessions();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));

    expect(find.text('和小林的私聊'), findsOneWidget);
    expect(find.textContaining('2 条消息'), findsOneWidget);
    expect(find.text('摸鱼群'), findsOneWidget);
    expect(find.textContaining('0 条消息'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('点击会话行选择，删除按钮显示数量', (tester) async {
    final state = await buildStateWithSessions();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));

    // 未选择时按钮置灰（IgnorePointer + 文案"删除"）
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('和小林的私聊'));
    await tester.pumpAndSettle();
    expect(find.text('删除 (1)'), findsOneWidget);

    // 再点取消选择
    await tester.tap(find.text('和小林的私聊'));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('全选后批量删除全部会话', (tester) async {
    final state = await buildStateWithSessions();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('删除 (3)'), findsOneWidget);

    await tester.tap(find.text('删除 (3)'));
    await tester.pumpAndSettle();
    // 确认弹窗
    expect(find.text('删除聊天记录'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(state.sessions, isEmpty);
    expect(find.text('还没有聊天记录'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('部分选择删除只删所选', (tester) async {
    final state = await buildStateWithSessions();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('和小林的私聊'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(state.sessions.length, 2);
    expect(state.sessions.any((s) => s.id == 's1'), isFalse);
    expect(find.text('已删除 1 个会话的聊天记录'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });
}
