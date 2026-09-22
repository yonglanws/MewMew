import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/memory_lifecycle.dart';

MemoryEntry _entry({
  required String id,
  double importance = 0.5,
  int accessCount = 0,
  DateTime? lastAccessTime,
  String status = 'active',
  DateTime? createdAt,
}) =>
    MemoryEntry(
      id: id,
      content: '内容$id',
      createdAt: createdAt ?? DateTime(2025, 10, 1),
      importance: importance,
      accessCount: accessCount,
      lastAccessTime: lastAccessTime,
      status: status,
    );

final now = DateTime(2025, 11, 20);

void main() {
  runTests(now);
}

void runTests(DateTime now) {

  group('每日衰减（applyDailyDecay）', () {
    test('常规衰减：importance 乘以 (1-rate)^days', () {
      final m = _entry(id: 'a', importance: 1.0 - 0.01);
      final report = applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 19),
        now: now,
      );
      expect(report.processedCount, 1);
      // 1 天间隔
      expect(m.importance, closeTo((1 - 0.01) * 0.99, 1e-6));
    });

    test('漏跑补齐：3 天间隔一次结算', () {
      final m = _entry(id: 'a', importance: 0.99);
      applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 17),
        now: now,
      );
      expect(m.importance, closeTo(0.99 * _p(0.99, 3), 1e-6));
    });

    test('同日重跑不衰减', () {
      final m = _entry(id: 'a', importance: 0.5);
      applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: now,
        now: now,
      );
      expect(m.importance, 0.5);
    });

    test('受保护记忆不衰减', () {
      final m = _entry(id: 'a', importance: 1.0);
      applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 19),
        now: now,
      );
      expect(m.importance, 1.0);
    });

    test('访问反馈：近期访问 + 高访问次数 → 衰减率减半', () {
      final accessed = _entry(
        id: 'accessed',
        importance: 0.99,
        accessCount: 10, // accessFactor = 1.0
        lastAccessTime: DateTime(2025, 11, 19), // 窗口内
      );
      final untouched = _entry(id: 'untouched', importance: 0.99);
      applyDailyDecay(
        [accessed, untouched],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 19),
        now: now,
      );
      // accessed: effectiveRate = 0.01 * (1 - 0.5*1*1) = 0.005
      expect(accessed.importance, closeTo(0.99 * _p(0.995, 1), 1e-6));
      // untouched: effectiveRate = 0.01（无访问反馈，但 recentAccessFactor=0.5）
      // accessFactor=0 → effectiveRate = 0.01
      expect(untouched.importance, closeTo(0.99 * _p(0.99, 1), 1e-6));
    });

    test('访问次数每轮减半', () {
      final m = _entry(id: 'a', accessCount: 7, importance: 0.5);
      applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 19),
        now: now,
      );
      expect(m.accessCount, 3); // floor(7*0.5)
    });

    test('归档记忆不衰减', () {
      final m = _entry(id: 'a', importance: 0.5, status: 'archived');
      final report = applyDailyDecay(
        [m],
        decayRate: 0.01,
        protectionThreshold: 1.0,
        maxAccessBoost: 10,
        accessWindowDays: 30,
        accessCountMultiplier: 0.5,
        lastRunDate: DateTime(2025, 11, 19),
        now: now,
      );
      expect(report.processedCount, 0);
      expect(m.importance, 0.5);
    });
  });

  group('原子清扫（三段生命周期）', () {
    AtomSweepReport sweep(List<MemoryAtom> atoms) => sweepAtoms(
          atoms,
          forgetDelayDays: 7,
          purgeDelayDays: 30,
          now: now,
        );

    test('active → expired（过期）', () {
      final atom = _expiredAtom(1); // 过期 1 天
      sweep([atom]);
      expect(atom.status, AtomStatus.expired);
    });

    test('expired → forgotten（超过 7 天遗忘延迟）', () {
      final atom = _expiredAtom(10); // 过期 10 天
      sweep([atom]);
      expect(atom.status, AtomStatus.forgotten);
    });

    test('forgotten → 物理删除（超过 30 天清理延迟）', () {
      final atom = _expiredAtom(40); // 过期 40 天
      final report = sweep([atom]);
      expect(report.purgedCount, 1);
    });

    test('未过期原子不受影响', () {
      final atom = MemoryAtom(
        id: 'a',
        parentMemoryId: 'p',
        content: '内容',
        createdAt: now.subtract(const Duration(days: 1)),
        ttlDays: 30,
        expiresAt: now.add(const Duration(days: 29)),
      );
      sweep([atom]);
      expect(atom.status, AtomStatus.active);
    });
  });

  group('清理候选与归档', () {
    test('满足年龄与重要性条件的记忆入选', () {
      final old = _entry(id: 'old', importance: 0.2, createdAt: DateTime(2025, 9, 1));
      final young = _entry(id: 'young', importance: 0.2, createdAt: DateTime(2025, 11, 19));
      final important = _entry(id: 'imp', importance: 0.9, createdAt: DateTime(2025, 9, 1));
      final merged = _entry(id: 'merged', importance: 0.2, createdAt: DateTime(2025, 9, 1))
        ..consolidatedFrom = ['x'];
      final candidates = findCleanupCandidates(
        [old, young, important, merged],
        daysThreshold: 30,
        importanceThreshold: 0.3,
        now: now,
      );
      expect(candidates.map((m) => m.id), ['old']);
    });

    test('归档与恢复', () {
      final m = _entry(id: 'a');
      archiveMemory(m, now: now);
      expect(m.status, 'archived');
      expect(m.archivedAt, now);
      restoreMemory(m);
      expect(m.status, 'active');
      expect(m.archivedAt, isNull);
    });
  });

  group('孤儿原子清理', () {
    test('父记忆不存在的原子被移除', () {
      final atoms = [
        _atomWithParent('kept', 'm1'),
        _atomWithParent('dropped', 'deleted'),
      ];
      final kept = pruneOrphanAtoms(atoms, {'m1'});
      expect(kept.map((a) => a.id), ['kept']);
    });
  });
}

double _p(double base, int exp) {
  var r = 1.0;
  for (var i = 0; i < exp; i++) {
    r *= base;
  }
  return r;
}

MemoryAtom _expiredAtom(int daysAgo) {
  final expiresAt = now.subtract(Duration(days: daysAgo));
  return MemoryAtom(
    id: 'atom-$daysAgo',
    parentMemoryId: 'p',
    content: '过期原子$daysAgo',
    createdAt: expiresAt.subtract(const Duration(days: 30)),
    ttlDays: 1,
    expiresAt: expiresAt,
    status: AtomStatus.active,
  );
}

MemoryAtom _atomWithParent(String id, String parentId) => MemoryAtom(
      id: id,
      parentMemoryId: parentId,
      content: '内容$id',
      createdAt: DateTime(2025, 11, 1),
    );
