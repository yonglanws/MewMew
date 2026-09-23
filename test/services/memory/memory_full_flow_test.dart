import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/ai_service.dart' show EmbeddingResult;
import 'package:mewmew/services/memory/memory_prompts.dart'
    show consolidationSystemPrompt;
import 'package:mewmew/services/memory/memory_recall_format.dart'
    show formatMemoriesForInjection, injectionOpenTag;
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> buildState({
    MemoryTaskRunner? taskRunner,
    MemoryEmbedder? embedder,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage, taskRunner: taskRunner, embedder: embedder);
    await state.load();
    return state;
  }

  void attachFakeApi(AppState state) {
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
  }

  ChatMessage msg(String role, String text) => ChatMessage(
    id: 'msg-${DateTime.now().microsecondsSinceEpoch}-$role-$text',
    role: role,
    content: text,
    timestamp: DateTime.now(),
  );

  /// 两条消息一轮，共 [rounds] 轮
  List<ChatMessage> conversation(int rounds) {
    final messages = <ChatMessage>[];
    for (var i = 0; i < rounds; i++) {
      messages.addAll([
        msg('user', '我家猫叫咪咪，今天又把杯子碰翻了，真拿它没办法'),
        msg('assistant', '哈哈，咪咪真调皮。对了我记得你不喜欢吃香菜吧？'),
      ]);
    }
    return messages;
  }

  String extractionResponseJson() => jsonEncode({
    'summary': '用户分享了养猫日常，并强调自己不吃香菜',
    'canonical_summary': '用户养了一只叫咪咪的猫，不吃香菜',
    'topics': ['宠物', '饮食'],
    'key_facts': ['用户养了一只叫咪咪的猫', '用户不吃香菜'],
    'participants': ['用户'],
    'sentiment': 'positive',
    'importance': 0.7,
  });

  String mergeResponseJson() => jsonEncode({
    'summary': '用户的生活偏好：养猫、不吃香菜（多条旧记忆合并）',
    'key_facts': ['用户养猫', '用户不吃香菜'],
    'topics': ['宠物', '饮食'],
    'importance': 0.6,
  });

  group('记忆系统全流程（提取 → 存储 → 检索 → 注入）', () {
    test('端到端：滑窗触发提取，产生记忆+原子+图谱，检索命中并可注入', () async {
      final extractionCalls = <String>[];
      final state = await buildState(
        taskRunner:
            ({required config, required system, required user, model}) async {
              extractionCalls.add(system);
              return (extractionResponseJson(), 120, 60);
            },
      );
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 2);
      attachFakeApi(state);

      final session = await state.newSession();
      session.messages.addAll(conversation(2));
      await state.debugCheckAndSummarize(session);

      // 提取调用发生过，且不是整理合并的提示词
      expect(extractionCalls, hasLength(1));
      expect(extractionCalls.first, isNot(consolidationSystemPrompt));

      // 记忆条目
      expect(state.memories, hasLength(1));
      final memory = state.memories.first;
      expect(memory.content, contains('咪咪'));
      expect(memory.keyFacts, hasLength(2));
      expect(memory.summaryQuality, 'normal');
      expect(memory.topics, contains('宠物'));
      expect(memory.sourceTimeLabel, isNotNull);

      // 记忆原子
      final atoms = state.memoryAtoms
          .where((a) => a.parentMemoryId == memory.id)
          .toList();
      expect(atoms, hasLength(2));
      expect(memory.atomTypes, isNotEmpty);

      // 实体图谱
      expect(state.graphStore.nodeCount, greaterThan(0));
      expect(state.graphStore.edgeCount, greaterThan(0));

      // 游标推进、无待重试区间
      final reflection = state.memoryReflectionState[session.id]!;
      expect(reflection['lastSummarizedIndex'], 4);
      expect(reflection['pending'], isNull);

      // 检索命中
      final results = await state.debugRetrieveRelevantMemories(
        '用户养了什么动物',
        null,
        session.id,
      );
      expect(results, isNotEmpty);
      expect(results.first.content, contains('咪咪'));

      // 注入格式包含包装标记与原子事实
      final injection = formatMemoriesForInjection(
        memories: results,
        atomsOf: (m) =>
            state.memoryAtoms.where((a) => a.parentMemoryId == m.id).toList(),
        atomPolicyEnabled: true,
      );
      expect(injection, startsWith(injectionOpenTag));
      expect(injection, contains('咪咪'));
    });

    test('嵌入 seam：配置嵌入 API 后提取自动回填向量、检索走向量路径', () async {
      final embedRequests = <String>[];
      final state = await buildState(
        taskRunner:
            ({required config, required system, required user, model}) async =>
                (extractionResponseJson(), 120, 60),
        embedder:
            ({
              required baseUrl,
              required apiKey,
              required model,
              required text,
            }) async {
              embedRequests.add(text);
              return EmbeddingResult(
                embedding: [0.2, 0.4, text.length / 100.0],
              );
            },
      );
      state.embeddingApiConfig = EmbeddingApiConfig(
        baseUrl: 'http://embedding.local',
        apiKey: 'k',
        model: 'emb-model',
      );
      state.memorySettings = state.memorySettings.copyWith(summaryThreshold: 2);
      attachFakeApi(state);

      final session = await state.newSession();
      session.messages.addAll(conversation(2));
      await state.debugCheckAndSummarize(session);

      // _computeEmbedding 是 fire-and-forget，让微任务跑完
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(embedRequests, isNotEmpty);
      expect(state.memories.first.embedding, isNotNull);
      expect(state.memories.first.embedding, hasLength(3));

      // 检索时查询也会请求嵌入（向量路径），且能命中
      final requestCountBefore = embedRequests.length;
      final results = await state.debugRetrieveRelevantMemories(
        '咪咪',
        null,
        session.id,
      );
      expect(embedRequests.length, greaterThan(requestCountBefore));
      expect(results, isNotEmpty);
    });
  });

  group('生命周期与整理（AppState 级）', () {
    test('runMemoryMaintenance：每日衰减降低重要性，过期原子进入遗忘', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(
        decayRate: 0.5,
        protectionThreshold: 0.9,
      );
      final memory = MemoryEntry(
        id: 'decay-1',
        content: '会衰减的记忆',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        importance: 0.8,
      );
      state.memories.add(memory);
      // 过期 10 天的原子：超过遗忘延迟（7 天）→ forgotten
      state.memoryAtoms.add(
        MemoryAtom(
          id: 'atom-expired',
          parentMemoryId: 'decay-1',
          content: '一个过期事实',
          createdAt: DateTime.now().subtract(const Duration(days: 40)),
          expiresAt: DateTime.now().subtract(const Duration(days: 10)),
        ),
      );
      state.memoryMaintenanceState['lastDecayDate'] = DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String();

      await state.runMemoryMaintenance();

      expect(memory.importance, lessThan(0.8));
      expect(memory.importance, greaterThan(0.0));
      expect(
        state.memoryAtoms.firstWhere((a) => a.id == 'atom-expired').status,
        AtomStatus.forgotten,
      );
    });

    test('整理合并：LLM 合并后原件归档、生成带原子的合并产物', () async {
      final systems = <String>[];
      final state = await buildState(
        taskRunner:
            ({required config, required system, required user, model}) async {
              systems.add(system);
              return (mergeResponseJson(), 90, 40);
            },
      );
      state.memorySettings = state.memorySettings.copyWith(
        consolidationEnabled: true,
      );
      attachFakeApi(state);

      for (var i = 0; i < 3; i++) {
        state.memories.add(
          MemoryEntry(
            id: 'old-$i',
            content: '旧记忆$i：用户提到养猫的日常小事',
            createdAt: DateTime.now().subtract(Duration(days: 10 + i)),
            importance: 0.4,
            sessionId: 'sess-1',
          ),
        );
      }

      await state.runConsolidationManually();

      // 调用走了整理提示词
      expect(systems, hasLength(1));
      expect(systems.first, consolidationSystemPrompt);

      // 原件全部归档
      for (var i = 0; i < 3; i++) {
        expect(
          state.memories.firstWhere((m) => m.id == 'old-$i').status,
          'archived',
        );
      }

      // 合并产物：溯源三条、带新原子与图谱
      final merged = state.memories
          .where((m) => m.consolidatedFrom.length == 3)
          .toList();
      expect(merged, hasLength(1));
      expect(merged.first.content, contains('不吃香菜'));
      expect(
        state.memoryAtoms.any((a) => a.parentMemoryId == merged.first.id),
        isTrue,
      );
      expect(state.graphStore.nodeCount, greaterThan(0));
    });
  });

  group('updateMemoryFull 与默认阈值', () {
    test('改关键事实重建原子与图谱，改主题只更新元数据', () async {
      final state = await buildState();
      state.memorySettings = state.memorySettings.copyWith(
        atomEnabled: true,
        graphEnabled: true,
      );
      final created = await state.addMemory('张三喜欢科幻电影', sessionId: 's1');
      expect(created, isNotNull);
      final memory = created!;
      expect(
        state.memoryAtoms.where((a) => a.parentMemoryId == memory.id),
        isNotEmpty,
      );

      final oldAtomIds = state.memoryAtoms.map((a) => a.id).toSet();
      await state.updateMemoryFull(
        memory.id,
        keyFacts: ['张三讨厌早起'],
        topics: ['作息'],
      );

      final newAtoms = state.memoryAtoms.where(
        (a) => a.parentMemoryId == memory.id,
      );
      expect(newAtoms, hasLength(1));
      expect(newAtoms.first.content, '张三讨厌早起');
      expect(oldAtomIds.contains(newAtoms.first.id), isFalse);
      expect(memory.topics, ['作息']);
      expect(state.graphStore.nodeCount, greaterThan(0));

      // 仅改主题：原子保持不变
      final atomsBefore = state.memoryAtoms.map((a) => a.id).toSet();
      await state.updateMemoryFull(memory.id, topics: ['作息', '电影']);
      expect(state.memoryAtoms.map((a) => a.id).toSet(), atomsBefore);
      expect(memory.topics, ['作息', '电影']);
    });

    test('总结轮数默认 20；旧默认 10 一次性迁移，自定义值不受影响', () async {
      expect(MemorySettings().summaryThreshold, 20);

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      // 存量配置还是旧默认 10
      await storage.saveMemorySettings(MemorySettings(summaryThreshold: 10));
      final state = AppState(storage);
      await state.load();
      expect(state.memorySettings.summaryThreshold, 20);

      // 迁移标记已写入：此后用户显式设置的值（含 10）不再被覆盖
      await storage.saveMemorySettings(MemorySettings(summaryThreshold: 15));
      final storage2 = StorageService();
      await storage2.init();
      final state2 = AppState(storage2);
      await state2.load();
      expect(state2.memorySettings.summaryThreshold, 15);
    });
  });
}
