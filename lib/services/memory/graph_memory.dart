/// 图谱记忆（移植自 LivingMemory graph_extractor.py / graph_store*.py /
/// graph_keyword_retriever.py / graph_retriever.py 的纯内存版）。
///
/// 不移植图谱向量子路线：每条记忆会多一次嵌入调用，移动端成本过高；
/// 关键词扩展检索已覆盖主要召回能力。
library;

import 'dart:math' as math;

import '../../models/models.dart';
import 'text_tokenizer.dart';

// ---- 数据模型 ----

/// 图谱节点类型
enum GraphNodeType { person, topic, fact, summary }

String graphNodeKey(GraphNodeType type, String canonicalValue) =>
    '${type.name}:$canonicalValue';

/// 实体名规范化（照抄 entity_resolver.canonicalize）
String canonicalizeEntity(String raw) {
  var t = raw.trim();
  t = t.replaceAll(RegExp('^[、，。！？；：\u201c\u201d\u2018\u2019\\s]+'), '');
  t = t.replaceAll(RegExp('[、，。！？；：\u201c\u201d\u2018\u2019\\s]\$'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  if (t.runes.every((c) => c < 0x80)) t = t.toLowerCase();
  return t;
}

/// 图谱节点
class GraphNode {
  final String key;
  final GraphNodeType type;
  final String value; // 显示名
  final String canonicalValue;
  Map<String, dynamic> metadata;

  GraphNode({
    required this.key,
    required this.type,
    required this.value,
    required this.canonicalValue,
    this.metadata = const {},
  });
}

/// 图谱边
class GraphEdge {
  final String sourceKey;
  final String targetKey;
  final String relationType;
  double confidence;
  double weight;
  String sourceMemoryId;

  GraphEdge({
    required this.sourceKey,
    required this.targetKey,
    required this.relationType,
    required this.sourceMemoryId,
    this.confidence = 0.8,
    this.weight = 1.0,
  });

  String get semanticKey => '$sourceKey|$relationType|$targetKey';
}

/// 可检索的图谱条目（对应原版 GraphEntry：挂到某条记忆上的可搜索片段）
class GraphEntry {
  final String entryKey;
  final String sourceMemoryId;
  final String? sessionId;
  final String? personaId;
  final String entryType; // fact / topic / participant / summary
  final String content;
  double confidence;
  final List<String> nodeKeys;
  final String? relationType;

  GraphEntry({
    required this.entryKey,
    required this.sourceMemoryId,
    this.sessionId,
    this.personaId,
    required this.entryType,
    required this.content,
    this.confidence = 0.8,
    List<String>? nodeKeys,
    this.relationType,
  }) : nodeKeys = List<String>.from(nodeKeys ?? const []);
}

/// 图谱检索结果
class GraphSearchHit {
  final String sourceMemoryId;
  final double score;
  final String
  matchSource; // direct / node_expansion / edge_neighbor / second_hop

  const GraphSearchHit({
    required this.sourceMemoryId,
    required this.score,
    required this.matchSource,
  });
}

// ---- 图谱存储（内存版） ----

class GraphMemoryStore {
  final Map<String, GraphNode> nodes = {};
  final Map<String, GraphEdge> edges = {}; // semanticKey -> edge
  final Map<String, GraphEntry> entries = {}; // entryKey -> entry
  final Map<String, Set<String>> _entryKeysByMemory = {};
  final Map<String, Set<String>> _edgesByMemory = {};
  final Map<String, Set<String>> _entriesByNode = {}; // nodeKey -> entryKeys
  final Map<String, Map<String, double>> _neighbors =
      {}; // nodeKey -> neighbor -> weight

  int get nodeCount => nodes.length;
  int get edgeCount => edges.length;
  int get entryCount => entries.length;

  /// 从一条记忆的原子/元数据构建并合入图谱（移植 GraphExtractor._extract_from_atoms）。
  void indexMemory(MemoryEntry memory, List<MemoryAtom> atoms) {
    deleteMemory(memory.id); // 增量重建该记忆的子图

    final personaId = memory.personaId;
    final sessionId = memory.sessionId;

    // 参与者 → person 节点
    final personKeys = <String>[];
    for (final p in memory.participants.take(8)) {
      final canonical = canonicalizeEntity(p);
      if (canonical.isEmpty) continue;
      final key = graphNodeKey(GraphNodeType.person, canonical);
      _upsertNode(
        GraphNode(
          key: key,
          type: GraphNodeType.person,
          value: p,
          canonicalValue: canonical,
        ),
      );
      personKeys.add(key);
    }

    for (final atom in atoms) {
      final factCanonical = canonicalizeEntity(atom.content);
      if (factCanonical.isEmpty) continue;
      final factKey = graphNodeKey(GraphNodeType.fact, factCanonical);
      _upsertNode(
        GraphNode(
          key: factKey,
          type: GraphNodeType.fact,
          value: atom.content,
          canonicalValue: factCanonical,
          metadata: {
            'atomType': atom.atomType.name,
            'importance': atom.importance,
          },
        ),
      );

      // fact 条目
      final factEntryKey = _sha1('fact|${memory.id}||$factCanonical');
      _upsertEntry(
        GraphEntry(
          entryKey: factEntryKey,
          sourceMemoryId: memory.id,
          sessionId: sessionId,
          personaId: personaId,
          entryType: 'fact',
          content: 'Atom: ${atom.content}',
          confidence: atom.confidence,
          nodeKeys: [factKey],
        ),
      );

      // 实体（排除与参与者重名的）→ topic 节点 + 边
      final factEntry = entries[factEntryKey]!;
      for (final entity in atom.entities.take(8)) {
        final canonical = canonicalizeEntity(entity);
        if (canonical.isEmpty) continue;
        final isPerson = memory.participants.any(
          (p) => canonicalizeEntity(p) == canonical,
        );
        final entityKey = graphNodeKey(
          isPerson ? GraphNodeType.person : GraphNodeType.topic,
          canonical,
        );
        if (!isPerson) {
          _upsertNode(
            GraphNode(
              key: entityKey,
              type: GraphNodeType.topic,
              value: entity,
              canonicalValue: canonical,
            ),
          );
        }
        final relation = isPerson ? 'mentioned_in' : 'describes';
        _addEdge(
          GraphEdge(
            sourceKey: entityKey,
            targetKey: factKey,
            relationType: relation,
            sourceMemoryId: memory.id,
            confidence: atom.confidence * 0.9,
          ),
        );
        _linkEntryToNode(factEntry, entityKey, relation);
      }
    }
  }

  /// 删除某条记忆的图谱痕迹并回收孤儿节点（照抄 delete_memory 语义）
  void deleteMemory(String memoryId) {
    for (final entryKey
        in _entryKeysByMemory.remove(memoryId) ?? const <String>{}) {
      final entry = entries.remove(entryKey);
      if (entry == null) continue;
      for (final nodeKey in entry.nodeKeys) {
        _entriesByNode[nodeKey]?.remove(entryKey);
      }
    }
    for (final semanticKey
        in _edgesByMemory.remove(memoryId) ?? const <String>{}) {
      edges.remove(semanticKey);
    }
    _rebuildNeighborIndex();
    _gcOrphanNodes();
  }

  void _upsertNode(GraphNode node) {
    nodes.putIfAbsent(node.key, () => node);
  }

  void _upsertEntry(GraphEntry entry) {
    entries[entry.entryKey] = entry;
    (_entryKeysByMemory[entry.sourceMemoryId] ??= {}).add(entry.entryKey);
    for (final nodeKey in entry.nodeKeys) {
      (_entriesByNode[nodeKey] ??= {}).add(entry.entryKey);
    }
  }

  void _linkEntryToNode(GraphEntry entry, String nodeKey, String relation) {
    entry.nodeKeys.add(nodeKey);
    (_entriesByNode[nodeKey] ??= {}).add(entry.entryKey);
  }

  /// 添加边：同语义边跨记忆合并（置信度 EMA 0.7/0.3，权重 +0.15 累积；
  /// 照抄 graph_store_write._add_edge 的三层匹配的语义层）。
  void _addEdge(GraphEdge edge) {
    final existing = edges[edge.semanticKey];
    if (existing != null) {
      existing.confidence = existing.confidence * 0.7 + edge.confidence * 0.3;
      existing.weight += edge.weight * 0.15;
      _rebuildNeighborIndex();
      return;
    }
    edges[edge.semanticKey] = edge;
    (_edgesByMemory[edge.sourceMemoryId] ??= {}).add(edge.semanticKey);
    _rebuildNeighborIndex();
  }

  void _rebuildNeighborIndex() {
    _neighbors.clear();
    for (final edge in edges.values) {
      (_neighbors[edge.sourceKey] ??= {})[edge.targetKey] =
          (_neighbors[edge.sourceKey]?[edge.targetKey] ?? 0) + edge.weight;
      (_neighbors[edge.targetKey] ??= {})[edge.sourceKey] =
          (_neighbors[edge.targetKey]?[edge.sourceKey] ?? 0) + edge.weight;
    }
  }

  void _gcOrphanNodes() {
    nodes.removeWhere((key, _) {
      final referencedByEntry = _entriesByNode[key]?.isNotEmpty ?? false;
      final referencedByEdge = _neighbors[key]?.isNotEmpty ?? false;
      return !referencedByEntry && !referencedByEdge;
    });
  }

  // ---- 关键词扩展检索（移植 graph_keyword_retriever + graph_retriever 评分） ----

  /// 检索与查询相关的记忆 id。
  /// [importanceOf] / [lastAccessOf] 由调用方提供用于最终评分。
  List<GraphSearchHit> search(
    String query, {
    required int limit,
    required int expansionLimit,
    required int expansionHops,
    required double secondHopWeight,
    required String? sessionId,
    required String? personaId,
    required double Function(String memoryId) importanceOf,
    required DateTime? Function(String memoryId) lastAccessOf,
    required DateTime? Function(String memoryId) createdAtOf,
    required double decayRate,
  }) {
    final tokens = tokenize(query);
    if (tokens.isEmpty) return const [];

    final now = DateTime.now();
    final candidates = <String, ({double score, Set<String> sources})>{};

    void mergeHit(String memoryId, double weightedScore, String source) {
      if (memoryId.isEmpty) return;
      final existing = candidates[memoryId];
      if (existing == null) {
        candidates[memoryId] = (score: weightedScore, sources: {source});
      } else if (weightedScore > existing.score) {
        candidates[memoryId] = (
          score: weightedScore,
          sources: {...existing.sources, source},
        );
      } else {
        // 较弱的补充命中叠加 0.35（照抄 merge_hit）
        candidates[memoryId] = (
          score: (existing.score + weightedScore * 0.35).clamp(0.0, 1.0),
          sources: {...existing.sources, source},
        );
      }
    }

    // 1. 条目 BM25 直命中（权重 1.0）
    final entryTokens = <String, List<String>>{};
    for (final entry in entries.values) {
      if (!_scopeMatches(
        entry.sessionId,
        entry.personaId,
        sessionId,
        personaId,
      )) {
        continue;
      }
      entryTokens[entry.entryKey] = tokenize(entry.content);
    }
    if (entryTokens.isNotEmpty) {
      final scores = <String, double>{};
      for (final token in tokens.toSet()) {
        for (final e in entryTokens.entries) {
          final tf = e.value.where((t) => t == token).length;
          if (tf > 0) {
            scores[e.key] = (scores[e.key] ?? 0) + tf / e.value.length;
          }
        }
      }
      final ranked = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final maxScore = ranked.isEmpty ? 1.0 : ranked.first.value;
      for (final e in ranked.take(
        expansionLimit * 3 < 12 ? 12 : expansionLimit * 3,
      )) {
        final entry = entries[e.key]!;
        final normalized = maxScore > 0 ? e.value / maxScore : 0.0;
        mergeHit(entry.sourceMemoryId, normalized.clamp(0.0, 1.0), 'direct');
      }
    }

    // 2. 节点子串匹配 → 扩展命中（权重 0.7）
    final matchedNodes = <String>[];
    for (final token in tokens) {
      if (token.length < 2) continue;
      for (final node in nodes.values) {
        if (node.type == GraphNodeType.fact) continue; // 只扩展实体节点
        if (node.canonicalValue.contains(token)) {
          matchedNodes.add(node.key);
        }
      }
    }
    final expandedEntries = <String, int>{};
    for (final nodeKey in matchedNodes.toSet()) {
      for (final entryKey in _entriesByNode[nodeKey] ?? const <String>{}) {
        expandedEntries[entryKey] = (expandedEntries[entryKey] ?? 0) + 1;
      }
    }
    for (final e in expandedEntries.entries) {
      final entry = entries[e.key];
      if (entry == null) continue;
      if (!_scopeMatches(
        entry.sessionId,
        entry.personaId,
        sessionId,
        personaId,
      )) {
        continue;
      }
      final score = (0.35 + 0.15 * e.value).clamp(0.0, 1.0);
      mergeHit(entry.sourceMemoryId, score * 0.7, 'node_expansion');
    }

    // 3. 边邻居扩展（权重 0.7）+ 可选二跳（权重 secondHopWeight）
    if (matchedNodes.isNotEmpty) {
      final firstHopNodes = <String>{};
      for (final nodeKey in matchedNodes.toSet()) {
        final nbrs = _neighbors[nodeKey];
        if (nbrs == null) continue;
        final sorted = nbrs.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final n in sorted.take(expansionLimit)) {
          firstHopNodes.add(n.key);
          for (final entryKey in _entriesByNode[n.key] ?? const <String>{}) {
            final entry = entries[entryKey];
            if (entry == null) continue;
            if (!_scopeMatches(
              entry.sessionId,
              entry.personaId,
              sessionId,
              personaId,
            )) {
              continue;
            }
            mergeHit(entry.sourceMemoryId, 0.5 * 0.7, 'edge_neighbor');
          }
        }
      }
      if (expansionHops >= 2) {
        final secondHop =
            <String>{for (final n in firstHopNodes) ...?_neighbors[n]?.keys}
              ..removeAll(matchedNodes.toSet())
              ..removeAll(firstHopNodes);
        for (final nodeKey in secondHop.take(expansionLimit)) {
          for (final entryKey in _entriesByNode[nodeKey] ?? const <String>{}) {
            final entry = entries[entryKey];
            if (entry == null) continue;
            if (!_scopeMatches(
              entry.sessionId,
              entry.personaId,
              sessionId,
              personaId,
            )) {
              continue;
            }
            mergeHit(entry.sourceMemoryId, 0.5 * secondHopWeight, 'second_hop');
          }
        }
      }
    }

    if (candidates.isEmpty) return const [];

    // 4. 图谱路最终评分（照抄 graph_retriever 106-178）：
    //    (0.55×kw + 0.2×importance + 0.15×recency + 0.1×confidence) × temporal
    const alpha = 0.55, beta = 0.2, gamma = 0.15, delta = 0.1;
    final hits = <GraphSearchHit>[];
    for (final c in candidates.entries) {
      final memoryId = c.key;
      final importance = importanceOf(memoryId).clamp(0.0, 1.0);
      final created = createdAtOf(memoryId);
      final accessed = lastAccessOf(memoryId) ?? created;
      final refTime =
          (accessed != null && created != null && accessed.isAfter(created))
          ? accessed
          : (created ?? now);
      final daysOld = now.difference(refTime).inMilliseconds / 86400000.0;
      final recency = math.exp(-decayRate * (daysOld < 0 ? 0 : daysOld));
      final kwScore = c.value.score;
      // 图谱置信度：取该记忆条目的最大置信度（缺省 0.7）
      var confidence = 0.7;
      for (final entryKey in _entryKeysByMemory[memoryId] ?? const <String>{}) {
        final entry = entries[entryKey];
        if (entry != null && entry.confidence > confidence) {
          confidence = entry.confidence;
        }
      }
      final finalScore =
          (alpha * kwScore +
                  beta * importance +
                  gamma * recency +
                  delta * confidence)
              .clamp(0.0, 1.0);
      hits.add(
        GraphSearchHit(
          sourceMemoryId: memoryId,
          score: finalScore,
          matchSource: c.value.sources.first,
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  static bool _scopeMatches(
    String? entrySession,
    String? entryPersona,
    String? sessionId,
    String? personaId,
  ) {
    final personaOk =
        entryPersona == null || personaId == null || entryPersona == personaId;
    final sessionOk =
        entrySession == null || sessionId == null || entrySession == sessionId;
    return personaOk && sessionOk;
  }

  // ---- 序列化（持久化到 SharedPreferences） ----

  Map<String, dynamic> toJson() => {
    'nodes': nodes.values
        .map(
          (n) => {
            'key': n.key,
            'type': n.type.name,
            'value': n.value,
            'canonicalValue': n.canonicalValue,
            'metadata': n.metadata,
          },
        )
        .toList(),
    'edges': edges.values
        .map(
          (e) => {
            'sourceKey': e.sourceKey,
            'targetKey': e.targetKey,
            'relationType': e.relationType,
            'sourceMemoryId': e.sourceMemoryId,
            'confidence': e.confidence,
            'weight': e.weight,
          },
        )
        .toList(),
    'entries': entries.values
        .map(
          (e) => {
            'entryKey': e.entryKey,
            'sourceMemoryId': e.sourceMemoryId,
            'sessionId': e.sessionId,
            'personaId': e.personaId,
            'entryType': e.entryType,
            'content': e.content,
            'confidence': e.confidence,
            'nodeKeys': e.nodeKeys,
            'relationType': e.relationType,
          },
        )
        .toList(),
  };

  static GraphMemoryStore fromJson(Map<String, dynamic> json) {
    final store = GraphMemoryStore();
    for (final n in (json['nodes'] as List? ?? [])) {
      final map = n as Map<String, dynamic>;
      final node = GraphNode(
        key: map['key'],
        type: GraphNodeType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => GraphNodeType.topic,
        ),
        value: map['value'] ?? '',
        canonicalValue: map['canonicalValue'] ?? '',
        metadata: (map['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      store.nodes[node.key] = node;
    }
    for (final e in (json['edges'] as List? ?? [])) {
      final map = e as Map<String, dynamic>;
      final edge = GraphEdge(
        sourceKey: map['sourceKey'],
        targetKey: map['targetKey'],
        relationType: map['relationType'] ?? 'related',
        sourceMemoryId: map['sourceMemoryId'] ?? '',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.8,
        weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
      );
      store.edges[edge.semanticKey] = edge;
    }
    for (final e in (json['entries'] as List? ?? [])) {
      final map = e as Map<String, dynamic>;
      final entry = GraphEntry(
        entryKey: map['entryKey'],
        sourceMemoryId: map['sourceMemoryId'] ?? '',
        sessionId: map['sessionId'],
        personaId: map['personaId'],
        entryType: map['entryType'] ?? 'fact',
        content: map['content'] ?? '',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.8,
        nodeKeys: List<String>.from(map['nodeKeys'] ?? const []),
        relationType: map['relationType'],
      );
      store.entries[entry.entryKey] = entry;
      (store._entryKeysByMemory[entry.sourceMemoryId] ??= {}).add(
        entry.entryKey,
      );
      for (final nodeKey in entry.nodeKeys) {
        (store._entriesByNode[nodeKey] ??= {}).add(entry.entryKey);
      }
    }
    for (final e in store.edges.values) {
      (store._edgesByMemory[e.sourceMemoryId] ??= {}).add(e.semanticKey);
    }
    store._rebuildNeighborIndex();
    return store;
  }
}

/// FNV-1a 稳定哈希（仅用于图谱 key 去重，不用于安全场景）
String _sha1(String input) {
  var hash = 0x811c9dc5;
  for (final cu in input.codeUnits) {
    hash ^= cu;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0') +
      input.length.toRadixString(16);
}
