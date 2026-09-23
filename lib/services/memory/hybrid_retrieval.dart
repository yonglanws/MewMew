/// 混合检索（移植自 LivingMemory hybrid_retriever.py / dual_route_retriever.py /
/// atom_retriever.py / memory_engine 检索策略层）。
///
/// 管线：文档路（BM25 + 向量 RRF 融合 → α/β/γ 加权 → MMR 去重）
///      + 图谱路（GraphMemoryStore.search）
///      → 双路意图动态加权融合 → 原子增强 → 策略过滤 → 最近记忆保留位。
library;

import 'dart:math' as math;

import '../../models/models.dart';
import 'bm25.dart';
import 'graph_memory.dart';
import 'text_tokenizer.dart';

/// 检索输入的记忆视图（AppState 组装，解耦存储）
class RetrievalMemory {
  final MemoryEntry entry;
  final List<MemoryAtom> atoms; // 该记忆的原子（可为空）

  const RetrievalMemory({required this.entry, this.atoms = const []});
}

/// 检索结果（带分数分解，便于调试与 UI 展示）
class RetrievalResult {
  final RetrievalMemory memory;
  final double finalScore;
  final Map<String, double> breakdown;
  final bool fromRecent; // 是否占用最近记忆保留位

  const RetrievalResult({
    required this.memory,
    required this.finalScore,
    this.breakdown = const {},
    this.fromRecent = false,
  });

  MemoryEntry get entry => memory.entry;
}

/// 混合检索参数（从 MemorySettings 提取的本模块所需子集）
class RetrievalConfig {
  final int topK;
  final int rrfK;
  final double scoreAlpha;
  final double scoreBeta;
  final double scoreGamma;
  final double mmrLambda;
  final bool graphEnabled;
  final double documentRouteWeight;
  final double graphRouteWeight;
  final double crossRouteBonus;
  final bool dynamicRouteWeighting;
  final double decayRate;
  final double minImportanceForRetrieval;
  final double minSimilarityForRetrieval;
  final String memoryTypeFilter;
  final int recentMemoryCount;
  final double recentMemoryMaxAgeHours;
  final bool atomEnabled;
  final int graphExpansionLimit;
  final int graphExpansionHops;
  final double graphSecondHopWeight;

  const RetrievalConfig({
    this.topK = 5,
    this.rrfK = 60,
    this.scoreAlpha = 0.5,
    this.scoreBeta = 0.25,
    this.scoreGamma = 0.25,
    this.mmrLambda = 0.7,
    this.graphEnabled = true,
    this.documentRouteWeight = 0.65,
    this.graphRouteWeight = 0.35,
    this.crossRouteBonus = 0.08,
    this.dynamicRouteWeighting = true,
    this.decayRate = 0.01,
    this.minImportanceForRetrieval = 0.0,
    this.minSimilarityForRetrieval = 0.0,
    this.memoryTypeFilter = 'all',
    this.recentMemoryCount = 2,
    this.recentMemoryMaxAgeHours = 72,
    this.atomEnabled = true,
    this.graphExpansionLimit = 24,
    this.graphExpansionHops = 1,
    this.graphSecondHopWeight = 0.4,
  });

  factory RetrievalConfig.fromSettings(MemorySettings s) => RetrievalConfig(
    topK: s.retrievalCount,
    rrfK: s.rrfK,
    scoreAlpha: s.scoreAlpha,
    scoreBeta: s.scoreBeta,
    scoreGamma: s.scoreGamma,
    mmrLambda: s.mmrLambda,
    graphEnabled: s.graphEnabled,
    documentRouteWeight: s.documentRouteWeight,
    graphRouteWeight: s.graphRouteWeight,
    crossRouteBonus: s.crossRouteBonus,
    dynamicRouteWeighting: s.dynamicRouteWeighting,
    decayRate: s.decayRate,
    minImportanceForRetrieval: s.minImportanceForRetrieval,
    minSimilarityForRetrieval: s.minSimilarityForRetrieval,
    memoryTypeFilter: s.memoryTypeFilter,
    recentMemoryCount: s.recentMemoryCount,
    recentMemoryMaxAgeHours: s.recentMemoryMaxAgeHours,
    atomEnabled: s.atomEnabled,
    graphExpansionLimit: s.graphExpansionLimit,
    graphExpansionHops: s.graphExpansionHops,
    graphSecondHopWeight: s.graphSecondHopWeight,
  );
}

/// 过滤条件（会话/人格 scope）
class RetrievalScope {
  final String? sessionId;
  final String? personaId;
  final bool sessionFiltering;

  /// 人物隔离：只保留 personaId 完全相同的记忆，不把“无人物”记忆混进来。
  final bool strictPersona;

  const RetrievalScope({
    this.sessionId,
    this.personaId,
    this.sessionFiltering = true,
    this.strictPersona = false,
  });
}

/// 执行混合检索。
///
/// [queryEmbedding] 可为 null（无嵌入 API 时退化为纯 BM25 + 图谱）。
/// 返回已排序、已去重的最终结果列表。
Future<List<RetrievalResult>> searchMemories({
  required String query,
  required List<RetrievalMemory> candidates,
  required RetrievalScope scope,
  required RetrievalConfig config,
  required GraphMemoryStore? graphStore,
  List<double>? queryEmbedding,
  DateTime? now,
}) async {
  final current = now ?? DateTime.now();
  if (candidates.isEmpty || query.trim().isEmpty) return const [];

  // ---- scope 预过滤（只保留 active 记忆） ----
  bool scopeOk(RetrievalMemory m) {
    if (!m.entry.isActive) return false;
    final e = m.entry;
    if (scope.strictPersona) {
      if (e.personaId != scope.personaId) return false;
    } else {
      final personaOk =
          e.personaId == null ||
          scope.personaId == null ||
          e.personaId == scope.personaId;
      if (!personaOk) return false;
    }
    if (!scope.sessionFiltering) return true;
    return e.sessionId == null || e.sessionId == scope.sessionId;
  }

  final scoped = candidates.where(scopeOk).toList();
  if (scoped.isEmpty) return const [];
  final byId = {for (final m in scoped) m.entry.id: m};

  // ---- 文档路：BM25 + 向量 RRF 融合 ----
  final bm25 = Bm25Index();
  for (final m in scoped) {
    bm25.addDocument(m.entry.id, tokenize(m.entry.displayContent));
  }
  final bm25Hits = bm25.search(query, limit: config.topK * 4);
  final keywordRanking = bm25Hits.map((h) => h.docId).toList();
  final keywordScores = {for (final h in bm25Hits) h.docId: h.score};

  var vectorScores = <String, double>{};
  if (queryEmbedding != null) {
    final scored = <String, double>{};
    for (final m in scoped) {
      final emb = m.entry.embedding;
      if (emb == null || emb.length != queryEmbedding.length) continue;
      scored[m.entry.id] = cosineSimilarity(queryEmbedding, emb);
    }
    vectorScores = scored;
  }
  final vectorRanking =
      (vectorScores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.key)
          .toList();

  final fused = rrfFuse(
    [keywordRanking, vectorRanking],
    k: config.rrfK,
    topK: math.max(config.topK * 4, config.graphExpansionLimit),
  );
  final maxRrf = fused.isEmpty ? 1.0 : fused.values.first;

  // ---- 文档路加权（照抄 hybrid_retriever._apply_weighting） ----
  final docWeighted =
      <String, ({double score, Map<String, double> breakdown})>{};
  for (final e in fused.entries) {
    final m = byId[e.key]!;
    final importance = m.entry.importance.clamp(0.0, 1.0);
    final refTime = _referenceTime(m.entry, current);
    final daysOld = current.difference(refTime).inMilliseconds / 86400000.0;
    final recency = math.exp(-config.decayRate * (daysOld < 0 ? 0 : daysOld));
    final relevance = (e.value / maxRrf).clamp(0.0, 1.0);
    final score =
        config.scoreAlpha * relevance +
        config.scoreBeta * importance +
        config.scoreGamma * recency;
    docWeighted[e.key] = (
      score: score,
      breakdown: {
        'rrf_normalized': relevance,
        'importance': importance,
        'recency': recency,
        'keyword_score': keywordScores[e.key] ?? 0.0,
        'vector_score': vectorScores[e.key] ?? 0.0,
      },
    );
  }

  // ---- MMR 去重（Jaccard，照抄 _apply_mmr）：
  // 文档路在融合前截断为 topK 条多样结果 ----
  final mmrSelected = _applyMmr(docWeighted, scoped, config);
  docWeighted.removeWhere((id, _) => !mmrSelected.contains(id));

  // ---- 图谱路 ----
  Map<String, double> graphScores = {};
  if (config.graphEnabled && graphStore != null) {
    final hits = graphStore.search(
      query,
      limit: config.topK * 4,
      expansionLimit: config.graphExpansionLimit,
      expansionHops: config.graphExpansionHops,
      secondHopWeight: config.graphSecondHopWeight,
      sessionId: scope.sessionFiltering ? scope.sessionId : null,
      personaId: scope.personaId,
      importanceOf: (id) => byId[id]?.entry.importance ?? 0.5,
      lastAccessOf: (id) => byId[id]?.entry.lastAccessTime,
      createdAtOf: (id) => byId[id]?.entry.createdAt,
      decayRate: config.decayRate,
    );
    graphScores = {for (final h in hits) h.sourceMemoryId: h.score};
  }

  // ---- 双路融合（照抄 dual_route_retriever） ----
  var docWeight = config.documentRouteWeight;
  var graphWeight = config.graphRouteWeight;
  if (config.dynamicRouteWeighting &&
      config.graphEnabled &&
      graphScores.isNotEmpty) {
    final (d, g) = _routeWeightsForQuery(query, docWeight, graphWeight);
    docWeight = d;
    graphWeight = g;
  }
  final sumW = docWeight + graphWeight;
  if (sumW > 0) {
    docWeight /= sumW;
    graphWeight /= sumW;
  }

  final docMax = docWeighted.isEmpty
      ? 1.0
      : docWeighted.values.map((v) => v.score).reduce(math.max);
  final graphMax = graphScores.isEmpty
      ? 1.0
      : graphScores.values.reduce(math.max);

  final unionIds = <String>{...docWeighted.keys, ...graphScores.keys};
  final dualScored =
      <String, ({double score, Map<String, double> breakdown})>{};
  for (final id in unionIds) {
    if (!byId.containsKey(id)) continue;
    final docSignal = docWeighted[id] == null
        ? 0.0
        : (docWeighted[id]!.score / (docMax > 0 ? docMax : 1.0));
    final graphSignal = graphScores[id] == null
        ? 0.0
        : graphScores[id]! / (graphMax > 0 ? graphMax : 1.0);
    final bonus = (docWeighted.containsKey(id) && graphScores.containsKey(id))
        ? config.crossRouteBonus
        : 0.0;
    final score = (docWeight * docSignal + graphWeight * graphSignal + bonus)
        .clamp(0.0, 1.0);
    dualScored[id] = (
      score: score,
      breakdown: {
        ...?docWeighted[id]?.breakdown,
        'graph_score': graphScores[id] ?? 0.0,
        'doc_weight': docWeight,
        'graph_weight': graphWeight,
        'cross_bonus': bonus,
      },
    );
  }

  // ---- 原子增强（照抄 AtomRetriever：原子 BM25 × 时间分） ----
  if (config.atomEnabled) {
    final atomIndex = Bm25Index();
    final atomMeta = <String, (String, MemoryAtom)>{};
    for (final m in scoped) {
      for (final atom in m.atoms) {
        if (atom.status != AtomStatus.active || atom.isExpired(current))
          continue;
        final key = atom.id;
        atomIndex.addDocument(key, tokenize(atom.content));
        atomMeta[key] = (m.entry.id, atom);
      }
    }
    if (atomMeta.isNotEmpty) {
      final atomHits = atomIndex.search(query, limit: config.topK * 4);
      for (final hit in atomHits) {
        final meta = atomMeta[hit.docId];
        if (meta == null) continue;
        final (memoryId, atom) = meta;
        if (dualScored.containsKey(memoryId)) continue;
        final temporal = atom.temporalScore(current);
        final atomScore = (hit.score * temporal).clamp(0.0, 1.0);
        dualScored[memoryId] = (
          score: atomScore,
          breakdown: {'atom_score': atomScore, 'atom_id_score': hit.score},
        );
      }
    }
  }

  // ---- 策略过滤（照抄 _filter_by_retrieval_policy） ----
  final filtered = <String, ({double score, Map<String, double> breakdown})>{};
  for (final e in dualScored.entries) {
    final m = byId[e.key]!;
    final importance = m.entry.importance;
    if (config.minImportanceForRetrieval > 0 &&
        importance < config.minImportanceForRetrieval) {
      continue;
    }
    if (config.minSimilarityForRetrieval > 0) {
      final vectorSignal = math.max(
        vectorScores[e.key] ?? 0.0,
        math.max(
          e.value.breakdown['keyword_score'] ?? 0.0,
          graphScores[e.key] ?? 0.0,
        ),
      );
      if (vectorSignal < config.minSimilarityForRetrieval) continue;
    }
    if (config.memoryTypeFilter == 'event_only') {
      const eventTypes = {'episodic', 'planned', 'factual'};
      if (!m.entry.atomTypes.any(eventTypes.contains) &&
          !m.atoms.any((a) => eventTypes.contains(a.atomType.name))) {
        continue;
      }
    }
    filtered[e.key] = e.value;
  }

  // ---- 主列表排序取前 k-recent 席位 + 最近记忆保留位 ----
  final ranked = filtered.entries.toList()
    ..sort((a, b) => b.value.score.compareTo(a.value.score));
  final k = config.topK.clamp(1, 100);
  final recentCount = config.recentMemoryCount.clamp(0, k);

  final results = <RetrievalResult>[];
  final taken = <String>{};
  final mainSlots = k - recentCount;
  for (final e in ranked) {
    if (results.length >= mainSlots) break;
    results.add(
      RetrievalResult(
        memory: byId[e.key]!,
        finalScore: e.value.score,
        breakdown: e.value.breakdown,
      ),
    );
    taken.add(e.key);
  }

  if (recentCount > 0) {
    final windowStart = current.subtract(
      Duration(hours: (config.recentMemoryMaxAgeHours).round()),
    );
    final recent =
        scoped
            .where(
              (m) =>
                  !taken.contains(m.entry.id) &&
                  m.entry.createdAt.isAfter(windowStart),
            )
            .toList()
          ..sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
    for (final m in recent.take(recentCount)) {
      results.add(
        RetrievalResult(
          memory: m,
          finalScore: 1.0,
          breakdown: const {'recent_memory': 1.0},
          fromRecent: true,
        ),
      );
      taken.add(m.entry.id);
    }
  }

  results.sort((a, b) => b.finalScore.compareTo(a.finalScore));
  return results;
}

DateTime _referenceTime(MemoryEntry e, DateTime now) {
  final last = e.lastAccessTime;
  if (last != null && last.isAfter(e.createdAt)) return last;
  return e.createdAt;
}

/// Jaccard MMR 贪心选择（照抄 hybrid_retriever._apply_mmr）
List<String> _applyMmr(
  Map<String, ({double score, Map<String, double> breakdown})> weighted,
  List<RetrievalMemory> scoped,
  RetrievalConfig config,
) {
  if (weighted.length <= config.topK) {
    return weighted.keys.toList();
  }
  final tokenSets = <String, Set<String>>{};
  for (final m in scoped) {
    final tokens = tokenize(m.entry.displayContent.toLowerCase());
    tokenSets[m.entry.id] = tokens.isEmpty ? {'<empty>'} : tokens.toSet();
  }
  double jaccard(Set<String> a, Set<String> b) {
    final union = a.union(b);
    if (union.isEmpty) return 0;
    return a.intersection(b).length / union.length;
  }

  final all = weighted.entries.toList()
    ..sort((a, b) => b.value.score.compareTo(a.value.score));
  final selected = <String>[all.first.key];
  final pool = all.map((e) => e.key).skip(1).toList();

  while (selected.length < config.topK && pool.isNotEmpty) {
    String? best;
    var bestMmr = double.negativeInfinity;
    for (final candidate in pool) {
      var maxSim = 0.0;
      for (final s in selected) {
        final sim = jaccard(tokenSets[candidate] ?? {}, tokenSets[s] ?? {});
        if (sim > maxSim) maxSim = sim;
      }
      final mmr =
          config.mmrLambda * weighted[candidate]!.score -
          (1 - config.mmrLambda) * maxSim;
      if (mmr > bestMmr) {
        bestMmr = mmr;
        best = candidate;
      }
    }
    if (best == null) break;
    selected.add(best);
    pool.remove(best);
  }
  return selected;
}

/// 查询意图动态调权（照抄 dual_route_retriever._route_weights_for_query）
(double, double) _routeWeightsForQuery(
  String query,
  double docWeight,
  double graphWeight,
) {
  final q = query.toLowerCase();
  var d = docWeight;
  var g = graphWeight;

  const relationshipTerms = [
    '谁',
    '和谁',
    '关系',
    '认识',
    '朋友',
    '同事',
    '家人',
    '父母',
    '妈妈',
    '爸爸',
    '老师',
    '同学',
    'partner',
    'friend',
    'relationship',
    'with whom',
  ];
  const temporalTerms = [
    '上次',
    '昨天',
    '前天',
    '刚才',
    '之前',
    '什么时候',
    '哪天',
    '最近',
    'last time',
    'yesterday',
    'recently',
    'when',
  ];
  const factualTerms = [
    '是什么',
    '什么是',
    '解释',
    '定义',
    '怎么',
    '如何',
    'why',
    'what is',
    'explain',
    'define',
    'how to',
  ];

  final hasRelationship = relationshipTerms.any(q.contains);
  final hasTemporal = temporalTerms.any(q.contains);
  final hasFactual = factualTerms.any(q.contains);

  if (hasRelationship) {
    g += 0.2;
    d -= 0.2;
  }
  if (hasTemporal) {
    g += 0.1;
    d -= 0.1;
  }
  if (hasFactual && !hasRelationship) {
    d += 0.15;
    g -= 0.15;
  }

  d = d.clamp(0.15, 0.9).toDouble();
  g = g.clamp(0.1, 0.85).toDouble();
  return (d, g);
}

/// 余弦相似度
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  double dot = 0, magA = 0, magB = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  if (magA == 0 || magB == 0) return 0;
  return dot / (math.sqrt(magA) * math.sqrt(magB));
}
