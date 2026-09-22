/// 记忆生命周期维护（移植自 LivingMemory memory_engine_crud.apply_daily_decay /
/// atom_lifecycle_manager / memory_engine_batch.cleanup_old_memories）。
/// 全部为纯函数，由 AppState 在启动/恢复/每日定时调用。
library;

import '../../models/models.dart';

/// 文档级每日衰减结果
class DecayReport {
  final int processedCount;
  final DateTime? lastRunDate;

  const DecayReport({required this.processedCount, this.lastRunDate});
}

/// 每日重要性衰减（照抄 apply_daily_decay 公式，支持漏跑天数补齐）。
///
/// - 最近 [accessWindowDays] 天内访问过的记忆衰减更慢（因子 1.0，否则 0.5）
/// - 访问次数越多衰减越慢（accessFactor 抵消一半以内的衰减率）
/// - importance ≥ [protectionThreshold] 的记忆受保护不衰减
/// - 每次执行后 accessCount 乘以 [accessCountMultiplier]
DecayReport applyDailyDecay(
  List<MemoryEntry> memories, {
  required double decayRate,
  required double protectionThreshold,
  required int maxAccessBoost,
  required double accessWindowDays,
  required double accessCountMultiplier,
  required DateTime? lastRunDate,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  if (decayRate <= 0) {
    return DecayReport(processedCount: 0, lastRunDate: today);
  }
  // 与上次执行的间隔天数（首次执行按 1 天计）
  var days = 1;
  if (lastRunDate != null) {
    final last = DateTime(lastRunDate.year, lastRunDate.month, lastRunDate.day);
    final diff = today.difference(last).inDays;
    if (diff <= 0) {
      return DecayReport(processedCount: 0, lastRunDate: lastRunDate);
    }
    days = diff; // 漏跑补齐：一次结算全部间隔
  }

  var processed = 0;
  for (final m in memories) {
    if (m.status != 'active') continue;
    if (m.importance >= protectionThreshold) continue;
    processed++;

    final recentAccessFactor =
        (m.lastAccessTime != null &&
                current.difference(m.lastAccessTime!).inDays <= accessWindowDays)
            ? 1.0
            : 0.5;
    final accessFactor = maxAccessBoost > 0
        ? (m.accessCount / maxAccessBoost).clamp(0.0, 1.0)
        : 0.0;
    final effectiveRate =
        decayRate * (1 - 0.5 * accessFactor * recentAccessFactor);
    final factor = _pow(1 - effectiveRate, days);
    m.importance = (m.importance * factor).clamp(0.01, 1.0);
    m.accessCount = (m.accessCount * accessCountMultiplier).floor();
  }
  return DecayReport(processedCount: processed, lastRunDate: today);
}

double _pow(double base, int exponent) {
  var result = 1.0;
  var b = base;
  var e = exponent;
  while (e > 0) {
    if (e & 1 == 1) result *= b;
    b *= b;
    e >>= 1;
  }
  return result;
}

/// 原子清扫结果
class AtomSweepReport {
  final int expiredCount;
  final int forgottenCount;
  final int purgedCount;

  const AtomSweepReport({
    required this.expiredCount,
    required this.forgottenCount,
    required this.purgedCount,
  });
}

/// 原子三段清扫（照抄 AtomLifecycleManager）：
/// active→expired（过期）、expired→forgotten（超过遗忘延迟）、forgotten→删除（超过清理延迟）。
AtomSweepReport sweepAtoms(
  List<MemoryAtom> atoms, {
  required double forgetDelayDays,
  required double purgeDelayDays,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  var expired = 0, forgotten = 0, purged = 0;

  final forgetDeadline =
      current.subtract(Duration(milliseconds: (forgetDelayDays * 86400000).round()));
  final purgeDeadline =
      current.subtract(Duration(milliseconds: (purgeDelayDays * 86400000).round()));

  atoms.removeWhere((atom) {
    if (atom.status == AtomStatus.active && atom.isExpired(current)) {
      atom.status = AtomStatus.expired;
      expired++;
    }
    if (atom.status == AtomStatus.expired && atom.expiresAt.isBefore(forgetDeadline)) {
      atom.status = AtomStatus.forgotten;
      forgotten++;
    }
    if (atom.status == AtomStatus.forgotten &&
        atom.expiresAt.isBefore(purgeDeadline)) {
      purged++;
      return true; // 物理删除
    }
    return false;
  });
  return AtomSweepReport(
    expiredCount: expired,
    forgottenCount: forgotten,
    purgedCount: purged,
  );
}

/// 访问强化：检索命中时调用（照抄 engine 的 access-time 更新 + atom touch）
void reinforceOnRetrieval(
  MemoryEntry entry,
  List<MemoryAtom> atoms, {
  required int maxAccessBoost,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  entry.lastAccessTime = current;
  entry.accessCount = entry.accessCount >= 1000000
      ? entry.accessCount
      : entry.accessCount + 1;
  for (final atom in atoms) {
    if (atom.status == AtomStatus.active && !atom.isExpired(current)) {
      atom.lastAccessedAt = current;
    }
  }
}

/// 清理候选筛选（照抄 cleanup_old_memories 的条件）
List<MemoryEntry> findCleanupCandidates(
  List<MemoryEntry> memories, {
  required int daysThreshold,
  required double importanceThreshold,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final cutoff = current.subtract(Duration(days: daysThreshold));
  return memories
      .where((m) =>
          m.status == 'active' &&
          m.createdAt.isBefore(cutoff) &&
          m.importance < importanceThreshold &&
          m.consolidatedFrom.isEmpty) // 合并产物保留（有溯源价值）
      .toList();
}

/// 归档一条记忆（保留文档，退出检索与注入）
void archiveMemory(MemoryEntry memory, {DateTime? now}) {
  memory.status = 'archived';
  memory.archivedAt = now ?? DateTime.now();
}

/// 恢复归档记忆
void restoreMemory(MemoryEntry memory) {
  memory.status = 'active';
  memory.archivedAt = null;
}

/// 启动一致性：清理指向已不存在记忆的原子（返回保留的原子列表）
List<MemoryAtom> pruneOrphanAtoms(
  List<MemoryAtom> atoms,
  Set<String> validMemoryIds,
) {
  return atoms.where((a) => validMemoryIds.contains(a.parentMemoryId)).toList();
}
