import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'logger_service.dart';

/// 本地持久化服务（基于 SharedPreferences）
class StorageService {
  static const _kApiConfigs = 'api_configs';
  static const _kActiveApiId = 'active_api_id';
  static const _kEmbeddingApiConfig = 'embedding_api_config';
  static const _kPersonas = 'personas';
  static const _kActivePersonaId = 'active_persona_id';
  static const _kTools = 'tools';
  static const _kMemories = 'memories';
  static const _kMemoryEmbeddings = 'memory_embeddings';
  static const _kMemoryAtoms = 'memory_atoms';
  static const _kMemoryReflectionState = 'memory_reflection_state';
  static const _kMemoryMaintenanceState = 'memory_maintenance_state';
  static const _kMemoryGraph = 'memory_graph_v1';
  static const _kSessions = 'sessions';
  static const _kThemeMode = 'theme_mode';
  static const _kInjectMemories = 'inject_memories';
  static const _kCrossSessionMemories = 'cross_session_memories';
  static const _kMemorySettings = 'memory_settings';
  static const _kSummaryThresholdMigrated =
      'memory_summary_threshold_migrated_v2';
  static const _kTokenUsage = 'token_usage';
  static const _kTokenDailyUsage = 'token_daily_usage';
  static const _kAppLaunchCount = 'app_launch_count';
  static const _kGroupChats = 'group_chats';
  static const _kUserProfile = 'user_profile';
  static const _kMessageMergeEnabled = 'message_merge_enabled';
  static const _kMessageMergeDebounce = 'message_merge_debounce';
  static const _kTypingDebounceEnabled = 'typing_debounce_enabled';
  static const _kSegmentedSendSettings = 'segmented_send_settings';
  static const _kStreamOutputEnabled = 'stream_output_enabled';
  static const _kAssistantOutputMode = 'assistant_output_mode';
  static const _kStickerSendMode = 'sticker_send_mode';
  static const _kStickerSendProbability = 'sticker_send_probability';
  static const _kStickerItems = 'sticker_items_v2';
  static const _kStickerFolders = 'sticker_folders_v2';
  static const _kStickerGroups = 'sticker_groups_v2';
  static const _kPersonaStickerBindings = 'persona_sticker_bindings_v2';
  static const _kPersonaStickerSettings = 'persona_sticker_settings_v1';
  static const _kPromptInjectionSettings = 'prompt_injection_settings_v1';
  static const _kWorldBookSettings = 'world_book_settings_v1';
  static const _kGenerationStyleSettings = 'generation_style_settings_v1';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    Log.d('storage', 'SharedPreferences 初始化完成');
  }

  List<T> _loadList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.w('storage', '反序列化 $key 失败，重置为空列表', error: e);
      return [];
    }
  }

  Future<void> _saveList(String key, List<dynamic> items) async {
    await _prefs.setString(
      key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  // API 配置
  List<ApiConfig> loadApiConfigs() =>
      _loadList(_kApiConfigs, ApiConfig.fromJson);
  Future<void> saveApiConfigs(List<ApiConfig> list) =>
      _saveList(_kApiConfigs, list);
  String? get activeApiId => _prefs.getString(_kActiveApiId);
  Future<void> setActiveApiId(String? id) async => id == null
      ? _prefs.remove(_kActiveApiId)
      : _prefs.setString(_kActiveApiId, id);

  // 嵌入 API 配置（独立于对话 API）
  EmbeddingApiConfig loadEmbeddingApiConfig() {
    final raw = _prefs.getString(_kEmbeddingApiConfig);
    if (raw != null) {
      try {
        return EmbeddingApiConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return EmbeddingApiConfig();
  }

  Future<void> saveEmbeddingApiConfig(EmbeddingApiConfig config) =>
      _prefs.setString(_kEmbeddingApiConfig, jsonEncode(config.toJson()));

  // 人格
  List<Persona> loadPersonas() => _loadList(_kPersonas, Persona.fromJson);
  Future<void> savePersonas(List<Persona> list) => _saveList(_kPersonas, list);
  String? get activePersonaId => _prefs.getString(_kActivePersonaId);
  Future<void> setActivePersonaId(String? id) async => id == null
      ? _prefs.remove(_kActivePersonaId)
      : _prefs.setString(_kActivePersonaId, id);

  // 工具
  List<ToolConfig> loadTools() => _loadList(_kTools, ToolConfig.fromJson);
  Future<void> saveTools(List<ToolConfig> list) => _saveList(_kTools, list);

  // 记忆
  //
  // 嵌入向量分离存储（memory_embeddings：id → 向量）：记忆列表保存频繁且小，
  // 向量大且稳定；分离后高频保存不再反复序列化大浮点数组。
  // 兼容旧格式：memories JSON 内联的 embedding 会在读取时提取并归位。
  List<MemoryEntry> loadMemories() {
    final entries = _loadList(_kMemories, MemoryEntry.fromJson);
    final embeddings = _loadEmbeddings();
    var migrated = false;
    for (final e in entries) {
      final inline = e.embedding;
      if (inline != null) {
        // 旧格式内联向量：提取到分离存储
        embeddings[e.id] = inline;
        e.embedding = null;
        migrated = true;
      }
      final stored = embeddings[e.id];
      if (stored != null) {
        e.embedding = stored;
      }
    }
    if (migrated) {
      // 一次性写出分离格式，并清掉 memories 里的内联向量
      unawaited(_saveMemoryEntries(entries, embeddings));
      Log.i('storage', '记忆嵌入向量迁移到独立存储：${embeddings.length} 条');
    }
    return entries;
  }

  Map<String, List<double>> _loadEmbeddings() {
    final raw = _prefs.getString(_kMemoryEmbeddings);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) =>
            MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMemoryEntries(
    List<MemoryEntry> list,
    Map<String, List<double>> embeddings,
  ) async {
    final items = list.map((e) {
      final json = e.toJson()..remove('embedding');
      return json;
    }).toList();
    await _prefs.setString(_kMemories, jsonEncode(items));
    await _prefs.setString(_kMemoryEmbeddings, jsonEncode(embeddings));
  }

  Future<void> saveMemories(List<MemoryEntry> list) async {
    final embeddings = <String, List<double>>{};
    for (final e in list) {
      if (e.embedding != null) embeddings[e.id] = e.embedding!;
    }
    await _saveMemoryEntries(list, embeddings);
  }

  // 记忆原子（细粒度事实单元，含 TTL/衰减状态）
  List<MemoryAtom> loadMemoryAtoms() =>
      _loadList(_kMemoryAtoms, MemoryAtom.fromJson);
  Future<void> saveMemoryAtoms(List<MemoryAtom> list) =>
      _saveList(_kMemoryAtoms, list);

  // 反思状态：每会话已总结到的消息下标 + 失败重试区间（重启后不丢）
  Map<String, Map<String, dynamic>> loadMemoryReflectionState() {
    final raw = _prefs.getString(_kMemoryReflectionState);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMemoryReflectionState(
    Map<String, Map<String, dynamic>> state,
  ) => _prefs.setString(_kMemoryReflectionState, jsonEncode(state));

  // 维护状态：上次衰减执行日期 / 上次整理时间
  Map<String, dynamic> loadMemoryMaintenanceState() {
    final raw = _prefs.getString(_kMemoryMaintenanceState);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMemoryMaintenanceState(Map<String, dynamic> state) =>
      _prefs.setString(_kMemoryMaintenanceState, jsonEncode(state));

  // 图谱记忆（节点/边/条目的 JSON 快照）
  Map<String, dynamic>? loadMemoryGraph() {
    final raw = _prefs.getString(_kMemoryGraph);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMemoryGraph(Map<String, dynamic> json) =>
      _prefs.setString(_kMemoryGraph, jsonEncode(json));

  List<StickerItem> loadStickerItems() =>
      _loadList(_kStickerItems, StickerItem.fromJson);
  Future<void> saveStickerItems(List<StickerItem> list) =>
      _saveList(_kStickerItems, list);
  List<StickerFolder> loadStickerFolders() =>
      _loadList(_kStickerFolders, StickerFolder.fromJson);
  Future<void> saveStickerFolders(List<StickerFolder> list) =>
      _saveList(_kStickerFolders, list);
  List<StickerGroup> loadStickerGroups() =>
      _loadList(_kStickerGroups, StickerGroup.fromJson);
  Future<void> saveStickerGroups(List<StickerGroup> list) =>
      _saveList(_kStickerGroups, list);
  List<PersonaStickerBinding> loadPersonaStickerBindings() =>
      _loadList(_kPersonaStickerBindings, PersonaStickerBinding.fromJson);
  Future<void> savePersonaStickerBindings(List<PersonaStickerBinding> list) =>
      _saveList(_kPersonaStickerBindings, list);
  List<PersonaStickerSettings> loadPersonaStickerSettings() =>
      _loadList(_kPersonaStickerSettings, PersonaStickerSettings.fromJson);
  Future<void> savePersonaStickerSettings(List<PersonaStickerSettings> list) =>
      _saveList(_kPersonaStickerSettings, list);

  Future<void> clearLegacyStickerData() async {
    await Future.wait([
      _prefs.remove('stickers'),
      _prefs.remove('sticker_folders'),
      _prefs.remove('sticker_groups'),
    ]);
  }

  // 会话
  List<ChatSession> loadSessions() =>
      _loadList(_kSessions, ChatSession.fromJson);
  Future<void> saveSessions(List<ChatSession> list) =>
      _saveList(_kSessions, list);

  // 群聊
  List<GroupChat> loadGroupChats() =>
      _loadList(_kGroupChats, GroupChat.fromJson);
  Future<void> saveGroupChats(List<GroupChat> list) =>
      _saveList(_kGroupChats, list);

  // 用户资料
  UserProfile loadUserProfile() {
    final raw = _prefs.getString(_kUserProfile);
    if (raw == null) return UserProfile();
    try {
      return UserProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return UserProfile();
    }
  }

  Future<void> saveUserProfile(UserProfile profile) =>
      _prefs.setString(_kUserProfile, jsonEncode(profile.toJson()));

  // 设置
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

  bool get injectMemories => _prefs.getBool(_kInjectMemories) ?? true;
  Future<void> setInjectMemories(bool v) => _prefs.setBool(_kInjectMemories, v);

  // 私聊消息合并防抖设置
  bool get messageMergeEnabled =>
      _prefs.getBool(_kMessageMergeEnabled) ?? false;
  Future<void> setMessageMergeEnabled(bool v) =>
      _prefs.setBool(_kMessageMergeEnabled, v);
  int get messageMergeDebounce => _prefs.getInt(_kMessageMergeDebounce) ?? 3;
  Future<void> setMessageMergeDebounce(int v) =>
      _prefs.setInt(_kMessageMergeDebounce, v);
  bool get typingDebounceEnabled =>
      _prefs.getBool(_kTypingDebounceEnabled) ?? false;
  Future<void> setTypingDebounceEnabled(bool v) =>
      _prefs.setBool(_kTypingDebounceEnabled, v);

  bool get crossSessionMemories =>
      _prefs.getBool(_kCrossSessionMemories) ?? true;
  Future<void> setCrossSessionMemories(bool v) =>
      _prefs.setBool(_kCrossSessionMemories, v);

  // 记忆系统配置
  MemorySettings loadMemorySettings() {
    final raw = _prefs.getString(_kMemorySettings);
    if (raw != null) {
      try {
        return MemorySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // 迁移旧配置
    final oldCross = _prefs.getBool(_kCrossSessionMemories);
    if (oldCross != null) {
      return MemorySettings(useSessionFiltering: !oldCross);
    }
    return MemorySettings();
  }

  Future<void> saveMemorySettings(MemorySettings settings) =>
      _prefs.setString(_kMemorySettings, jsonEncode(settings.toJson()));

  /// 总结轮数默认值 10 → 20 的一次性迁移标记
  bool get summaryThresholdMigrated =>
      _prefs.getBool(_kSummaryThresholdMigrated) ?? false;
  Future<void> markSummaryThresholdMigrated() =>
      _prefs.setBool(_kSummaryThresholdMigrated, true);

  // 对话分段发送设置
  SegmentedSendSettings loadSegmentedSendSettings() {
    final raw = _prefs.getString(_kSegmentedSendSettings);
    if (raw != null) {
      try {
        return SegmentedSendSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return SegmentedSendSettings();
  }

  Future<void> saveSegmentedSendSettings(SegmentedSendSettings s) =>
      _prefs.setString(_kSegmentedSendSettings, jsonEncode(s.toJson()));

  AssistantOutputMode loadAssistantOutputMode() {
    final raw = _prefs.getString(_kAssistantOutputMode);
    if (raw != null) {
      for (final mode in AssistantOutputMode.values) {
        if (mode.name == raw) return mode;
      }
    }

    final legacyStream = _prefs.getBool(_kStreamOutputEnabled);
    final legacySegmented = loadSegmentedSendSettings().enabled;
    if (legacyStream == true) return AssistantOutputMode.streaming;
    if (legacySegmented) return AssistantOutputMode.segmented;
    if (legacyStream == false) return AssistantOutputMode.complete;
    return AssistantOutputMode.streaming;
  }

  Future<void> setAssistantOutputMode(AssistantOutputMode mode) =>
      _prefs.setString(_kAssistantOutputMode, mode.name);

  // 流式输出开关（与分段发送互斥）
  bool get streamOutputEnabled => _prefs.getBool(_kStreamOutputEnabled) ?? true;
  Future<void> setStreamOutputEnabled(bool v) =>
      _prefs.setBool(_kStreamOutputEnabled, v);

  // 提示词注入设置（设置-提示词-提示词注入）
  PromptInjectionSettings loadPromptInjectionSettings() {
    final raw = _prefs.getString(_kPromptInjectionSettings);
    if (raw == null) return PromptInjectionSettings();
    try {
      return PromptInjectionSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return PromptInjectionSettings();
    }
  }

  Future<void> savePromptInjectionSettings(PromptInjectionSettings s) =>
      _prefs.setString(_kPromptInjectionSettings, jsonEncode(s.toJson()));

  // 世界书（设置-提示词-世界书）
  WorldBookSettings loadWorldBookSettings() {
    final raw = _prefs.getString(_kWorldBookSettings);
    if (raw == null) return WorldBookSettings();
    try {
      return WorldBookSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return WorldBookSettings();
    }
  }

  Future<void> saveWorldBookSettings(WorldBookSettings s) =>
      _prefs.setString(_kWorldBookSettings, jsonEncode(s.toJson()));

  // 生成文本风格参数合集
  GenerationStyleSettings loadGenerationStyleSettings() {
    final raw = _prefs.getString(_kGenerationStyleSettings);
    if (raw == null) return GenerationStyleSettings();
    try {
      return GenerationStyleSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return GenerationStyleSettings();
    }
  }

  Future<void> saveGenerationStyleSettings(GenerationStyleSettings s) =>
      _prefs.setString(_kGenerationStyleSettings, jsonEncode(s.toJson()));

  StickerSendMode get stickerSendMode {
    final rawMode = _prefs.getString(_kStickerSendMode);
    if (rawMode != null) {
      for (final mode in StickerSendMode.values) {
        if (mode.name == rawMode) return mode;
      }
    }
    return stickerSendModeFromLegacyProbability(
      _prefs.getInt(_kStickerSendProbability) ?? 10,
    );
  }

  Future<void> setStickerSendMode(StickerSendMode mode) async {
    await Future.wait<void>([
      _prefs.setString(_kStickerSendMode, mode.name),
      // Keep this value for older builds that do not know about sendMode.
      _prefs.setInt(_kStickerSendProbability, mode.gateProbability),
    ]);
  }

  int get stickerSendProbability => stickerSendMode.gateProbability;

  Future<void> setStickerSendProbability(int value) =>
      setStickerSendMode(stickerSendModeFromLegacyProbability(value));

  // Token 使用统计
  TokenUsage loadTokenUsage() {
    final raw = _prefs.getString(_kTokenUsage);
    if (raw != null) {
      try {
        return TokenUsage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return TokenUsage();
  }

  Future<void> saveTokenUsage(TokenUsage usage) =>
      _prefs.setString(_kTokenUsage, jsonEncode(usage.toJson()));

  // Token 按天使用记录
  List<DailyTokenUsage> loadTokenDailyRecords() {
    final raw = _prefs.getString(_kTokenDailyUsage);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((d) => DailyTokenUsage.fromJson(d as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> saveTokenDailyRecords(List<DailyTokenUsage> records) =>
      _prefs.setString(
        _kTokenDailyUsage,
        jsonEncode(records.map((d) => d.toJson()).toList()),
      );

  // 应用启动次数
  int get appLaunchCount => _prefs.getInt(_kAppLaunchCount) ?? 0;
  Future<void> setAppLaunchCount(int count) =>
      _prefs.setInt(_kAppLaunchCount, count);
}
