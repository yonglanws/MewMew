import 'dart:async';
import 'dart:convert';
import 'dart:math' show pow;

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'logger_service.dart';

/// 模型返回的工具调用请求
class ToolCallRequest {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCallRequest({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// 流式请求取消令牌
class CancelToken {
  bool _cancelled = false;
  http.Client? _client;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    try {
      _client?.close();
    } catch (_) {}
  }
}

/// 模型响应
class AiResponse {
  final String? content;
  final List<ToolCallRequest> toolCalls;
  final Map<String, dynamic> rawMessage;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;

  AiResponse({
    this.content,
    this.toolCalls = const [],
    required this.rawMessage,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
  });
}

/// 嵌入向量结果
class EmbeddingResult {
  final List<double> embedding;
  final int inputTokens;

  EmbeddingResult({required this.embedding, this.inputTokens = 0});
}

/// OpenAI 兼容的 Chat Completions 客户端
class AiService {
  static String _endpoint(ApiConfig config) {
    var base = config.baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return base.endsWith('/chat/completions') ? base : '$base/chat/completions';
  }

  /// 模型列表端点
  static String _modelsEndpoint(String baseUrl) {
    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    // 移除可能的 /chat/completions 后缀
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    return '$base/models';
  }

  /// 嵌入向量端点
  static String _embeddingsEndpoint(String baseUrl) {
    var base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    return '$base/embeddings';
  }

  /// 获取文本的嵌入向量（使用独立的嵌入 API 配置）
  static Future<EmbeddingResult> getEmbedding({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String text,
  }) async {
    Log.d('api', '请求嵌入向量：model=$model 文本长度=${text.length}');
    final resp = await http
        .post(
          Uri.parse(_embeddingsEndpoint(baseUrl)),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({'model': model, 'input': text}),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      Log.e('api', '嵌入 API 错误 ${resp.statusCode}');
      throw Exception(
        '嵌入 API 错误 (${resp.statusCode}): ${utf8.decode(resp.bodyBytes)}',
      );
    }

    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final embedding = data['data']?[0]?['embedding'] as List?;
    if (embedding == null) {
      Log.e('api', '嵌入 API 返回格式异常：data 为空');
      throw Exception('嵌入 API 返回格式异常');
    }
    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens = _extractInputTokens(usage);
    Log.d('api', '嵌入向量返回：维度=${embedding.length} 输入token=$inputTokens');
    return EmbeddingResult(
      embedding: embedding.map((e) => (e as num).toDouble()).toList(),
      inputTokens: inputTokens,
    );
  }

  /// 通用后台任务调用（记忆提取 / 整理合并共用）。
  ///
  /// 与 [summarizeConversation] 的区别：不做总结专用的提示词拼装与 JSON 解析，
  /// 只负责带重试地完成一次 system+user 的非流式调用并透传原文与 token 用量。
  /// 重试策略照抄 LivingMemory _call_llm_with_retry：最多 3 次，指数退避
  /// 2^attempt + 随机抖动。
  static Future<(String text, int inputTokens, int outputTokens)> runTask({
    required ApiConfig config,
    required String system,
    required String user,
    String? model,
    int maxRetries = 3,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        final backoff = Duration(
          milliseconds:
              ((pow(2, attempt) * 1000).toInt()) +
              DateTime.now().millisecondsSinceEpoch % 1000,
        );
        await Future<void>.delayed(backoff);
      }
      try {
        final resp = await chat(
          config: config,
          messages: [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          modelOverride: model,
        );
        return (
          (resp.content ?? '').trim(),
          resp.inputTokens,
          resp.outputTokens,
        );
      } catch (e) {
        lastError = e;
        Log.w('api', '记忆任务调用失败（第 ${attempt + 1} 次）', error: e);
      }
    }
    throw Exception('记忆任务调用连续失败 $maxRetries 次: $lastError');
  }

  /// 获取可用模型列表（OpenAI 兼容 /v1/models）
  static Future<List<String>> listModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    Log.d('api', '获取模型列表：$baseUrl');
    final resp = await http
        .get(
          Uri.parse(_modelsEndpoint(baseUrl)),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      Log.e('api', '获取模型失败 ${resp.statusCode}');
      throw Exception(
        '获取模型失败 (${resp.statusCode}): ${utf8.decode(resp.bodyBytes)}',
      );
    }
    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    final models =
        list
            .map((m) => (m as Map<String, dynamic>)['id'] as String?)
            .whereType<String>()
            .toList()
          ..sort();
    Log.i('api', '获取到 ${models.length} 个模型');
    return models;
  }

  static Map<String, dynamic> _buildBody({
    required ApiConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolConfig> tools,
    bool stream = false,
    String? modelOverride,
  }) {
    final body = <String, dynamic>{
      'model': modelOverride ?? config.model,
      'messages': messages,
      'temperature': config.temperature,
      if (stream) ...{
        'stream': true,
        'stream_options': {'include_usage': true},
      },
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools
          .map(
            (t) => {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.paramsSchema,
              },
            },
          )
          .toList();
    }
    return body;
  }

  /// 非流式请求
  static Future<AiResponse> chat({
    required ApiConfig config,
    required List<Map<String, dynamic>> messages,
    List<ToolConfig> tools = const [],
    String? modelOverride,
  }) async {
    Log.d(
      'api',
      '非流式请求：model=${modelOverride ?? config.model} '
          '消息数=${messages.length}',
    );
    final resp = await http
        .post(
          Uri.parse(_endpoint(config)),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(
            _buildBody(
              config: config,
              messages: messages,
              tools: tools,
              modelOverride: modelOverride,
            ),
          ),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      Log.e('api', '非流式请求失败 ${resp.statusCode}');
      throw Exception(
        'API 错误 (${resp.statusCode}): ${utf8.decode(resp.bodyBytes)}',
      );
    }

    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final message = data['choices'][0]['message'] as Map<String, dynamic>;
    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens = _extractInputTokens(usage);
    final outputTokens = _extractOutputTokens(usage);
    Log.d(
      'api',
      '非流式响应：输入=$inputTokens 输出=$outputTokens '
          '工具调用=${_parseToolCalls(message['tool_calls']).length}',
    );
    return AiResponse(
      content: message['content'] as String?,
      toolCalls: _parseToolCalls(message['tool_calls']),
      rawMessage: message,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cachedTokens: _extractCachedTokens(usage),
    );
  }

  /// 流式请求（SSE），内容增量通过 [onDelta] 回调，返回完整响应。
  /// 传入 [cancelToken] 可中途打断，打断后返回已生成的部分内容。
  static Future<AiResponse> chatStream({
    required ApiConfig config,
    required List<Map<String, dynamic>> messages,
    List<ToolConfig> tools = const [],
    void Function(String delta)? onDelta,
    CancelToken? cancelToken,
  }) async {
    Log.d(
      'api',
      '流式请求开始：model=${config.model} '
          '消息数=${messages.length} 工具数=${tools.length}',
    );
    final client = http.Client();
    cancelToken?._client = client;
    try {
      final request = http.Request('POST', Uri.parse(_endpoint(config)))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(
          _buildBody(
            config: config,
            messages: messages,
            tools: tools,
            stream: true,
          ),
        );

      final resp = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        Log.e(
          'api',
          '流式请求失败 ${resp.statusCode}：'
              '${body.length > 200 ? "${body.substring(0, 200)}..." : body}',
        );
        throw Exception('API 错误 (${resp.statusCode}): $body');
      }

      final contentBuf = StringBuffer();
      // index -> {id, name, argsBuf}
      final toolAcc = <int, Map<String, dynamic>>{};
      var buffer = '';
      Map<String, dynamic>? streamUsage;

      try {
        await for (final chunk in resp.stream.transform(
          const Utf8Decoder(allowMalformed: true),
        )) {
          if (cancelToken?.isCancelled == true) break;
          buffer += chunk;
          while (true) {
            final nl = buffer.indexOf('\n');
            if (nl < 0) break;
            final line = buffer.substring(0, nl).trim();
            buffer = buffer.substring(nl + 1);
            if (!line.startsWith('data:')) continue;
            final data = line.substring(5).trim();
            if (data.isEmpty || data == '[DONE]') continue;
            Map<String, dynamic> json;
            try {
              json = jsonDecode(data) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }
            // 捕获 usage（启用 include_usage 后，末尾 chunk 会携带）
            if (json['usage'] is Map<String, dynamic>) {
              streamUsage = json['usage'] as Map<String, dynamic>;
            }
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              contentBuf.write(content);
              onDelta?.call(content);
            }

            if (delta['tool_calls'] != null) {
              for (final tc in delta['tool_calls'] as List) {
                final idx = (tc['index'] ?? 0) as int;
                final acc = toolAcc.putIfAbsent(
                  idx,
                  () => {'id': '', 'name': '', 'args': StringBuffer()},
                );
                if (tc['id'] != null) acc['id'] = tc['id'];
                final fn = tc['function'] as Map<String, dynamic>?;
                if (fn != null) {
                  if (fn['name'] != null) {
                    acc['name'] = '${acc['name']}${fn['name']}';
                  }
                  if (fn['arguments'] != null) {
                    (acc['args'] as StringBuffer).write(fn['arguments']);
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        // 被取消时 client.close() 会导致流异常，保留已生成内容
        if (cancelToken?.isCancelled != true) {
          Log.e('api', '流式响应解析异常', error: e);
          rethrow;
        }
        Log.d('api', '流式响应被取消，保留已生成内容');
      }

      // 被打断时丢弃未完成的工具调用
      if (cancelToken?.isCancelled == true) toolAcc.clear();

      final content = contentBuf.isEmpty ? null : contentBuf.toString();
      final rawToolCalls = toolAcc.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final toolCallsJson = rawToolCalls
          .map(
            (e) => {
              'id': e.value['id'],
              'type': 'function',
              'function': {
                'name': e.value['name'],
                'arguments': (e.value['args'] as StringBuffer).toString(),
              },
            },
          )
          .toList();

      final rawMessage = <String, dynamic>{
        'role': 'assistant',
        'content': content,
        if (toolCallsJson.isNotEmpty) 'tool_calls': toolCallsJson,
      };

      // 优先使用循环中捕获的 usage；兜底解析 buffer 剩余部分
      Map<String, dynamic>? finalUsage = streamUsage;
      if (finalUsage == null) {
        try {
          final leftover = buffer.trim();
          if (leftover.isNotEmpty) {
            for (final line in leftover.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.startsWith('data:')) {
                final payload = trimmed.substring(5).trim();
                if (payload.isNotEmpty && payload != '[DONE]') {
                  final json = jsonDecode(payload) as Map<String, dynamic>;
                  if (json['usage'] != null) {
                    finalUsage = json['usage'] as Map<String, dynamic>;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      return AiResponse(
        content: content,
        toolCalls: _parseToolCalls(
          toolCallsJson.isEmpty ? null : toolCallsJson,
        ),
        rawMessage: rawMessage,
        inputTokens: _extractInputTokens(finalUsage),
        outputTokens: _extractOutputTokens(finalUsage),
        cachedTokens: _extractCachedTokens(finalUsage),
      );
    } finally {
      client.close();
    }
  }

  static List<ToolCallRequest> _parseToolCalls(dynamic toolCallsJson) {
    final result = <ToolCallRequest>[];
    if (toolCallsJson == null) return result;
    for (final tc in toolCallsJson as List) {
      Map<String, dynamic> args = {};
      try {
        args = jsonDecode(tc['function']['arguments'] ?? '{}');
      } catch (_) {}
      result.add(
        ToolCallRequest(
          id: tc['id'] ?? '',
          name: tc['function']['name'] ?? '',
          arguments: args,
        ),
      );
    }
    return result;
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int _extractInputTokens(Map<String, dynamic>? usage) {
    if (usage == null) return 0;
    return _toInt(
      usage['prompt_tokens'] ??
          usage['input_tokens'] ??
          usage['promptTokens'] ??
          usage['inputTokens'],
    );
  }

  static int _extractOutputTokens(Map<String, dynamic>? usage) {
    if (usage == null) return 0;
    return _toInt(
      usage['completion_tokens'] ??
          usage['output_tokens'] ??
          usage['completionTokens'] ??
          usage['outputTokens'],
    );
  }

  static int _extractCachedTokens(Map<String, dynamic>? usage) {
    if (usage == null) return 0;
    final details =
        usage['prompt_tokens_details'] ??
        usage['prompt_token_details'] ??
        usage['cached_tokens'] ??
        usage['cachedTokens'];
    if (details is Map<String, dynamic>) {
      return _toInt(details['cached_tokens'] ?? details['cachedTokens']);
    }
    return _toInt(details);
  }
}
