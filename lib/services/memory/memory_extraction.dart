/// 结构化记忆提取管线（移植自 LivingMemory core/processors/memory_processor*.py）。
///
/// 包含：对话行格式化 → LLM JSON 解析级联 → 归一化 → 质量门 → 存储内容构建
/// → 确定性时间标签。除 LLM 调用本身外全部为纯函数。
library;

import 'dart:convert';

import 'memory_prompts.dart';

/// 参与提取的对话消息（来自 ChatSession，解耦后的最小结构）
class ExtractionMessage {
  final String role; // user / assistant
  final String content;
  final DateTime timestamp;
  final String? speakerId;
  final String? speakerName;
  final bool isBot; // 是否为当前 AI 角色自己的发言

  const ExtractionMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.speakerId,
    this.speakerName,
    this.isBot = false,
  });
}

/// 提取产物
class ExtractionResult {
  final String summary; // 人格口吻摘要
  final String canonicalSummary;
  final List<String> topics;
  final List<String> keyFacts;
  final List<String> participants;
  final String sentiment;
  final double importance;
  final String quality; // normal / low

  const ExtractionResult({
    required this.summary,
    required this.canonicalSummary,
    required this.topics,
    required this.keyFacts,
    required this.participants,
    required this.sentiment,
    required this.importance,
    required this.quality,
  });
}

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTimestamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// 对话格式化（照抄原版 _format_conversation）：
/// 自己的发言 `[Bot: 昵称 | ID: x | 时间] content`，
/// 对方 `[昵称 | ID: x | 时间] content`。
String formatConversationForExtraction(
  List<ExtractionMessage> messages, {
  required String botDisplayName,
  String? botId,
}) {
  final lines = <String>[];
  for (final m in messages) {
    final content = m.content.trim();
    if (content.isEmpty) continue;
    final time = _formatTimestamp(m.timestamp);
    if (m.isBot || m.role == 'assistant') {
      final name = m.speakerName ?? botDisplayName;
      final id = m.speakerId ?? botId ?? 'bot';
      lines.add('[Bot: $name | ID: $id | $time] $content');
    } else {
      final name = m.speakerName ?? '用户';
      final id = m.speakerId ?? 'user';
      lines.add('[$name | ID: $id | $time] $content');
    }
  }
  return lines.join('\n');
}

/// 构建提取的系统提示词（带人格时使用人格模板）
String buildExtractionSystemPrompt({
  required String currentDate,
  String? personaPrompt,
}) {
  if (personaPrompt != null && personaPrompt.trim().isNotEmpty) {
    return replaceVars(memorySystemPromptWithPersona, {
      'base_prompt': replaceVars(memorySystemPromptBase, {
        'current_date': currentDate,
      }),
      'persona_prompt': personaPrompt.trim(),
      'current_date': currentDate,
    });
  }
  return replaceVars(memorySystemPromptBase, {'current_date': currentDate});
}

/// 构建提取的用户提示词（私聊/群聊模板不同）
String buildExtractionUserPrompt({
  required String conversationText,
  required String currentDate,
  required bool isGroup,
}) {
  final template = isGroup ? groupChatPrompt : privateChatPrompt;
  return replaceVars(template, {
    'conversation': conversationText,
    'current_date': currentDate,
  });
}

/// LLM 原始输出 → ExtractionResult（解析级联 + 归一化 + 质量门）
ExtractionResult parseExtractionResponse(
  String raw, {
  required bool isGroup,
}) {
  final parsed = _extractJson(raw, isGroup);
  return _toResult(parsed, isGroup);
}

/// 解析级联（照抄 parse 级联顺序）：
/// 去代码栅栏 → jsonDecode → 修复未闭合 → 正则块 → 逐字段 → 默认值
Map<String, dynamic> _extractJson(String raw, bool isGroup) {
  var text = raw.trim();
  text = text.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
  text = text.replaceAll(RegExp(r'\s*```$'), '').trim();

  Map<String, dynamic>? parsed = _tryDecodeObject(text);
  parsed ??= _tryDecodeObject(_fixJson(text));
  parsed ??= _extractByRegexBlock(text);
  parsed ??= _extractByFieldRegex(text);
  return parsed ?? _defaultParsed(isGroup);
}

Map<String, dynamic>? _tryDecodeObject(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return null;
}

String _fixJson(String text) {
  var t = text.trim();
  // 去掉尾逗号（replaceAll 不支持 \1 反向引用，须用 replaceAllMapped）
  t = t.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1] ?? '');
  // 裸换行转义
  t = t.replaceAll('\r', r'\r').replaceAll('\n', r'\n').replaceAll('\t', r'\t');
  // 计数闭合括号（简化处理：不做完整词法分析，仅跟踪引号内外）
  var braces = 0, brackets = 0;
  var quoteOpen = false;
  var escaped = false;
  for (final cu in t.runes) {
    final ch = String.fromCharCode(cu);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch == '\\') {
      escaped = true;
      continue;
    }
    if (ch == '"') quoteOpen = !quoteOpen;
    if (quoteOpen) continue;
    if (ch == '{') braces++;
    if (ch == '}') braces--;
    if (ch == '[') brackets++;
    if (ch == ']') brackets--;
  }
  // 引号未闭合时补引号
  if (quoteOpen) t += '"';
  t += ']' * (brackets < 0 ? 0 : brackets);
  t += '}' * (braces < 0 ? 0 : braces);
  return t;
}

/// 从文本中找第一个包含 "summary" 的平衡 JSON 对象块
Map<String, dynamic>? _extractByRegexBlock(String text) {
  final blockPattern = RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}');
  for (final match in blockPattern.allMatches(text)) {
    final candidate = _tryDecodeObject(match.group(0)!);
    if (candidate != null && candidate.containsKey('summary')) {
      return candidate;
    }
  }
  return null;
}

/// 逐字段正则兜底
Map<String, dynamic>? _extractByFieldRegex(String text) {
  final summaryMatch =
      RegExp(r'"summary"\s*:\s*"([^"]+)"').firstMatch(text);
  if (summaryMatch == null) return null;
  final parsed = <String, dynamic>{'summary': summaryMatch.group(1)!};

  final importanceMatch =
      RegExp(r'"importance"\s*:\s*([0-9.]+)').firstMatch(text);
  if (importanceMatch != null) {
    final v = double.tryParse(importanceMatch.group(1)!);
    if (v != null) parsed['importance'] = v;
  }
  final sentimentMatch =
      RegExp(r'"sentiment"\s*:\s*"(\w+)"').firstMatch(text);
  if (sentimentMatch != null) parsed['sentiment'] = sentimentMatch.group(1);
  for (final field in ['topics', 'key_facts', 'participants']) {
    final arrayMatch =
        RegExp('"$field"\\s*:\\s*\\[(.*?)\\]').firstMatch(text);
    if (arrayMatch != null) {
      final items = RegExp(r'"([^"]*)"')
          .allMatches(arrayMatch.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      if (items.isNotEmpty) parsed[field] = items;
    }
  }
  return parsed;
}

Map<String, dynamic> _defaultParsed(bool isGroup) => {
      'summary': '对话记录',
      'topics': <String>[],
      'key_facts': <String>[],
      if (isGroup) 'participants': <String>[],
      'sentiment': 'neutral',
      'importance': 0.5,
    };

List<String> _ensureList(dynamic raw, {int cap = 5}) {
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).take(cap).toList();
  }
  return const [];
}

ExtractionResult _toResult(Map<String, dynamic> parsed, bool isGroup) {
  final summary = (parsed['summary'] ?? '').toString();
  final topics = _ensureList(parsed['topics']);
  final keyFacts = _ensureList(parsed['key_facts']);
  final participants = isGroup ? _ensureList(parsed['participants'], cap: 20) : const <String>[];

  var sentiment = (parsed['sentiment'] ?? 'neutral').toString();
  if (!const {'positive', 'neutral', 'negative'}.contains(sentiment)) {
    sentiment = 'neutral';
  }

  var importance = 0.5;
  final rawImportance = parsed['importance'];
  if (rawImportance is num) {
    importance = rawImportance.toDouble().clamp(0.0, 1.0);
  } else if (rawImportance is String) {
    importance = (double.tryParse(rawImportance) ?? 0.5).clamp(0.0, 1.0);
  }

  final canonical = (parsed['canonical_summary'] ?? '').toString();
  final quality = validateSummaryQuality(
    summary: summary,
    keyFacts: keyFacts,
    importance: importance,
  );

  // 存储正文 = summary + " | " + facts（照抄 build 存储格式）
  final richContent = keyFacts.isEmpty
      ? summary
      : '$summary | ${keyFacts.join('；')}';

  return ExtractionResult(
    summary: summary.isEmpty ? '对话记录' : summary,
    canonicalSummary: canonical.isNotEmpty ? canonical : richContent,
    topics: topics,
    keyFacts: keyFacts,
    participants: participants,
    sentiment: sentiment,
    importance: importance,
    quality: quality,
  );
}

/// 质量门（照抄 _validate_summary_quality）：
/// 摘要过短 / 无关键事实 / 重要性非法 / 含泛化称呼 → low。
/// low 仅打标记不拒写（与原版一致）。
String validateSummaryQuality({
  required String summary,
  required List<String> keyFacts,
  required double importance,
}) {
  if (summary.trim().length < 10) return 'low';
  if (keyFacts.isEmpty) return 'low';
  if (importance <= 0 || importance >= 1.0) {
    // 原版判定"非数值或不在 [0,1]"——归一化后 0/1 边界视为可疑
    if (importance == 0.0 || importance == 1.0) return 'low';
  }
  const genericTerms = [
    '某用户', '有人', '某人', '用户说', '对方说', '群成员', '某群成员',
  ];
  for (final term in genericTerms) {
    if (summary.contains(term)) return 'low';
  }
  return 'normal';
}

/// 从消息时间戳生成确定性日期标签（照抄 _apply_source_time_tags；
/// 不依赖 LLM，保证可复现）。
({List<String> timeTags, String? sourceTimeLabel}) buildSourceTimeTags(
  List<ExtractionMessage> messages,
) {
  if (messages.isEmpty) return (timeTags: const <String>[], sourceTimeLabel: null);
  final dates = messages
      .map((m) =>
          '${m.timestamp.year}-${_two(m.timestamp.month)}-${_two(m.timestamp.day)}')
      .toSet()
      .toList()
    ..sort();
  final label = dates.length == 1 ? dates.first : '${dates.first} - ${dates.last}';
  return (timeTags: dates, sourceTimeLabel: label);
}
