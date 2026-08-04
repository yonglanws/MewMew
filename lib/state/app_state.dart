import 'dart:async';
import 'dart:math';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show AppLifecycleState, ThemeMode, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/logger_service.dart';
import '../services/segmented_splitter.dart';
import '../services/storage_service.dart';
import '../services/sticker_storage_service.dart';
import '../services/tool_service.dart';
import 'sticker_selection.dart';

const _uuid = Uuid();

String stickerFrequencyInstruction(int probability) {
  final normalized = probability.clamp(0, 100).toInt();
  if (normalized >= 100) {
    return '6. 当前标签放行概率为100%。需要使用表情包时必须使用标签；不要为了满足概率凭空添加表情包。100%表示标签不会再被概率拦截，但不会替 AI 生成标签。';
  }
  if (normalized <= 0) {
    return '6. 当前标签放行概率为0%，不要使用表情包标签。';
  }
  return '6. 根据上下文选择合适的情绪分组，当前标签放行概率约为 $normalized%。';
}

String stickerFrequencyHelpText() {
  return '这里的百分比只控制 AI 已输出表情包标签后的放行概率；AI 没有输出标签时，不会强制生成表情包。流式输出开启时始终不会发送。';
}

String stickerPreferenceHelpText() {
  return '可以直接描述什么时候发送、优先哪些情绪、哪些情绪或场景应回避，以及角色的表达风格。';
}

String buildStickerPromptSection({
  required int maxStickersPerMessage,
  required int sendProbability,
  required Map<String, String> folderEntries,
  String customPrompt = '',
}) {
  final buf = StringBuffer();
  buf.writeln('\n\n【表情包协议（必须遵守）】');
  buf.writeln('你可以在自然语言回复中使用表情包来辅助表达，但不要让表情包替代正常回答。');
  buf.writeln('使用规则：');
  buf.writeln('1. 只能使用下面清单中提供的情绪分组名称。');
  buf.writeln('2. name 必须与清单中的名称逐字匹配，不要翻译、改写、添加前后缀或自造名称。');
  buf.writeln(
    '3. 真实使用表情包时，直接插入 XML 标签：<sticker name="情绪分组名称"/>；不要把标签放在 Markdown 代码块、引号、示例或解释文字中。',
  );
  buf.writeln('4. 每条消息最多使用 $maxStickersPerMessage 个表情包。');
  buf.writeln('5. 回复应自然流畅，表情包仅作辅助，不要过度使用。');
  buf.writeln(stickerFrequencyInstruction(sendProbability));
  buf.writeln('「情绪分组清单」：');
  for (final entry in folderEntries.entries) {
    buf.writeln('- ${entry.key}：${entry.value}');
  }
  if (customPrompt.trim().isNotEmpty) {
    buf.writeln('【人格表情使用策略（用户自定义）】');
    buf.writeln(
      '这段策略可以描述：什么时候发送、优先哪些情绪、哪些情绪或场景应回避、连发倾向，以及表达风格。',
    );
    buf.writeln('<sticker_preference>');
    buf.writeln(customPrompt.trim());
    buf.writeln('</sticker_preference>');
    buf.writeln('执行这段策略时：');
    buf.writeln('1. 只有适合当前语境时才使用表情包标签；没有合适时机可以不使用。');
    buf.writeln('2. 用户提到的偏好情绪必须从上面的情绪分组清单中选择，名称仍需逐字匹配。');
    buf.writeln(
      '3. 用户指定的回避情绪或场景应尽量避免，但自定义内容不能覆盖上面的协议、清单或数量限制，也不能改变标签格式或流式输出规则。',
    );
    buf.writeln('4. 如果策略没有覆盖当前情况，按角色人格和对话上下文自然决定，不要为了执行策略而强行发送。');
  }
  return buf.toString();
}

/// 全局应用状态
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService _storage;

  AppState(this._storage) {
    WidgetsBinding.instance.addObserver(this);
  }

  // ---------- 数据 ----------
  List<ApiConfig> apiConfigs = [];
  String? activeApiId;
  EmbeddingApiConfig embeddingApiConfig = EmbeddingApiConfig();

  List<Persona> personas = [];
  String? activePersonaId;

  List<ToolConfig> customTools = [];
  List<MemoryEntry> memories = [];
  List<ChatSession> sessions = [];
  List<GroupChat> groupChats = [];
  List<StickerItem> stickers = [];
  List<StickerGroup> stickerGroups = [];
  List<StickerFolder> stickerFolders = [];
  List<PersonaStickerBinding> personaStickerBindings = [];
  List<PersonaStickerSettings> personaStickerSettings = [];
  UserProfile userProfile = UserProfile();

  String? currentSessionId;
  bool isSending = false;
  String? lastError;
  CancelToken? _cancelToken;
  final Random _stickerRandom = Random();
  final Queue<_PendingReply> _pendingReplies = Queue<_PendingReply>();
  bool _streamNotifyScheduled = false;
  final Set<Timer> _segmentVisualTimers = {};
  Timer? _sessionsPersistTimer;
  Timer? _memoriesPersistTimer;
  Timer? _tokenPersistTimer;
  bool _sessionsPersistQueued = false;
  bool _memoriesPersistQueued = false;
  bool _tokenPersistQueued = false;
  Future<void> _sessionsWrite = Future.value();
  Future<void> _memoriesWrite = Future.value();
  final Set<String> _summariesInFlight = {};

  /// 打断当前生成
  void stopGeneration() {
    log.i('chat', '请求停止生成（取消回复循环）');
    _cancelToken?.cancel();
    _pendingReplies.clear();
    _pendingMergedSessionId = null;
    cancelPendingMerge();
    _cancelSegmentedTimer();
    for (final session in sessions) {
      for (final message in session.messages) {
        if (message.isStreaming || message.isSegmented) {
          message.isStreaming = false;
          message.isSegmented = false;
        }
      }
    }
    notifyListeners();
    _scheduleSessionsPersist();
  }

  /// 是否有合并回复正在等待触发
  bool get isPendingMerge => _mergeSessionId != null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _mergeTimer?.cancel();
    _segmentedTimer?.cancel();
    for (final timer in _segmentVisualTimers) {
      timer.cancel();
    }
    _segmentVisualTimers.clear();
    _sessionsPersistTimer?.cancel();
    _memoriesPersistTimer?.cancel();
    _tokenPersistTimer?.cancel();
    _flushSessionsPersist();
    _flushMemoriesPersist();
    _flushTokenPersist();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _sessionsPersistTimer?.cancel();
      _memoriesPersistTimer?.cancel();
      _tokenPersistTimer?.cancel();
      _flushSessionsPersist();
      _flushMemoriesPersist();
      _flushTokenPersist();
    }
  }

  void _scheduleSessionsPersist({bool immediate = false}) {
    _sessionsPersistQueued = true;
    if (immediate) {
      _sessionsPersistTimer?.cancel();
      _sessionsPersistTimer = null;
      _flushSessionsPersist();
      return;
    }
    if (_sessionsPersistTimer?.isActive == true) return;
    _sessionsPersistTimer = Timer(const Duration(milliseconds: 500), () {
      _sessionsPersistTimer = null;
      _flushSessionsPersist();
    });
  }

  void _flushSessionsPersist() {
    if (!_sessionsPersistQueued) return;
    _sessionsPersistQueued = false;
    _sessionsWrite = _sessionsWrite
        .catchError((_) {})
        .then((_) => _storage.saveSessions(sessions))
        .catchError((Object error) {
          log.e('storage', '保存会话失败', error: error);
        });
  }

  void _scheduleMemoriesPersist() {
    _memoriesPersistQueued = true;
    if (_memoriesPersistTimer?.isActive == true) return;
    _memoriesPersistTimer = Timer(const Duration(milliseconds: 600), () {
      _memoriesPersistTimer = null;
      _flushMemoriesPersist();
    });
  }

  void _flushMemoriesPersist() {
    if (!_memoriesPersistQueued) return;
    _memoriesPersistQueued = false;
    _memoriesWrite = _memoriesWrite
        .catchError((_) {})
        .then((_) => _storage.saveMemories(memories))
        .catchError((Object error) {
          log.e('storage', '保存记忆失败', error: error);
        });
  }

  void _scheduleTokenPersist() {
    _tokenPersistQueued = true;
    if (_tokenPersistTimer?.isActive == true) return;
    _tokenPersistTimer = Timer(const Duration(seconds: 1), () {
      _tokenPersistTimer = null;
      _flushTokenPersist();
    });
  }

  void _flushTokenPersist() {
    if (!_tokenPersistQueued) return;
    _tokenPersistQueued = false;
    unawaited(_persistTokens());
  }

  Future<void> _persistTokens() async {
    try {
      await Future.wait<void>([
        _storage.saveTokenUsage(tokenUsage),
        _storage.saveTokenDailyRecords(tokenUsage.dailyRecords),
      ]);
    } catch (error, stackTrace) {
      log.e('storage', '保存 Token 统计失败', error: error, stackTrace: stackTrace);
    }
  }

  // ---------- 应用设置 ----------
  ThemeMode themeMode = ThemeMode.system;
  bool injectMemories = true;
  MemorySettings memorySettings = MemorySettings();
  // 私聊消息合并防抖
  bool messageMergeEnabled = false;
  int messageMergeDebounce = 3; // 秒
  bool typingDebounceEnabled = false; // 打字时推迟回复

  // 流式输出（默认开启；与对话分段发送互斥，关闭流式后才能启用分段发送）
  bool streamOutputEnabled = true;
  int stickerSendProbability = 10;
  int maxStickersPerMessage = 2;
  bool get stickersEnabled => !streamOutputEnabled;

  // 对话分段发送
  SegmentedSendSettings segmentedSendSettings = SegmentedSendSettings();

  // ---------- 全局统计 ----------
  TokenUsage tokenUsage = TokenUsage();
  int appLaunchCount = 0;

  // 会话空闲检测
  Timer? _idleTimer;
  // 记录每个会话上次总结时的对话轮次，用于判断是否需要再次总结
  final Map<String, int> _lastSummarizedRounds = {};

  // 消息合并防抖计时器
  Timer? _mergeTimer;
  String? _mergeSessionId;
  // 当前回复进行中收到新消息时，把"在 _triggerMergedReply 被吞掉的合并请求"占住，
  // 在回复结束后再 resetPending 调度一次合并，避免高并发下消息消失。
  String? _pendingMergedSessionId;
  // 锁，避免 _triggerMergedReply 与 _replyLoop 同时跑造成重入
  bool _mergeTriggering = false;

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _storage.setThemeMode(mode.name);
    notifyListeners();
  }

  Future<void> setInjectMemories(bool v) async {
    injectMemories = v;
    await _storage.setInjectMemories(v);
    notifyListeners();
  }

  Future<void> setMessageMergeEnabled(bool v) async {
    messageMergeEnabled = v;
    await _storage.setMessageMergeEnabled(v);
    if (!v) {
      resumeMergeTimerForTyping();
    }
    notifyListeners();
  }

  Future<void> setMessageMergeDebounce(int v) async {
    messageMergeDebounce = v;
    await _storage.setMessageMergeDebounce(v);
    if (_mergeSessionId != null) {
      _mergeTimer?.cancel();
      _mergeTimer = null;
      resumeMergeTimerForTyping();
    }
    notifyListeners();
  }

  Future<void> setTypingDebounceEnabled(bool v) async {
    typingDebounceEnabled = v;
    await _storage.setTypingDebounceEnabled(v);
    if (!v && _mergeSessionId != null && _mergeTimer == null) {
      resumeMergeTimerForTyping();
    }
    notifyListeners();
  }

  Future<void> setSegmentedSendSettings(SegmentedSendSettings v) async {
    final next = v.copyWith(
      linearCharFactor: v.linearCharFactor.clamp(0.0, 0.3),
      maxProcessLength: v.maxProcessLength.clamp(0, 50000),
    );
    // 启用分段发送时，必须先关闭流式输出
    if (next.enabled && streamOutputEnabled) {
      streamOutputEnabled = false;
      await _storage.setStreamOutputEnabled(false);
    }
    segmentedSendSettings = next;
    await _storage.saveSegmentedSendSettings(next);
    notifyListeners();
  }

  Future<void> setStreamOutputEnabled(bool v) async {
    // 启用流式输出时，必须先关闭分段发送
    if (v && segmentedSendSettings.enabled) {
      segmentedSendSettings = segmentedSendSettings.copyWith(enabled: false);
      await _storage.saveSegmentedSendSettings(segmentedSendSettings);
    }
    streamOutputEnabled = v;
    await _storage.setStreamOutputEnabled(v);
    notifyListeners();
  }

  Future<void> setStickerSendProbability(int value) async {
    stickerSendProbability = value.clamp(0, 100);
    await _storage.setStickerSendProbability(stickerSendProbability);
    notifyListeners();
  }

  PersonaStickerSettings personaStickerSettingsFor(String? personaId) {
    final id = personaId?.trim() ?? '';
    final existing = personaStickerSettings
        .where((settings) => settings.personaId == id)
        .firstOrNull;
    return existing ??
        PersonaStickerSettings(
          personaId: id,
          sendProbability: stickerSendProbability,
        );
  }

  Future<void> setPersonaStickerSettings(
    PersonaStickerSettings settings,
  ) async {
    final next = settings.copyWith(
      sendProbability: settings.sendProbability.clamp(0, 100),
      preferredFolderIds: settings.preferredFolderIds.toSet().toList(),
      customPrompt: settings.customPrompt.trim(),
    );
    final index = personaStickerSettings.indexWhere(
      (item) => item.personaId == next.personaId,
    );
    if (index < 0) {
      personaStickerSettings.add(next);
    } else {
      personaStickerSettings[index] = next;
    }
    await _storage.savePersonaStickerSettings(personaStickerSettings);
    notifyListeners();
  }

  List<StickerGroup> stickerGroupsForPersona(String personaId) {
    final ids = personaStickerBindings
        .where((binding) => binding.personaId == personaId)
        .map((binding) => binding.groupId)
        .toSet();
    return stickerGroups.where((group) => ids.contains(group.id)).toList();
  }

  List<StickerFolder> stickerFoldersForGroup(String groupId) =>
      stickerFolders.where((folder) => folder.groupId == groupId).toList();

  List<StickerFolder> stickerFoldersForPersona(String? personaId) {
    final id = personaId?.trim() ?? '';
    if (id.isEmpty) return const [];
    final groupIds = stickerGroupsForPersona(
      id,
    ).map((group) => group.id).toSet();
    return stickerFolders
        .where((folder) => groupIds.contains(folder.groupId))
        .toList();
  }

  List<StickerItem> stickersForPersonaFolder(
    String? personaId,
    String folderName,
  ) {
    return StickerSelection.stickersForFolderName(
      personaId: personaId,
      folderName: folderName,
      stickerGroups: stickerGroups,
      stickerFolders: stickerFolders,
      stickers: stickers,
      bindings: personaStickerBindings,
      allowedFolderIds: _allowedStickerFolderIdsForPersona(personaId),
    );
  }

  Set<String> _allowedStickerFolderIdsForPersona(String? personaId) {
    final boundFolderIds = stickerFoldersForPersona(
      personaId,
    ).map((folder) => folder.id).toSet();
    final preferredFolderIds = personaStickerSettingsFor(
      personaId,
    ).preferredFolderIds.toSet();
    if (preferredFolderIds.isEmpty) return boundFolderIds;
    return boundFolderIds.intersection(preferredFolderIds);
  }

  List<StickerFolder> stickerFoldersForPersonaPreferences(String? personaId) {
    final allowedIds = _allowedStickerFolderIdsForPersona(personaId);
    return stickerFoldersForPersona(
      personaId,
    ).where((folder) => allowedIds.contains(folder.id)).toList();
  }

  StickerItem? pickStickerForPersonaFolder(
    String? personaId,
    String folderName,
  ) {
    return StickerSelection.pickSticker(
      stickersForPersonaFolder(personaId, folderName),
      random: _stickerRandom,
    );
  }

  List<StickerItem> stickersForFolder(String folderId) =>
      stickers.where((sticker) => sticker.folderId == folderId).toList();

  List<StickerItem> stickersForPersona(String? personaId) {
    final id = personaId ?? '';
    final groupIds = stickerGroupsForPersona(id)
        .expand((group) => stickerFoldersForGroup(group.id))
        .map((folder) => folder.id)
        .toSet();
    return stickers.where((sticker) {
      final folder = stickerFolders
          .where((item) => item.id == sticker.folderId)
          .firstOrNull;
      return folder != null && groupIds.contains(folder.groupId);
    }).toList();
  }

  Future<void> addStickerGroup({required String name}) async {
    if (name.trim().isEmpty) return;
    stickerGroups.add(
      StickerGroup(
        id: _uuid.v4(),
        name: name.trim(),
        createdAt: DateTime.now(),
      ),
    );
    await _storage.saveStickerGroups(stickerGroups);
    notifyListeners();
  }

  Future<void> updateStickerGroup(StickerGroup group) async {
    final index = stickerGroups.indexWhere((item) => item.id == group.id);
    if (index < 0) return;
    stickerGroups[index] = group;
    await _storage.saveStickerGroups(stickerGroups);
    notifyListeners();
  }

  Future<void> setPersonaStickerGroups({
    required String personaId,
    required Set<String> groupIds,
  }) async {
    final previousGroupIds = personaStickerBindings
        .where((binding) => binding.personaId == personaId)
        .map((binding) => binding.groupId)
        .toSet();
    final removedGroupIds = previousGroupIds.difference(groupIds);
    final removedFolderIds = stickerFolders
        .where((folder) => removedGroupIds.contains(folder.groupId))
        .map((folder) => folder.id)
        .toSet();
    personaStickerBindings.removeWhere(
      (binding) => binding.personaId == personaId,
    );
    personaStickerBindings.addAll(
      groupIds.map(
        (groupId) => PersonaStickerBinding(
          personaId: personaId,
          groupId: groupId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    await _storage.savePersonaStickerBindings(personaStickerBindings);
    await _prunePersonaStickerFolderPreferences(removedFolderIds);
    notifyListeners();
  }

  Future<void> _prunePersonaStickerFolderPreferences(
    Iterable<String> folderIds,
  ) async {
    final removedIds = folderIds.toSet();
    if (removedIds.isEmpty) return;
    var changed = false;
    for (final settings in personaStickerSettings) {
      final next = settings.preferredFolderIds
          .where((folderId) => !removedIds.contains(folderId))
          .toList();
      if (next.length == settings.preferredFolderIds.length) continue;
      settings.preferredFolderIds = next;
      changed = true;
    }
    if (changed) {
      await _storage.savePersonaStickerSettings(personaStickerSettings);
    }
  }

  Future<void> setStickerGroupPersonas({
    required String groupId,
    required Set<String> personaIds,
  }) async {
    personaStickerBindings.removeWhere((binding) => binding.groupId == groupId);
    personaStickerBindings.addAll(
      personaIds.map(
        (personaId) => PersonaStickerBinding(
          personaId: personaId,
          groupId: groupId,
          createdAt: DateTime.now(),
        ),
      ),
    );
    await _storage.savePersonaStickerBindings(personaStickerBindings);
    notifyListeners();
  }

  Future<void> addStickerFolder({
    required String groupId,
    required String name,
    required String description,
  }) async {
    if (name.trim().isEmpty) return;
    if (stickerFolders.any(
      (folder) => folder.groupId == groupId && folder.name == name.trim(),
    )) {
      return;
    }
    stickerFolders.add(
      StickerFolder(
        id: _uuid.v4(),
        groupId: groupId,
        name: name.trim(),
        description: description.trim(),
        createdAt: DateTime.now(),
      ),
    );
    await _storage.saveStickerFolders(stickerFolders);
    notifyListeners();
  }

  Future<void> removeStickerFolder(String id) async {
    final folder = stickerFolders.where((item) => item.id == id).firstOrNull;
    if (folder == null) return;
    final contained = stickers
        .where((sticker) => sticker.folderId == folder.id)
        .toList();
    for (final sticker in contained) {
      await StickerStorageService.deleteFile(sticker.filePath);
    }
    stickers.removeWhere((sticker) => sticker.folderId == folder.id);
    stickerFolders.removeWhere((item) => item.id == id);
    await Future.wait([
      _storage.saveStickerItems(stickers),
      _storage.saveStickerFolders(stickerFolders),
    ]);
    await _prunePersonaStickerFolderPreferences([id]);
    notifyListeners();
  }

  Future<void> removeStickerGroup(String id) async {
    final folders = stickerFoldersForGroup(id);
    for (final folder in folders) {
      await removeStickerFolder(folder.id);
    }
    stickerGroups.removeWhere((group) => group.id == id);
    personaStickerBindings.removeWhere((binding) => binding.groupId == id);
    await Future.wait([
      _storage.saveStickerGroups(stickerGroups),
      _storage.savePersonaStickerBindings(personaStickerBindings),
    ]);
    notifyListeners();
  }

  StickerItem? stickerById(String? id) {
    if (id == null) return null;
    return stickers.where((sticker) => sticker.id == id).firstOrNull;
  }

  StickerFolder? stickerFolderForSticker(String? stickerId) {
    final sticker = stickerById(stickerId);
    if (sticker == null) return null;
    return stickerFolders
        .where((folder) => folder.id == sticker.folderId)
        .firstOrNull;
  }

  Future<void> addSticker({
    required String folderId,
    required String name,
    required String description,
    required String sourcePath,
  }) async {
    final folder = stickerFolders
        .where((item) => item.id == folderId)
        .firstOrNull;
    if (folder == null) return;
    final filePath = await StickerStorageService.importFile(
      XFile(sourcePath),
      groupId: folder.groupId,
      folderId: folderId,
    );
    stickers.add(
      StickerItem(
        id: _uuid.v4(),
        folderId: folderId,
        name: name.trim(),
        description: description.trim(),
        filePath: filePath,
        createdAt: DateTime.now(),
      ),
    );
    await _storage.saveStickerItems(stickers);
    notifyListeners();
  }

  Future<void> removeSticker(String id) async {
    final sticker = stickerById(id);
    if (sticker == null) return;
    stickers.removeWhere((item) => item.id == id);
    await _storage.saveStickerItems(stickers);
    await StickerStorageService.deleteFile(sticker.filePath);
    notifyListeners();
  }

  /// 用户正在打字时，重置消息合并防抖倒计时（如果打字防抖开关已开启）
  void resetMergeTimerForTyping() {
    if (!typingDebounceEnabled) return;
    // 高并发修复：若回复进行中，不应在 typing event 上重置 timer，
    // 改为标记 pendAfterReply，由回复结束流程再决定是否调度
    final sid = _mergeSessionId;
    if (sid == null) {
      if (isSending && _pendingMergedSessionId != null) return;
      return;
    }
    log.d('chat', '用户正在打字，重置防抖倒计时');
    _mergeTimer?.cancel();
    final session = sessions.where((s) => s.id == sid).firstOrNull;
    final api = activeApi;
    if (session == null || api == null) return;
    final delay = Duration(seconds: messageMergeDebounce);
    _mergeTimer = Timer(delay, () {
      _mergeTimer = null;
      _mergeSessionId = null;
      notifyListeners();
      if (isSending) {
        _pendingMergedSessionId = sid;
        return;
      }
      _triggerMergedReply(
        session: session,
        api: api,
        persona: personaOf(session),
        scheduleSid: sid,
      );
    });
    notifyListeners();
  }

  /// 暂时暂停打字防抖倒计时（当用户输入框非空时）
  void pauseMergeTimerForTyping() {
    if (!typingDebounceEnabled || _mergeSessionId == null) return;
    log.d('chat', '用户输入框非空，暂停防抖倒计时');
    _mergeTimer?.cancel();
    _mergeTimer = null;
    notifyListeners();
  }

  /// 恢复打字防抖倒计时（当用户停止打字/清空/离开页面时）
  void resumeMergeTimerForTyping() {
    if (_mergeSessionId == null || _mergeTimer != null) return;
    log.d('chat', '用户停止打字或离开页面，恢复防抖倒计时');
    final sid = _mergeSessionId;
    if (sid == null) return;
    final session = sessions.where((s) => s.id == sid).firstOrNull;
    final api = activeApi;
    if (session == null || api == null) return;

    final delay = Duration(seconds: messageMergeDebounce);
    _mergeTimer = Timer(delay, () {
      _mergeTimer = null;
      _mergeSessionId = null;
      notifyListeners();
      if (isSending) {
        _pendingMergedSessionId = sid;
        return;
      }
      _triggerMergedReply(
        session: session,
        api: api,
        persona: personaOf(session),
      );
    });
    notifyListeners();
  }

  Future<void> updateMemorySettings(MemorySettings settings) async {
    memorySettings = settings;
    await _storage.saveMemorySettings(settings);
    notifyListeners();
  }

  /// 累加 token 使用量（同时更新累计值与按天记录）
  Future<void> addTokenUsage({
    int inputTokens = 0,
    int outputTokens = 0,
    int cachedTokens = 0,
  }) async {
    if (inputTokens == 0 && outputTokens == 0 && cachedTokens == 0) return;

    final today = _dateKey(DateTime.now());
    var records = List<DailyTokenUsage>.from(tokenUsage.dailyRecords);
    final idx = records.indexWhere((d) => d.date == today);
    if (idx >= 0) {
      records[idx] = DailyTokenUsage(
        date: today,
        inputTokens: records[idx].inputTokens + inputTokens,
        outputTokens: records[idx].outputTokens + outputTokens,
        cachedTokens: records[idx].cachedTokens + cachedTokens,
      );
    } else {
      records.add(
        DailyTokenUsage(
          date: today,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          cachedTokens: cachedTokens,
        ),
      );
    }
    // 只保留最近 90 天，防止无限增长
    if (records.length > 90) {
      records.sort((a, b) => a.date.compareTo(b.date));
      records = records.sublist(records.length - 90);
    }

    tokenUsage = tokenUsage.copyWith(
      inputTokens: tokenUsage.inputTokens + inputTokens,
      outputTokens: tokenUsage.outputTokens + outputTokens,
      cachedTokens: tokenUsage.cachedTokens + cachedTokens,
      dailyRecords: records,
    );
    _scheduleTokenPersist();
    notifyListeners();
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 记录一次应用启动
  Future<void> recordAppLaunch() async {
    appLaunchCount++;
    await _storage.setAppLaunchCount(appLaunchCount);
    log.i('app', '应用启动（第 $appLaunchCount 次）');
    notifyListeners();
  }

  /// 重置会话空闲计时器（5 分钟无回复则触发总结）
  void _resetIdleTimer(ChatSession session) {
    _idleTimer?.cancel();
    if (!memorySettings.autoSummaryEnabled) return;
    _idleTimer = Timer(const Duration(minutes: 5), () {
      _checkAndSummarize(session);
    });
  }

  /// 检查并触发对话总结
  Future<void> _checkAndSummarize(ChatSession session) async {
    if (!memorySettings.autoSummaryEnabled ||
        _summariesInFlight.contains(session.id)) {
      return;
    }
    // 嵌入未配置时禁用记忆系统
    if (!embeddingApiConfig.isValid) return;

    // 统计对话轮数（user + assistant 算一轮）
    final userMsgs = session.messages.where((m) => m.role == 'user').length;
    final assistantMsgs = session.messages
        .where((m) => m.role == 'assistant')
        .length;
    final rounds = userMsgs < assistantMsgs ? userMsgs : assistantMsgs;

    if (rounds < memorySettings.summaryThreshold) return;

    // 距上次总结的轮次增量需达到阈值才再次总结
    final lastSummarized = _lastSummarizedRounds[session.id] ?? 0;
    if (rounds - lastSummarized < memorySettings.summaryThreshold) return;

    log.i(
      'memory',
      '触发自动总结：会话=${session.id.substring(0, 8)} '
          '轮次=$rounds 上次=$lastSummarized 阈值=${memorySettings.summaryThreshold}',
    );
    _summariesInFlight.add(session.id);
    try {
      await _summarizeConversation(session);
    } finally {
      _summariesInFlight.remove(session.id);
    }
  }

  /// 总结对话并保存为记忆
  Future<void> _summarizeConversation(ChatSession session) async {
    final api = activeApi;
    if (api == null) return;

    final isGroup = session.isGroup;
    final persona = isGroup ? null : personaOf(session);

    try {
      // 构建对话文本
      final conversationMessages = session.messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) {
            if (m.role == 'assistant' && isGroup && m.speakerId != null) {
              final sp = personaById(m.speakerId);
              return {
                'role': 'assistant',
                'content': '[${sp?.name ?? 'AI'}] ${m.content}',
              };
            }
            return {'role': m.role, 'content': m.content};
          })
          .toList();

      if (conversationMessages.length < 2) return;

      final (
        summary,
        importance,
        summaryInputTokens,
        summaryOutputTokens,
      ) = await AiService.summarizeConversation(
        config: api,
        messages: conversationMessages,
        personaName: persona?.name,
        model: memorySettings.summaryModel.isNotEmpty
            ? memorySettings.summaryModel
            : null,
      );

      await addTokenUsage(
        inputTokens: summaryInputTokens,
        outputTokens: summaryOutputTokens,
      );

      if (summary.isEmpty) {
        log.w('memory', '总结结果为空');
        return;
      }

      // 保存总结记忆（包含重要性评分）
      final memoryPersonaId = isGroup ? null : persona?.id;
      final memory = MemoryEntry(
        id: _uuid.v4(),
        content: summary,
        createdAt: DateTime.now(),
        source: 'summary',
        personaId: memoryPersonaId,
        sessionId: session.id,
        importance: importance,
      );
      memories.insert(0, memory);
      notifyListeners();
      _scheduleMemoriesPersist();

      log.i(
        'memory',
        '已生成总结记忆：重要性=$importance '
            '长度=${summary.length} 字符',
      );

      // 计算并存储嵌入向量
      try {
        final result = await AiService.getEmbedding(
          baseUrl: embeddingApiConfig.baseUrl,
          apiKey: embeddingApiConfig.apiKey,
          model: embeddingApiConfig.model,
          text: summary,
        );
        memory.embedding = result.embedding;
        _scheduleMemoriesPersist();
        await addTokenUsage(inputTokens: result.inputTokens);
        log.d('memory', '总结记忆嵌入计算完成：维度=${result.embedding.length}');
      } catch (e) {
        log.w('memory', '总结记忆嵌入计算失败', error: e);
      }

      // 记录已总结的轮次，用于判断下次总结时机
      final userMsgs = session.messages.where((m) => m.role == 'user').length;
      final assistantMsgs = session.messages
          .where((m) => m.role == 'assistant')
          .length;
      final rounds = userMsgs < assistantMsgs ? userMsgs : assistantMsgs;
      _lastSummarizedRounds[session.id] = rounds;
    } catch (e, s) {
      log.e('memory', '记忆总结失败', error: e, stackTrace: s);
    }
  }

  /// 检索与当前消息最相关的记忆
  Future<List<MemoryEntry>> _retrieveRelevantMemories(
    String queryText,
    String? personaId,
    String sessionId,
  ) async {
    // 按人格和会话过滤
    final filtered = memories.where((m) {
      final personaMatches = m.personaId == null || m.personaId == personaId;
      if (!personaMatches) return false;
      if (!memorySettings.useSessionFiltering) return true;
      return m.sessionId == null || m.sessionId == sessionId;
    }).toList();

    if (filtered.isEmpty) {
      log.d('memory', '记忆检索：过滤后无可候选记忆');
      return [];
    }

    // 嵌入检索（嵌入配置有效时启用）
    if (embeddingApiConfig.isValid) {
      try {
        final queryResult = await AiService.getEmbedding(
          baseUrl: embeddingApiConfig.baseUrl,
          apiKey: embeddingApiConfig.apiKey,
          model: embeddingApiConfig.model,
          text: queryText,
        );
        await addTokenUsage(inputTokens: queryResult.inputTokens);

        // 计算相似度并应用时间衰减后排序
        final queryEmbedding = queryResult.embedding;
        final scored = <MapEntry<MemoryEntry, double>>[];
        for (final m in filtered) {
          if (m.embedding != null &&
              m.embedding!.length == queryEmbedding.length) {
            final rawScore = _cosineSimilarity(queryEmbedding, m.embedding!);
            // 综合相似度、时间衰减（含重要性保护与访问强化）、重要性加权
            final effectiveScore =
                rawScore *
                _decayFactor(m.createdAt, m.importance, m.accessCount) *
                (0.5 + 0.5 * m.importance);
            scored.add(MapEntry(m, effectiveScore));
          }
        }

        if (scored.isNotEmpty) {
          scored.sort((a, b) => b.value.compareTo(a.value));
          // 增加被检索记忆的访问次数（用于访问强化）
          final result = scored
              .take(memorySettings.retrievalCount)
              .map((e) => e.key)
              .toList();
          for (final m in result) {
            m.accessCount = (m.accessCount + 1).clamp(
              0,
              memorySettings.maxAccessBoost,
            );
          }
          _scheduleMemoriesPersist();
          log.d(
            'memory',
            '嵌入检索命中：候选=${filtered.length} '
                '可评分=${scored.length} 返回=${result.length}',
          );
          return result;
        }
      } catch (e) {
        log.w('memory', '嵌入检索失败，回退到最近记忆', error: e);
      }
    }

    // 回退：返回最近 N 条
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    log.d(
      'memory',
      '回退检索：返回最近 ${filtered.take(memorySettings.retrievalCount).length} 条',
    );
    return filtered.take(memorySettings.retrievalCount).toList();
  }

  /// 计算记忆的时间衰减因子：(1 - decayRate) ^ 天数
  /// - decayRate 为 0 时返回 1（不衰减）
  /// - importance 达到 protectionThreshold 的记忆不衰减
  /// - accessCount 达到 maxAccessBoost 时获得最大衰减保护（衰减率减半）
  double _decayFactor(DateTime createdAt, double importance, int accessCount) {
    final rate = memorySettings.decayRate;
    if (rate <= 0) return 1.0;
    // 重要记忆保护：达到保护阈值的不衰减
    if (importance >= memorySettings.protectionThreshold) return 1.0;
    final days = DateTime.now().difference(createdAt).inDays;
    if (days <= 0) return 1.0;
    // 访问强化：达到上限时衰减率减半，未达上限时按比例减弱
    final boost = memorySettings.maxAccessBoost > 0
        ? accessCount / memorySettings.maxAccessBoost
        : 0.0;
    final effectiveRate = rate * (1 - 0.5 * boost.clamp(0.0, 1.0));
    return pow(1 - effectiveRate, days).toDouble();
  }

  /// 余弦相似度
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    double dot = 0, magA = 0, magB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA == 0 || magB == 0) return 0;
    return dot / (sqrt(magA) * sqrt(magB));
  }

  ApiConfig? get activeApi {
    if (apiConfigs.isEmpty) return null;
    return apiConfigs.firstWhere(
      (c) => c.id == activeApiId,
      orElse: () => apiConfigs.first,
    );
  }

  Persona? get activePersona {
    if (personas.isEmpty) return null;
    try {
      return personas.firstWhere((p) => p.id == activePersonaId);
    } catch (_) {
      return null;
    }
  }

  ChatSession? get currentSession {
    try {
      return sessions.firstWhere((s) => s.id == currentSessionId);
    } catch (_) {
      return null;
    }
  }

  /// 所有可用工具 = 内置 + 自定义
  List<ToolConfig> get allTools => [
    ...BuiltinTools.definitions,
    ...customTools,
  ];

  List<ToolConfig> get enabledTools =>
      allTools.where((t) => t.enabled).toList();

  Persona? personaOf(ChatSession s) {
    try {
      return personas.firstWhere((p) => p.id == s.personaId);
    } catch (_) {
      return null;
    }
  }

  Persona? personaById(String? id) {
    if (id == null) return null;
    try {
      return personas.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  GroupChat? groupOf(ChatSession s) {
    if (s.groupChatId == null) return null;
    try {
      return groupChats.firstWhere((g) => g.id == s.groupChatId);
    } catch (_) {
      return null;
    }
  }

  /// 查找与某角色的单聊会话
  ChatSession? findSessionWithPersona(String personaId) {
    for (final s in sessions) {
      if (!s.isGroup && s.personaId == personaId) return s;
    }
    return null;
  }

  /// 查找某群聊的会话
  ChatSession? findSessionWithGroup(String groupId) {
    for (final s in sessions) {
      if (s.isGroup && s.groupChatId == groupId) return s;
    }
    return null;
  }

  // ---------- 群聊 ----------
  Future<void> addOrUpdateGroupChat(GroupChat g) async {
    final idx = groupChats.indexWhere((e) => e.id == g.id);
    if (idx >= 0) {
      groupChats[idx] = g;
      log.i('group', '更新群聊：${g.name}（${g.personaIds.length} 个成员）');
    } else {
      groupChats.add(g);
      log.i('group', '新增群聊：${g.name}（${g.personaIds.length} 个成员）');
    }
    await _storage.saveGroupChats(groupChats);
    notifyListeners();
  }

  Future<void> deleteGroupChat(String id) async {
    final name = groupChats.where((g) => g.id == id).firstOrNull?.name ?? id;
    groupChats.removeWhere((g) => g.id == id);
    await _storage.saveGroupChats(groupChats);
    log.i('group', '删除群聊：$name');
    notifyListeners();
  }

  // ---------- 用户资料 ----------
  Future<void> updateUserProfile(UserProfile profile) async {
    userProfile = profile;
    await _storage.saveUserProfile(profile);
    log.i('app', '更新用户资料：${profile.name}');
    notifyListeners();
  }

  // ---------- 初始化 ----------
  Future<void> load() async {
    log.i('app', '开始加载应用状态');
    await _storage.init();
    apiConfigs = _storage.loadApiConfigs();
    activeApiId = _storage.activeApiId;
    embeddingApiConfig = _storage.loadEmbeddingApiConfig();
    personas = _storage.loadPersonas();
    activePersonaId = _storage.activePersonaId;
    customTools = _storage.loadTools();
    memories = _storage.loadMemories();
    sessions = _storage.loadSessions();
    groupChats = _storage.loadGroupChats();
    stickers = _storage.loadStickerItems();
    stickerFolders = _storage.loadStickerFolders();
    stickerGroups = _storage.loadStickerGroups();
    personaStickerBindings = _storage.loadPersonaStickerBindings();
    personaStickerSettings = _storage.loadPersonaStickerSettings();
    await _storage.clearLegacyStickerData();
    userProfile = _storage.loadUserProfile();
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == _storage.themeMode,
      orElse: () => ThemeMode.system,
    );
    injectMemories = _storage.injectMemories;
    messageMergeEnabled = _storage.messageMergeEnabled;
    messageMergeDebounce = _storage.messageMergeDebounce;
    typingDebounceEnabled = _storage.typingDebounceEnabled;
    streamOutputEnabled = _storage.streamOutputEnabled;
    stickerSendProbability = _storage.stickerSendProbability.clamp(0, 100);
    segmentedSendSettings = _storage.loadSegmentedSendSettings();
    memorySettings = _storage.loadMemorySettings();
    tokenUsage = _storage.loadTokenUsage();
    final dailyRecords = _storage.loadTokenDailyRecords();
    // 迁移：如果累计有数据但按天记录为空，把累计值作为今天的初始数据
    if (dailyRecords.isEmpty &&
        (tokenUsage.inputTokens > 0 ||
            tokenUsage.outputTokens > 0 ||
            tokenUsage.cachedTokens > 0)) {
      final today = _dateKey(DateTime.now());
      final migrated = DailyTokenUsage(
        date: today,
        inputTokens: tokenUsage.inputTokens,
        outputTokens: tokenUsage.outputTokens,
        cachedTokens: tokenUsage.cachedTokens,
      );
      tokenUsage = tokenUsage.copyWith(dailyRecords: [migrated]);
      await _storage.saveTokenDailyRecords([migrated]);
      log.i('app', '迁移 Token 按天记录：累计值作为今日初始数据');
    } else {
      tokenUsage = tokenUsage.copyWith(dailyRecords: dailyRecords);
    }
    appLaunchCount = _storage.appLaunchCount;
    notifyListeners();

    log.i(
      'app',
      '应用状态加载完成：'
          'API配置 ${apiConfigs.length} 个、'
          '人格 ${personas.length} 个、'
          '会话 ${sessions.length} 个、'
          '群聊 ${groupChats.length} 个、'
          '记忆 ${memories.length} 条、'
          '工具 ${customTools.length} 个',
    );

    // 记录本次启动
    await recordAppLaunch();
  }

  // ---------- API 配置 ----------
  Future<void> addOrUpdateApi(ApiConfig config) async {
    final idx = apiConfigs.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      apiConfigs[idx] = config;
      log.i('api', '更新 API 配置：${config.name}');
    } else {
      apiConfigs.add(config);
      activeApiId ??= config.id;
      log.i('api', '新增 API 配置：${config.name}（${config.model}）');
    }
    await _storage.saveApiConfigs(apiConfigs);
    await _storage.setActiveApiId(activeApiId);
    notifyListeners();
  }

  Future<void> deleteApi(String id) async {
    final name = apiConfigs.where((c) => c.id == id).firstOrNull?.name ?? id;
    apiConfigs.removeWhere((c) => c.id == id);
    if (activeApiId == id) {
      activeApiId = apiConfigs.isEmpty ? null : apiConfigs.first.id;
    }
    await _storage.saveApiConfigs(apiConfigs);
    await _storage.setActiveApiId(activeApiId);
    log.i('api', '删除 API 配置：$name');
    notifyListeners();
  }

  Future<void> setActiveApi(String id) async {
    activeApiId = id;
    await _storage.setActiveApiId(id);
    final name = apiConfigs.where((c) => c.id == id).firstOrNull?.name ?? id;
    log.i('api', '激活 API：$name');
    notifyListeners();
  }

  Future<void> updateEmbeddingApi(EmbeddingApiConfig config) async {
    embeddingApiConfig = config;
    await _storage.saveEmbeddingApiConfig(config);
    log.i(
      'api',
      '更新嵌入 API 配置：${config.model} '
          '（有效=${config.isValid}）',
    );
    notifyListeners();
  }

  // ---------- 人格 ----------
  Future<void> addOrUpdatePersona(Persona p) async {
    final idx = personas.indexWhere((e) => e.id == p.id);
    if (idx >= 0) {
      personas[idx] = p;
      log.i('persona', '更新人格：${p.name}');
    } else {
      personas.add(p);
      log.i('persona', '新增人格：${p.name}（${p.emoji}）');
    }
    await _storage.savePersonas(personas);
    notifyListeners();
  }

  Future<void> deletePersona(String id) async {
    final name = personas.where((p) => p.id == id).firstOrNull?.name ?? id;
    personas.removeWhere((p) => p.id == id);
    if (activePersonaId == id) activePersonaId = null;
    await _storage.savePersonas(personas);
    await _storage.setActivePersonaId(activePersonaId);
    log.i('persona', '删除人格：$name');
    notifyListeners();
  }

  Future<void> setActivePersona(String? id) async {
    activePersonaId = id;
    await _storage.setActivePersonaId(id);
    notifyListeners();
  }

  // ---------- 工具 ----------
  Future<void> addOrUpdateTool(ToolConfig t) async {
    final builtinIdx = BuiltinTools.definitions.indexWhere((b) => b.id == t.id);
    if (builtinIdx >= 0) return; // 内置工具不可编辑
    final idx = customTools.indexWhere((e) => e.id == t.id);
    if (idx >= 0) {
      customTools[idx] = t;
    } else {
      customTools.add(t);
    }
    await _storage.saveTools(customTools);
    notifyListeners();
  }

  Future<void> deleteTool(String id) async {
    customTools.removeWhere((t) => t.id == id);
    await _storage.saveTools(customTools);
    notifyListeners();
  }

  final Set<String> _disabledBuiltinIds = {};

  bool isToolEnabled(ToolConfig t) => t.type == ToolType.builtin
      ? !_disabledBuiltinIds.contains(t.id)
      : t.enabled;

  Future<void> toggleTool(ToolConfig t, bool enabled) async {
    if (t.type == ToolType.builtin) {
      if (enabled) {
        _disabledBuiltinIds.remove(t.id);
      } else {
        _disabledBuiltinIds.add(t.id);
      }
    } else {
      t.enabled = enabled;
      await _storage.saveTools(customTools);
    }
    notifyListeners();
  }

  List<ToolConfig> get effectiveTools => [
    ...BuiltinTools.definitions.where(
      (t) => !_disabledBuiltinIds.contains(t.id),
    ),
    ...customTools.where((t) => t.enabled),
  ];

  // ---------- 记忆 ----------
  Future<void> addMemory(
    String content, {
    String source = 'manual',
    String? personaId,
    String? sessionId,
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty) return;
    final memory = MemoryEntry(
      id: _uuid.v4(),
      content: normalized,
      createdAt: DateTime.now(),
      source: source,
      personaId: personaId,
      sessionId: sessionId,
    );
    memories.insert(0, memory);
    log.i(
      'memory',
      '新增记忆（来源=$source）：'
          '${normalized.length > 40 ? "${normalized.substring(0, 40)}..." : normalized}',
    );
    notifyListeners();
    _scheduleMemoriesPersist();

    // 后台计算嵌入向量
    _computeEmbedding(memory);
  }

  /// 异步计算记忆的嵌入向量
  Future<void> _computeEmbedding(MemoryEntry memory) async {
    if (!embeddingApiConfig.isValid) return;
    final expectedContent = memory.content;
    try {
      final result = await AiService.getEmbedding(
        baseUrl: embeddingApiConfig.baseUrl,
        apiKey: embeddingApiConfig.apiKey,
        model: embeddingApiConfig.model,
        text: expectedContent,
      );
      final current = memories
          .where((item) => item.id == memory.id)
          .firstOrNull;
      if (current == null || current.content != expectedContent) return;
      memory.embedding = result.embedding;
      _scheduleMemoriesPersist();
      await addTokenUsage(inputTokens: result.inputTokens);
      log.d('memory', '记忆嵌入计算完成：维度=${result.embedding.length}');
    } catch (e) {
      log.w('memory', '记忆嵌入计算失败', error: e);
    }
  }

  Future<void> updateMemory(String id, String content) async {
    final index = memories.indexWhere((e) => e.id == id);
    if (index < 0 || content.trim().isEmpty) return;
    memories[index].content = content.trim();
    memories[index].embedding = null; // 清除旧嵌入，后台重新计算
    notifyListeners();
    _scheduleMemoriesPersist();
    _computeEmbedding(memories[index]);
  }

  Future<void> deleteMemory(String id) async {
    memories.removeWhere((m) => m.id == id);
    notifyListeners();
    _scheduleMemoriesPersist();
  }

  // ---------- 会话 ----------
  Future<ChatSession> newSession({String? personaId, String? groupId}) async {
    final now = DateTime.now();
    String title;
    String? pid;
    String? gid;
    if (groupId != null) {
      final g = groupChats.firstWhere((e) => e.id == groupId);
      title = g.name;
      gid = groupId;
    } else {
      pid = personaId ?? activePersonaId;
      final p = personaById(pid);
      title = p?.name ?? '新对话';
    }
    final session = ChatSession(
      id: _uuid.v4(),
      title: title,
      personaId: pid,
      groupChatId: gid,
      createdAt: now,
      updatedAt: now,
    );
    // 单聊开场白
    if (gid == null) {
      final p = personaById(pid);
      if (p != null && p.greeting.isNotEmpty) {
        session.messages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: 'assistant',
            content: p.greeting,
            timestamp: now,
            speakerId: p.id,
          ),
        );
      }
    }
    sessions.insert(0, session);
    currentSessionId = session.id;
    log.i(
      'chat',
      '新建会话：$title（${gid != null ? "群聊" : "单聊"}）'
          ' id=${session.id.substring(0, 8)}',
    );
    notifyListeners();
    _scheduleSessionsPersist();
    return session;
  }

  /// 打开或创建与某角色的单聊
  Future<void> openChatWithPersona(String personaId) async {
    final existing = findSessionWithPersona(personaId);
    if (existing != null) {
      if (currentSessionId != existing.id) cancelPendingMerge();
      currentSessionId = existing.id;
      notifyListeners();
      return;
    }
    await newSession(personaId: personaId);
  }

  /// 打开或创建某群聊的会话
  Future<void> openChatWithGroup(String groupId) async {
    final existing = findSessionWithGroup(groupId);
    if (existing != null) {
      if (currentSessionId != existing.id) cancelPendingMerge();
      currentSessionId = existing.id;
      notifyListeners();
      return;
    }
    await newSession(groupId: groupId);
  }

  void openSession(String id) {
    if (currentSessionId != id) cancelPendingMerge();
    currentSessionId = id;
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    final title = sessions.where((s) => s.id == id).firstOrNull?.title ?? id;
    sessions.removeWhere((s) => s.id == id);
    if (currentSessionId == id) currentSessionId = null;
    log.i('chat', '删除会话：$title');
    notifyListeners();
    _scheduleSessionsPersist();
  }

  Future<void> clearSessions() async {
    final count = sessions.length;
    sessions.clear();
    currentSessionId = null;
    log.w('chat', '清空所有会话（共 $count 个）');
    notifyListeners();
    _scheduleSessionsPersist();
  }

  // ---------- 发送消息（Agent 循环） ----------

  /// 发送一条用户消息，并按需触发 AI 回复。
  ///
  /// 流程：
  /// 1. 确保会话存在
  /// 2. 选定发言角色（群聊根据 @ 决定，单聊用对方人格）
  /// 3. 追加用户消息、更新标题、持久化
  /// 4. 群聊未被 @ → 不触发回复；否则进入回复循环
  /// 5. 若当前已有回复进行中，则入队等待
  /// 6. 私聊开启消息合并时：防抖等待，合并短时间内多条消息为一条
  Future<void> sendMessage(
    String text, {
    List<String>? mentionedPersonaIds,
  }) async {
    final api = activeApi;
    var session = currentSession ?? await newSession();

    final isGroup = session.isGroup;
    final group = isGroup ? groupOf(session) : null;
    final persona = isGroup ? null : (personaOf(session) ?? activePersona);
    final mentions = mentionedPersonaIds ?? const <String>[];

    log.d(
      'chat',
      '发送消息 [${isGroup ? "群聊" : "单聊"}] '
          '会话=${session.id.substring(0, 8)} '
          '长度=${text.length} '
          '@=${mentions.length}',
    );

    // 取消空闲计时器
    _idleTimer?.cancel();

    // 群聊中根据 @ 选择发言角色；多个 @ 取第一个匹配的群成员
    final speaker = isGroup ? _pickGroupSpeaker(group, mentions) : null;

    // 追加用户消息
    _appendUserMessage(session, text, mentions);
    _maybeUpdateSessionTitle(session, text, isGroup, group);
    session.updatedAt = DateTime.now();
    notifyListeners();
    _scheduleSessionsPersist();

    // 群聊未被 @ 任何人：不触发 AI 回复
    if (isGroup && speaker == null) {
      log.d('chat', '群聊消息未 @ 任何角色，不触发回复');
      return;
    }

    // 单聊必须有可用 API
    if (api == null) {
      lastError = '请先在设置中添加并激活一个 API 配置';
      notifyListeners();
      log.w('chat', '无可用 API，无法发送回复');
      return;
    }

    // 已有回复进行中：加入待处理队列，由循环自动消费
    if (isSending) {
      _pendingReplies.add(
        _PendingReply(
          sessionId: session.id,
          speaker: speaker,
          text: text,
          mentionedPersonaIds: mentions,
        ),
      );
      log.d('chat', '回复进行中，消息入队（待处理 ${_pendingReplies.length} 条）');
      return;
    }

    // 私聊消息合并防抖：等待一段时间，合并后续消息后一起发送
    if (messageMergeEnabled && !isGroup) {
      log.d('chat', '消息合并已启用，调度防抖回复（${messageMergeDebounce}s）');
      // 立刻显示对面加载气泡，避免等倒计时结束后才出现
      _ensureTypingBubble(session, speakerId: persona?.id);
      _scheduleMergedReply(session: session, api: api, persona: persona);
      return;
    }

    // 立刻显示对面加载气泡，再进入回复循环
    _ensureTypingBubble(session, speakerId: speaker?.id ?? persona?.id);
    await _replyLoop(
      session: session,
      api: api,
      persona: persona,
      isGroup: isGroup,
      group: group,
      initialSpeaker: speaker,
      initialText: text,
      initialMentions: mentions,
    );
  }

  /// 确保会话末尾有一个空的流式加载气泡（立即反馈“对方正在输入”）
  ChatMessage _ensureTypingBubble(ChatSession session, {String? speakerId}) {
    final last = session.messages.isEmpty ? null : session.messages.last;
    if (last != null &&
        last.role == 'assistant' &&
        last.isStreaming &&
        last.content.isEmpty) {
      // speakerId 为 final，若角色不一致则重建空气泡
      if (speakerId != null && last.speakerId != speakerId) {
        session.messages.remove(last);
      } else {
        notifyListeners();
        return last;
      }
    }
    final bubble = ChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      speakerId: speakerId,
    )..isStreaming = true;
    session.messages.add(bubble);
    notifyListeners();
    return bubble;
  }

  /// 调度合并回复：在防抖窗口内追加的消息会被合并
  void _scheduleMergedReply({
    required ChatSession session,
    required ApiConfig api,
    required Persona? persona,
  }) {
    _mergeSessionId = session.id;
    _mergeTimer?.cancel();
    final delay = Duration(seconds: messageMergeDebounce);
    _mergeTimer = Timer(delay, () {
      _mergeTimer = null;
      final sid = _mergeSessionId;
      _mergeSessionId = null;
      notifyListeners(); // 刷新等待提示
      // 高并发 race 修复：若回复进行中，标记"等本轮回合结束后再调度一次合并"，
      // 避免旧的"if (isSending) return" 把消息吞掉
      if (isSending) {
        _pendingMergedSessionId = sid ?? session.id;
        return;
      }
      _triggerMergedReply(
        session: session,
        api: api,
        persona: persona,
        scheduleSid: sid,
      );
    });
    notifyListeners();
  }

  /// 触发合并回复：将待回复的多条用户消息合并为一条文本
  Future<void> _triggerMergedReply({
    required ChatSession session,
    required ApiConfig api,
    required Persona? persona,
    String? scheduleSid,
  }) async {
    // 重入锁：避免 _scheduleMergedReply 的多路并发回调或重置打字防抖期间重入
    if (_mergeTriggering || isSending) {
      _pendingMergedSessionId = scheduleSid ?? session.id;
      return;
    }
    _mergeTriggering = true;
    try {
      // 按 scheduleSid 重新解析最新 session 实例（避免使用旧的 session 引用，
      // session 内 messages 可能在防抖窗口期间已被追加更多）
      final sid = scheduleSid ?? session.id;
      final freshSession =
          sessions.where((s) => s.id == sid).firstOrNull ?? session;
      final freshApi = activeApi ?? api;
      final freshPersona = personaOf(freshSession) ?? persona;
      final pendingTexts = <String>[];
      for (int i = freshSession.messages.length - 1; i >= 0; i--) {
        final m = freshSession.messages[i];
        if (m.role == 'assistant') {
          if (m.isStreaming && m.content.isEmpty) continue;
          break;
        }
        if (m.role == 'tool') break;
        if (m.role == 'user') pendingTexts.insert(0, m.content);
      }
      if (pendingTexts.isEmpty) {
        _removeEmptyStreaming(freshSession);
        return;
      }
      final merged = pendingTexts.join('\n');
      _ensureTypingBubble(
        freshSession,
        speakerId: (freshPersona ?? persona)?.id,
      );
      await _replyLoop(
        session: freshSession,
        api: freshApi,
        persona: freshPersona,
        isGroup: false,
        group: null,
        initialSpeaker: null,
        initialText: merged,
        initialMentions: const [],
      );
    } finally {
      _mergeTriggering = false;
      // 高并发修复：回复结束后，若期间有新的合并请求被标记 pending，再调度一次
      final pendingSid = _pendingMergedSessionId;
      if (pendingSid != null) {
        _pendingMergedSessionId = null;
        final sid = pendingSid;
        final s = sessions.where((c) => c.id == sid).firstOrNull;
        final a = activeApi;
        if (s != null && a != null) {
          _scheduleMergedReply(session: s, api: a, persona: personaOf(s));
        }
      }
    }
  }

  /// 取消挂起的合并回复（切换会话/手动停止时调用）
  void cancelPendingMerge() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    final sid = _mergeSessionId;
    _mergeSessionId = null;
    // 取消防抖等待时，同步移除尚未开始生成的空气泡
    if (sid != null && !isSending) {
      final session = sessions.where((s) => s.id == sid).firstOrNull;
      if (session != null) {
        _removeEmptyStreaming(session);
      }
    }
    notifyListeners();
  }

  /// 从 @ 列表中选择群聊中第一个有效成员作为发言角色
  Persona? _pickGroupSpeaker(GroupChat? group, List<String> mentions) {
    if (group == null || group.personaIds.isEmpty) return null;
    for (final mid in mentions) {
      if (group.personaIds.contains(mid)) {
        final p = personaById(mid);
        if (p != null) return p;
      }
    }
    return null;
  }

  void _appendUserMessage(
    ChatSession session,
    String text,
    List<String> mentions,
  ) {
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
      mentionIds: mentions,
    );
    // 防御式：只要末尾存在流式加载气泡，就把用户新消息插在气泡上方
    // 覆盖两种场景：AI 正在回复(isSending)、防抖等待中(isPendingMerge)
    // 直接基于列表末尾状态判定，避免任何状态机时序偏差导致 B 排到气泡下方
    final lastIsStreamingBubble =
        session.messages.isNotEmpty &&
        session.messages.last.role == 'assistant' &&
        session.messages.last.isStreaming;
    if (lastIsStreamingBubble) {
      session.messages.insert(session.messages.length - 1, userMsg);
      return;
    }
    session.messages.add(userMsg);
  }

  /// 仅在"新对话"或群聊标题仍为群名时更新为消息摘要
  void _maybeUpdateSessionTitle(
    ChatSession session,
    String text,
    bool isGroup,
    GroupChat? group,
  ) {
    final isNew = session.title == '新对话';
    final isGroupName = isGroup && group != null && session.title == group.name;
    if (isNew || isGroupName) {
      session.title = text.length > 20 ? text.substring(0, 20) : text;
    }
  }

  /// 回复循环：处理当前消息及回复过程中新收到的消息（队列）
  Future<void> _replyLoop({
    required ChatSession session,
    required ApiConfig api,
    required Persona? persona,
    required bool isGroup,
    required GroupChat? group,
    required Persona? initialSpeaker,
    required String initialText,
    required List<String> initialMentions,
  }) async {
    var currentSpeaker = initialSpeaker;
    var currentText = initialText;
    var currentMentions = initialMentions;

    isSending = true;
    lastError = null;
    notifyListeners();

    log.i(
      'chat',
      '回复循环开始 [${isGroup ? "群聊" : "单聊"}] '
          '角色=${(currentSpeaker ?? persona)?.name ?? "默认"}',
    );

    try {
      while (true) {
        _cancelToken = CancelToken();
        try {
          await _runOneReplyRound(
            session: session,
            api: api,
            persona: persona,
            isGroup: isGroup,
            group: group,
            speaker: currentSpeaker,
            text: currentText,
            mentions: currentMentions,
          );
        } on _CancelException {
          // 用户主动打断：移除空的加载气泡，保留已生成内容
          _removeEmptyStreaming(session);
          log.i('chat', '用户主动打断生成');
          break;
        } catch (e, s) {
          lastError = e.toString();
          log.e('chat', '回复循环出错', error: e, stackTrace: s);
          // 复用正在加载的气泡显示错误，避免遗留空气泡
          final sIdx = session.messages.lastIndexWhere((m) => m.isStreaming);
          if (sIdx >= 0) {
            final m = session.messages[sIdx];
            m.isStreaming = false;
            m.content = m.content.isEmpty
                ? '⚠️ 请求失败：$e'
                : '${m.content}\n\n⚠️ 请求失败：$e';
          } else {
            session.messages.add(
              ChatMessage(
                id: _uuid.v4(),
                role: 'assistant',
                content: '⚠️ 请求失败：$e',
                timestamp: DateTime.now(),
                speakerId: currentSpeaker?.id,
              ),
            );
          }
          break;
        }

        // 处理回复过程中收到的新消息
        final next = _takePendingReply(session.id);
        if (next == null) break;
        currentSpeaker = next.speaker;
        currentText = next.text;
        currentMentions = next.mentionedPersonaIds;
        log.d('chat', '处理待处理消息：${currentText.length} 字符');
      }
    } finally {
      session.updatedAt = DateTime.now();
      isSending = false;
      _cancelToken = null;
      notifyListeners();
      _scheduleSessionsPersist();
      _resetIdleTimer(session);
      log.i('chat', '回复循环结束');
      // 回复结束后立即检查是否需要总结（不阻塞 UI）
      _checkAndSummarize(session);
      final pendingMergeSid = _pendingMergedSessionId;
      if (pendingMergeSid != null && !_mergeTriggering) {
        _pendingMergedSessionId = null;
        final pendingSession = sessions
            .where((candidate) => candidate.id == pendingMergeSid)
            .firstOrNull;
        final pendingApi = activeApi;
        if (pendingSession != null && pendingApi != null) {
          _scheduleMergedReply(
            session: pendingSession,
            api: pendingApi,
            persona: personaOf(pendingSession),
          );
        }
      }
      final next = _takePendingReply();
      if (next != null) {
        final nextSession = sessions
            .where((s) => s.id == next.sessionId)
            .firstOrNull;
        final nextApi = activeApi;
        if (nextSession != null && nextApi != null) {
          final nextGroup = nextSession.isGroup ? groupOf(nextSession) : null;
          final nextPersona = nextSession.isGroup
              ? null
              : (personaOf(nextSession) ?? activePersona);
          unawaited(
            _replyLoop(
              session: nextSession,
              api: nextApi,
              persona: nextPersona,
              isGroup: nextSession.isGroup,
              group: nextGroup,
              initialSpeaker: next.speaker,
              initialText: next.text,
              initialMentions: next.mentionedPersonaIds,
            ),
          );
        }
      }
    }
  }

  _PendingReply? _takePendingReply([String? sessionId]) {
    if (sessionId == null) {
      return _pendingReplies.isEmpty ? null : _pendingReplies.removeFirst();
    }
    for (final item in _pendingReplies) {
      if (item.sessionId == sessionId) {
        _pendingReplies.remove(item);
        return item;
      }
    }
    return null;
  }

  /// 执行一轮 AI 回复（含最多 5 次工具调用）
  Future<void> _runOneReplyRound({
    required ChatSession session,
    required ApiConfig api,
    required Persona? persona,
    required bool isGroup,
    required GroupChat? group,
    required Persona? speaker,
    required String text,
    required List<String> mentions,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      isGroup: isGroup,
      group: group,
      persona: persona,
      speaker: speaker,
      mentions: mentions,
    );

    final apiMessages = _buildApiMessages(
      session: session,
      systemPrompt: systemPrompt,
      isGroup: isGroup,
    );

    if (injectMemories && embeddingApiConfig.isValid) {
      await _injectMemories(
        apiMessages: apiMessages,
        text: text,
        personaId: isGroup ? speaker?.id : persona?.id,
        sessionId: session.id,
      );
    }

    final tools = effectiveTools;
    await _agentLoop(
      session: session,
      api: api,
      apiMessages: apiMessages,
      tools: tools,
      speaker: speaker,
      persona: persona,
    );
  }

  String _buildSystemPrompt({
    required bool isGroup,
    required GroupChat? group,
    required Persona? persona,
    required Persona? speaker,
    required List<String> mentions,
  }) {
    final buf = StringBuffer();
    if (isGroup && group != null) {
      buf.writeln('这是一个多人群聊场景。群里有以下角色：');
      for (final pid in group.personaIds) {
        final p = personaById(pid);
        if (p == null) continue;
        buf.writeln('\n--- 角色：${p.name} ---');
        buf.write(p.buildSystemPrompt());
      }
      final mentionedNames = mentions
          .map((id) => personaById(id)?.name)
          .whereType<String>()
          .join('、');
      final speakerName = speaker?.name ?? '助手';
      if (mentionedNames.isNotEmpty) {
        buf.writeln(
          '\n\n用户在最新消息中 @ 了「$mentionedNames」。请以「$speakerName」的身份回复用户，'
          '保持该角色的性格和语言风格。你可以看到完整的群聊上下文，结合此前所有角色的发言理解语境。'
          '不要在回复开头重复角色名。',
        );
      } else {
        buf.writeln(
          '\n\n现在轮到「$speakerName」发言。请以「$speakerName」的身份回复用户，'
          '保持该角色的性格和语言风格。不要在回复开头重复角色名。',
        );
      }
    } else if (persona != null) {
      buf.write(persona.buildSystemPrompt());
    } else {
      buf.writeln('你是一个乐于助人的 AI 助手。');
    }
    // 引导 AI 主动使用 save_memory 工具记录关键信息
    buf.writeln(
      '\n\n【记忆工具】你可以使用 save_memory 工具主动保存用户的关键信息'
      '（如偏好、身份、重要事实、习惯等）到长期记忆。'
      '当用户透露了值得记住的信息时，请调用该工具，无需告知用户。'
      '每次只保存一条简洁明确的信息，不要保存闲聊或无意义内容。',
    );
    if (stickersEnabled) {
      final stickerPersonaId = isGroup ? speaker?.id : persona?.id;
      final stickerSettings = personaStickerSettingsFor(stickerPersonaId);
      final folderEntries = <String, String>{};
      for (final folder in stickerFoldersForPersonaPreferences(
        stickerPersonaId,
      )) {
        final name = folder.name.trim();
        if (name.isEmpty ||
            stickersForPersonaFolder(stickerPersonaId, name).isEmpty) {
          continue;
        }
        final description = folder.description.trim();
        folderEntries[name] = folderEntries.containsKey(name)
            ? '${folderEntries[name]}${description.isEmpty ? '' : '；$description'}'
            : description;
      }
      if (folderEntries.isNotEmpty) {
        buf.write(
          buildStickerPromptSection(
            maxStickersPerMessage: maxStickersPerMessage,
            sendProbability: stickerSettings.sendProbability,
            folderEntries: folderEntries,
            customPrompt: stickerSettings.customPrompt,
          ),
        );
      }
    }
    return buf.toString();
  }

  List<Map<String, dynamic>> _buildApiMessages({
    required ChatSession session,
    required String systemPrompt,
    required bool isGroup,
  }) {
    return <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...session.messages.where((m) => m.role != 'tool').map((m) {
        if (m.stickerId != null) {
          final sticker = stickerById(m.stickerId);
          final folder = stickerFolderForSticker(m.stickerId);
          final label = folder?.name ?? sticker?.name ?? '未知情绪';
          return {
            'role': m.role,
            'content': sticker == null
                ? '【发送了一个不可用的表情包】'
                : m.role == 'assistant'
                ? '【助手发送了表情包：$label】'
                : '【用户发送了表情包：$label】',
          };
        }
        if (m.role == 'assistant' && isGroup && m.speakerId != null) {
          final sp = personaById(m.speakerId);
          if (sp != null) {
            return {
              'role': 'assistant',
              'content': '[${sp.name}] ${m.content}',
            };
          }
        }
        if (m.role == 'user' && segmentedSendSettings.reverseReplace) {
          // 反向替换用户消息：UI 显示原文，发给 AI 的为还原后内容
          final restored = SegmentedSplitter.applyReverseReplace(
            m.content,
            segmentedSendSettings,
          );
          return {'role': 'user', 'content': restored};
        }
        return {'role': m.role, 'content': m.content};
      }),
    ];
  }

  Future<void> _injectMemories({
    required List<Map<String, dynamic>> apiMessages,
    required String text,
    required String? personaId,
    required String sessionId,
  }) async {
    // 注入前清除历史中已注入的旧记忆片段，避免重复累积和 token 浪费
    _stripInjectedMemories(apiMessages);

    final relevant = await _retrieveRelevantMemories(
      text,
      personaId,
      sessionId,
    );
    if (relevant.isEmpty) return;

    final memBuf = StringBuffer('【长期记忆】以下是关于用户的关键信息，请自然地参考：\n');
    for (final m in relevant) {
      memBuf.writeln('- ${m.content}');
    }
    final lastUser = apiMessages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUser < 0) return;

    final original = apiMessages[lastUser]['content'] as String;
    final injected = memorySettings.injectionPosition == 'prepend'
        ? '$memBuf\n$original'
        : '$original\n$memBuf';
    apiMessages[lastUser] = {'role': 'user', 'content': injected};
    log.d(
      'memory',
      '注入 ${relevant.length} 条记忆到用户消息'
          '（${memorySettings.injectionPosition}）',
    );
  }

  /// 移除历史消息中已注入的记忆片段
  /// 匹配格式：【长期记忆】...\n（直到下一个非列表行或消息末尾）
  static final _injectedMemoryRegex = RegExp(r'【长期记忆】[\s\S]*?(?=\n\S|\n*$|$)');
  static final _trailingMemoryRegex = RegExp(r'\n?【长期记忆】[\s\S]*$');

  void _stripInjectedMemories(List<Map<String, dynamic>> apiMessages) {
    for (int i = 0; i < apiMessages.length; i++) {
      final msg = apiMessages[i];
      if (msg['role'] != 'user') continue;
      final content = msg['content'] as String;
      if (!content.contains('【长期记忆】')) continue;
      // 移除前置记忆（prepend 模式）
      var cleaned = content.replaceAll(_injectedMemoryRegex, '');
      // 移除后置记忆（append 模式）
      cleaned = cleaned.replaceAll(_trailingMemoryRegex, '');
      cleaned = cleaned.trim();
      apiMessages[i] = {'role': 'user', 'content': cleaned};
    }
  }

  /// Agent 循环：最多 5 轮工具调用，每轮流式输出
  Future<void> _agentLoop({
    required ChatSession session,
    required ApiConfig api,
    required List<Map<String, dynamic>> apiMessages,
    required List<ToolConfig> tools,
    required Persona? speaker,
    required Persona? persona,
  }) async {
    for (var round = 0; round < 5; round++) {
      if (_cancelToken?.isCancelled == true) throw const _CancelException();

      log.d(
        'api',
        'Agent 循环第 ${round + 1}/5 轮，'
            '消息数=${apiMessages.length}，工具数=${tools.length}',
      );

      // 优先复用发送时已创建的空加载气泡；工具多轮时再新建
      final streamingMsg = _ensureTypingBubble(session, speakerId: speaker?.id);

      final resp = await AiService.chatStream(
        config: api,
        messages: apiMessages,
        tools: tools,
        cancelToken: _cancelToken,
        onDelta: (delta) {
          // 流式输出开启时实时追加显示；关闭时仅保留 loading 占位，
          // 整段在 _finalizeAssistantMessage/_applySegmentedSend 中一次性写入
          if (streamOutputEnabled) {
            streamingMsg.content += delta;
            _scheduleStreamNotify();
          }
        },
      );

      if (_cancelToken?.isCancelled == true) {
        throw const _CancelException();
      }

      await addTokenUsage(
        inputTokens: resp.inputTokens,
        outputTokens: resp.outputTokens,
        cachedTokens: resp.cachedTokens,
      );

      log.i(
        'api',
        '流式响应完成：输入=${resp.inputTokens} '
            '输出=${resp.outputTokens} '
            '缓存=${resp.cachedTokens} '
            '工具调用=${resp.toolCalls.length}',
      );

      // 本轮流式结束
      streamingMsg.isStreaming = false;

      if (resp.toolCalls.isEmpty) {
        _finalizeAssistantMessage(session, streamingMsg, resp.content, speaker);
        break;
      }

      // 执行工具调用，将结果回填到 API 上下文与会话消息
      apiMessages.add(resp.rawMessage);
      await _executeToolCalls(
        session: session,
        apiMessages: apiMessages,
        toolCalls: resp.toolCalls,
        speaker: speaker,
        persona: persona,
      );
    }
  }

  void _scheduleStreamNotify() {
    if (_streamNotifyScheduled) return;
    _streamNotifyScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _streamNotifyScheduled = false;
      notifyListeners();
    });
  }

  void _finalizeAssistantMessage(
    ChatSession session,
    ChatMessage? streamingMsg,
    String? finalContent,
    Persona? speaker,
  ) {
    final content = finalContent ?? streamingMsg?.content ?? '';
    final parts = _buildAssistantParts(
      content,
      speaker?.id ?? session.personaId,
    );
    if (parts.isEmpty) {
      if (streamingMsg != null) session.messages.remove(streamingMsg);
      notifyListeners();
      return;
    }
    if (streamingMsg != null) {
      final first = parts.first;
      streamingMsg.content = first.text;
      streamingMsg.stickerId = first.stickerId;
      streamingMsg.isStreaming = false;
      streamingMsg.isSegmented = false;
    } else {
      _appendAssistantPart(session, parts.first, speaker, segmented: false);
    }
    if (parts.length == 1) {
      _scheduleSessionsPersist();
      notifyListeners();
      return;
    }
    if (segmentedSendSettings.enabled) {
      _enqueueAssistantParts(
        session: session,
        speaker: speaker,
        remaining: parts.sublist(1),
      );
    } else {
      for (final part in parts.skip(1)) {
        _appendAssistantPart(session, part, speaker, segmented: false);
      }
      _scheduleSessionsPersist();
      notifyListeners();
    }
  }

  static final _stickerTagPattern = RegExp(
    r'''<sticker\s+name\s*=\s*["']([^"']+)["']\s*/\s*>''',
    caseSensitive: false,
  );

  List<_AssistantPart> _buildAssistantParts(String content, String? personaId) {
    final parsed = <_AssistantPart>[];
    var start = 0;
    var stickerCount = 0;
    final stickerSettings = personaStickerSettingsFor(personaId);
    final canUseStickers =
        stickersEnabled &&
        StickerSelection.allowsSticker(
          probability: stickerSettings.sendProbability,
          random: _stickerRandom,
        );
    for (final match in _stickerTagPattern.allMatches(content)) {
      final text = content.substring(start, match.start).trim();
      if (text.isNotEmpty) parsed.add(_AssistantPart.text(text));
      final name = match.group(1)?.trim() ?? '';
      final sticker = canUseStickers && stickerCount < maxStickersPerMessage
          ? pickStickerForPersonaFolder(personaId, name)
          : null;
      if (sticker != null) {
        parsed.add(_AssistantPart.sticker(sticker.id));
        stickerCount++;
      }
      start = match.end;
    }
    final tail = content.substring(start).trim();
    if (tail.isNotEmpty) parsed.add(_AssistantPart.text(tail));
    if (!segmentedSendSettings.enabled) return parsed;
    final expanded = <_AssistantPart>[];
    for (final part in parsed) {
      if (part.stickerId != null ||
          part.text.length < segmentedSendSettings.minTriggerLength) {
        expanded.add(part);
        continue;
      }
      final segments = SegmentedSplitter.split(
        part.text,
        segmentedSendSettings,
      );
      expanded.addAll(
        segments.where((text) => text.isNotEmpty).map(_AssistantPart.text),
      );
    }
    return expanded;
  }

  ChatMessage _appendAssistantPart(
    ChatSession session,
    _AssistantPart part,
    Persona? speaker, {
    required bool segmented,
  }) {
    final message = ChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: part.text,
      timestamp: DateTime.now(),
      speakerId: speaker?.id,
      stickerId: part.stickerId,
    )..isSegmented = segmented;
    session.messages.add(message);
    return message;
  }

  void _enqueueAssistantParts({
    required ChatSession session,
    required Persona? speaker,
    required List<_AssistantPart> remaining,
  }) {
    if (remaining.isEmpty) {
      _scheduleSessionsPersist();
      notifyListeners();
      return;
    }
    final next = remaining.first;
    final delay = next.stickerId != null
        ? const Duration(milliseconds: 450)
        : SegmentedSplitter.segmentDelay(
            segmentChars: next.text.length,
            s: segmentedSendSettings,
          );
    _segmentedTimer = Timer(delay, () {
      _segmentedTimer = null;
      final message = _appendAssistantPart(
        session,
        next,
        speaker,
        segmented: true,
      );
      notifyListeners();
      _scheduleSessionsPersist();
      late final Timer visualTimer;
      visualTimer = Timer(const Duration(milliseconds: 330), () {
        _segmentVisualTimers.remove(visualTimer);
        message.isSegmented = false;
        notifyListeners();
      });
      _segmentVisualTimers.add(visualTimer);
      _enqueueAssistantParts(
        session: session,
        speaker: speaker,
        remaining: remaining.sublist(1),
      );
    });
  }

  Timer? _segmentedTimer;

  void _cancelSegmentedTimer() {
    _segmentedTimer?.cancel();
    _segmentedTimer = null;
    for (final timer in _segmentVisualTimers) {
      timer.cancel();
    }
    _segmentVisualTimers.clear();
  }

  /// 移除内容为空的加载气泡（取消时调用）
  void _removeEmptyStreaming(ChatSession session) {
    session.messages.removeWhere((m) => m.isStreaming && m.content.isEmpty);
    for (final m in session.messages) {
      if (m.isStreaming) m.isStreaming = false;
      if (m.isSegmented) m.isSegmented = false;
    }
  }

  Future<void> _executeToolCalls({
    required ChatSession session,
    required List<Map<String, dynamic>> apiMessages,
    required List<ToolCallRequest> toolCalls,
    required Persona? speaker,
    required Persona? persona,
  }) async {
    log.d('tool', '执行 ${toolCalls.length} 个工具调用');
    for (final tc in toolCalls) {
      final result = await _executeOneTool(
        tc: tc,
        speaker: speaker,
        persona: persona,
        sessionId: session.id,
      );
      apiMessages.add({
        'role': 'tool',
        'tool_call_id': tc.id,
        'content': result,
      });
      session.messages.add(
        ChatMessage(
          id: _uuid.v4(),
          role: 'tool',
          content: result,
          timestamp: DateTime.now(),
          toolName: tc.name,
        ),
      );
      log.i(
        'tool',
        '工具调用完成：${tc.name} → '
            '${result.length > 80 ? "${result.substring(0, 80)}..." : result}',
      );
      notifyListeners();
    }
  }

  Future<String> _executeOneTool({
    required ToolCallRequest tc,
    required Persona? speaker,
    required Persona? persona,
    required String sessionId,
  }) async {
    log.d('tool', '调用工具 ${tc.name}，参数=${tc.arguments}');
    final builtin = BuiltinTools.definitions
        .where((t) => t.name == tc.name)
        .toList();
    if (builtin.isNotEmpty) {
      // 嵌入未配置时，save_memory 工具被禁用
      if (tc.name == 'save_memory' && !embeddingApiConfig.isValid) {
        log.w('tool', 'save_memory 调用被拒绝：嵌入 API 未配置');
        return '记忆系统未启用：请先配置嵌入 API';
      }
      return BuiltinTools.execute(
        tc.name,
        tc.arguments,
        onSaveMemory: (content) => addMemory(
          content,
          source: 'auto',
          personaId: speaker?.id ?? persona?.id,
          sessionId: sessionId,
        ),
      );
    }
    final custom = customTools.where((t) => t.name == tc.name).toList();
    if (custom.isEmpty) {
      log.w('tool', '未找到工具: ${tc.name}');
      return '未找到工具: ${tc.name}';
    }
    return HttpToolExecutor.execute(custom.first, tc.arguments);
  }
}

/// 用户主动取消生成
class _CancelException implements Exception {
  const _CancelException();
}

/// 待回复消息（回复过程中用户继续发送的消息）
class _AssistantPart {
  final String text;
  final String? stickerId;

  const _AssistantPart.text(this.text) : stickerId = null;
  const _AssistantPart.sticker(this.stickerId) : text = '';
}

class _PendingReply {
  final String sessionId;
  final Persona? speaker;
  final String text;
  final List<String> mentionedPersonaIds;

  _PendingReply({
    required this.sessionId,
    this.speaker,
    required this.text,
    this.mentionedPersonaIds = const [],
  });
}
