/// 记忆整理合并（移植自 LivingMemory consolidation_manager.py /
/// memory_engine_batch.find_similar_pairs / memory_processor.merge_memories）。
/// 纯函数部分：候选筛选、会话/语义分组（并查集）；LLM 合并由调用方注入。
library;

import 'dart:convert';

import '../../models/models.dart';
import 'hybrid_retrieval.dart' show cosineSimilarity;

/// 整理合并参数
class ConsolidationConfig {
  final String granularity; // session / semantic
  final String keepOriginal; // archive / delete
  final int minMemoriesPerGroup;
  final int maxGroupsPerRun;
  final double maxImportance;
  final int minAgeDays;
  final double semanticThreshold;

  const ConsolidationConfig({
    this.granularity = 'session',
    this.keepOriginal = 'archive',
    this.minMemoriesPerGroup = 3,
    this.maxGroupsPerRun = 5,
    this.maxImportance = 0.5,
    this.minAgeDays = 7,
    this.semanticThreshold = 0.7,
  });

  factory ConsolidationConfig.fromSettings(MemorySettings s) =>
      ConsolidationConfig(
        granularity: s.consolidationGranularity,
        keepOriginal: s.consolidationKeepOriginal,
        minMemoriesPerGroup: s.consolidationMinMemoriesPerGroup,
        maxGroupsPerRun: s.consolidationMaxGroupsPerRun,
        maxImportance: s.consolidationMaxImportance,
        minAgeDays: s.consolidationMinAgeDays,
        semanticThreshold: s.consolidationSemanticThreshold,
      );
}

/// 候选筛选（照抄 _query_candidates：active、重要性低于上限、组龄达到下限）
List<MemoryEntry> findConsolidationCandidates(
  List<MemoryEntry> memories, {
  required ConsolidationConfig config,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final cutoff = current.subtract(Duration(days: config.minAgeDays));
  return memories
      .where((m) =>
          m.status == 'active' &&
          m.importance < config.maxImportance &&
          m.createdAt.isBefore(cutoff))
      .toList();
}

/// 按会话分组（granularity=session）
List<List<MemoryEntry>> groupBySession(List<MemoryEntry> candidates) {
  final bySession = <String?, List<MemoryEntry>>{};
  for (final m in candidates) {
    if (m.sessionId == null) continue; // 无会话归属的无法按会话合并
    (bySession[m.sessionId] ??= []).add(m);
  }
  return bySession.values.toList();
}

/// 语义分组：嵌入余弦 ≥ 阈值连边 + 并查集连通分量（照抄 find_similar_pairs +
/// union-find with path halving）
List<List<MemoryEntry>> groupBySemantic(
  List<MemoryEntry> candidates,
  double threshold,
) {
  final withEmbedding =
      candidates.where((m) => m.embedding != null && m.embedding!.isNotEmpty).toList();
  if (withEmbedding.length < 2) return [];

  final parent = List<int>.generate(withEmbedding.length, (i) => i);

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]]; // path halving
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  for (var i = 0; i < withEmbedding.length; i++) {
    for (var j = i + 1; j < withEmbedding.length; j++) {
      final sim = cosineSimilarity(withEmbedding[i].embedding!, withEmbedding[j].embedding!);
      if (sim >= threshold) union(i, j);
    }
  }

  final groups = <int, List<MemoryEntry>>{};
  for (var i = 0; i < withEmbedding.length; i++) {
    (groups[find(i)] ??= []).add(withEmbedding[i]);
  }
  return groups.values.toList();
}

/// 生成完整分组结果（按大小降序、过滤最小组规模、截断每轮上限）
List<List<MemoryEntry>> buildConsolidationGroups(
  List<MemoryEntry> candidates, {
  required ConsolidationConfig config,
}) {
  final groups = config.granularity == 'semantic'
      ? groupBySemantic(candidates, config.semanticThreshold)
      : groupBySession(candidates);
  return groups
      .where((g) => g.length >= config.minMemoriesPerGroup)
      .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
}

/// 为一组待合并记忆构建 LLM 输入（照抄 merge_memories 的 items 结构）
List<Map<String, dynamic>> buildMergeItems(List<MemoryEntry> group) {
  return group
      .asMap()
      .entries
      .map((e) => {
            'id': e.key,
            'summary': e.value.displayContent,
            'key_facts': e.value.keyFacts,
            'topics': e.value.topics,
          })
      .toList();
}

/// 解析 LLM 合并输出（容忍栅栏/未闭合；照抄 _parse_merge_response）
({String summary, List<String> keyFacts, List<String> topics, double importance})?
    parseMergeResponse(String raw) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
  text = text.replaceAll(RegExp(r'\s*```$'), '').trim();
  // 去掉尾逗号（常见 LLM 输出瑕疵）；replaceAll 不支持 \1 反向引用，须用 replaceAllMapped
  text = text.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1] ?? '');

  Map<String, dynamic>? parsed;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) parsed = decoded;
  } catch (_) {}
  if (parsed == null) {
    final block = RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}').firstMatch(text);
    if (block != null) {
      try {
        final decoded = jsonDecode(block.group(0)!);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {}
    }
  }
  if (parsed == null) return null;

  final summary = (parsed['summary'] ?? '').toString().trim();
  if (summary.isEmpty) return null;
  final keyFacts = _stringList(parsed['key_facts'], 5);
  final topics = _stringList(parsed['topics'], 5);
  var importance = 0.5;
  final rawImp = parsed['importance'];
  if (rawImp is num) importance = rawImp.toDouble().clamp(0.0, 1.0);
  return (summary: summary, keyFacts: keyFacts, topics: topics, importance: importance);
}

List<String> _stringList(dynamic raw, int cap) {
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .take(cap)
        .toList();
  }
  return const [];
}
