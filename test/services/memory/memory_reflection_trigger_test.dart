import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

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

  ChatMessage msg(String role, String text) => ChatMessage(
    id: 'msg-${DateTime.now().microsecondsSinceEpoch}-$role-$text',
    role: role,
    content: text,
    timestamp: DateTime.now(),
  );

  group('记忆提取滑窗触发（AppState 级）', () {
    test('未达阈值不触发', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 5);
      final session = await state.newSession();
      for (var i = 0; i < 3; i++) {
        session.messages.addAll([
          msg('user', '消息$i'),
          msg('assistant', '回复$i'),
        ]);
      }
      // 无可用 API 时直接跳过；这里主要验证不炸、无 pending
      await state.debugCheckAndSummarize(session);
      expect(state.memoryReflectionState[session.id]?['pending'], isNull);
    });

    test('达到阈值且无 API → 不触发（需要对话模型）', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 2);
      final session = await state.newSession();
      for (var i = 0; i < 5; i++) {
        session.messages.addAll([
          msg('user', '用户消息$i，包含一些内容'),
          msg('assistant', '助手回复$i，包含一些内容'),
        ]);
      }
      await state.debugCheckAndSummarize(session);
      // activeApi 为 null → 直接 return，无 pending 也无游标推进
      final rs = state.memoryReflectionState[session.id];
      expect(rs == null || rs['pending'] == null, isTrue);
    });

    test(
      '有 API 但请求失败 → 记录 pending 重试区间',
      () async {
        final state = await buildState();
        state.memorySettings = state.memorySettings.copyWith(
          summaryThreshold: 2,
        );
        // 配置一个指向不可达端口的 API（连接立即失败）
        state.apiConfigs.add(
          ApiConfig(
            id: 'fake',
            name: 'fake',
            baseUrl: 'http://127.0.0.1:1',
            apiKey: 'k',
            model: 'm',
          ),
        );
        state.activeApiId = 'fake';
        final session = await state.newSession();
        for (var i = 0; i < 5; i++) {
          session.messages.addAll([
            msg('user', '用户消息$i，包含一些内容'),
            msg('assistant', '助手回复$i，包含一些内容'),
          ]);
        }
        await state.debugCheckAndSummarize(session);

        final rs = state.memoryReflectionState[session.id]!;
        final pending = rs['pending'] as Map<String, dynamic>?;
        expect(pending, isNotNull);
        expect(pending!['retryCount'], 1);
        expect(pending['startIndex'], 0);
        expect(pending['endIndex'], 10);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('pending 超过 3 次后放弃并推进游标', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 2);
      state.apiConfigs.add(
        ApiConfig(
          id: 'fake',
          name: 'fake',
          baseUrl: 'http://127.0.0.1:1',
          apiKey: 'k',
          model: 'm',
        ),
      );
      state.activeApiId = 'fake';
      final session = await state.newSession();
      for (var i = 0; i < 5; i++) {
        session.messages.addAll([
          msg('user', '用户消息$i'),
          msg('assistant', '回复$i'),
        ]);
      }
      // 预置已达上限的 pending
      state.memoryReflectionState[session.id] = {
        'lastSummarizedIndex': 0,
        'pending': {'startIndex': 0, 'endIndex': 10, 'retryCount': 3},
      };
      await state.debugCheckAndSummarize(session);
      final rs = state.memoryReflectionState[session.id]!;
      expect(rs['pending'], isNull);
      expect(rs['lastSummarizedIndex'], 10);
    });

    test('lastSummarizedIndex 超过消息总数时钳位', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 2);
      final session = await state.newSession();
      session.messages.addAll([msg('user', '只有一条')]);
      state.memoryReflectionState[session.id] = {
        'lastSummarizedIndex': 100, // 异常值
      };
      await state.debugCheckAndSummarize(session);
      // 钳位到 1，未总结 0 轮 → 无 pending
      final rs = state.memoryReflectionState[session.id]!;
      expect(rs['lastSummarizedIndex'], 1);
      expect(rs['pending'], isNull);
    });

    test('删除会话时清理反思状态', () async {
      final state = await buildState();
      final session = await state.newSession();
      state.memoryReflectionState[session.id] = {'lastSummarizedIndex': 4};
      await state.deleteSession(session.id);
      expect(state.memoryReflectionState.containsKey(session.id), isFalse);
    });

    test('无嵌入 API 时检索仍走关键词/图谱路径命中', () async {
      final state = await buildState();
      // 默认未配置嵌入 API
      expect(state.embeddingApiConfig.isValid, isFalse);
      state.memorySettings = state.memorySettings.copyWith(
        useSessionFiltering: false,
        graphEnabled: true,
        atomEnabled: true,
      );
      await state.addMemory('张三最喜欢吃的食物是火锅', sessionId: 's1');
      await state.addMemory('明天下午三点要开会讨论项目', sessionId: 's1');

      final results = await state.debugRetrieveRelevantMemories(
        '张三喜欢吃什么',
        null,
        's1',
      );
      expect(results, isNotEmpty);
      expect(results.first.content.contains('火锅'), isTrue);
    });

    test('clearSessions 同步清空反思游标', () async {
      final state = await buildState();
      final s1 = await state.newSession();
      final s2 = await state.newSession();
      state.memoryReflectionState[s1.id] = {'lastSummarizedIndex': 4};
      state.memoryReflectionState[s2.id] = {'lastSummarizedIndex': 6};
      await state.clearSessions();
      expect(state.memoryReflectionState, isEmpty);
    });

    test('deletePersona 级联清理该人物的记忆/原子/图谱', () async {
      final state = await buildState();
      final persona = await _addPersona(state, '小雪');
      state.memorySettings = state.memorySettings.copyWith(
        atomEnabled: true,
        graphEnabled: true,
      );
      // 该人物的记忆（含原子与图谱）
      await state.addMemory(
        '小雪喜欢科幻电影',
        personaId: persona.id,
        sessionId: 's-xue',
      );
      // 无主记忆不受影响
      await state.addMemory('通用记忆一条', sessionId: 's-other');

      final personaMemory = state.memories
          .where((m) => m.personaId == persona.id)
          .first;
      expect(state.graphStore.nodeCount, greaterThan(0));

      await state.deletePersona(persona.id);

      expect(state.memories.any((m) => m.personaId == persona.id), isFalse);
      expect(
        state.memoryAtoms.any((a) => a.parentMemoryId == personaMemory.id),
        isFalse,
      );
      expect(state.memories.any((m) => m.content.contains('通用记忆')), isTrue);
    });

    test('嵌入向量分离存储：保存后 memories JSON 不含向量，重载可恢复', () async {
      final state = await buildState();
      await state.addMemory('带嵌入的记忆');
      final memory = state.memories.first;
      memory.embedding = [0.1, 0.2, 0.3];
      // 走一轮持久化
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final prefs = await SharedPreferences.getInstance();
      final memoriesJson = prefs.getString('memories')!;
      expect(memoriesJson.contains('embedding'), isFalse);
      final embeddingsJson = prefs.getString('memory_embeddings');
      expect(embeddingsJson, isNotNull);
      expect(embeddingsJson!.contains(memory.id), isTrue);

      // 重载恢复：不重置 mock prefs，直接新开一个 AppState 读同一份存储
      final storage2 = StorageService();
      await storage2.init();
      final state2 = AppState(storage2);
      await state2.load();
      expect(state2.memories.first.id, memory.id);
      expect(state2.memories.first.embedding, [0.1, 0.2, 0.3]);
    });

    test('importMemoryEntries 保留元数据并为冲突 id 重新生成', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(atomEnabled: true);
      final existing = MemoryEntry(
        id: 'dup',
        content: '已有记忆',
        createdAt: DateTime(2025, 11, 19),
        importance: 0.6,
      );
      state.memories.add(existing);
      final imported = [
        MemoryEntry(
          id: 'new-1',
          content: '张三喜欢科幻电影 | 张三喜欢科幻',
          createdAt: DateTime(2025, 11, 20),
          source: 'summary',
          importance: 0.8,
          personaSummary: '张三喜欢科幻电影',
          topics: const ['电影'],
          keyFacts: const ['张三喜欢科幻电影'],
          interactionType: 'private_chat',
        ),
        MemoryEntry(
          id: 'dup', // 与现有冲突
          content: '另一条记忆',
          createdAt: DateTime(2025, 11, 20),
          importance: 0.4,
        ),
      ];
      final count = await state.importMemoryEntries(imported);
      expect(count, 2);
      // 元数据保留
      expect(
        state.memories.any((m) => m.id == 'new-1' && m.importance == 0.8),
        isTrue,
      );
      // 冲突 id 已重新生成，原 id 不存在第二条
      expect(state.memories.where((m) => m.id == 'dup').length, 1);
      // 原子与图谱已补建
      expect(state.memoryAtoms.isNotEmpty, isTrue);
      expect(state.memoryAtoms.any((a) => a.parentMemoryId == 'new-1'), isTrue);
      expect(state.graphStore.nodeCount, greaterThan(0));
    });
  });
}

Future<dynamic> _addPersona(AppState state, String name) async {
  final persona = Persona(id: 'persona-$name', name: name);
  await state.addOrUpdatePersona(persona);
  return persona;
}
