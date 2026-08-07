import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/chat_page.dart';
import 'package:mewmew/services/segmented_delivery_scheduler.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('聊天页显示分段进度并支持立即显示全部', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final scheduler = SegmentedDeliveryScheduler(
      wait: (_) => Completer<void>().future,
    );
    final state = AppState(storage, segmentedDeliveryScheduler: scheduler);
    addTearDown(state.dispose);

    final now = DateTime.now();
    state.sessions = [
      ChatSession(
        id: 's1',
        title: '测试会话',
        messages: [
          ChatMessage(id: 'u1', role: 'user', content: '你好', timestamp: now),
          ChatMessage(
            id: 'a1',
            role: 'assistant',
            content: '第一段',
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
    state.currentSessionId = 's1';

    final done = scheduler.deliver(
      sessionId: 's1',
      itemCount: 2,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: (_) {},
    );
    state.notifyListeners();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    expect(find.text('正在发送 1/3'), findsOneWidget);
    expect(find.text('立即显示全部'), findsOneWidget);
    expect(find.byTooltip('停止回复'), findsWidgets);

    await tester.tap(find.text('立即显示全部'));
    await tester.pump();
    expect(await done, SegmentedDeliveryResult.flushed);
    state.notifyListeners();
    await tester.pump();
    expect(find.text('立即显示全部'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
