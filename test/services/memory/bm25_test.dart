import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/services/memory/bm25.dart';
import 'package:mewmew/services/memory/text_tokenizer.dart';

void main() {
  group('BM25 索引', () {
    test('相关文档得分更高（归一化到 0-1）', () {
      final index = Bm25Index();
      index.addDocument('d1', tokenize('用户喜欢猫，每天喂猫粮'));
      index.addDocument('d2', tokenize('明天下午三点开会讨论项目进度'));
      index.addDocument('d3', tokenize('天气不错出去散步'));

      final hits = index.search('用户喜欢什么动物', limit: 3);
      expect(hits, isNotEmpty);
      expect(hits.first.docId, 'd1');
      for (final h in hits) {
        expect(h.score, inInclusiveRange(0, 1));
      }
      // 降序
      for (var i = 0; i < hits.length - 1; i++) {
        expect(hits[i].score >= hits[i + 1].score, isTrue);
      }
    });

    test('白名单过滤生效', () {
      final index = Bm25Index();
      index.addDocument('s1-m1', tokenize('用户喜欢猫'));
      index.addDocument('s2-m1', tokenize('用户喜欢猫'));
      index.allowedDocIds = {'s1-m1'};
      final hits = index.search('喜欢猫的宠物', limit: 10);
      expect(hits.map((h) => h.docId), ['s1-m1']);
    });

    test('空查询或无命中返回空', () {
      final index = Bm25Index();
      index.addDocument('d1', tokenize('完全无关的内容'));
      expect(index.search('', limit: 5), isEmpty);
      expect(index.search('量子计算机器学习', limit: 5), isEmpty);
    });
  });

  group('RRF 融合', () {
    test('双路都命中的文档得分高于单路命中', () {
      final fused = rrfFuse(
        [
          ['a', 'b', 'c'],
          ['b', 'a', 'd'],
        ],
        k: 60,
        topK: 10,
      );
      // a: 1/61 + 1/62；b: 1/62 + 1/61 —— 并列，都高于 c 与 d
      expect(fused['a']!, closeTo(fused['b']!, 1e-9));
      expect(fused['a']!, greaterThan(fused['c']!));
      expect(fused['b']!, greaterThan(fused['d']!));
    });

    test('k 常数影响名次差距（k=60 照抄原版默认）', () {
      final fused = rrfFuse(
        [
          ['x', 'y'],
        ],
        k: 60,
        topK: 10,
      );
      expect(fused['x']!, closeTo(1 / 61, 1e-9));
      expect(fused['y']!, closeTo(1 / 62, 1e-9));
    });

    test('topK 截断', () {
      final fused = rrfFuse(
        [
          ['1', '2', '3', '4', '5'],
        ],
        k: 60,
        topK: 2,
      );
      expect(fused.length, 2);
    });
  });
}
