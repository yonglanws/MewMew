import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/atom_classifier.dart';

void main() {
  final now = DateTime(2025, 11, 19, 14); // 周三

  MemoryAtom classify(String fact) => classifyFact(
    fact: fact,
    parentMemoryId: 'parent-1',
    parentImportance: 0.7,
    entities: const ['张三'],
    sessionId: 's1',
    personaId: 'p1',
    now: now,
  )!;

  group('原子分类（规则优先级照抄原版）', () {
    test('时间词 + 动作词 → planned，并解析事件时间', () {
      final atom = classify('张三安排明天下午3点开会');
      expect(atom.atomType, AtomType.planned);
      expect(atom.confidence, 0.85);
      expect(atom.eventTime, isNotNull);
      expect(atom.decayType, AtomDecayType.step);
    });

    test('偏好词 → preference', () {
      final atom = classify('张三最喜欢吃辣');
      expect(atom.atomType, AtomType.preference);
      expect(atom.confidence, 0.82);
    });

    test('关系词 → relational', () {
      final atom = classify('李四是张三的同事');
      expect(atom.atomType, AtomType.relational);
      expect(atom.confidence, 0.80);
      expect(atom.decayType, AtomDecayType.linear);
    });

    test(
      '状态动词 → factual',
      () => expect(
        classify('项目仓库的地址是 github.com/example').atomType,
        AtomType.factual,
      ),
    );

    test('仅动作词 → episodic', () {
      final atom = classify('张三提交了代码');
      expect(atom.atomType, AtomType.episodic);
      expect(atom.confidence, 0.75);
    });

    test('兜底 → unknown', () {
      final atom = classify('今天天气很好');
      expect(atom.atomType, AtomType.unknown);
      expect(atom.confidence, 0.60);
    });

    test('空事实返回 null', () {
      expect(
        classifyFact(
          fact: '  ',
          parentMemoryId: 'p',
          parentImportance: 0.5,
          entities: const [],
          sessionId: null,
          personaId: null,
        ),
        isNull,
      );
    });
  });

  group('中文相对时间解析', () {
    test('明天', () {
      expect(parseChineseRelativeTime('明天见面', now), DateTime(2025, 11, 20));
    });
    test('昨天', () {
      expect(parseChineseRelativeTime('昨天聊过', now), DateTime(2025, 11, 18));
    });
    test('后天', () {
      expect(parseChineseRelativeTime('后天出发', now), DateTime(2025, 11, 21));
    });
    test('N月D日（未来保留当年）', () {
      expect(parseChineseRelativeTime('12月1日聚会', now), DateTime(2025, 12, 1));
    });
    test('N月D日（已过顺延一年）', () {
      expect(parseChineseRelativeTime('1月5日的约定', now), DateTime(2026, 1, 5));
    });
    test('无法解析返回 null', () {
      expect(parseChineseRelativeTime('随便聊聊', now), isNull);
    });
  });

  group('TTL 与衰减', () {
    test('基础 TTL 对照表', () {
      expect(baseTtlDays(AtomType.episodic), 7);
      expect(baseTtlDays(AtomType.planned), 2);
      expect(baseTtlDays(AtomType.factual), 180);
      expect(baseTtlDays(AtomType.relational), 90);
      expect(baseTtlDays(AtomType.preference), 60);
      expect(baseTtlDays(AtomType.unknown), 30);
    });

    test('TTL 公式：base × (0.5+importance) × (1+min(0.5, n×0.1))', () {
      final ttl = computeAtomTtl(
        atomType: AtomType.unknown,
        baseTtlDays: 30,
        importance: 0.5,
        reinforcementCount: 0,
        now: now,
      );
      expect(ttl, closeTo(30.0, 0.01)); // 0.5+0.5=1.0，无强化
      final reinforced = computeAtomTtl(
        atomType: AtomType.unknown,
        baseTtlDays: 30,
        importance: 0.5,
        reinforcementCount: 3,
        now: now,
      );
      expect(reinforced, closeTo(30 * 1.3, 0.01));
      // importance=1.0 → 1.5 倍
      final important = computeAtomTtl(
        atomType: AtomType.unknown,
        baseTtlDays: 30,
        importance: 1.0,
        reinforcementCount: 0,
        now: now,
      );
      expect(important, closeTo(45.0, 0.01));
    });

    test('planned 原子按未来事件时间顺延 TTL', () {
      final ttl = computeAtomTtl(
        atomType: AtomType.planned,
        baseTtlDays: 2,
        importance: 0.5,
        reinforcementCount: 0,
        eventTime: now.add(const Duration(days: 10)),
        now: now,
      );
      expect(ttl, closeTo(12.0, 0.01));
    });

    test('指数衰减半衰期为 ttl/2', () {
      // ttl=30 → 半衰期 15 天 → 15 天后分数应为 0.5
      final score = atomDecayScore(AtomDecayType.exponential, 30, 15);
      expect(score, closeTo(0.5, 0.01));
    });

    test('线性衰减在 ttl 处为 0', () {
      expect(atomDecayScore(AtomDecayType.linear, 90, 90), 0.0);
      expect(atomDecayScore(AtomDecayType.linear, 90, 45), closeTo(0.5, 0.01));
    });

    test('step 衰减在 ttl 后骤降至 0.05', () {
      expect(atomDecayScore(AtomDecayType.step, 2, 1), 1.0);
      expect(atomDecayScore(AtomDecayType.step, 2, 3), 0.05);
    });
  });
}
