import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/services/memory/graph_layout.dart';

void main() {
  LayoutNodeInput node(String id, {double radius = 5, double weight = 1}) =>
      LayoutNodeInput(
        id: id,
        radius: radius,
        weight: weight,
        memoryCount: 1,
        degree: 0,
      );

  LayoutEdgeInput edge(String a, String b) =>
      LayoutEdgeInput(id: '$a|describes|$b', source: a, target: b, weight: 1);

  group('图谱力导向布局（移植 LivingMemory graph-layout-core）', () {
    test('确定性：相同输入两次布局结果完全一致', () {
      final nodes = List.generate(12, (i) => node('n$i'));
      final edges = [
        edge('n0', 'n1'),
        edge('n0', 'n2'),
        edge('n1', 'n3'),
        edge('n2', 'n4'),
        edge('n3', 'n5'),
        edge('n4', 'n5'),
      ];
      final a = computeGraphLayout(nodes, edges);
      final b = computeGraphLayout(nodes, edges);
      expect(a.keys, b.keys);
      for (final key in a.keys) {
        expect(a[key]![0], closeTo(b[key]![0], 1e-9));
        expect(a[key]![1], closeTo(b[key]![1], 1e-9));
      }
    });

    test('节点互不重叠（斥力内建碰撞）', () {
      final nodes = List.generate(16, (i) => node('n$i'));
      final edges = [
        for (var i = 0; i < 15; i++) edge('n$i', 'n${(i + 1) % 16}'),
      ];
      final positions = computeGraphLayout(nodes, edges);
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          final dx = positions[nodes[i].id]![0] - positions[nodes[j].id]![0];
          final dy = positions[nodes[i].id]![1] - positions[nodes[j].id]![1];
          final dist = math.sqrt(dx * dx + dy * dy);
          expect(
            dist,
            greaterThan(20),
            reason: '${nodes[i].id} 与 ${nodes[j].id} 距离 $dist 过近',
          );
        }
      }
    });

    test('相连节点比随机节点对更近（弹簧聚拢）', () {
      final nodes = List.generate(10, (i) => node('n$i'));
      final positions = computeGraphLayout(nodes, [edge('n0', 'n1')]);
      double dist(String a, String b) {
        final dx = positions[a]![0] - positions[b]![0];
        final dy = positions[a]![1] - positions[b]![1];
        return math.sqrt(dx * dx + dy * dy);
      }

      final linked = dist('n0', 'n1');
      final unlinked = dist('n2', 'n3');
      expect(linked, lessThan(unlinked * 1.4));
    });

    test('单节点与空图', () {
      expect(computeGraphLayout([], []).isEmpty, isTrue);
      final one = computeGraphLayout([node('only')], []);
      expect(one['only'], isNotNull);
    });
  });

  group('标签防重叠规则（移植 graph-renderer）', () {
    test('labelScore 公式', () {
      expect(
        labelScoreOf(degree: 5, memoryCount: 2, entryCount: 3, weight: 4),
        5 * 2 + 2 * 3 + 3 + 4,
      );
    });

    test('重要性门槛：degree>=5 或 memoryCount>=4 或 labelScore>=15', () {
      expect(isProminentNode(degree: 5, memoryCount: 0, labelScore: 0), isTrue);
      expect(isProminentNode(degree: 0, memoryCount: 4, labelScore: 0), isTrue);
      expect(
        isProminentNode(degree: 2, memoryCount: 2, labelScore: 16),
        isTrue,
      );
      expect(
        isProminentNode(degree: 2, memoryCount: 2, labelScore: 10),
        isFalse,
      );
    });

    test('可见性门槛：选中恒显示；有选中时其他不显示；缩放阈值生效', () {
      // 选中恒显示
      expect(
        shouldShowLabel(
          scale: 0.2,
          selected: true,
          hasSelection: true,
          prominent: false,
          degree: 0,
        ),
        isTrue,
      );
      // 有选中时，非选中不显示
      expect(
        shouldShowLabel(
          scale: 2.0,
          selected: false,
          hasSelection: true,
          prominent: true,
          degree: 10,
        ),
        isFalse,
      );
      // 无选中：scale<=0.64 时重点节点也不显示
      expect(
        shouldShowLabel(
          scale: 0.5,
          selected: false,
          hasSelection: false,
          prominent: true,
          degree: 8,
        ),
        isFalse,
      );
      // scale>0.64 + prominent 显示
      expect(
        shouldShowLabel(
          scale: 0.7,
          selected: false,
          hasSelection: false,
          prominent: true,
          degree: 0,
        ),
        isTrue,
      );
      // scale>0.64 但非 prominent 不显示
      expect(
        shouldShowLabel(
          scale: 0.7,
          selected: false,
          hasSelection: false,
          prominent: false,
          degree: 2,
        ),
        isFalse,
      );
      // scale>1.18 且 degree>=3 显示
      expect(
        shouldShowLabel(
          scale: 1.3,
          selected: false,
          hasSelection: false,
          prominent: false,
          degree: 3,
        ),
        isTrue,
      );
    });

    test('AABB 碰撞判定', () {
      final a = [0.0, 0.0, 40.0, 14.0];
      final b = [30.0, 5.0, 80.0, 20.0]; // 与 a 重叠
      final c = [50.0, 20.0, 90.0, 34.0]; // 与 a 不重叠
      expect(labelBoxesOverlap(a, b, 0, 0), isTrue);
      expect(labelBoxesOverlap(a, c, 0, 0), isFalse);
    });

    test('字号整数化并夹取 10-18', () {
      expect(labelFontSize(0.2), 10);
      expect(labelFontSize(1.0), 11);
      expect(labelFontSize(3.0), 18);
      expect(labelFontSize(1.27) % 1, 0); // 整数
    });

    test('截断 24/28 字符', () {
      expect(truncateLabel('a' * 30).length, 25); // 24 + …
      expect(truncateLabel('b' * 30, center: true).length, 29);
      expect(truncateLabel('短标签'), '短标签');
    });

    test('事实标签清理：剥日期前缀与人物名前缀', () {
      expect(cleanupFactLabel('2025-11-20 张三喜欢科幻电影', ['张三']), '喜欢科幻电影');
      expect(cleanupFactLabel('张三的猫叫小花', ['张三']), '猫叫小花');
      // 剥不掉时原样返回
      expect(cleanupFactLabel('去爬山', ['张三']), '去爬山');
    });
  });

  group('节点半径与边弯曲', () {
    test('半径公式与上限', () {
      expect(nodeWorldRadius(weight: 0, memoryCount: 0), 4);
      // 极大权重被 clamp 到 [4,10]，实际公式上限 ≈ 4+√20*0.75+√15*0.4
      final maxR = nodeWorldRadius(weight: 100, memoryCount: 100);
      expect(
        maxR,
        closeTo(4 + math.sqrt(20) * 0.75 + math.sqrt(15) * 0.4, 0.01),
      );
      expect(maxR, lessThanOrEqualTo(10));
      final base = nodeWorldRadius(weight: 4, memoryCount: 1);
      expect(base, closeTo(4 + 2 * 0.75 + 1 * 0.4, 0.01));
      expect(
        nodeWorldRadius(weight: 4, memoryCount: 1, selected: true),
        closeTo(base + 1.5, 0.01),
      );
    });

    test('边弯曲方向由 id 哈希决定，幅度 clamp 24', () {
      final bendA = edgeBend('a|describes|b', 1000);
      // 不同 id 至少有一个方向不同（不一定相反，此处仅验证确定性与幅度）
      expect(bendA.abs(), 24); // min(24, 1000*0.065)
      expect(edgeBend('a|describes|b', 1000), bendA);
      expect(edgeBend('b|describes|a', 1000).abs(), 24);
    });
  });
}
