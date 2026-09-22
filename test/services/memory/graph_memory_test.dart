import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/graph_memory.dart';

MemoryEntry _memory(
  String id, {
  List<String> participants = const [],
  String? sessionId,
}) =>
  MemoryEntry(
    id: id,
    content: '测试记忆 $id',
    createdAt: DateTime(2025, 11, 10),
    participants: participants,
    sessionId: sessionId,
  );

MemoryAtom _atom(
  String parent,
  String content, {
  List<String> entities = const [],
  double confidence = 0.8,
  AtomType type = AtomType.factual,
}) =>
    MemoryAtom(
      id: 'atom-$content.hashCode',
      parentMemoryId: parent,
      content: content,
      entities: entities,
      confidence: confidence,
      atomType: type,
      createdAt: DateTime(2025, 11, 10),
    );

void main() {
  group('图谱构建', () {
    test('参与者生成 person 节点，实体生成 topic 节点，事实生成 fact 节点', () {
      final store = GraphMemoryStore();
      final memory = _memory('m1', participants: ['张三']);
      final atoms = [
        _atom('m1', '张三喜欢科幻电影', entities: ['科幻电影'], type: AtomType.preference),
      ];
      store.indexMemory(memory, atoms);

      expect(store.nodeCount, greaterThanOrEqualTo(3));
      expect(
        store.nodes.keys,
        contains(graphNodeKey(GraphNodeType.person, '张三')),
      );
      expect(
        store.nodes.keys,
        contains(graphNodeKey(GraphNodeType.topic, '科幻电影')),
      );
      expect(
        store.nodes.values.any((n) => n.type == GraphNodeType.fact),
        isTrue,
      );
    });

    test('同语义边跨记忆合并：置信度 EMA 与权重累积', () {
      final store = GraphMemoryStore();
      final m1 = _memory('m1', participants: ['张三']);
      final m2 = _memory('m2', participants: ['张三']);
      // 张三同时出现在 entities 中才会生成 person→fact 边（照抄原版原子路径）
      store.indexMemory(m1, [
        _atom('m1', '张三会弹钢琴', entities: ['张三', '钢琴'], confidence: 0.8),
      ]);
      store.indexMemory(m2, [
        _atom('m2', '张三会弹钢琴', entities: ['张三', '钢琴'], confidence: 1.0),
      ]);

      final personKey = graphNodeKey(GraphNodeType.person, '张三');
      final factCanonical = canonicalizeEntity('张三会弹钢琴');
      final factKey = graphNodeKey(GraphNodeType.fact, factCanonical);
      // 两次写入同语义边 → 只保留一条
      final edges = store.edges.values
          .where((e) => e.semanticKey == '$personKey|mentioned_in|$factKey')
          .toList();
      expect(edges.length, 1);
      // EMA: 0.72(=0.8×0.9) → 0.72×0.7 + 0.9×0.3 = 0.774 < 1.0
      expect(edges.first.confidence, closeTo(0.774, 0.01));
      // 权重累积：1.0 + 1.0×0.15
      expect(edges.first.weight, closeTo(1.15, 0.01));
    });

    test('删除记忆回收孤儿节点', () {
      final store = GraphMemoryStore();
      store.indexMemory(_memory('m1', participants: ['张三']), [
        _atom('m1', '张三住在上海', entities: ['上海']),
      ]);
      final beforeNodes = store.nodeCount;
      expect(beforeNodes, greaterThan(0));
      store.deleteMemory('m1');
      expect(store.nodeCount, 0);
      expect(store.edgeCount, 0);
      expect(store.entryCount, 0);
    });
  });

  group('图谱检索', () {
    late GraphMemoryStore store;
    setUp(() {
      store = GraphMemoryStore();
      store.indexMemory(_memory('m1', participants: ['张三']), [
        _atom('m1', '张三最喜欢的食物是火锅', entities: ['火锅', '食物'], type: AtomType.preference),
      ]);
      store.indexMemory(_memory('m2', participants: ['李四']), [
        _atom('m2', '李四负责前端开发', entities: ['前端开发']),
      ]);
    });

    double importanceOf(String id) => 0.6;
    DateTime? createdAtOf(String id) => DateTime(2025, 11, 10);
    DateTime? lastAccessOf(String id) => null;

    test('直命中：查询词命中事实内容', () {
      final hits = store.search(
        '张三喜欢吃什么',
        limit: 5,
        expansionLimit: 24,
        expansionHops: 1,
        secondHopWeight: 0.4,
        sessionId: null,
        personaId: null,
        importanceOf: importanceOf,
        lastAccessOf: lastAccessOf,
        createdAtOf: createdAtOf,
        decayRate: 0.01,
      );
      expect(hits.map((h) => h.sourceMemoryId), contains('m1'));
      expect(hits.first.sourceMemoryId, 'm1');
    });

    test('节点扩展：通过实体节点找到关联记忆', () {
      final hits = store.search(
        '火锅',
        limit: 5,
        expansionLimit: 24,
        expansionHops: 1,
        secondHopWeight: 0.4,
        sessionId: null,
        personaId: null,
        importanceOf: importanceOf,
        lastAccessOf: lastAccessOf,
        createdAtOf: createdAtOf,
        decayRate: 0.01,
      );
      expect(hits.map((h) => h.sourceMemoryId), contains('m1'));
    });

    test('scope 过滤：会话隔离下不返回其他会话的记忆', () {
      // 带会话归属的图谱
      final scopedStore = GraphMemoryStore();
      scopedStore.indexMemory(
          _memory('m1', participants: ['张三'], sessionId: 'session-a'), [
        _atom('m1', '张三最喜欢的食物是火锅', entities: ['火锅'], type: AtomType.preference),
      ]);
      final hits = scopedStore.search(
        '张三喜欢吃什么',
        limit: 5,
        expansionLimit: 24,
        expansionHops: 1,
        secondHopWeight: 0.4,
        sessionId: 'session-b',
        personaId: null,
        importanceOf: importanceOf,
        lastAccessOf: lastAccessOf,
        createdAtOf: createdAtOf,
        decayRate: 0.01,
      );
      expect(hits, isEmpty);
      // 本会话可命中
      final ownHits = scopedStore.search(
        '张三喜欢吃什么',
        limit: 5,
        expansionLimit: 24,
        expansionHops: 1,
        secondHopWeight: 0.4,
        sessionId: 'session-a',
        personaId: null,
        importanceOf: importanceOf,
        lastAccessOf: lastAccessOf,
        createdAtOf: createdAtOf,
        decayRate: 0.01,
      );
      expect(ownHits.map((h) => h.sourceMemoryId), contains('m1'));
    });
  });

  group('序列化', () {
    test('toJson/fromJson 往返', () {
      final store = GraphMemoryStore();
      store.indexMemory(_memory('m1', participants: ['张三']), [
        _atom('m1', '张三喜欢爬山', entities: ['爬山']),
      ]);
      final json = store.toJson();
      final restored = GraphMemoryStore.fromJson(json);
      expect(restored.nodeCount, store.nodeCount);
      expect(restored.edgeCount, store.edgeCount);
      expect(restored.entryCount, store.entryCount);
    });
  });

  group('实体规范化', () {
    test('去除首尾标点、压缩空白、ASCII 转小写', () {
      expect(canonicalizeEntity('  张三，'), '张三');
      expect(canonicalizeEntity('Flutter  SDK'), 'flutter sdk');
      expect(canonicalizeEntity('咖啡'), '咖啡');
    });
  });
}
