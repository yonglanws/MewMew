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
      ];

  static Future<String> execute(
    String name,
    Map<String, dynamic> args, {
    required Future<void> Function(String content) onSaveMemory,
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
      while (pos < tokens.length &&
          (RegExp(r'[0-9.]').hasMatch(tokens[pos]))) {
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
      ToolConfig tool, Map<String, dynamic> args) async {
    log.d('tool', 'HTTP 工具调用：${tool.name} ${tool.method} ${tool.url}');
    try {
      Map<String, String> headers = {};
      try {
        headers = (jsonDecode(tool.headersJson) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}

      http.Response resp;
      if (tool.method.toUpperCase() == 'GET') {
        final uri = Uri.parse(tool.url).replace(queryParameters: {
          ...Uri.parse(tool.url).queryParameters,
          ...args.map((k, v) => MapEntry(k, v.toString())),
        });
        resp = await http.get(uri, headers: headers).timeout(
              const Duration(seconds: 30),
            );
      } else {
        headers.putIfAbsent('Content-Type', () => 'application/json');
        resp = await http
            .post(Uri.parse(tool.url), headers: headers, body: jsonEncode(args))
            .timeout(const Duration(seconds: 30));
      }
      final body = utf8.decode(resp.bodyBytes);
      log.i('tool', 'HTTP 工具响应：${tool.name} ${resp.statusCode} '
          '长度=${body.length}');
      return body.length > 4000 ? body.substring(0, 4000) : body;
    } catch (e) {
      log.e('tool', 'HTTP 工具调用失败：${tool.name}', error: e);
      return '工具调用失败: $e';
    }
  }
}
