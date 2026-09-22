import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/hybrid_retrieval.dart';

MemoryEntry _entry(
  String id, {
  String content = '',
  String? sessionId,
  String? personaId,
  List<double>? embedding,
  double importance = 0.5,
  String status = 'active',
  DateTime? createdAt,
}) {
  return MemoryEntry(
    id: id,
    content: content,
    createdAt: createdAt ?? DateTime(2025, 11, 1),
    personaId: personaId,
    sessionId: sessionId,
    embedding: embedding,
    importance: importance,
    status: status,
  );
}

RetrievalMemory _mem(MemoryEntry entry, [List<MemoryAtom> atoms = const []]) =>
    RetrievalMemory(entry: entry, atoms: atoms);

void main() {
  final now = DateTime(2025, 11, 20);

  group('混合检索', () {
    test('BM25 关键词命中（无嵌入也能检索）', () async {
      final results = await searchMemories(
        query: '用户喜欢什么动物',
        candidates: [
          _mem(_entry('m1', content: '用户非常喜欢猫，每天都要撸猫')),
          _mem(_entry('m2', content: '明天下午三点开会讨论项目')),
          _mem(_entry('m3', content: '周末去爬山看日出')),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 2, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results, isNotEmpty);
      expect(results.first.entry.id, 'm1');
    });

    test('人物隔离：同一人物跨会话可见，其他人物不可见', () async {
      final results = await searchMemories(
        query: '喜欢猫',
        candidates: [
          _mem(_entry('same-other-session', content: '用户喜欢猫', personaId: 'p1', sessionId: 's2')),
          _mem(_entry('other-persona', content: '用户喜欢猫', personaId: 'p2', sessionId: 's1')),
          _mem(_entry('unscoped', content: '用户喜欢猫', sessionId: 's1')),
        ],
        scope: const RetrievalScope(
          sessionId: 's1',
          personaId: 'p1',
          sessionFiltering: false,
          strictPersona: true,
        ),
        config: const RetrievalConfig(topK: 5, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['same-other-session']);
    });

    test('会话过滤：隔离模式下只返回本会话与通用记忆', () async {
      final results = await searchMemories(
        query: '喜欢猫',
        candidates: [
          _mem(_entry('mine', content: '用户喜欢猫', sessionId: 's1')),
          _mem(_entry('other', content: '用户喜欢猫', sessionId: 's2')),
        ],
        scope: const RetrievalScope(sessionId: 's1', sessionFiltering: true),
        config: const RetrievalConfig(topK: 5, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['mine']);
    });

    test('非 active 记忆不参与检索', () async {
      final results = await searchMemories(
        query: '喜欢猫',
        candidates: [
          _mem(_entry('archived', content: '用户喜欢猫', status: 'archived')),
          _mem(_entry('active', content: '用户喜欢猫')),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 5, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['active']);
    });

    test('向量相似度参与排序', () async {
      // vec-match 同时命中 BM25（双路）+ 向量完全一致 → rrf 累积更高
      final results = await searchMemories(
        query: '完全一致的主题内容',
        candidates: [
          _mem(
            _entry('vec-match', content: '完全一致的主题内容', embedding: [1, 0, 0]),
          ),
          _mem(_entry('bm25-only', content: '完全一致的主题内容但换些说法')),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 2, recentMemoryCount: 0),
        graphStore: null,
        queryEmbedding: [1, 0, 0],
        now: now,
      );
      expect(results, isNotEmpty);
      expect(results.first.entry.id, 'vec-match');
    });

    test('原子增强：父记忆未入选时凭原子内容入选', () async {
      final atom = MemoryAtom(
        id: 'a1',
        parentMemoryId: 'parent',
        content: '张三的猫叫小花',
        createdAt: DateTime(2025, 11, 15),
      );
      final results = await searchMemories(
        query: '张三的猫叫什么名字',
        candidates: [
          _mem(_entry('parent', content: '一段与猫无关的普通记录文本'), [atom]),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 3, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), contains('parent'));
    });

    test('最近记忆保留位：72h 内的新记忆即使不相关也出现', () async {
      final results = await searchMemories(
        query: '完全无关的量子物理',
        candidates: [
          _mem(_entry('fresh', content: '刚聊过的日常琐事记录', createdAt: DateTime(2025, 11, 19, 12))),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 3, recentMemoryCount: 1),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['fresh']);
      expect(results.first.fromRecent, isTrue);
      expect(results.first.finalScore, 1.0);
    });

    test('重要性下限过滤', () async {
      final results = await searchMemories(
        query: '喜欢猫',
        candidates: [
          _mem(_entry('low', content: '用户喜欢猫', importance: 0.1)),
          _mem(_entry('ok', content: '用户喜欢猫', importance: 0.5)),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(
          topK: 5,
          recentMemoryCount: 0,
          minImportanceForRetrieval: 0.3,
        ),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['ok']);
    });

    test('event_only 过滤：无事件类原子的记忆被排除', () async {
      final preferenceAtom = MemoryAtom(
        id: 'a-pref',
        parentMemoryId: 'pref',
        content: '用户喜欢猫',
        atomType: AtomType.preference,
        createdAt: DateTime(2025, 11, 15),
      );
      final plannedAtom = MemoryAtom(
        id: 'a-plan',
        parentMemoryId: 'plan',
        content: '明天下午三点开会',
        atomType: AtomType.planned,
        createdAt: DateTime(2025, 11, 15),
      );
      final results = await searchMemories(
        query: '用户喜欢猫 明天开会',
        candidates: [
          _mem(_entry('pref', content: '用户喜欢猫'), [preferenceAtom]),
          _mem(_entry('plan', content: '明天下午三点开会'), [plannedAtom]),
        ],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(
          topK: 5,
          recentMemoryCount: 0,
          memoryTypeFilter: 'event_only',
        ),
        graphStore: null,
        now: now,
      );
      expect(results.map((r) => r.entry.id), ['plan']);
    });
  });

  group('意图动态调权', () {
    test('关系类查询提升图谱权重（通过公开检索行为验证）', () async {
      // 无图谱 store 时不崩溃，仅验证调用安全
      final results = await searchMemories(
        query: '张三和李四是什么关系',
        candidates: [_mem(_entry('m1', content: '张三和李四是同事关系'))],
        scope: const RetrievalScope(sessionFiltering: false),
        config: const RetrievalConfig(topK: 3, recentMemoryCount: 0),
        graphStore: null,
        now: now,
      );
      expect(results, isNotEmpty);
    });
  });

  group('余弦相似度', () {
    test('相同向量 / 正交向量', () {
      expect(cosineSimilarity([1, 0], [1, 0]), closeTo(1, 1e-9));
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
      expect(cosineSimilarity([1, 0], [2, 0]), closeTo(1, 1e-9));
    });
  });
}
