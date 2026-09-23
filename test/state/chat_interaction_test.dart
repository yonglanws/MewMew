import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 消息删除 / 会话批量删除 / 引用上下文注入 / 角色专属生成风格 的状态层测试
void main() {
  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    return state;
  }

  group('消息删除', () {
    testWidgets('删除单条消息后不再出现在会话中', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      state.sessions = [
        ChatSession(
          id: 's1',
          title: '测试',
          messages: [
            ChatMessage(id: 'u1', role: 'user', content: '你好', timestamp: now),
            ChatMessage(
              id: 'a1',
              role: 'assistant',
              content: '嗨',
              timestamp: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ];

      state.deleteMessage('s1', 'u1');
      await tester.pump(const Duration(seconds: 2));

      final session = state.sessions.first;
      expect(session.messages.length, 1);
      expect(session.messages.first.id, 'a1');
    });

    testWidgets('删除正在生成的消息会先停止回复再移除', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      final streaming = ChatMessage(
        id: 'a1',
        role: 'assistant',
        content: '正在生成的部分',
        timestamp: now,
      )..isStreaming = true;
      state.sessions = [
        ChatSession(
          id: 's1',
          title: '测试',
          messages: [streaming],
          createdAt: now,
          updatedAt: now,
        ),
      ];
      state.isSending = true;

      state.deleteMessage('s1', 'a1');
      await tester.pump(const Duration(seconds: 2));

      expect(state.sessions.first.messages, isEmpty);
    });

    testWidgets('不存在的会话或消息为安全空操作', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      state.sessions = [
        ChatSession(
          id: 's1',
          title: '测试',
          messages: [
            ChatMessage(id: 'u1', role: 'user', content: '你好', timestamp: now),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ];

      state.deleteMessage('nope', 'u1');
      state.deleteMessage('s1', 'nope');
      await tester.pump(const Duration(seconds: 2));
      expect(state.sessions.first.messages.length, 1);
    });
  });

  group('会话批量删除', () {
    testWidgets('deleteSessions 只删除指定会话并清理提取游标', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      state.sessions = [
        ChatSession(
          id: 's1',
          title: 'A',
          messages: [],
          createdAt: now,
          updatedAt: now,
        ),
        ChatSession(
          id: 's2',
          title: 'B',
          messages: [],
          createdAt: now,
          updatedAt: now,
        ),
      ];
      state.memoryReflectionState['s1'] = {'lastSummarizedIndex': 4};
      state.currentSessionId = 's1';

      await state.deleteSessions(['s1']);
      await tester.pump(const Duration(seconds: 2));

      expect(state.sessions.map((s) => s.id), ['s2']);
      expect(state.currentSessionId, isNull);
      expect(state.memoryReflectionState.containsKey('s1'), isFalse);
    });

    testWidgets('空列表为空操作', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      await state.deleteSessions([]);
      await tester.pump(const Duration(seconds: 2));
      expect(state.sessions, isEmpty);
    });
  });

  group('引用注入上下文', () {
    testWidgets('带引用的用户消息在 API 上下文里携带引用行', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      state.sessions = [
        ChatSession(
          id: 's1',
          title: '测试',
          messages: [
            ChatMessage(
              id: 'a1',
              role: 'assistant',
              content: '周末去漫展吗',
              timestamp: now,
            ),
            ChatMessage(
              id: 'u1',
              role: 'user',
              content: '去！',
              timestamp: now,
              quote: MessageQuote(
                messageId: 'a1',
                authorName: '小林玖奈',
                text: '周末去漫展吗',
              ),
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final apiMessages = state.debugBuildApiMessages(
        state.sessions.first,
        systemPrompt: 'sys',
      );

      final userMsg = apiMessages
          .where((m) => m['role'] == 'user')
          .map((m) => m['content'])
          .first as String;
      expect(userMsg, contains('【引用 小林玖奈 的消息：「周末去漫展吗」】'));
      expect(userMsg, contains('去！'));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('无引用消息不带引用行', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      final now = DateTime(2026);
      state.sessions = [
        ChatSession(
          id: 's1',
          title: '测试',
          messages: [
            ChatMessage(id: 'u1', role: 'user', content: '普通消息', timestamp: now),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final apiMessages = state.debugBuildApiMessages(
        state.sessions.first,
        systemPrompt: 'sys',
      );
      final userMsg = apiMessages.last['content'] as String;
      expect(userMsg, '普通消息');
      expect(userMsg, isNot(contains('引用')));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('角色专属生成风格', () {
    testWidgets('角色自定义风格优先于全局', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      state.generationStyleSettings = GenerationStyleSettings(
        stylePrompt: '全局风格：简短',
      );
      state.personas = [
        Persona(id: 'p1', name: '小林玖奈', stylePrompt: '专属风格：口语化到底'),
      ];
      final session = ChatSession(
        id: 's1',
        title: '小林玖奈',
        personaId: 'p1',
        messages: [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final prompt = state.debugBuildSystemPrompt(session);
      expect(prompt, contains('专属风格：口语化到底'));
      expect(prompt, isNot(contains('全局风格：简短')));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('角色风格留空时跟随全局', (tester) async {
      final state = await buildState();
      addTearDown(state.dispose);
      state.generationStyleSettings = GenerationStyleSettings(
        stylePrompt: '全局风格：简短',
      );
      state.personas = [Persona(id: 'p1', name: '小林玖奈')];
      final session = ChatSession(
        id: 's1',
        title: '小林玖奈',
        personaId: 'p1',
        messages: [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final prompt = state.debugBuildSystemPrompt(session);
      expect(prompt, contains('全局风格：简短'));
      await tester.pump(const Duration(seconds: 2));
    });

    test('Persona stylePrompt 序列化', () {
      final p = Persona(id: 'p1', name: 'A', stylePrompt: '专属');
      final restored = Persona.fromJson(p.toJson());
      expect(restored.stylePrompt, '专属');
      expect(Persona.fromJson({}..['id'] = 'x'..['name'] = 'B').stylePrompt, '');
    });
  });

  group('MessageQuote', () {
    test('引用快照序列化与上下文行', () {
      final quote = MessageQuote(
        messageId: 'm1',
        authorName: '小林玖奈',
        text: '今天吃什么',
      );
      final restored = MessageQuote.fromJson(quote.toJson());
      expect(restored.authorName, '小林玖奈');
      expect(restored.text, '今天吃什么');
      expect(restored.toContextLine(), '【引用 小林玖奈 的消息：「今天吃什么」】');
    });

    test('ChatMessage 携带引用并持久化', () {
      final now = DateTime(2026);
      final message = ChatMessage(
        id: 'u1',
        role: 'user',
        content: '火锅！',
        timestamp: now,
        quote: MessageQuote(
          messageId: 'a1',
          authorName: '小林玖奈',
          text: '吃什么',
        ),
      );
      final restored = ChatMessage.fromJson(message.toJson());
      expect(restored.quote, isNotNull);
      expect(restored.quote!.text, '吃什么');

      final noQuote = ChatMessage.fromJson({
        'id': 'u2',
        'role': 'user',
        'content': '无引用',
        'timestamp': now.toIso8601String(),
      });
      expect(noQuote.quote, isNull);
    });
  });
}
