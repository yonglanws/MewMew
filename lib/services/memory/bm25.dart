/// BM25 关键词检索与 RRF 融合（移植自 LivingMemory bm25_retriever.py / rrf_fusion.py）。
///
/// 原版使用 SQLite FTS5 内置 bm25()（k1=1.2, b=0.75），结果 min-max 归一化到 [0,1]；
/// 此处实现相同参数的纯 Dart BM25。融合常数 rrf_k 默认 60。
library;

import 'dart:math' as math;

import 'text_tokenizer.dart';

/// 一条 BM25 检索结果
class Bm25Hit {
  final String docId;
  final double score; // 归一化后的 [0,1]，越大越相关

  const Bm25Hit({required this.docId, required this.score});
}

/// BM25 内存索引。构建后可多次查询；文档变更时需重建（纯函数语义，无失效问题）。
class Bm25Index {
  final double k1;
  final double b;

  final Map<String, Map<String, int>> _termFreqs = {}; // docId -> term -> tf
  final Map<String, int> _docLengths = {};
  final Map<String, int> _df = {}; // term -> 出现文档数
  int _totalLength = 0;
  Set<String>? _allowedDocIds; // 预过滤集合（会话/人格过滤等）

  Bm25Index({this.k1 = 1.2, this.b = 0.75});

  int get docCount => _docLengths.length;

  /// 添加文档。[tokens] 来自 [tokenize]；[allowedDocIds] 限定可检索文档范围。
  void addDocument(String docId, List<String> tokens) {
    final freqs = <String, int>{};
    for (final t in tokens) {
      freqs[t] = (freqs[t] ?? 0) + 1;
    }
    _termFreqs[docId] = freqs;
    _docLengths[docId] = tokens.length;
    _totalLength += tokens.length;
    for (final term in freqs.keys) {
      _df[term] = (_df[term] ?? 0) + 1;
    }
  }

  /// 设定可检索文档白名单（null = 全部）。用于把会话/人格过滤前置到打分阶段。
  set allowedDocIds(Set<String>? ids) => _allowedDocIds = ids;

  /// 查询并返回归一化得分（降序）。[limit] 截断返回条数。
  List<Bm25Hit> search(String query, {int limit = 10}) {
    if (_docLengths.isEmpty) return const [];
    final queryTerms = tokenize(query);
    if (queryTerms.isEmpty) return const [];

    final avgLen = _totalLength / _docLengths.length;
    final n = _docLengths.length;
    final rawScores = <String, double>{};

    for (final term in queryTerms.toSet()) {
      final df = _df[term];
      if (df == null) continue;
      // 原 SQLite FTS5 的排序依据即 bm25() 分值本身（k1/b 默认），
      // 这里用标准 Okapi BM25 IDF 上限平滑（避免负分）。
      final idf = math.log((n - df + 0.5) / (df + 0.5) + 1.0);
      for (final entry in _termFreqs.entries) {
        final docId = entry.key;
        if (_allowedDocIds != null && !_allowedDocIds!.contains(docId)) {
          continue;
        }
        final tf = entry.value[term];
        if (tf == null || tf == 0) continue;
        final dl = _docLengths[docId] ?? 0;
        final denom = tf + k1 * (1 - b + b * dl / avgLen);
        rawScores[docId] =
            (rawScores[docId] ?? 0) + idf * tf * (k1 + 1) / denom;
      }
    }
    if (rawScores.isEmpty) return const [];

    // min-max 归一化（照抄原版：(max - s) / (max - min)，BM25 越小越相关）
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final s in rawScores.values) {
      if (s < min) min = s;
      if (s > max) max = s;
    }
    final hits = <Bm25Hit>[];
    if (max == min) {
      // 全部等分时原版返回 1.0
      for (final docId in rawScores.keys) {
        hits.add(Bm25Hit(docId: docId, score: 1.0));
      }
    } else {
      final range = max - min;
      for (final entry in rawScores.entries) {
        hits.add(Bm25Hit(docId: entry.key, score: (max - entry.value) / range));
      }
    }
    hits.sort((a, b2) => b2.score.compareTo(a.score));
    return hits.take(limit).toList();
  }
}

/// RRF 融合：rrf(d) = Σ 1/(k + rank + 1)，rank 从 0 起。
/// [routeLists] 为各路线的有序 docId 列表。
Map<String, double> rrfFuse(
  List<List<String>> routeLists, {
  int k = 60,
  int topK = 10,
}) {
  final scores = <String, double>{};
  for (final list in routeLists) {
    for (var i = 0; i < list.length; i++) {
      scores[list[i]] = (scores[list[i]] ?? 0) + 1.0 / (k + i + 1);
    }
  }
  final entries = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries.take(topK));
}
