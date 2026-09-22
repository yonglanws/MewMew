import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/chat_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new assistant bubble morphs from loading size to content', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Animation test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    session.messages.add(
      ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'Hi there',
        timestamp: now,
      ),
    );
    state.notifyListeners();
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    final morphFinder = find.byKey(const ValueKey('bubble-morph-a1'));
    expect(morphFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('bubble-morph-size-a1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-a1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: morphFinder, matching: find.byType(SlideTransition)),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-a1')),
      findsOneWidget,
    );

    // 缩放层常驻（结束时拆子树会闪），断言它仍在树上且不再动画。
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-a1')),
      findsOneWidget,
    );
  });

  testWidgets('new user bubble shows content in the first animated frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'User animation test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    session.messages.add(
      ChatMessage(
        id: 'u2',
        role: 'user',
        content: 'A new message',
        timestamp: now,
      ),
    );
    state.notifyListeners();
    await tester.pump();
    final userTransform = find.byKey(
      const ValueKey('bubble-morph-transform-u2'),
    );
    expect(find.text('A new message'), findsOneWidget);
    expect(userTransform, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 60));

    final morphFinder = find.byKey(const ValueKey('bubble-morph-u2'));
    expect(morphFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('bubble-morph-size-u2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-u2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: morphFinder, matching: find.byType(SlideTransition)),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 350));
    expect(userTransform, findsOneWidget);

    // 缩放层常驻，结束后仍在树上。
    await tester.pump(const Duration(milliseconds: 300));
    expect(userTransform, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'user bubble keeps its entrance when inserted above loading reply',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      final now = DateTime(2026, 8, 8);
      final assistant = ChatMessage(
        id: 'a-loading',
        role: 'assistant',
        content: '',
        timestamp: now,
      )..isStreaming = true;
      final session = ChatSession(
        id: 's1',
        title: 'Queued user animation test',
        messages: [
          ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
          assistant,
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final user = ChatMessage(
        id: 'u2',
        role: 'user',
        content: 'Queued message',
        timestamp: now,
      );
      session.messages.insert(session.messages.length - 1, user);
      state.notifyListeners();
      await tester.pump();

      final morph = find.byKey(const ValueKey('bubble-morph-u2'));
      final transform = find.byKey(const ValueKey('bubble-morph-transform-u2'));
      expect(find.text('Queued message'), findsOneWidget);
      expect(morph, findsOneWidget);
      expect(transform, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      // 缩放层常驻，结束后仍在树上。
      expect(transform, findsOneWidget);
    },
  );

  testWidgets(
    'long user bubble grows its list slot instead of jumping to final height',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 's1',
        title: 'User size handoff test',
        messages: [
          for (var i = 0; i < 24; i++)
            ChatMessage(
              id: 'old-$i',
              role: i.isEven ? 'user' : 'assistant',
              content:
                  'Previous message $i with enough text to make the list tall.',
              timestamp: now,
            ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final content = List<String>.filled(
        8,
        'This is a long user message that should expand smoothly.',
      ).join('\n');
      session.messages.add(
        ChatMessage(id: 'u2', role: 'user', content: content, timestamp: now),
      );
      state.notifyListeners();
      await tester.pump();

      final morph = find.byKey(const ValueKey('row-entrance-u2'));
      final initialHeight = tester.getSize(morph).height;
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final initialMaxScrollExtent = scrollable.position.maxScrollExtent;
      expect(find.text(content), findsOneWidget);
      expect(initialHeight, lessThan(70));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final midHeight = tester.getSize(morph).height;
      expect(midHeight, greaterThan(initialHeight));
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(initialMaxScrollExtent),
      );

      await tester.pump(const Duration(milliseconds: 400));
      final finalHeight = tester.getSize(morph).height;
      expect(finalHeight, greaterThan(initialHeight + 40));
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(initialMaxScrollExtent + 40),
      );
    },
  );

  testWidgets(
    'sending a message shows the user bubble and loading bubble together',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      state.apiConfigs = [
        ApiConfig(
          id: 'api-1',
          name: 'Animation test API',
          baseUrl: 'https://example.com',
          apiKey: 'test-key',
          model: 'test-model',
        ),
      ];
      state.activeApiId = 'api-1';
      state.messageMergeEnabled = true;
      state.messageMergeDebounce = 3;

      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 'session-1',
        title: 'Message handoff test',
        messages: [
          for (var i = 0; i < 24; i++)
            ChatMessage(
              id: 'old-$i',
              role: i.isEven ? 'user' : 'assistant',
              content:
                  'Previous message $i with enough text to make the list tall.',
              timestamp: now,
            ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final sendFuture = state.sendMessage('A new message');
      await tester.pump();

      expect(session.messages.length, 26);
      expect(session.messages[session.messages.length - 2].role, 'user');
      expect(session.messages.last.role, 'assistant');
      expect(session.messages.last.isStreaming, isTrue);
      expect(find.text('A new message'), findsOneWidget);
      final userMessageId = session.messages[session.messages.length - 2].id;
      final assistantMessageId = session.messages.last.id;
      expect(
        find.byKey(ValueKey('bubble-morph-transform-$userMessageId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('bubble-morph-transform-$assistantMessageId')),
        findsOneWidget,
      );

      await sendFuture;
      state.cancelPendingMerge();
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('assistant loading starts with the shared size morph', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Loading animation test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    session.messages.add(
      ChatMessage(id: 'a1', role: 'assistant', content: '', timestamp: now)
        ..isStreaming = true,
    );
    state.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final morphFinder = find.byKey(const ValueKey('bubble-morph-a1'));
    expect(morphFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('bubble-morph-size-a1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-a1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('assistant-loading-start')), findsNothing);

    await tester.pump(const Duration(milliseconds: 650));
    // 缩放层常驻，结束后仍在树上。
    expect(
      find.byKey(const ValueKey('bubble-morph-transform-a1')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'streaming content updates do not interrupt the entrance animation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 's1',
        title: 'Animation update test',
        messages: [
          ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final assistant = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: 'Hi',
        timestamp: now,
      )..isStreaming = true;
      session.messages.add(assistant);
      state.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final morphFinder = find.byKey(const ValueKey('bubble-morph-a1'));
      final transformFinder = find.byKey(
        const ValueKey('bubble-morph-transform-a1'),
      );
      expect(morphFinder, findsOneWidget);
      expect(transformFinder, findsOneWidget);
      final scaleBeforeUpdate = tester
          .widget<Transform>(transformFinder)
          .transform
          .storage[0];

      assistant.content = 'Hi there, this is still streaming';
      state.notifyListeners();
      await tester.pump();

      expect(transformFinder, findsOneWidget);
      final scaleAfterUpdate = tester
          .widget<Transform>(transformFinder)
          .transform
          .storage[0];
      expect(scaleAfterUpdate, greaterThanOrEqualTo(scaleBeforeUpdate - 0.001));

      await tester.pump(const Duration(milliseconds: 700));
    },
  );

  testWidgets(
    'loading completion continues the current morph instead of restarting it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 's1',
        title: 'Loading completion continuity test',
        messages: [
          ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final assistant = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '',
        timestamp: now,
      )..isStreaming = true;
      session.messages.add(assistant);
      state.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final transformFinder = find.byKey(
        const ValueKey('bubble-morph-transform-a1'),
      );
      expect(transformFinder, findsOneWidget);
      final scaleBeforeCompletion = tester
          .widget<Transform>(transformFinder)
          .transform
          .storage[0];

      assistant.content = '正文到来';
      assistant.isStreaming = false;
      state.notifyListeners();
      await tester.pump();

      expect(transformFinder, findsOneWidget);
      final scaleAfterCompletion = tester
          .widget<Transform>(transformFinder)
          .transform
          .storage[0];
      expect(
        scaleAfterCompletion,
        greaterThanOrEqualTo(scaleBeforeCompletion - 0.001),
      );

      await tester.pump(const Duration(milliseconds: 800));
    },
  );

  testWidgets(
    'loading completion stretches the bubble into the final content size',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final state = AppState(storage);
      addTearDown(state.dispose);

      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 's1',
        title: 'Bubble stretch test',
        messages: [
          ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final assistant = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '',
        timestamp: now,
      )..isStreaming = true;
      session.messages.add(assistant);
      state.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final bubbleFinder = find.byKey(const ValueKey('bubble-morph-size-a1'));
      final loadingHeight = tester.getSize(bubbleFinder).height;

      assistant.content = '第一段回复内容。\n\n第二段回复内容会让气泡明显变高，方便观察拉伸动画。';
      state.notifyListeners();
      await tester.pump();

      final stretchStartHeight = tester.getSize(bubbleFinder).height;
      // 新一段尺寸动画的首个 tick 只记录起点，从下一帧才开始推进。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final stretchMiddleHeight = tester.getSize(bubbleFinder).height;
      await tester.pump(const Duration(milliseconds: 450));
      final finalHeight = tester.getSize(bubbleFinder).height;

      expect(finalHeight, greaterThan(loadingHeight));
      expect(stretchStartHeight, lessThan(finalHeight));
      expect(stretchMiddleHeight, greaterThanOrEqualTo(stretchStartHeight));
      expect(stretchMiddleHeight, lessThanOrEqualTo(finalHeight));
      // 缩放层常驻，结束后仍在树上。
      expect(
        find.byKey(const ValueKey('bubble-morph-transform-a1')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 700));
    },
  );

  testWidgets('re-entering loading keeps the size morph active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Loading re-entry test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    final assistant = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: '',
      timestamp: now,
    )..isStreaming = true;
    session.messages.add(assistant);
    state.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    assistant.content = '正文';
    state.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    assistant.content = '';
    assistant.isStreaming = true;
    state.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('bubble-morph-size-a1')), findsOneWidget);
  });

  testWidgets('streaming content growth keeps the size morph enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Streaming size test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    final assistant = ChatMessage(
      id: 'a1',
      role: 'assistant',
      content: '',
      timestamp: now,
    )..isStreaming = true;
    session.messages.add(assistant);
    state.notifyListeners();
    await tester.pump();

    assistant.content = '第一小段';
    state.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    assistant.content = '第一小段已经继续生成了更多内容，后面的文字应该仍然通过尺寸动画展开。';
    state.notifyListeners();
    await tester.pump();

    expect(find.byKey(const ValueKey('bubble-morph-size-a1')), findsOneWidget);
  });

  testWidgets('sticker bubble grows in without a loading flash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    state.stickers = [
      StickerItem(
        id: 'sticker-1',
        folderId: 'folder-1',
        name: 'image',
        description: '',
        filePath: 'missing-test-image.png',
        createdAt: now,
      ),
    ];
    final session = ChatSession(
      id: 's1',
      title: 'Image animation test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    session.messages.add(
      ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '',
        timestamp: now,
        stickerId: 'sticker-1',
      ),
    );
    state.notifyListeners();
    await tester.pump();

    final morphFinder = find.byKey(const ValueKey('bubble-morph-a1'));
    final sizeFinder = find.byKey(const ValueKey('row-entrance-a1'));
    expect(morphFinder, findsOneWidget);
    expect(sizeFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('sticker-reveal-a1')), findsNothing);
    final initialHeight = tester.getSize(sizeFinder).height;
    expect(initialHeight, lessThan(80));

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    final midHeight = tester.getSize(sizeFinder).height;
    expect(midHeight, greaterThan(initialHeight));

    await tester.pump(const Duration(milliseconds: 400));
    final finalHeight = tester.getSize(sizeFinder).height;
    expect(finalHeight, greaterThanOrEqualTo(midHeight));
    // 整行含上下内边距（2 + 16），图片本体 120。
    expect(finalHeight, closeTo(138, 8));
  });

  testWidgets('ready segmented text does not start with loading dots', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Segmented ready test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    session.messages.add(
      ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '第二段已经准备好了',
        timestamp: now,
      )..isSegmented = true,
    );
    state.notifyListeners();
    await tester.pump();

    expect(find.text('第二段已经准备好了'), findsOneWidget);
    expect(find.byKey(const ValueKey('bubble-morph-a1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('new incoming messages animate the auto-follow scroll', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    final session = ChatSession(
      id: 's1',
      title: 'Scroll animation test',
      messages: [
        for (var i = 0; i < 28; i++)
          ChatMessage(
            id: 'old-$i',
            role: i.isEven ? 'user' : 'assistant',
            content: '历史消息 $i，确保列表足够长。',
            timestamp: now,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    final scrollableFinder = find.byType(Scrollable);
    late ScrollableState scrollable;
    for (var index = 0; index < scrollableFinder.evaluate().length; index++) {
      final candidate = tester.state<ScrollableState>(
        scrollableFinder.at(index),
      );
      if (candidate.position.maxScrollExtent > 200) {
        scrollable = candidate;
        break;
      }
    }
    expect(scrollable.position.maxScrollExtent, greaterThan(200));
    scrollable.position.jumpTo(40);
    await tester.pump();

    session.messages.add(
      ChatMessage(
        id: 'a-new',
        role: 'assistant',
        content: '新到达的回复',
        timestamp: now,
      ),
    );
    state.notifyListeners();
    await tester.pump();

    // 恒速跟随滚动：短距离在下限时长内带缓动地滚完，
    // 而不是像旧实现那样固定 460ms 拖满全程。
    // （ticker 首 tick 只记起始时间，动画从第二个 pump 帧起推进。）
    expect(scrollable.position.isScrollingNotifier.value, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.isScrollingNotifier.value, isFalse);
    expect(scrollable.position.pixels, moreOrLessEquals(0, epsilon: 1));
  });

  testWidgets('bubble stretch speed is constant regardless of height', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    Future<int> measureSettleMs(int copies) async {
      final state = AppState(storage);
      addTearDown(state.dispose);
      final now = DateTime(2026, 8, 8);
      final session = ChatSession(
        id: 's-settle',
        title: 'Settle speed test',
        messages: [
          for (var i = 0; i < 24; i++)
            ChatMessage(
              id: 'old-$i',
              role: i.isEven ? 'user' : 'assistant',
              content:
                  'Previous message $i with enough text to make the list tall.',
              timestamp: now,
            ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      state.sessions = [session];
      state.currentSessionId = session.id;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: ChatPage()),
        ),
      );
      await tester.pump();

      final content = List<String>.filled(
        copies,
        'This is a long user message that should expand smoothly.',
      ).join('\n');
      session.messages.add(
        ChatMessage(
          id: 'u-new',
          role: 'user',
          content: content,
          timestamp: now,
        ),
      );
      state.notifyListeners();
      // 首帧显示单行预览，下一帧切换为完整正文并开始尺寸伸展。
      await tester.pump();
      await tester.pump();

      final sizeMorph = find.byKey(const ValueKey('row-entrance-u-new'));
      var elapsed = 0;
      double? previous;
      while (elapsed < 1500) {
        await tester.pump(const Duration(milliseconds: 20));
        elapsed += 20;
        final height = tester.getSize(sizeMorph).height;
        if (previous != null && (height - previous).abs() < 0.5) break;
        previous = height;
      }
      return elapsed;
    }

    final shortSettle = await measureSettleMs(3);
    final tallSettle = await measureSettleMs(12);

    // 恒定像素速度：高气泡伸展距离更长、落定成比例更久；
    // 若退回固定时长的实现，两者几乎同时落定，此断言即失败。
    expect(tallSettle, greaterThan(shortSettle));
    expect(shortSettle, lessThan(600));
    expect(tallSettle, lessThan(800));
  });

  testWidgets('avatar and sticker fade in with the bubble entrance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    final now = DateTime(2026, 8, 8);
    state.stickers = [
      StickerItem(
        id: 'sticker-1',
        folderId: 'folder-1',
        name: 'image',
        description: '',
        filePath: 'missing-test-image.png',
        createdAt: now,
      ),
    ];
    final session = ChatSession(
      id: 's1',
      title: 'Entrance fade test',
      messages: [
        ChatMessage(id: 'u1', role: 'user', content: 'Hello', timestamp: now),
      ],
      createdAt: now,
      updatedAt: now,
    );
    state.sessions = [session];
    state.currentSessionId = session.id;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    // 新用户消息：头像应从透明淡入，而不是瞬间出现。
    session.messages.add(
      ChatMessage(id: 'u2', role: 'user', content: 'Hi', timestamp: now),
    );
    state.notifyListeners();
    await tester.pump();
    var fading = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((o) => o.opacity < 1.0);
    expect(fading, isTrue);

    session.messages.add(
      ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '',
        timestamp: now,
        stickerId: 'sticker-1',
      ),
    );
    state.notifyListeners();
    await tester.pump();
    fading = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .any((o) => o.opacity < 1.0);
    expect(fading, isTrue);

    // ticker 首 tick 只记录起点，动画从下一帧开始推进，需要两帧走完。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final allVisible = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .every((o) => o.opacity >= 1.0);
    expect(allVisible, isTrue);

    // 冲刷 720ms 入场保持 Timer。
    await tester.pump(const Duration(milliseconds: 600));
  });
}
