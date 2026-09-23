import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'logger_service.dart';

/// 内置工具的执行器
class BuiltinTools {
  /// 内置工具定义
  static List<ToolConfig> get definitions => [
    ToolConfig(
      id: 'builtin_current_time',
      name: 'get_current_time',
      description: '获取当前日期和时间',
      type: ToolType.builtin,
      paramsSchemaJson: '{"type":"object","properties":{}}',
    ),
    ToolConfig(
      id: 'builtin_calculator',
      name: 'calculate',
      description: '计算数学表达式。支持加减乘除和括号，用于需要精确数值计算时',
      type: ToolType.builtin,
      paramsSchemaJson:
          '{"type":"object","properties":{"expression":{"type":"string","description":"数学表达式，如 (1+2)*3"}},"required":["expression"]}',
    ),
    ToolConfig(
      id: 'builtin_save_memory',
      name: 'save_memory',
      description: '保存用户的关键信息到长期记忆。用于记住用户的偏好、身份、重要事实等，便于后续对话参考',
      type: ToolType.builtin,
      paramsSchemaJson:
          '{"type":"object","properties":{"content":{"type":"string","description":"要记住的关键信息，简洁明确"}},"required":["content"]}',
    ),
    ToolConfig(
      id: 'builtin_recall_memory',
      name: 'recall_long_term_memory',
      description:
          '按需检索长期记忆。当需要回忆用户的过往偏好、历史约定、人物关系或之前聊过的话题时调用。query 使用简短的主题关键词，而非整句话',
      type: ToolType.builtin,
      paramsSchemaJson:
          '{"type":"object","properties":{"query":{"type":"string","description":"简短的召回关键词，如 用户喜欢的食物、上周的约定"},"k":{"type":"integer","description":"返回条数，默认 5"}},"required":["query"]}',
    ),
  ];

  static Future<String> execute(
    String name,
    Map<String, dynamic> args, {
    required Future<void> Function(String content) onSaveMemory,
    Future<String> Function(String query, int k)? onRecallMemory,
  }) async {
    switch (name) {
      case 'get_current_time':
        return DateTime.now().toString();
      case 'calculate':
        try {
          final result = _evaluate(args['expression'] as String);
          return result.toString();
        } catch (e) {
          return '计算失败: $e';
        }
      case 'save_memory':
        final content = args['content'] as String? ?? '';
        if (content.isEmpty) return '内容为空，未保存';
        await onSaveMemory(content);
        return '已保存到记忆: $content';
      case 'recall_long_term_memory':
        final query = (args['query'] as String? ?? '').trim();
        if (query.isEmpty) return '查询词为空，未执行召回';
        final k = (args['k'] as num?)?.toInt() ?? 5;
        if (onRecallMemory == null) return '记忆召回不可用';
        return onRecallMemory(query, k);
      default:
        return '未知内置工具: $name';
    }
  }

  /// 简单的四则运算解析器（递归下降）
  static double _evaluate(String expr) {
    final tokens = expr.replaceAll(' ', '');
    int pos = 0;

    late double Function() parseExpr;
    late double Function() parseTerm;
    late double Function() parseFactor;

    parseExpr = () {
      double v = parseTerm();
      while (pos < tokens.length &&
          (tokens[pos] == '+' || tokens[pos] == '-')) {
        final op = tokens[pos++];
        final r = parseTerm();
        v = op == '+' ? v + r : v - r;
      }
      return v;
    };

    parseTerm = () {
      double v = parseFactor();
      while (pos < tokens.length &&
          (tokens[pos] == '*' || tokens[pos] == '/')) {
        final op = tokens[pos++];
        final r = parseFactor();
        v = op == '*' ? v * r : v / r;
      }
      return v;
    };

    parseFactor = () {
      if (pos < tokens.length && tokens[pos] == '(') {
        pos++;
        final v = parseExpr();
        pos++; // skip ')'
        return v;
      }
      if (pos < tokens.length && tokens[pos] == '-') {
        pos++;
        return -parseFactor();
      }
      final start = pos;
      while (pos < tokens.length && (RegExp(r'[0-9.]').hasMatch(tokens[pos]))) {
        pos++;
      }
      return double.parse(tokens.substring(start, pos));
    };

    return parseExpr();
  }
}

/// 自定义 HTTP 工具执行器
class HttpToolExecutor {
  static Future<String> execute(
    ToolConfig tool,
    Map<String, dynamic> args,
  ) async {
    Log.d('tool', 'HTTP 工具调用：${tool.name} ${tool.method} ${tool.url}');
    try {
      Map<String, String> headers = {};
      try {
        headers = (jsonDecode(tool.headersJson) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v.toString()),
        );
      } catch (_) {}

      http.Response resp;
      if (tool.method.toUpperCase() == 'GET') {
        final uri = Uri.parse(tool.url).replace(
          queryParameters: {
            ...Uri.parse(tool.url).queryParameters,
            ...args.map((k, v) => MapEntry(k, v.toString())),
          },
        );
        resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
      } else {
        headers.putIfAbsent('Content-Type', () => 'application/json');
        resp = await http
            .post(Uri.parse(tool.url), headers: headers, body: jsonEncode(args))
            .timeout(const Duration(seconds: 30));
      }
      final body = utf8.decode(resp.bodyBytes);
      Log.i(
        'tool',
        'HTTP 工具响应：${tool.name} ${resp.statusCode} '
            '长度=${body.length}',
      );
      return body.length > 4000 ? body.substring(0, 4000) : body;
    } catch (e) {
      Log.e('tool', 'HTTP 工具调用失败：${tool.name}', error: e);
      return '工具调用失败: $e';
    }
  }
}
