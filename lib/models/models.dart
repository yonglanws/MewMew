import 'dart:convert';
import 'dart:math' show exp;

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

/// 记忆条目（移植自 LivingMemory 的 memory document 概念）
///
/// 除了原有的摘要正文，还携带结构化元数据（主题/关键事实/参与者/情感等），
/// 以及生命周期字段（status / lastAccessTime），供检索加权与归档管理使用。
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
  DateTime? lastAccessTime; // 最近一次被检索命中的时间（衰减基准）

  // ---- 生命周期 ----
  String status; // active / archived
  DateTime? archivedAt;

  // ---- 结构化提取元数据（v2 摘要） ----
  String personaSummary; // 人格口吻的摘要（注入展示优先用它）
  String canonicalSummary; // 中性摘要
  List<String> topics; // 主题（≤5）
  List<String> keyFacts; // 关键事实（≤5，记忆原子的来源）
  List<String> participants; // 参与者昵称
  String? sentiment; // positive / neutral / negative
  String interactionType; // private_chat / group_chat / manual
  String? summaryQuality; // normal / low
  List<String> timeTags; // 来源消息的日期标签 yyyy-MM-dd
  String? sourceTimeLabel; // 来源时间范围 "d1" 或 "d1 - d2"

  // ---- 整理合并溯源 ----
  List<String> consolidatedFrom; // 被合并掉的旧记忆 id
  List<String> atomTypes; // 拥有的原子类型（去重排序）

  /// 其余未提升为字段的元数据（source_window 等）
  Map<String, dynamic> extraMetadata;

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
    this.lastAccessTime,
    this.status = 'active',
    this.archivedAt,
    this.personaSummary = '',
    this.canonicalSummary = '',
    List<String>? topics,
    List<String>? keyFacts,
    List<String>? participants,
    this.sentiment,
    this.interactionType = 'manual',
    this.summaryQuality,
    List<String>? timeTags,
    this.sourceTimeLabel,
    List<String>? consolidatedFrom,
    List<String>? atomTypes,
    Map<String, dynamic>? extraMetadata,
  })  : topics = topics ?? const [],
        keyFacts = keyFacts ?? const [],
        participants = participants ?? const [],
        timeTags = timeTags ?? const [],
        consolidatedFrom = consolidatedFrom ?? const [],
        atomTypes = atomTypes ?? const [],
        extraMetadata = extraMetadata ?? const {};

  /// 注入展示用内容：优先人格口吻摘要，退回正文
  String get displayContent => personaSummary.isNotEmpty ? personaSummary : content;

  bool get isActive => status == 'active';

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
        if (lastAccessTime != null)
          'lastAccessTime': lastAccessTime!.toIso8601String(),
        'status': status,
        if (archivedAt != null) 'archivedAt': archivedAt!.toIso8601String(),
        'personaSummary': personaSummary,
        'canonicalSummary': canonicalSummary,
        'topics': topics,
        'keyFacts': keyFacts,
        'participants': participants,
        'sentiment': sentiment,
        'interactionType': interactionType,
        'summaryQuality': summaryQuality,
        'timeTags': timeTags,
        'sourceTimeLabel': sourceTimeLabel,
        'consolidatedFrom': consolidatedFrom,
        'atomTypes': atomTypes,
        if (extraMetadata.isNotEmpty) 'extraMetadata': extraMetadata,
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
        lastAccessTime: json['lastAccessTime'] == null
            ? null
            : DateTime.tryParse(json['lastAccessTime'] as String),
        status: json['status'] ?? 'active',
        archivedAt: json['archivedAt'] == null
            ? null
            : DateTime.tryParse(json['archivedAt'] as String),
        personaSummary: json['personaSummary'] ?? '',
        canonicalSummary: json['canonicalSummary'] ?? '',
        topics: _readStringList(json['topics']),
        keyFacts: _readStringList(json['keyFacts']),
        participants: _readStringList(json['participants']),
        sentiment: json['sentiment'],
        interactionType: json['interactionType'] ??
            (json['source'] == 'summary' ? 'private_chat' : 'manual'),
        summaryQuality: json['summaryQuality'],
        timeTags: _readStringList(json['timeTags']),
        sourceTimeLabel: json['sourceTimeLabel'],
        consolidatedFrom: _readStringList(json['consolidatedFrom']),
        atomTypes: _readStringList(json['atomTypes']),
        extraMetadata:
            (json['extraMetadata'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

List<String> _readStringList(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

/// 记忆原子类型（移植自 LivingMemory AtomType）
enum AtomType { episodic, factual, relational, preference, planned, unknown }

/// 原子衰减曲线
enum AtomDecayType { linear, exponential, step }

/// 原子生命周期状态：active → expired → forgotten（物理删除在清理阶段）
enum AtomStatus { active, expired, forgotten }

/// 记忆原子：从关键事实拆出的细粒度记忆单元，独立 TTL 与衰减
class MemoryAtom {
  final String id;
  final String parentMemoryId;
  AtomType atomType;
  String content;
  List<String> entities; // 关联实体（主题 + 参与者）
  double importance; // 继承父记忆
  double confidence; // 分类置信度
  final DateTime createdAt;
  DateTime lastAccessedAt; // 衰减基准
  DateTime? lastReinforcedAt;
  DateTime? eventTime; // 计划类原子解析出的事件时间
  double ttlDays;
  DateTime expiresAt;
  AtomStatus status;
  int reinforcementCount;
  AtomDecayType decayType;
  final String? sessionId;
  final String? personaId;

  MemoryAtom({
    required this.id,
    required this.parentMemoryId,
    this.atomType = AtomType.unknown,
    required this.content,
    List<String>? entities,
    this.importance = 0.5,
    this.confidence = 0.7,
    required this.createdAt,
    DateTime? lastAccessedAt,
    this.lastReinforcedAt,
    this.eventTime,
    this.ttlDays = 30,
    DateTime? expiresAt,
    this.status = AtomStatus.active,
    this.reinforcementCount = 0,
    this.decayType = AtomDecayType.exponential,
    this.sessionId,
    this.personaId,
  })  : entities = entities ?? const [],
        lastAccessedAt = lastAccessedAt ?? createdAt,
        expiresAt = expiresAt ?? createdAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// 时间衰减分（以 lastAccessedAt 为基准）
  double temporalScore(DateTime now) => atomDecayScore(
      decayType, ttlDays, now.difference(lastAccessedAt).inDays.toDouble());

  Map<String, dynamic> toJson() => {
        'id': id,
        'parentMemoryId': parentMemoryId,
        'atomType': atomType.name,
        'content': content,
        'entities': entities,
        'importance': importance,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
        'lastAccessedAt': lastAccessedAt.toIso8601String(),
        'lastReinforcedAt': lastReinforcedAt?.toIso8601String(),
        'eventTime': eventTime?.toIso8601String(),
        'ttlDays': ttlDays,
        'expiresAt': expiresAt.toIso8601String(),
        'status': status.name,
        'reinforcementCount': reinforcementCount,
        'decayType': decayType.name,
        'sessionId': sessionId,
        'personaId': personaId,
      };

  factory MemoryAtom.fromJson(Map<String, dynamic> json) => MemoryAtom(
        id: json['id'],
        parentMemoryId: json['parentMemoryId'],
        atomType: AtomType.values.firstWhere(
          (e) => e.name == json['atomType'],
          orElse: () => AtomType.unknown,
        ),
        content: json['content'] ?? '',
        entities: _readStringList(json['entities']),
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        lastAccessedAt:
            DateTime.tryParse(json['lastAccessedAt'] ?? '') ??
                DateTime.tryParse(json['createdAt'] ?? '') ??
                DateTime.now(),
        lastReinforcedAt: json['lastReinforcedAt'] == null
            ? null
            : DateTime.tryParse(json['lastReinforcedAt'] as String),
        eventTime: json['eventTime'] == null
            ? null
            : DateTime.tryParse(json['eventTime'] as String),
        ttlDays: (json['ttlDays'] as num?)?.toDouble() ?? 30,
        expiresAt: DateTime.tryParse(json['expiresAt'] ?? '') ?? DateTime.now(),
        status: AtomStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => AtomStatus.active,
        ),
        reinforcementCount:
            (json['reinforcementCount'] as num?)?.toInt() ?? 0,
        decayType: AtomDecayType.values.firstWhere(
          (e) => e.name == json['decayType'],
          orElse: () => AtomDecayType.exponential,
        ),
        sessionId: json['sessionId'],
        personaId: json['personaId'],
      );
}

/// 原子时间衰减分（移植自 LivingMemory compute_decay_score）
double atomDecayScore(AtomDecayType type, double ttlDays, double daysSince) {
  final effectiveTtl = ttlDays < 1.0 ? 1.0 : ttlDays;
  final days = daysSince < 0 ? 0.0 : daysSince;
  switch (type) {
    case AtomDecayType.linear:
      final v = 1.0 - days / effectiveTtl;
      return v < 0 ? 0.0 : v;
    case AtomDecayType.step:
      return days <= effectiveTtl ? 1.0 : 0.05;
    case AtomDecayType.exponential:
      final halfLife = effectiveTtl / 2;
      final denom = halfLife < 0.5 ? 0.5 : halfLife;
      return exp(-_ln2 * days / denom);
  }
}

const double _ln2 = 0.6931471805599453;

/// 记忆系统配置
///
/// 字段默认值整体移植自 LivingMemory（astrbot_plugin_livingmemory）的
/// _conf_schema.json，分为：提取 / 检索 / 图谱与原子 / 衰减与遗忘 / 整理合并 五组。
class MemorySettings {
  // ---- 提取 ----
  bool useSessionFiltering; // 兼容旧配置；真正的范围以 memoryScopeMode 为准
  String memoryScopeMode; // session / persona / global
  int summaryThreshold; // 触发总结的对话轮数阈值
  bool autoSummaryEnabled; // 是否启用自动总结
  String summaryModel; // 总结用模型，空字符串表示使用当前 API 主模型
  bool includeSourceTimeTags; // 从消息时间戳生成日期标签

  // ---- 检索 ----
  int retrievalCount; // 自动注入的记忆数量 top_k
  int maxK; // 召回工具允许的最大 k
  String injectionPosition; // prepend / append
  double minImportanceForRetrieval; // 检索最低重要性过滤（0 = 不过滤）
  double minSimilarityForRetrieval; // 检索最低相似度过滤（0 = 不过滤）
  int recentMemoryCount; // 保留给最近记忆的席位
  double recentMemoryMaxAgeHours; // 最近记忆窗口
  String memoryTypeFilter; // all / event_only
  int rrfK; // RRF 融合常数
  double scoreAlpha; // 相关性权重
  double scoreBeta; // 重要性权重
  double scoreGamma; // 新鲜度权重
  double mmrLambda; // MMR 去重（相关性 vs 多样性）

  // ---- 图谱与原子 ----
  bool graphEnabled; // 图谱记忆总开关（含双路检索）
  bool atomEnabled; // 记忆原子开关
  double documentRouteWeight; // 文档路权重
  double graphRouteWeight; // 图谱路权重
  double crossRouteBonus; // 双路同时命中加成
  bool dynamicRouteWeighting; // 按查询意图动态调权
  int graphExpansionLimit; // 图谱扩展候选上限
  int graphExpansionHops; // 扩展跳数 1-2
  double graphSecondHopWeight; // 二跳权重
  double atomForgetDelayDays; // 过期→遗忘延迟
  double atomPurgeDelayDays; // 遗忘→物理删除延迟

  // ---- 衰减与遗忘 ----
  double decayRate; // 每日衰减率，0.01 表示每天降低 1%，0 禁用衰减
  double protectionThreshold; // 重要记忆保护阈值，达到此值的记忆不衰减，0-1，默认 1.0
  int maxAccessBoost; // 访问强化次数上限（同时作为衰减减缓的满分基准）
  double accessDecayWindowDays; // 最近访问窗口：窗口内访问过的记忆衰减更慢
  double accessCountDecayMultiplier; // 每日衰减后访问次数的保留比例
  bool autoCleanupEnabled; // 自动清理旧低价值记忆
  bool autoArchiveEnabled; // true = 清理时归档而非删除
  int cleanupDaysThreshold; // 清理年龄阈值（天）
  double cleanupImportanceThreshold; // 清理重要性阈值

  // ---- 整理合并 ----
  bool consolidationEnabled;
  String consolidationGranularity; // session / semantic
  String consolidationKeepOriginal; // archive / delete
  int consolidationMinMemoriesPerGroup;
  int consolidationMaxGroupsPerRun;
  double consolidationMaxImportance; // 候选重要性上限
  int consolidationMinAgeDays; // 候选最小组龄
  double consolidationSemanticThreshold; // 语义分组相似度阈值
  double consolidationMinIntervalHours; // 触发冷却

  MemorySettings({
    // 提取
    this.useSessionFiltering = true,
    this.memoryScopeMode = 'session',
    this.summaryThreshold = 20,
    this.autoSummaryEnabled = true,
    this.summaryModel = '',
    this.includeSourceTimeTags = true,
    // 检索
    this.retrievalCount = 5,
    this.maxK = 10,
    this.injectionPosition = 'prepend',
    this.minImportanceForRetrieval = 0.0,
    this.minSimilarityForRetrieval = 0.0,
    this.recentMemoryCount = 2,
    this.recentMemoryMaxAgeHours = 72,
    this.memoryTypeFilter = 'all',
    this.rrfK = 60,
    this.scoreAlpha = 0.5,
    this.scoreBeta = 0.25,
    this.scoreGamma = 0.25,
    this.mmrLambda = 0.7,
    // 图谱与原子
    this.graphEnabled = true,
    this.atomEnabled = true,
    this.documentRouteWeight = 0.65,
    this.graphRouteWeight = 0.35,
    this.crossRouteBonus = 0.08,
    this.dynamicRouteWeighting = true,
    this.graphExpansionLimit = 24,
    this.graphExpansionHops = 1,
    this.graphSecondHopWeight = 0.4,
    this.atomForgetDelayDays = 7,
    this.atomPurgeDelayDays = 30,
    // 衰减与遗忘
    this.decayRate = 0.01,
    this.protectionThreshold = 1.0,
    this.maxAccessBoost = 10,
    this.accessDecayWindowDays = 30,
    this.accessCountDecayMultiplier = 0.5,
    this.autoCleanupEnabled = true,
    this.autoArchiveEnabled = false,
    this.cleanupDaysThreshold = 30,
    this.cleanupImportanceThreshold = 0.3,
    // 整理合并
    this.consolidationEnabled = false,
    this.consolidationGranularity = 'session',
    this.consolidationKeepOriginal = 'archive',
    this.consolidationMinMemoriesPerGroup = 3,
    this.consolidationMaxGroupsPerRun = 5,
    this.consolidationMaxImportance = 0.5,
    this.consolidationMinAgeDays = 7,
    this.consolidationSemanticThreshold = 0.7,
    this.consolidationMinIntervalHours = 6,
  });

  Map<String, dynamic> toJson() => {
        'useSessionFiltering': useSessionFiltering,
        'memoryScopeMode': memoryScopeMode,
        'summaryThreshold': summaryThreshold,
        'autoSummaryEnabled': autoSummaryEnabled,
        'summaryModel': summaryModel,
        'includeSourceTimeTags': includeSourceTimeTags,
        'retrievalCount': retrievalCount,
        'maxK': maxK,
        'injectionPosition': injectionPosition,
        'minImportanceForRetrieval': minImportanceForRetrieval,
        'minSimilarityForRetrieval': minSimilarityForRetrieval,
        'recentMemoryCount': recentMemoryCount,
        'recentMemoryMaxAgeHours': recentMemoryMaxAgeHours,
        'memoryTypeFilter': memoryTypeFilter,
        'rrfK': rrfK,
        'scoreAlpha': scoreAlpha,
        'scoreBeta': scoreBeta,
        'scoreGamma': scoreGamma,
        'mmrLambda': mmrLambda,
        'graphEnabled': graphEnabled,
        'atomEnabled': atomEnabled,
        'documentRouteWeight': documentRouteWeight,
        'graphRouteWeight': graphRouteWeight,
        'crossRouteBonus': crossRouteBonus,
        'dynamicRouteWeighting': dynamicRouteWeighting,
        'graphExpansionLimit': graphExpansionLimit,
        'graphExpansionHops': graphExpansionHops,
        'graphSecondHopWeight': graphSecondHopWeight,
        'atomForgetDelayDays': atomForgetDelayDays,
        'atomPurgeDelayDays': atomPurgeDelayDays,
        'decayRate': decayRate,
        'protectionThreshold': protectionThreshold,
        'maxAccessBoost': maxAccessBoost,
        'accessDecayWindowDays': accessDecayWindowDays,
        'accessCountDecayMultiplier': accessCountDecayMultiplier,
        'autoCleanupEnabled': autoCleanupEnabled,
        'autoArchiveEnabled': autoArchiveEnabled,
        'cleanupDaysThreshold': cleanupDaysThreshold,
        'cleanupImportanceThreshold': cleanupImportanceThreshold,
        'consolidationEnabled': consolidationEnabled,
        'consolidationGranularity': consolidationGranularity,
        'consolidationKeepOriginal': consolidationKeepOriginal,
        'consolidationMinMemoriesPerGroup': consolidationMinMemoriesPerGroup,
        'consolidationMaxGroupsPerRun': consolidationMaxGroupsPerRun,
        'consolidationMaxImportance': consolidationMaxImportance,
        'consolidationMinAgeDays': consolidationMinAgeDays,
        'consolidationSemanticThreshold': consolidationSemanticThreshold,
        'consolidationMinIntervalHours': consolidationMinIntervalHours,
      };

  factory MemorySettings.fromJson(Map<String, dynamic> json) => MemorySettings(
        useSessionFiltering: json['useSessionFiltering'] ?? true,
        memoryScopeMode: json['memoryScopeMode'] as String? ??
            ((json['useSessionFiltering'] ?? true) == true ? 'session' : 'global'),
        summaryThreshold: json['summaryThreshold'] ?? 20,
        autoSummaryEnabled: json['autoSummaryEnabled'] ?? true,
        summaryModel: json['summaryModel'] ?? '',
        includeSourceTimeTags: json['includeSourceTimeTags'] ?? true,
        retrievalCount: json['retrievalCount'] ?? 5,
        maxK: json['maxK'] ?? 10,
        injectionPosition: json['injectionPosition'] ?? 'prepend',
        minImportanceForRetrieval:
            (json['minImportanceForRetrieval'] as num?)?.toDouble() ?? 0.0,
        minSimilarityForRetrieval:
            (json['minSimilarityForRetrieval'] as num?)?.toDouble() ?? 0.0,
        recentMemoryCount: json['recentMemoryCount'] ?? 2,
        recentMemoryMaxAgeHours:
            (json['recentMemoryMaxAgeHours'] as num?)?.toDouble() ?? 72,
        memoryTypeFilter: json['memoryTypeFilter'] ?? 'all',
        rrfK: json['rrfK'] ?? 60,
        scoreAlpha: (json['scoreAlpha'] as num?)?.toDouble() ?? 0.5,
        scoreBeta: (json['scoreBeta'] as num?)?.toDouble() ?? 0.25,
        scoreGamma: (json['scoreGamma'] as num?)?.toDouble() ?? 0.25,
        mmrLambda: (json['mmrLambda'] as num?)?.toDouble() ?? 0.7,
        graphEnabled: json['graphEnabled'] ?? true,
        atomEnabled: json['atomEnabled'] ?? true,
        documentRouteWeight:
            (json['documentRouteWeight'] as num?)?.toDouble() ?? 0.65,
        graphRouteWeight:
            (json['graphRouteWeight'] as num?)?.toDouble() ?? 0.35,
        crossRouteBonus: (json['crossRouteBonus'] as num?)?.toDouble() ?? 0.08,
        dynamicRouteWeighting: json['dynamicRouteWeighting'] ?? true,
        graphExpansionLimit: json['graphExpansionLimit'] ?? 24,
        graphExpansionHops: json['graphExpansionHops'] ?? 1,
        graphSecondHopWeight:
            (json['graphSecondHopWeight'] as num?)?.toDouble() ?? 0.4,
        atomForgetDelayDays:
            (json['atomForgetDelayDays'] as num?)?.toDouble() ?? 7,
        atomPurgeDelayDays:
            (json['atomPurgeDelayDays'] as num?)?.toDouble() ?? 30,
        decayRate: (json['decayRate'] as num?)?.toDouble() ?? 0.01,
        protectionThreshold:
            (json['protectionThreshold'] as num?)?.toDouble() ?? 1.0,
        maxAccessBoost: json['maxAccessBoost'] ?? 10,
        accessDecayWindowDays:
            (json['accessDecayWindowDays'] as num?)?.toDouble() ?? 30,
        accessCountDecayMultiplier:
            (json['accessCountDecayMultiplier'] as num?)?.toDouble() ?? 0.5,
        autoCleanupEnabled: json['autoCleanupEnabled'] ?? true,
        autoArchiveEnabled: json['autoArchiveEnabled'] ?? false,
        cleanupDaysThreshold: json['cleanupDaysThreshold'] ?? 30,
        cleanupImportanceThreshold:
            (json['cleanupImportanceThreshold'] as num?)?.toDouble() ?? 0.3,
        consolidationEnabled: json['consolidationEnabled'] ?? false,
        consolidationGranularity: json['consolidationGranularity'] ?? 'session',
        consolidationKeepOriginal:
            json['consolidationKeepOriginal'] ?? 'archive',
        consolidationMinMemoriesPerGroup:
            json['consolidationMinMemoriesPerGroup'] ?? 3,
        consolidationMaxGroupsPerRun:
            json['consolidationMaxGroupsPerRun'] ?? 5,
        consolidationMaxImportance:
            (json['consolidationMaxImportance'] as num?)?.toDouble() ?? 0.5,
        consolidationMinAgeDays: json['consolidationMinAgeDays'] ?? 7,
        consolidationSemanticThreshold:
            (json['consolidationSemanticThreshold'] as num?)?.toDouble() ?? 0.7,
        consolidationMinIntervalHours:
            (json['consolidationMinIntervalHours'] as num?)?.toDouble() ?? 6,
      );

  MemorySettings copyWith({
    bool? useSessionFiltering,
    String? memoryScopeMode,
    int? summaryThreshold,
    bool? autoSummaryEnabled,
    String? summaryModel,
    bool? includeSourceTimeTags,
    int? retrievalCount,
    int? maxK,
    String? injectionPosition,
    double? minImportanceForRetrieval,
    double? minSimilarityForRetrieval,
    int? recentMemoryCount,
    double? recentMemoryMaxAgeHours,
    String? memoryTypeFilter,
    int? rrfK,
    double? scoreAlpha,
    double? scoreBeta,
    double? scoreGamma,
    double? mmrLambda,
    bool? graphEnabled,
    bool? atomEnabled,
    double? documentRouteWeight,
    double? graphRouteWeight,
    double? crossRouteBonus,
    bool? dynamicRouteWeighting,
    int? graphExpansionLimit,
    int? graphExpansionHops,
    double? graphSecondHopWeight,
    double? atomForgetDelayDays,
    double? atomPurgeDelayDays,
    double? decayRate,
    double? protectionThreshold,
    int? maxAccessBoost,
    double? accessDecayWindowDays,
    double? accessCountDecayMultiplier,
    bool? autoCleanupEnabled,
    bool? autoArchiveEnabled,
    int? cleanupDaysThreshold,
    double? cleanupImportanceThreshold,
    bool? consolidationEnabled,
    String? consolidationGranularity,
    String? consolidationKeepOriginal,
    int? consolidationMinMemoriesPerGroup,
    int? consolidationMaxGroupsPerRun,
    double? consolidationMaxImportance,
    int? consolidationMinAgeDays,
    double? consolidationSemanticThreshold,
    double? consolidationMinIntervalHours,
  }) =>
      MemorySettings(
        useSessionFiltering: useSessionFiltering ?? this.useSessionFiltering,
        memoryScopeMode: memoryScopeMode ?? this.memoryScopeMode,
        summaryThreshold: summaryThreshold ?? this.summaryThreshold,
        autoSummaryEnabled: autoSummaryEnabled ?? this.autoSummaryEnabled,
        summaryModel: summaryModel ?? this.summaryModel,
        includeSourceTimeTags:
            includeSourceTimeTags ?? this.includeSourceTimeTags,
        retrievalCount: retrievalCount ?? this.retrievalCount,
        maxK: maxK ?? this.maxK,
        injectionPosition: injectionPosition ?? this.injectionPosition,
        minImportanceForRetrieval:
            minImportanceForRetrieval ?? this.minImportanceForRetrieval,
        minSimilarityForRetrieval:
            minSimilarityForRetrieval ?? this.minSimilarityForRetrieval,
        recentMemoryCount: recentMemoryCount ?? this.recentMemoryCount,
        recentMemoryMaxAgeHours:
            recentMemoryMaxAgeHours ?? this.recentMemoryMaxAgeHours,
        memoryTypeFilter: memoryTypeFilter ?? this.memoryTypeFilter,
        rrfK: rrfK ?? this.rrfK,
        scoreAlpha: scoreAlpha ?? this.scoreAlpha,
        scoreBeta: scoreBeta ?? this.scoreBeta,
        scoreGamma: scoreGamma ?? this.scoreGamma,
        mmrLambda: mmrLambda ?? this.mmrLambda,
        graphEnabled: graphEnabled ?? this.graphEnabled,
        atomEnabled: atomEnabled ?? this.atomEnabled,
        documentRouteWeight: documentRouteWeight ?? this.documentRouteWeight,
        graphRouteWeight: graphRouteWeight ?? this.graphRouteWeight,
        crossRouteBonus: crossRouteBonus ?? this.crossRouteBonus,
        dynamicRouteWeighting:
            dynamicRouteWeighting ?? this.dynamicRouteWeighting,
        graphExpansionLimit: graphExpansionLimit ?? this.graphExpansionLimit,
        graphExpansionHops: graphExpansionHops ?? this.graphExpansionHops,
        graphSecondHopWeight:
            graphSecondHopWeight ?? this.graphSecondHopWeight,
        atomForgetDelayDays: atomForgetDelayDays ?? this.atomForgetDelayDays,
        atomPurgeDelayDays: atomPurgeDelayDays ?? this.atomPurgeDelayDays,
        decayRate: decayRate ?? this.decayRate,
        protectionThreshold: protectionThreshold ?? this.protectionThreshold,
        maxAccessBoost: maxAccessBoost ?? this.maxAccessBoost,
        accessDecayWindowDays:
            accessDecayWindowDays ?? this.accessDecayWindowDays,
        accessCountDecayMultiplier:
            accessCountDecayMultiplier ?? this.accessCountDecayMultiplier,
        autoCleanupEnabled: autoCleanupEnabled ?? this.autoCleanupEnabled,
        autoArchiveEnabled: autoArchiveEnabled ?? this.autoArchiveEnabled,
        cleanupDaysThreshold: cleanupDaysThreshold ?? this.cleanupDaysThreshold,
        cleanupImportanceThreshold:
            cleanupImportanceThreshold ?? this.cleanupImportanceThreshold,
        consolidationEnabled: consolidationEnabled ?? this.consolidationEnabled,
        consolidationGranularity:
            consolidationGranularity ?? this.consolidationGranularity,
        consolidationKeepOriginal:
            consolidationKeepOriginal ?? this.consolidationKeepOriginal,
        consolidationMinMemoriesPerGroup: consolidationMinMemoriesPerGroup ??
            this.consolidationMinMemoriesPerGroup,
        consolidationMaxGroupsPerRun:
            consolidationMaxGroupsPerRun ?? this.consolidationMaxGroupsPerRun,
        consolidationMaxImportance:
            consolidationMaxImportance ?? this.consolidationMaxImportance,
        consolidationMinAgeDays:
            consolidationMinAgeDays ?? this.consolidationMinAgeDays,
        consolidationSemanticThreshold: consolidationSemanticThreshold ??
            this.consolidationSemanticThreshold,
        consolidationMinIntervalHours:
            consolidationMinIntervalHours ?? this.consolidationMinIntervalHours,
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

enum StickerSendMode { off, low, high }

extension StickerSendModeInfo on StickerSendMode {
  String get label {
    switch (this) {
      case StickerSendMode.off:
        return '不发送表情包';
      case StickerSendMode.low:
        return '低频率发表情包';
      case StickerSendMode.high:
        return '高频率发表情包';
    }
  }

  String get description {
    switch (this) {
      case StickerSendMode.off:
        return '这个人格不会发送表情包';
      case StickerSendMode.low:
        return '只在少数特别合适的情绪节点使用';
      case StickerSendMode.high:
        return '每个非流式回复至少使用 1 个表情包';
    }
  }

  int get gateProbability {
    switch (this) {
      case StickerSendMode.off:
        return 0;
      case StickerSendMode.low:
        return 25;
      case StickerSendMode.high:
        return 100;
    }
  }
}

StickerSendMode stickerSendModeFromLegacyProbability(int probability) {
  final normalized = probability.clamp(0, 100).toInt();
  if (normalized <= 0) return StickerSendMode.off;
  if (normalized < 50) return StickerSendMode.low;
  return StickerSendMode.high;
}

StickerSendMode stickerSendModeFromJson(Map<String, dynamic> json) {
  final rawMode = json['sendMode'] as String?;
  if (rawMode != null) {
    for (final mode in StickerSendMode.values) {
      if (mode.name == rawMode) return mode;
    }
  }
  return stickerSendModeFromLegacyProbability(
    (json['sendProbability'] as num?)?.toInt() ?? 10,
  );
}

class PersonaStickerSettings {
  final String personaId;
  StickerSendMode sendMode;
  List<String> preferredFolderIds;
  String customPrompt;

  PersonaStickerSettings({
    required this.personaId,
    StickerSendMode? sendMode,
    int? sendProbability,
    List<String>? preferredFolderIds,
    this.customPrompt = '',
  }) : sendMode =
           sendMode ??
           stickerSendModeFromLegacyProbability(sendProbability ?? 10),
       preferredFolderIds = List<String>.from(preferredFolderIds ?? const []);

  int get sendProbability => sendMode.gateProbability;

  set sendProbability(int value) {
    sendMode = stickerSendModeFromLegacyProbability(value);
  }

  PersonaStickerSettings copyWith({
    StickerSendMode? sendMode,
    int? sendProbability,
    List<String>? preferredFolderIds,
    String? customPrompt,
  }) {
    return PersonaStickerSettings(
      personaId: personaId,
      sendMode:
          sendMode ??
          (sendProbability == null
              ? this.sendMode
              : stickerSendModeFromLegacyProbability(sendProbability)),
      preferredFolderIds: preferredFolderIds ?? this.preferredFolderIds,
      customPrompt: customPrompt ?? this.customPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
    'personaId': personaId,
    'sendMode': sendMode.name,
    // Keep the legacy value so older builds can still read this setting.
    'sendProbability': sendMode.gateProbability,
    'preferredFolderIds': preferredFolderIds,
    'customPrompt': customPrompt,
  };

  factory PersonaStickerSettings.fromJson(Map<String, dynamic> json) {
    return PersonaStickerSettings(
      personaId: json['personaId'] as String,
      sendMode: stickerSendModeFromJson(json),
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

/// 助手回复的显示模式。
enum AssistantOutputMode { streaming, complete, segmented }

/// 对话分段发送设置：将 AI 长文本智能切分为多段短消息，并按线性延迟逐段追加
class SegmentedSendSettings {
  // 基础设置
  bool enabled; // 是否启用分段发送
  int minTriggerLength; // 最短触发字数（短于此不分段）
  int maxProcessLength; // 最长分段处理字数（超出时保留整段，避免截断）

  // 均分算法
  int maxSegments; // 最大段数
  int minSegmentLength; // 最小段长（均分模式避免过短碎片，默认 35）
  double balanceLowerRatio; // 均分下限比，低于理想长度此比例时不切，默认 0.4
  double balanceUpperRatio; // 均分上限比，高于理想长度此比例时尝试次级标点切，默认 0.9
  bool trimBlankLines; // 清理每段首尾空行（不影响段内换行）

  // 线性延迟算法：延迟(秒) = linearBase + 字数 * linearCharFactor
  double linearBase; // 默认 0.8
  double linearCharFactor; // 默认 0.09

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

  factory SegmentedSendSettings.fromJson(Map<String, dynamic> json) {
    final rawRules = json['replaceRules'];
    final rules = rawRules is List
        ? rawRules
              .whereType<Map>()
              .map(
                (e) =>
                    SegmentedReplaceRule.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <SegmentedReplaceRule>[];
    return SegmentedSendSettings(
      enabled: _readBool(json, 'enabled', false),
      minTriggerLength: _readInt(json, 'minTriggerLength', 20),
      maxProcessLength: _readInt(json, 'maxProcessLength', 500).clamp(0, 50000),
      maxSegments: _readInt(json, 'maxSegments', 5),
      minSegmentLength: _readInt(json, 'minSegmentLength', 35),
      balanceLowerRatio: _readDouble(json, 'balanceLowerRatio', 0.4),
      balanceUpperRatio: _readDouble(json, 'balanceUpperRatio', 0.9),
      trimBlankLines: _readBool(json, 'trimBlankLines', true),
      linearBase: _readDouble(json, 'linearBase', 0.8),
      linearCharFactor: _readDouble(
        json,
        'linearCharFactor',
        0.09,
      ).clamp(0.0, 0.3),
      preCleanRegex: _readString(json, 'preCleanRegex'),
      postCleanRegex: _readString(json, 'postCleanRegex'),
      replaceRules: rules,
      reverseReplace: _readBool(json, 'reverseReplace', false),
    ).normalized();
  }

  /// 将配置限制在分段算法可以安全处理的范围内。
  ///
  /// 设置可能来自旧版本持久化数据、手动编辑的配置或 UI 外部调用，
  /// 因此不能假设数值一定有效。这里统一做边界校验，并保证上下比例
  /// 不会出现 lower > upper 的矛盾状态。
  SegmentedSendSettings normalized() {
    int boundedInt(int value, int min, int max) => value.clamp(min, max);

    double boundedDouble(
      double value,
      double fallback,
      double min,
      double max,
    ) {
      if (!value.isFinite) return fallback;
      return value.clamp(min, max).toDouble();
    }

    final lower = boundedDouble(balanceLowerRatio, 0.4, 0.0, 0.99);
    final upper = boundedDouble(balanceUpperRatio, 0.9, lower, 1.0);
    return copyWith(
      minTriggerLength: boundedInt(minTriggerLength, 1, 50000),
      maxProcessLength: boundedInt(maxProcessLength, 0, 50000),
      maxSegments: boundedInt(maxSegments, 1, 50),
      minSegmentLength: boundedInt(minSegmentLength, 1, 5000),
      balanceLowerRatio: lower,
      balanceUpperRatio: upper,
      linearBase: boundedDouble(linearBase, 0.8, 0.0, 30.0),
      linearCharFactor: boundedDouble(linearCharFactor, 0.09, 0.0, 0.3),
    );
  }

  static int _readInt(Map<String, dynamic> json, String key, int fallback) {
    final value = json[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _readBool(Map<String, dynamic> json, String key, bool fallback) {
    final value = json[key];
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return fallback;
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : '';
  }

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
        find: json['find'] is String ? json['find'] as String : '',
        replace: json['replace'] is String ? json['replace'] as String : '',
      );
}
