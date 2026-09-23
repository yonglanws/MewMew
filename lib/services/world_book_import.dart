import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// 世界书导入解析器
///
/// 兼容两种格式：
/// 1. 酒馆（SillyTavern）World Info 导出格式：
///    `{"entries": {"0": {"key": [...], "keysecondary": [...], "content": "...",
///     "comment": "标题", "constant": false, "disable": false, "order": 100}}}`
///    （entries 为数组的老格式、或顶层就是条目数组的变体同样兼容）
/// 2. 本应用导出格式：条目对象数组或 `{"entries": [...]}`。
const _uuid = Uuid();

/// 解析世界书 JSON 文本，返回可追加的条目列表（id 全部重新生成避免冲突）。
/// 解析失败或格式不识别时抛 [FormatException]。
List<WorldBookEntry> parseWorldBookJson(String raw) {
  final decoded = jsonDecode(raw);
  final rawEntries = _extractEntryList(decoded);
  if (rawEntries.isEmpty) {
    throw const FormatException('未在世界书文件中找到任何条目');
  }
  final entries = <WorldBookEntry>[];
  for (final item in rawEntries) {
    final entry = _parseEntry(item);
    if (entry != null) entries.add(entry);
  }
  if (entries.isEmpty) {
    throw const FormatException('世界书文件中没有可识别的条目字段');
  }
  return entries;
}

List<dynamic> _extractEntryList(dynamic decoded) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    final entries = decoded['entries'];
    if (entries is List) return entries;
    if (entries is Map) return entries.values.toList();
    // 顶层就是一个条目对象
    if (decoded['content'] is String) return [decoded];
  }
  throw const FormatException('无法识别的世界书 JSON 结构');
}

WorldBookEntry? _parseEntry(dynamic raw) {
  if (raw is! Map) return null;
  final json = Map<String, dynamic>.from(raw);

  final keywords = _readStringList(json['keywords'] ?? json['key']);
  final secondary = _readStringList(
    json['secondaryKeywords'] ?? json['keysecondary'],
  );
  final content = (json['content'] ?? '').toString();
  final title = (json['title'] ?? json['comment'] ?? '').toString();
  final constant =
      (json['constant'] ?? false) == true ||
      (json['constant'] ?? false).toString() == 'true';
  final disabled =
      json['disable'] != null
          ? (json['disable'] == true || json['disable'].toString() == 'true')
          : !(json['enabled'] ?? true);
  final order =
      (json['order'] as num?)?.toInt() ??
      (json['order'] is String ? int.tryParse(json['order'] as String) : null) ??
      (json['insertion_order'] as num?)?.toInt() ??
      100;

  // 既没有内容也没有关键词的空条目直接跳过
  if (content.trim().isEmpty && keywords.isEmpty) {
    return null;
  }

  return WorldBookEntry(
    id: _uuid.v4(),
    title: title,
    keywords: keywords,
    secondaryKeywords: secondary,
    content: content,
    enabled: !disabled,
    constant: constant,
    order: order,
  );
}

List<String> _readStringList(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }
  if (raw is String) {
    // 部分导出工具会把关键词存成逗号分隔字符串
    return raw
        .split(RegExp(r'[,，;；]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

/// 导出为紧凑 JSON（条目数组，本应用格式，可直接再次导入）
String exportWorldBookJson(List<WorldBookEntry> entries) =>
    jsonEncode(entries.map((e) => e.toJson()).toList());
