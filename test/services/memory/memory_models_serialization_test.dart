import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';

void main() {
  group('MemoryEntry 序列化（v2 元数据 + 生命周期字段）', () {
    test('完整字段往返', () {
      final entry = MemoryEntry(
        id: 'm1',
        content: '张三提醒明天开会 | 张三安排明天下午3点会议',
        createdAt: DateTime(2025, 11, 19, 14, 30),
        source: 'summary',
        personaId: 'p1',
        sessionId: 's1',
        importance: 0.85,
        accessCount: 3,
        lastAccessTime: DateTime(2025, 11, 20, 9),
        status: 'active',
        personaSummary: '张三提醒我明天开会',
        canonicalSummary: '张三安排会议',
        topics: ['会议'],
        keyFacts: ['张三安排明天开会'],
        participants: ['张三'],
        sentiment: 'neutral',
        interactionType: 'private_chat',
        summaryQuality: 'normal',
        timeTags: ['2025-11-19'],
        sourceTimeLabel: '2025-11-19',
      );
      final restored = MemoryEntry.fromJson(entry.toJson());
      expect(restored.id, 'm1');
      expect(restored.status, 'active');
      expect(restored.lastAccessTime, entry.lastAccessTime);
      expect(restored.personaSummary, '张三提醒我明天开会');
      expect(restored.topics, ['会议']);
      expect(restored.keyFacts, ['张三安排明天开会']);
      expect(restored.participants, ['张三']);
      expect(restored.sentiment, 'neutral');
      expect(restored.summaryQuality, 'normal');
      expect(restored.timeTags, ['2025-11-19']);
      expect(restored.displayContent, '张三提醒我明天开会');
    });

    test('旧数据兼容：无新字段时回退默认值', () {
      final restored = MemoryEntry.fromJson({
        'id': 'legacy',
        'content': '旧记忆',
        'createdAt': '2025-01-01T00:00:00.000',
        'source': 'manual',
      });
      expect(restored.status, 'active');
      expect(restored.importance, 0.5);
      expect(restored.interactionType, 'manual');
      expect(restored.displayContent, '旧记忆');
      expect(restored.lastAccessTime, isNull);
    });

    test('归档往返', () {
      final entry = MemoryEntry(
        id: 'm2',
        content: '内容',
        createdAt: DateTime(2025, 11, 19),
        status: 'archived',
        archivedAt: DateTime(2025, 11, 20),
        consolidatedFrom: ['old1', 'old2'],
        atomTypes: ['preference', 'planned'],
      );
      final restored = MemoryEntry.fromJson(entry.toJson());
      expect(restored.status, 'archived');
      expect(restored.archivedAt, entry.archivedAt);
      expect(restored.consolidatedFrom, ['old1', 'old2']);
      expect(restored.atomTypes, ['preference', 'planned']);
    });
  });

  group('MemoryAtom 序列化', () {
    test('完整字段往返', () {
      final atom = MemoryAtom(
        id: 'a1',
        parentMemoryId: 'm1',
        atomType: AtomType.planned,
        content: '明天开会',
        entities: ['会议'],
        importance: 0.8,
        confidence: 0.85,
        createdAt: DateTime(2025, 11, 19),
        lastAccessedAt: DateTime(2025, 11, 20),
        eventTime: DateTime(2025, 11, 21, 15),
        ttlDays: 3,
        expiresAt: DateTime(2025, 11, 22),
        reinforcementCount: 2,
        sessionId: 's1',
        personaId: 'p1',
      );
      final restored = MemoryAtom.fromJson(atom.toJson());
      expect(restored.atomType, AtomType.planned);
      expect(restored.eventTime, atom.eventTime);
      expect(restored.expiresAt, atom.expiresAt);
      expect(restored.reinforcementCount, 2);
      expect(restored.decayType, AtomDecayType.exponential);
      expect(restored.sessionId, 's1');
    });

    test('非法枚举回退默认', () {
      final restored = MemoryAtom.fromJson({
        'id': 'a',
        'parentMemoryId': 'p',
        'atomType': 'weird',
        'content': '内容',
        'createdAt': '2025-11-19T00:00:00.000',
        'expiresAt': '2025-12-19T00:00:00.000',
        'status': 'unknown-status',
      });
      expect(restored.atomType, AtomType.unknown);
      expect(restored.status, AtomStatus.active);
    });
  });

  group('MemorySettings 序列化（含新字段默认值）', () {
    test('默认值对照 LivingMemory schema', () {
      final s = MemorySettings();
      expect(s.memoryScopeMode, 'session');
      expect(s.retrievalCount, 5);
      expect(s.maxK, 10);
      expect(s.rrfK, 60);
      expect(s.scoreAlpha, 0.5);
      expect(s.scoreBeta, 0.25);
      expect(s.scoreGamma, 0.25);
      expect(s.mmrLambda, 0.7);
      expect(s.graphEnabled, isTrue);
      expect(s.atomEnabled, isTrue);
      expect(s.documentRouteWeight, 0.65);
      expect(s.graphRouteWeight, 0.35);
      expect(s.crossRouteBonus, 0.08);
      expect(s.recentMemoryCount, 2);
      expect(s.recentMemoryMaxAgeHours, 72);
      expect(s.consolidationEnabled, isFalse);
      expect(s.consolidationKeepOriginal, 'archive');
      expect(s.cleanupDaysThreshold, 30);
      expect(s.autoArchiveEnabled, isFalse);
    });

    test('copyWith + 往返', () {
      final s = MemorySettings().copyWith(
        summaryThreshold: 5,
        graphEnabled: false,
        consolidationEnabled: true,
        consolidationGranularity: 'semantic',
        decayRate: 0.02,
      );
      final restored = MemorySettings.fromJson(s.toJson());
      expect(restored.summaryThreshold, 5);
      expect(restored.graphEnabled, isFalse);
      expect(restored.consolidationEnabled, isTrue);
      expect(restored.consolidationGranularity, 'semantic');
      expect(restored.decayRate, 0.02);
      // 未改动的字段保持默认
      expect(restored.maxK, 10);
    });

    test('旧配置 JSON 兼容（只有老字段）', () {
      final restored = MemorySettings.fromJson({
        'useSessionFiltering': false,
        'summaryThreshold': 8,
        'retrievalCount': 3,
      });
      expect(restored.useSessionFiltering, isFalse);
      expect(restored.memoryScopeMode, 'global');
      expect(restored.summaryThreshold, 8);
      expect(restored.retrievalCount, 3);
      expect(restored.graphEnabled, isTrue); // 新字段默认
    });
  });
}
