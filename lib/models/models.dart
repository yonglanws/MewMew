import 'dart:convert';

/// 用户资料
class UserProfile {
  String name;
  String avatarPath;

  UserProfile({this.name = '我', this.avatarPath = ''});

  Map<String, dynamic> toJson() => {'name': name, 'avatarPath': avatarPath};

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] ?? '我',
    avatarPath: json['avatarPath'] ?? '',
  );
}

/// AI 服务接口配置（OpenAI 兼容格式）—— 仅对话模型
class ApiConfig {
  final String id;
  String name;
  String baseUrl;
  String apiKey;
  String model;
  double temperature;

  ApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.7,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'temperature': temperature,
  };

  factory ApiConfig.fromJson(Map<String, dynamic> json) => ApiConfig(
    id: json['id'],
    name: json['name'],
    baseUrl: json['baseUrl'],
    apiKey: json['apiKey'],
    model: json['model'],
    temperature: (json['temperature'] ?? 0.7).toDouble(),
  );
}

/// 嵌入模型 API 配置（独立于对话 API，可指向不同服务商）
class EmbeddingApiConfig {
  String baseUrl;
  String apiKey;
  String model;

  EmbeddingApiConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  bool get isValid => baseUrl.startsWith('http') && apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory EmbeddingApiConfig.fromJson(Map<String, dynamic> json) =>
      EmbeddingApiConfig(
        baseUrl: json['baseUrl'] ?? '',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? '',
      );
}

/// 角色人格设定
class Persona {
  final String id;
  String name;
  String emoji;
  String avatarPath; // 图片头像路径（本地文件），为空时回退到 emoji
  String personality; // 性格特征
  String languageStyle; // 语言风格
  String backstory; // 背景故事
  String greeting; // 开场白
  bool useRawPrompt; // true = 完整提示词模式
  String rawPrompt; // 完整提示词内容

  Persona({
    required this.id,
    required this.name,
    this.emoji = '🤖',
    this.avatarPath = '',
    this.personality = '',
    this.languageStyle = '',
    this.backstory = '',
    this.greeting = '',
    this.useRawPrompt = false,
    this.rawPrompt = '',
  });

  /// 构建系统提示词
  String buildSystemPrompt() {
    if (useRawPrompt && rawPrompt.trim().isNotEmpty) {
      return rawPrompt;
    }
    final buf = StringBuffer();
    buf.writeln('你正在扮演角色「$name」，请始终保持角色设定，不要跳出角色。');
    if (personality.isNotEmpty) buf.writeln('【性格特征】$personality');
    if (languageStyle.isNotEmpty) buf.writeln('【语言风格】$languageStyle');
    if (backstory.isNotEmpty) buf.writeln('【背景故事】$backstory');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'avatarPath': avatarPath,
    'personality': personality,
    'languageStyle': languageStyle,
    'backstory': backstory,
    'greeting': greeting,
    'useRawPrompt': useRawPrompt,
    'rawPrompt': rawPrompt,
  };

  factory Persona.fromJson(Map<String, dynamic> json) => Persona(
    id: json['id'],
    name: json['name'],
    emoji: json['emoji'] ?? '🤖',
    avatarPath: json['avatarPath'] ?? '',
    personality: json['personality'] ?? '',
    languageStyle: json['languageStyle'] ?? '',
    backstory: json['backstory'] ?? '',
    greeting: json['greeting'] ?? '',
    useRawPrompt: json['useRawPrompt'] ?? false,
    rawPrompt: json['rawPrompt'] ?? '',
  );
}

enum ToolType { builtin, http }

/// 工具配置
class ToolConfig {
  final String id;
  String name; // 函数名（英文）
  String description;
  ToolType type;
  bool enabled;
  // HTTP 工具字段
  String url;
  String method;
  String headersJson; // JSON 字符串
  String paramsSchemaJson; // JSON Schema 字符串

  ToolConfig({
    required this.id,
    required this.name,
    required this.description,
    this.type = ToolType.http,
    this.enabled = true,
    this.url = '',
    this.method = 'GET',
    this.headersJson = '{}',
    this.paramsSchemaJson = '{"type":"object","properties":{}}',
  });

  Map<String, dynamic> get paramsSchema {
    try {
      return jsonDecode(paramsSchemaJson) as Map<String, dynamic>;
    } catch (_) {
      return {'type': 'object', 'properties': {}};
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'enabled': enabled,
    'url': url,
    'method': method,
    'headersJson': headersJson,
    'paramsSchemaJson': paramsSchemaJson,
  };

  factory ToolConfig.fromJson(Map<String, dynamic> json) => ToolConfig(
    id: json['id'],
    name: json['name'],
    description: json['description'] ?? '',
    type: ToolType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ToolType.http,
    ),
    enabled: json['enabled'] ?? true,
    url: json['url'] ?? '',
    method: json['method'] ?? 'GET',
    headersJson: json['headersJson'] ?? '{}',
    paramsSchemaJson:
        json['paramsSchemaJson'] ?? '{"type":"object","properties":{}}',
  );
}

/// 记忆条目
class MemoryEntry {
  final String id;
  String content;
  final DateTime createdAt;
  final String source; // manual / auto / summary
  final String? personaId;
  final String? sessionId;
  List<double>? embedding; // 嵌入向量，用于语义检索
  double importance; // 重要性 0.0-1.0，由总结模型评估或默认 0.5
  int accessCount; // 被检索注入的次数，用于访问强化

  MemoryEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    this.source = 'manual',
    this.personaId,
    this.sessionId,
    this.embedding,
    this.importance = 0.5,
    this.accessCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'source': source,
    'personaId': personaId,
    'sessionId': sessionId,
    if (embedding != null) 'embedding': embedding,
    'importance': importance,
    'accessCount': accessCount,
  };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) => MemoryEntry(
    id: json['id'],
    content: json['content'],
    createdAt: DateTime.parse(json['createdAt']),
    source: json['source'] ?? 'manual',
    personaId: json['personaId'],
    sessionId: json['sessionId'],
    embedding: (json['embedding'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList(),
    importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
    accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
  );
}

/// 记忆系统配置
class MemorySettings {
  bool useSessionFiltering; // true = 会话隔离, false = 全局共享
  int summaryThreshold; // 触发总结的对话轮数阈值
  int retrievalCount; // 检索返回的记忆数量
  String injectionPosition; // prepend / append
  bool autoSummaryEnabled; // 是否启用自动总结
  String summaryModel; // 总结用模型，空字符串表示使用当前 API 主模型
  double decayRate; // 每日衰减率，0.01 表示每天降低 1%，0 禁用衰减
  double protectionThreshold; // 重要记忆保护阈值，达到此值的记忆不衰减，0-1，默认 1.0
  int maxAccessBoost; // 访问强化次数上限，达到后获得最大衰减保护，默认 10

  MemorySettings({
    this.useSessionFiltering = true,
    this.summaryThreshold = 10,
    this.retrievalCount = 5,
    this.injectionPosition = 'prepend',
    this.autoSummaryEnabled = true,
    this.summaryModel = '',
    this.decayRate = 0.01,
    this.protectionThreshold = 1.0,
    this.maxAccessBoost = 10,
  });

  Map<String, dynamic> toJson() => {
    'useSessionFiltering': useSessionFiltering,
    'summaryThreshold': summaryThreshold,
    'retrievalCount': retrievalCount,
    'injectionPosition': injectionPosition,
    'autoSummaryEnabled': autoSummaryEnabled,
    'summaryModel': summaryModel,
    'decayRate': decayRate,
    'protectionThreshold': protectionThreshold,
    'maxAccessBoost': maxAccessBoost,
  };

  factory MemorySettings.fromJson(Map<String, dynamic> json) => MemorySettings(
    useSessionFiltering: json['useSessionFiltering'] ?? true,
    summaryThreshold: json['summaryThreshold'] ?? 10,
    retrievalCount: json['retrievalCount'] ?? 5,
    injectionPosition: json['injectionPosition'] ?? 'prepend',
    autoSummaryEnabled: json['autoSummaryEnabled'] ?? true,
    summaryModel: json['summaryModel'] ?? '',
    decayRate: (json['decayRate'] as num?)?.toDouble() ?? 0.01,
    protectionThreshold:
        (json['protectionThreshold'] as num?)?.toDouble() ?? 1.0,
    maxAccessBoost: (json['maxAccessBoost'] as num?)?.toInt() ?? 10,
  );

  MemorySettings copyWith({
    bool? useSessionFiltering,
    int? summaryThreshold,
    int? retrievalCount,
    String? injectionPosition,
    bool? autoSummaryEnabled,
    String? summaryModel,
    double? decayRate,
    double? protectionThreshold,
    int? maxAccessBoost,
  }) => MemorySettings(
    useSessionFiltering: useSessionFiltering ?? this.useSessionFiltering,
    summaryThreshold: summaryThreshold ?? this.summaryThreshold,
    retrievalCount: retrievalCount ?? this.retrievalCount,
    injectionPosition: injectionPosition ?? this.injectionPosition,
    autoSummaryEnabled: autoSummaryEnabled ?? this.autoSummaryEnabled,
    summaryModel: summaryModel ?? this.summaryModel,
    decayRate: decayRate ?? this.decayRate,
    protectionThreshold: protectionThreshold ?? this.protectionThreshold,
    maxAccessBoost: maxAccessBoost ?? this.maxAccessBoost,
  );
}

/// 群聊（多角色对话组）
class GroupChat {
  final String id;
  String name;
  String avatarPath;
  List<String> personaIds;

  GroupChat({
    required this.id,
    required this.name,
    this.avatarPath = '',
    List<String>? personaIds,
  }) : personaIds = personaIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarPath': avatarPath,
    'personaIds': personaIds,
  };

  factory GroupChat.fromJson(Map<String, dynamic> json) => GroupChat(
    id: json['id'],
    name: json['name'],
    avatarPath: json['avatarPath'] ?? '',
    personaIds: List<String>.from(json['personaIds'] ?? []),
  );
}

class StickerItem {
  final String id;
  final String folderId;
  final String name;
  final String description;
  final String filePath;
  final DateTime createdAt;

  const StickerItem({
    required this.id,
    required this.folderId,
    required this.name,
    required this.description,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'name': name,
    'description': description,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StickerItem.fromJson(Map<String, dynamic> json) => StickerItem(
    id: json['id'] as String,
    folderId: json['folderId'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    filePath: json['filePath'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class StickerGroup {
  final String id;
  final String name;
  final DateTime createdAt;

  const StickerGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StickerGroup.fromJson(Map<String, dynamic> json) => StickerGroup(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class StickerFolder {
  final String id;
  final String groupId;
  final String name;
  final String description;
  final DateTime createdAt;

  const StickerFolder({
    required this.id,
    required this.groupId,
    required this.name,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StickerFolder.fromJson(Map<String, dynamic> json) => StickerFolder(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class PersonaStickerBinding {
  final String personaId;
  final String groupId;
  final DateTime createdAt;

  const PersonaStickerBinding({
    required this.personaId,
    required this.groupId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'personaId': personaId,
    'groupId': groupId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PersonaStickerBinding.fromJson(Map<String, dynamic> json) =>
      PersonaStickerBinding(
        personaId: json['personaId'] as String,
        groupId: json['groupId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class PersonaStickerSettings {
  final String personaId;
  int sendProbability;
  List<String> preferredFolderIds;
  String customPrompt;

  PersonaStickerSettings({
    required this.personaId,
    this.sendProbability = 10,
    List<String>? preferredFolderIds,
    this.customPrompt = '',
  }) : preferredFolderIds = List<String>.from(preferredFolderIds ?? const []);

  PersonaStickerSettings copyWith({
    int? sendProbability,
    List<String>? preferredFolderIds,
    String? customPrompt,
  }) {
    return PersonaStickerSettings(
      personaId: personaId,
      sendProbability: sendProbability ?? this.sendProbability,
      preferredFolderIds: preferredFolderIds ?? this.preferredFolderIds,
      customPrompt: customPrompt ?? this.customPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
    'personaId': personaId,
    'sendProbability': sendProbability,
    'preferredFolderIds': preferredFolderIds,
    'customPrompt': customPrompt,
  };

  factory PersonaStickerSettings.fromJson(Map<String, dynamic> json) {
    return PersonaStickerSettings(
      personaId: json['personaId'] as String,
      sendProbability: (json['sendProbability'] as num?)?.toInt() ?? 10,
      preferredFolderIds: List<String>.from(
        json['preferredFolderIds'] as List? ?? const [],
      ),
      customPrompt: json['customPrompt'] as String? ?? '',
    );
  }
}

/// 聊天消息
class ChatMessage {
  final String id;
  final String role; // user / assistant / tool
  String content;
  final DateTime timestamp;
  final String? toolName; // 工具调用产生的消息
  final String? speakerId; // 群聊中发言的角色 ID
  final List<String> mentionIds; // 群聊中用户消息 @ 的角色 ID 列表
  String? stickerId;
  // 运行时标记：AI 正在流式生成中（不持久化）
  bool isStreaming = false;
  // 运行时标记：本条消息是"对话分段发送"产生的一段（不持久化）
  // 用于 UI 区分"流式打字光标"和"按段延迟追加"两种形态
  bool isSegmented = false;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolName,
    this.speakerId,
    this.stickerId,
    List<String>? mentionIds,
  }) : mentionIds = mentionIds ?? const [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'toolName': toolName,
    'speakerId': speakerId,
    'mentionIds': mentionIds,
    'stickerId': stickerId,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    role: json['role'],
    content: json['content'],
    timestamp: DateTime.parse(json['timestamp']),
    toolName: json['toolName'],
    speakerId: json['speakerId'],
    mentionIds: List<String>.from(json['mentionIds'] ?? const []),
    stickerId: json['stickerId'] as String?,
  );
}

/// 聊天会话
class ChatSession {
  final String id;
  String title;
  String? personaId; // 单聊绑定的角色
  String? groupChatId; // 群聊绑定的群组
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    this.personaId,
    this.groupChatId,
    List<ChatMessage>? messages,
    required this.createdAt,
    required this.updatedAt,
  }) : messages = messages ?? [];

  bool get isGroup => groupChatId != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'personaId': personaId,
    'groupChatId': groupChatId,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'],
    title: json['title'],
    personaId: json['personaId'],
    groupChatId: json['groupChatId'],
    messages: (json['messages'] as List? ?? [])
        .map((m) => ChatMessage.fromJson(m))
        .toList(),
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}

/// 单日 Token 使用记录
class DailyTokenUsage {
  final String date; // yyyy-MM-dd
  int inputTokens;
  int outputTokens;
  int cachedTokens;

  DailyTokenUsage({
    required this.date,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
  });

  int get totalTokens => inputTokens + outputTokens;

  Map<String, dynamic> toJson() => {
    'date': date,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cachedTokens': cachedTokens,
  };

  factory DailyTokenUsage.fromJson(Map<String, dynamic> json) =>
      DailyTokenUsage(
        date: json['date'] as String,
        inputTokens: json['inputTokens'] ?? 0,
        outputTokens: json['outputTokens'] ?? 0,
        cachedTokens: json['cachedTokens'] ?? 0,
      );
}

/// Token 使用统计
class TokenUsage {
  int inputTokens;
  int outputTokens;
  int cachedTokens;
  List<DailyTokenUsage> dailyRecords;

  TokenUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
    this.dailyRecords = const [],
  });

  int get totalTokens => inputTokens + outputTokens;

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cachedTokens': cachedTokens,
    'dailyRecords': dailyRecords.map((d) => d.toJson()).toList(),
  };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    inputTokens: json['inputTokens'] ?? 0,
    outputTokens: json['outputTokens'] ?? 0,
    cachedTokens: json['cachedTokens'] ?? 0,
    dailyRecords: ((json['dailyRecords'] ?? []) as List)
        .map((d) => DailyTokenUsage.fromJson(d as Map<String, dynamic>))
        .toList(),
  );

  TokenUsage copyWith({
    int? inputTokens,
    int? outputTokens,
    int? cachedTokens,
    List<DailyTokenUsage>? dailyRecords,
  }) => TokenUsage(
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    cachedTokens: cachedTokens ?? this.cachedTokens,
    dailyRecords: dailyRecords ?? this.dailyRecords,
  );
}

/// 对话分段发送设置：将 AI 长文本智能切分为多段短消息，并按线性延迟逐段追加
class SegmentedSendSettings {
  // 基础设置
  bool enabled; // 是否启用分段发送
  int minTriggerLength; // 最短触发字数（短于此不分段）
  int maxProcessLength; // 最长处理字数（超出截断或不再追加段）

  // 均分算法
  int maxSegments; // 最大段数
  int minSegmentLength; // 最小段长（均分模式避免过短碎片，默认 35）
  double balanceLowerRatio; // 均分下限比，低于理想长度此比例时不切，默认 0.4
  double balanceUpperRatio; // 均分上限比，高于理想长度此比例时尝试次级标点切，默认 0.9
  bool trimBlankLines; // 清理每段首尾空行（不影响段内换行）

  // 线性延迟算法：延迟(秒) = linearBase + 字数 * linearCharFactor
  double linearBase; // 默认 0.5
  double linearCharFactor; // 默认 0.1

  // 文本清理
  String preCleanRegex; // 前置清理正则
  String postCleanRegex; // 后置清理正则
  List<SegmentedReplaceRule> replaceRules; // 替换规则
  bool reverseReplace; // 是否对用户输入反向应用替换

  SegmentedSendSettings({
    this.enabled = false,
    this.minTriggerLength = 20,
    this.maxProcessLength = 500,
    this.maxSegments = 5,
    this.minSegmentLength = 35,
    this.balanceLowerRatio = 0.4,
    this.balanceUpperRatio = 0.9,
    this.trimBlankLines = true,
    this.linearBase = 0.8,
    this.linearCharFactor = 0.09,
    this.preCleanRegex = '',
    this.postCleanRegex = '',
    this.replaceRules = const [],
    this.reverseReplace = false,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'minTriggerLength': minTriggerLength,
    'maxProcessLength': maxProcessLength,
    'maxSegments': maxSegments,
    'minSegmentLength': minSegmentLength,
    'balanceLowerRatio': balanceLowerRatio,
    'balanceUpperRatio': balanceUpperRatio,
    'trimBlankLines': trimBlankLines,
    'linearBase': linearBase,
    'linearCharFactor': linearCharFactor,
    'preCleanRegex': preCleanRegex,
    'postCleanRegex': postCleanRegex,
    'replaceRules': replaceRules.map((r) => r.toJson()).toList(),
    'reverseReplace': reverseReplace,
  };

  factory SegmentedSendSettings.fromJson(
    Map<String, dynamic> json,
  ) => SegmentedSendSettings(
    enabled: json['enabled'] ?? false,
    minTriggerLength: json['minTriggerLength'] ?? 20,
    maxProcessLength: ((json['maxProcessLength'] as num?)?.toInt() ?? 500)
        .clamp(0, 50000),
    maxSegments: json['maxSegments'] ?? 5,
    minSegmentLength: json['minSegmentLength'] ?? 35,
    balanceLowerRatio: (json['balanceLowerRatio'] as num?)?.toDouble() ?? 0.4,
    balanceUpperRatio: (json['balanceUpperRatio'] as num?)?.toDouble() ?? 0.9,
    trimBlankLines: json['trimBlankLines'] ?? true,
    linearBase: (json['linearBase'] as num?)?.toDouble() ?? 0.5,
    linearCharFactor: ((json['linearCharFactor'] as num?)?.toDouble() ?? 0.07)
        .clamp(0.0, 0.3),
    preCleanRegex: json['preCleanRegex'] ?? '',
    postCleanRegex: json['postCleanRegex'] ?? '',
    replaceRules: ((json['replaceRules'] ?? []) as List)
        .map((e) => SegmentedReplaceRule.fromJson(e as Map<String, dynamic>))
        .toList(),
    reverseReplace: json['reverseReplace'] ?? false,
  );

  SegmentedSendSettings copyWith({
    bool? enabled,
    int? minTriggerLength,
    int? maxProcessLength,
    int? maxSegments,
    int? minSegmentLength,
    double? balanceLowerRatio,
    double? balanceUpperRatio,
    bool? trimBlankLines,
    double? linearBase,
    double? linearCharFactor,
    String? preCleanRegex,
    String? postCleanRegex,
    List<SegmentedReplaceRule>? replaceRules,
    bool? reverseReplace,
  }) => SegmentedSendSettings(
    enabled: enabled ?? this.enabled,
    minTriggerLength: minTriggerLength ?? this.minTriggerLength,
    maxProcessLength: maxProcessLength ?? this.maxProcessLength,
    maxSegments: maxSegments ?? this.maxSegments,
    minSegmentLength: minSegmentLength ?? this.minSegmentLength,
    balanceLowerRatio: balanceLowerRatio ?? this.balanceLowerRatio,
    balanceUpperRatio: balanceUpperRatio ?? this.balanceUpperRatio,
    trimBlankLines: trimBlankLines ?? this.trimBlankLines,
    linearBase: linearBase ?? this.linearBase,
    linearCharFactor: linearCharFactor ?? this.linearCharFactor,
    preCleanRegex: preCleanRegex ?? this.preCleanRegex,
    postCleanRegex: postCleanRegex ?? this.postCleanRegex,
    replaceRules: replaceRules ?? this.replaceRules,
    reverseReplace: reverseReplace ?? this.reverseReplace,
  );
}

/// 分段发送替换规则：查找文本 → 替换为
class SegmentedReplaceRule {
  String find;
  String replace;

  SegmentedReplaceRule({required this.find, required this.replace});

  Map<String, dynamic> toJson() => {'find': find, 'replace': replace};

  factory SegmentedReplaceRule.fromJson(Map<String, dynamic> json) =>
      SegmentedReplaceRule(
        find: json['find'] ?? '',
        replace: json['replace'] ?? '',
      );
}
