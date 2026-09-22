import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/consolidation.dart';

MemoryEntry _entry(
  String id, {
  required String sessionId,
  double importance = 0.3,
  DateTime? createdAt,
  List<double>? embedding,
}) =>
    MemoryEntry(
      id: id,
      content: '记忆$id',
      createdAt: createdAt ?? DateTime(2025, 9, 1),
      source: 'summary',
      sessionId: sessionId,
      importance: importance,
      embedding: embedding,
    );

void main() {
  final now = DateTime(2025, 11, 20);
  const config = ConsolidationConfig();

  group('候选筛选', () {
    test('active + 重要性低于上限 + 组龄达标', () {
      final candidates = findConsolidationCandidates(
        [
          _entry('ok', sessionId: 's1'),
          _entry('young', sessionId: 's1', createdAt: DateTime(2025, 11, 19)),
          _entry('important', sessionId: 's1', importance: 0.8),
        ],
        config: config,
        now: now,
      );
      expect(candidates.map((m) => m.id), ['ok']);
    });
  });

  group('分组', () {
    test('会话分组：同会话归组、无会话跳过', () {
      final groups = groupBySession([
        _entry('a', sessionId: 's1'),
        _entry('b', sessionId: 's1'),
        _entry('c', sessionId: 's2'),
        _entry('general', sessionId: 's1'),
      ]);
      expect(groups.length, 2);
      final s1 = groups.firstWhere((g) => g.first.sessionId == 's1');
      expect(s1.length, 3);
    });

    test('语义分组：相似嵌入聚成一簇（并查集）', () {
      final groups = groupBySemantic([
        _entry('a', sessionId: 's1', embedding: [1, 0, 0]),
        _entry('b', sessionId: 's2', embedding: [0.99, 0.14, 0]), // 与 a 高相似
        _entry('c', sessionId: 's3', embedding: [0, 0, 1]), // 无关
      ], 0.7);
      // {a, b} 一簇，{c} 自成一簇
      expect(groups.length, 2);
      final abGroup = groups.firstWhere((g) => g.any((m) => m.id == 'a'));
      expect(abGroup.map((m) => m.id).toSet(), {'a', 'b'});
    });

    test('buildConsolidationGroups 过滤最小组规模并按大小排序', () {
      final groups = buildConsolidationGroups([
        _entry('a', sessionId: 's1'),
        _entry('b', sessionId: 's1'),
        _entry('c', sessionId: 's1'),
        _entry('d', sessionId: 's2'),
        _entry('e', sessionId: 's2'),
      ], config: config);
      expect(groups.length, 1);
      expect(groups.first.length, 3);
    });
  });

  group('LLM 合并输出解析', () {
    test('标准 JSON', () {
      final r = parseMergeResponse(
        '{"summary":"合并后的摘要","key_facts":["事实1","事实2"],"topics":["主题"],"importance":0.6}',
      );
      expect(r, isNotNull);
      expect(r!.summary, '合并后的摘要');
      expect(r.keyFacts.length, 2);
      expect(r.importance, 0.6);
    });

    test('带栅栏与尾逗号', () {
      final r = parseMergeResponse(
        '```json\n{"summary":"摘要内容","key_facts":["a",],"topics":[],"importance":0.4,}\n```',
      );
      expect(r, isNotNull);
      expect(r!.keyFacts, ['a']);
    });

    test('空摘要返回 null', () {
      expect(parseMergeResponse('{"summary":"","key_facts":[]}'), isNull);
      expect(parseMergeResponse('乱码'), isNull);
    });

    test('合并条目构建', () {
      final items = buildMergeItems([
        _entry('a', sessionId: 's1')..keyFacts = ['事实'],
      ]);
      expect(items.first['summary'], '记忆a');
      expect(items.first['key_facts'], ['事实']);
    });
  });
}
