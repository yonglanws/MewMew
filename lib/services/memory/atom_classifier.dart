/// 记忆原子分类与 TTL（移植自 LivingMemory core/processors/atom_classifier.py
/// 与 core/models/memory_atom.py）。纯规则、无 LLM。
library;

import 'package:uuid/uuid.dart';

import '../../models/models.dart';

const _uuid = Uuid();

// ---- 中文关键词正则（照抄原版词表） ----

/// 时间指示词
final RegExp timeIndicatorPattern = RegExp(
  r'明天|后天|大后天|昨天|前天|今天|(上周|本周|下下周|下周)?周[一二三四五六日天]|下个?月|上个?月|明年|后年|去年|前年|\d{1,2}月\d{1,2}[日号]|\d{4}年\d{1,2}月|上午|下午|晚上|凌晨|早上|中午|傍晚|\d{1,2}[点时：:]\d{1,2}',
);

/// 动作/计划动词
final RegExp actionVerbPattern = RegExp(
  r'开会|讨论|参加|组织|安排|举办|进行|执行|完成|提交|发送|发布|去|来|到|做|要|准备|计划|打算',
);

/// 状态动词（事实类）
final RegExp stativeVerbPattern = RegExp(r'是|有|属于|等于|代表|意味|包含|包括|位于');

/// 关系关键词
final RegExp relationPattern = RegExp(
  r'同事|朋友|同学|家人|亲戚|队友|搭档|伙伴|老板|上司|下属|合作|合伙|夫妻|情侣|邻居|室友|老乡',
);

/// 偏好关键词
final RegExp preferencePattern = RegExp(
  r'喜欢|讨厌|爱|不爱|偏好|最爱|不喜欢|热衷于|沉迷|爱吃|爱喝|喜欢喝|喜欢去|讨厌吃|讨厌去',
);

/// 单条关键事实 → 记忆原子
MemoryAtom? classifyFact({
  required String fact,
  required String parentMemoryId,
  required double parentImportance,
  required List<String> entities,
  required String? sessionId,
  required String? personaId,
  DateTime? now,
}) {
  final content = fact.trim();
  if (content.isEmpty) return null;
  final current = now ?? DateTime.now();

  final (type, confidence, eventTime) = _classifySingle(content, current);
  final baseTtl = baseTtlDays(type);
  final ttl = computeAtomTtl(
    atomType: type,
    baseTtlDays: baseTtl,
    importance: parentImportance,
    reinforcementCount: 0,
    eventTime: eventTime,
    now: current,
  );

  return MemoryAtom(
    id: _uuid.v4(),
    parentMemoryId: parentMemoryId,
    atomType: type,
    content: content,
    entities: List.of(entities),
    importance: parentImportance,
    confidence: confidence,
    createdAt: current,
    lastAccessedAt: current,
    eventTime: eventTime,
    ttlDays: ttl,
    expiresAt: current.add(Duration(milliseconds: (ttl * 86400000).round())),
    decayType: baseDecayType(type),
    sessionId: sessionId,
    personaId: personaId,
  );
}

/// 分类优先级与置信度（照抄原版 _classify_single）
(AtomType, double, DateTime?) _classifySingle(String text, DateTime now) {
  final hasTime = timeIndicatorPattern.hasMatch(text);
  final hasAction = actionVerbPattern.hasMatch(text);
  final hasStative = stativeVerbPattern.hasMatch(text);

  if (hasTime && hasAction) {
    return (AtomType.planned, 0.85, parseChineseRelativeTime(text, now));
  }
  if (preferencePattern.hasMatch(text)) {
    return (AtomType.preference, 0.82, null);
  }
  if (relationPattern.hasMatch(text)) {
    return (AtomType.relational, 0.80, null);
  }
  if (hasStative) {
    return (AtomType.factual, 0.78, null);
  }
  if (hasAction) {
    return (AtomType.episodic, 0.75, null);
  }
  return (AtomType.unknown, 0.60, null);
}

/// 各类型的基准 TTL（天）与衰减曲线（照抄原版 MEMORY_TYPE_TTL_CONFIG）
double baseTtlDays(AtomType type) => switch (type) {
  AtomType.episodic => 7,
  AtomType.planned => 2,
  AtomType.factual => 180,
  AtomType.relational => 90,
  AtomType.preference => 60,
  AtomType.unknown => 30,
};

AtomDecayType baseDecayType(AtomType type) => switch (type) {
  AtomType.planned => AtomDecayType.step,
  AtomType.relational => AtomDecayType.linear,
  _ => AtomDecayType.exponential,
};

/// TTL 计算（照抄原版 compute_ttl）：
/// planned 且有未来事件时间时基准顺延；importance 抬升、访问强化延长。
double computeAtomTtl({
  required AtomType atomType,
  required double baseTtlDays,
  required double importance,
  required int reinforcementCount,
  DateTime? eventTime,
  required DateTime now,
}) {
  var base = baseTtlDays;
  if (atomType == AtomType.planned && eventTime != null) {
    final daysUntil = eventTime.difference(now).inMilliseconds / 86400000.0;
    if (daysUntil > 0) base += daysUntil;
  }
  final importanceFactor = 0.5 + importance.clamp(0.0, 1.0);
  final reinforcementBonus = reinforcementCount * 0.1;
  final reinforcementFactor =
      1.0 + (reinforcementBonus > 0.5 ? 0.5 : reinforcementBonus);
  final ttl = base * importanceFactor * reinforcementFactor;
  return ttl < 1.0 ? 1.0 : ttl;
}

/// 中文相对时间解析（照抄原版 _parse_event_time 的主干）。
/// 解析不出返回 null。
DateTime? parseChineseRelativeTime(String text, DateTime now) {
  final date = DateTime(now.year, now.month, now.day);

  if (text.contains('大后天')) return date.add(const Duration(days: 3));
  if (text.contains('后天')) return date.add(const Duration(days: 2));
  if (text.contains('明天')) return date.add(const Duration(days: 1));
  if (text.contains('今天')) return date;
  if (text.contains('昨天')) return date.subtract(const Duration(days: 1));
  if (text.contains('前天')) return date.subtract(const Duration(days: 2));

  // 周 X（上周/本周/下周/下下周）
  final weekMatch = RegExp(r'(上周|本周|下周|下下周)?[周禮][一二三四五六日天]').firstMatch(text);
  if (weekMatch != null) {
    const prefixOffset = {'上周': -7, '本周': 0, '下周': 7, '下下周': 14};
    const weekdayMap = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    final prefix = weekMatch.group(1) ?? '本周';
    final weekdayChar = text.substring(weekMatch.end - 1, weekMatch.end);
    final targetWeekday = weekdayMap[weekdayChar];
    if (targetWeekday != null) {
      // 周一=1 ... 周日=7（DateTime.weekday 即此约定）
      var delta = targetWeekday - now.weekday + (prefixOffset[prefix] ?? 0);
      return date.add(Duration(days: delta));
    }
  }

  // N月D日（已过则顺延一年）
  final mdMatch = RegExp(r'(\d{1,2})月(\d{1,2})[日号]').firstMatch(text);
  if (mdMatch != null) {
    final month = int.tryParse(mdMatch.group(1)!);
    final day = int.tryParse(mdMatch.group(2)!);
    if (month != null && day != null && month >= 1 && month <= 12) {
      var candidate = DateTime(now.year, month, day);
      if (candidate.isBefore(date)) {
        candidate = DateTime(now.year + 1, month, day);
      }
      return candidate;
    }
  }

  // 时刻（今天/明天的几点几分）——默认挂到最近的一天
  final hmMatch = RegExp(r'(\d{1,2})[点时：:](\d{1,2})?分?').firstMatch(text);
  if (hmMatch != null) {
    final hour = int.tryParse(hmMatch.group(1)!);
    final minute = int.tryParse(hmMatch.group(2) ?? '0') ?? 0;
    if (hour != null && hour >= 0 && hour <= 23) {
      var candidate = DateTime(now.year, now.month, now.day, hour, minute);
      if (text.contains('明天')) {
        candidate = candidate.add(const Duration(days: 1));
      } else if (text.contains('后天')) {
        candidate = candidate.add(const Duration(days: 2));
      }
      return candidate;
    }
  }

  return null;
}

/// 批量分类：关键事实列表 → 原子列表（移植 classify_atoms_from_metadata）
List<MemoryAtom> classifyFacts({
  required List<String> keyFacts,
  required List<String> topics,
  required List<String> participants,
  required String parentMemoryId,
  required double parentImportance,
  required String? sessionId,
  required String? personaId,
  DateTime? now,
}) {
  final entities = <String>[...topics, ...participants];
  final atoms = <MemoryAtom>[];
  for (final fact in keyFacts) {
    final atom = classifyFact(
      fact: fact,
      parentMemoryId: parentMemoryId,
      parentImportance: parentImportance,
      entities: entities,
      sessionId: sessionId,
      personaId: personaId,
      now: now,
    );
    if (atom != null) atoms.add(atom);
  }
  return atoms;
}
