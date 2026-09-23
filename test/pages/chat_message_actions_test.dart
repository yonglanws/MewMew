import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/chat_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

/// 聊天页长按消息菜单（复制/引用/删除/多选）与引用发送的交互测试
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> buildState() async {
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
            id: 'a1',
            role: 'assistant',
            content: '周末去漫展吗',
            timestamp: now,
            speakerId: 'p1',
          ),
          ChatMessage(id: 'u1', role: 'user', content: '去！买票了吗', timestamp: now),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
    state.currentSessionId = 's1';
    return state;
  }

  Widget host(AppState state) => ChangeNotifierProvider.value(
    value: state,
    child: const MaterialApp(home: ChatPage()),
  );

  testWidgets('长按消息弹出浅色主题悬浮菜单：复制/引用/删除/多选', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a1')).first);
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);

    // 面板是浅色主题材质（surfaceContainerLow），不再使用深色固定色
    final expectedColor = Theme.of(
      tester.element(find.text('复制')),
      // 面板在 Overlay 中，取任意 element 的主题
    ).colorScheme.surfaceContainerLow;
    final panelMaterials = tester
        .widgetList<Material>(find.byType(Material))
        .where((m) => m.color != null)
        .toList();
    expect(
      panelMaterials.any((m) => m.color == expectedColor),
      isTrue,
      reason: '悬浮菜单应为浅色主题面板',
    );
  });

  testWidgets('长按消息文字也能触发菜单（手势不被文本选择抢走）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    // 直接长按文字本身（而非气泡空白区）
    await tester.longPress(find.text('周末去漫展吗'));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
  });

  testWidgets('长按菜单打开期间消息不做任何高亮，点面板外关闭', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a1')).first);
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);

    // 不再有整块蒙层 / 文字选区高亮
    expect(find.byKey(const ValueKey('msg-highlight-a1')), findsNothing);

    // 点面板外关闭
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('复制：拷贝整条消息文字并提示', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a1')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('引用：输入框上方出现引用条，发送后消息携带引用', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    // 群聊未 @ 不触发回复，消息与引用直接落库便于验证
    state.groupChats = [GroupChat(id: 'g1', name: '摸鱼群', personaIds: ['p1'])];
    final groupSession = ChatSession(
      id: 'g1s00000-0000-0000',
      title: '摸鱼群',
      groupChatId: 'g1',
      messages: state.sessions.first.messages,
      createdAt: DateTime(2026, 9, 23),
      updatedAt: DateTime(2026, 9, 23),
    );
    state.sessions
      ..clear()
      ..add(groupSession);
    state.currentSessionId = 'g1s00000-0000-0000';

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a1')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();

    // 引用条出现在输入区上方（发言角色名）
    expect(find.text('引用 小林玖奈'), findsOneWidget);
    expect(find.textContaining('周末去漫展吗'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, '去！');
    await tester.pump();
    // 发送按钮
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    final session = state.sessions.first;
    final lastMsg = session.messages.last;
    expect(lastMsg.role, 'user');
    expect(lastMsg.quote, isNotNull);
    expect(lastMsg.quote!.text, '周末去漫展吗');
    // 引用条已随发送清除（气泡内的引用块保留）
    expect(find.byKey(const ValueKey('quote-bar')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('删除：确认后消息从会话中移除', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('u1')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除消息'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(state.sessions.first.messages.any((m) => m.id == 'u1'), isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('多选：进入选择模式，点文字区域即选中，批量删除', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a1')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    // 进入多选：标题计数 + 底部操作栏
    expect(find.text('已选 1 条'), findsWidgets);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsWidgets);

    // 点第二条消息的文字区域即选中（AbsorbPointer 吸收内容手势）
    await tester.tap(find.text('去！买票了吗'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsWidgets);

    // 全选 / 取消全选（AppBar 与底栏都有入口，取 AppBar 的）
    await tester.tap(find.text('取消全选').first);
    await tester.pumpAndSettle();
    expect(find.text('已选 0 条'), findsWidgets);
    await tester.tap(find.text('全选').first);
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsWidgets);

    // 批量删除（确认）——TextButton.icon 是私有子类，直接按文本点
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(state.sessions.first.messages, isEmpty);
    // 删除完成自动退出多选
    expect(find.text('已选 2 条'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('气泡内展示引用块', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    state.sessions.first.messages.add(
      ChatMessage(
        id: 'u2',
        role: 'user',
        content: '去！',
        timestamp: DateTime(2026, 9, 23),
        quote: MessageQuote(
          messageId: 'a1',
          authorName: '小林玖奈',
          text: '周末去漫展吗',
        ),
      ),
    );

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    expect(find.text('引用 小林玖奈'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
