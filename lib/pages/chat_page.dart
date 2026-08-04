import 'dart:io';
import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/fast_route.dart';
import '../widgets/persona_avatar.dart';
import '../widgets/chat_image_preview.dart';
import '../widgets/sticker_message_body.dart';
import 'group_settings_page.dart';
import 'persona_page.dart';

String _formatMessageTime(DateTime time) {
  final now = DateTime.now();
  final date = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final offset = date.difference(today).inDays;
  final clock =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  if (offset == -1) return '昨天 $clock';
  if (offset == 0) return clock;
  if (offset >= -6 && offset <= -2) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${weekdays[time.weekday - 1]} $clock';
  }
  if (time.year == now.year) return '${time.month}月${time.day}日 $clock';
  return '${time.year}年${time.month}月${time.day}日 $clock';
}

Set<String> _messageTimeAnchorIds(List<ChatMessage> messages) {
  final anchors = <String>{};
  DateTime? lastAnchor;
  for (final message in messages) {
    if (message.isStreaming && message.content.isEmpty) continue;
    final time = message.timestamp;
    final previousAnchor = lastAnchor;
    final changedDay =
        previousAnchor != null &&
        (time.year != previousAnchor.year ||
            time.month != previousAnchor.month ||
            time.day != previousAnchor.day);
    if (previousAnchor == null ||
        changedDay ||
        time.difference(previousAnchor) >= const Duration(minutes: 5)) {
      anchors.add(message.id);
      lastAnchor = time;
    }
  }
  return anchors;
}

class _MentionToken {
  final String personaId;
  final String label;
  int start;
  int end;

  _MentionToken({
    required this.personaId,
    required this.label,
    required this.start,
    required this.end,
  });
}

class _MessageTimeDivider extends StatelessWidget {
  final DateTime time;
  const _MessageTimeDivider({required this.time});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            _formatMessageTime(time),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 聊天页面（从主页进入）
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();
  final List<_MentionToken> _mentionTokens = [];
  String? _mentionQuery; // 非 null 表示正在 @ 检索中
  int _mentionStart = -1; // @ 起始偏移
  TextEditingValue _previousInput = TextEditingValue.empty;
  bool _applyingMentionEdit = false;
  bool _scrollScheduled = false;
  bool _followBottom = true;
  String? _followSessionId;
  int _lastMsgCount = 0;
  int _lastContentLen = 0;
  // 已"已知"的消息 id 集合：用于区分"首屏历史消息"与"运行时新追加的消息"，
  // 仅对后者播放入场动画，避免首屏满屏闪。
  final Set<String> _knownMessageIds = {};
  final Set<String> _pendingEntranceIds = {};
  // 当前会话 id（用于切换会话时重置已知集合）
  String? _knownSessionId;
  int _knownMessageCount = 0;
  String? _timeAnchorSessionId;
  int _timeAnchorMessageCount = -1;
  String? _timeAnchorLastMessageId;
  Set<String> _timeAnchorIds = const {};

  @override
  void initState() {
    super.initState();
    _input.addListener(_onTextChanged);
    _scroll.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    if (!_scroll.hasClients) return;
    _followBottom = _scroll.position.pixels <= 96;
  }

  Set<String> _resolveMessageTimeAnchors(
    String sessionId,
    List<ChatMessage> messages,
  ) {
    final lastMessageId = messages.isEmpty ? null : messages.last.id;
    if (_timeAnchorSessionId == sessionId &&
        _timeAnchorMessageCount == messages.length &&
        _timeAnchorLastMessageId == lastMessageId) {
      return _timeAnchorIds;
    }
    _timeAnchorSessionId = sessionId;
    _timeAnchorMessageCount = messages.length;
    _timeAnchorLastMessageId = lastMessageId;
    _timeAnchorIds = _messageTimeAnchorIds(messages);
    return _timeAnchorIds;
  }

  void _onTextChanged() {
    if (!mounted) return;
    final value = _input.value;
    if (_applyingMentionEdit) {
      _previousInput = value;
      return;
    }
    if (_handleMentionBackspace(_previousInput, value)) return;
    _syncMentionTokens(_previousInput.text, value.text);
    _previousInput = value;

    // 打字防抖逻辑：当输入框非空且打字时，暂停结算；输入框为空时恢复结算
    final text = value.text;
    final appState = context.read<AppState>();
    if (text.trim().isNotEmpty) {
      appState.pauseMergeTimerForTyping();
    } else {
      appState.resumeMergeTimerForTyping();
    }

    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _mentionQuery = null;
      _mentionStart = -1;
      setState(() {});
      return;
    }
    final cursor = sel.baseOffset;
    // 向左查找最近的未闭合 @
    int atIdx = -1;
    for (int i = cursor - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        atIdx = i;
        break;
      }
      if (ch == ' ' || ch == '\n') {
        break;
      }
    }
    if (atIdx >= 0 && atIdx < cursor) {
      _mentionStart = atIdx;
      _mentionQuery = text.substring(atIdx + 1, cursor);
    } else {
      _mentionQuery = null;
      _mentionStart = -1;
    }
    setState(() {});
  }

  bool _handleMentionBackspace(
    TextEditingValue previous,
    TextEditingValue current,
  ) {
    if (!previous.selection.isValid ||
        !previous.selection.isCollapsed ||
        current.text.length != previous.text.length - 1) {
      return false;
    }
    var prefix = 0;
    while (prefix < current.text.length &&
        previous.text[prefix] == current.text[prefix]) {
      prefix++;
    }
    final tokenIndex = _mentionTokens.indexWhere(
      (token) => prefix >= token.start && prefix < token.end,
    );
    if (tokenIndex < 0) return false;
    final token = _mentionTokens[tokenIndex];
    final newText = previous.text.replaceRange(token.start, token.end, '');
    final removedLength = token.end - token.start;
    _mentionTokens.removeAt(tokenIndex);
    for (final other in _mentionTokens) {
      if (other.start >= token.end) {
        other.start -= removedLength;
        other.end -= removedLength;
      }
    }
    _applyingMentionEdit = true;
    _input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: token.start),
    );
    _applyingMentionEdit = false;
    _previousInput = _input.value;
    _mentionQuery = null;
    _mentionStart = -1;
    setState(() {});
    return true;
  }

  void _syncMentionTokens(String oldText, String newText) {
    if (oldText == newText || _mentionTokens.isEmpty) return;
    var prefix = 0;
    final commonLength = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < commonLength && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    final oldEnd = oldText.length - suffix;
    final newEnd = newText.length - suffix;
    final delta = newEnd - oldEnd;
    _mentionTokens.removeWhere((token) {
      final overlaps = token.start < oldEnd && token.end > prefix;
      if (!overlaps && token.start >= oldEnd) {
        token.start += delta;
        token.end += delta;
      }
      return overlaps;
    });
  }

  @override
  void dispose() {
    // 退出当前聊天界面时，恢复打字防抖倒计时结算
    context.read<AppState>().resumeMergeTimerForTyping();
    _input.dispose();
    _scroll.removeListener(_onScrollChanged);
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool jump = false}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (!_followBottom && !jump) return;
      const target = 0.0;
      if (_scroll.position.pixels <= 1) return;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _autoFollow(AppState state) {
    final session = state.currentSession;
    if (session == null) return;
    final count = session.messages.length;
    final lastLen = session.messages.isEmpty
        ? 0
        : session.messages.last.content.length;
    if (_followSessionId != session.id) {
      _followSessionId = session.id;
      _lastMsgCount = count;
      _lastContentLen = lastLen;
      _followBottom = true;
      return;
    }
    if (count != _lastMsgCount) {
      _lastMsgCount = count;
      _lastContentLen = lastLen;
      if (_followBottom) {
        _scrollToBottom(jump: true);
      }
    } else if (state.isSending && lastLen != _lastContentLen) {
      _lastContentLen = lastLen;
      if (_followBottom) {
        _scrollToBottom(jump: true);
      }
    }
  }

  /// 校验输入并提取有效的 @ 提及（位置与文本均需匹配）
  ({String text, List<String> mentions})? _validateInput(AppState state) {
    final text = _input.text.trim();
    if (text.isEmpty) return null;

    final session = state.currentSession;
    final isGroup = session?.isGroup ?? false;
    final mentions = isGroup ? _validMentions() : <String>[];
    final needsApi = !isGroup || mentions.isNotEmpty;
    if (needsApi && state.activeApi == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中配置 AI 接口')));
      return null;
    }
    return (text: text, mentions: mentions);
  }

  /// 仅保留文本中真实存在的 @ 提及（防止用户手动删除了部分字符）
  List<String> _validMentions() {
    final text = _input.text;
    final result = <String>{};
    for (final token in _mentionTokens) {
      if (token.start < 0 ||
          token.start + token.label.length > text.length ||
          text.substring(token.start, token.start + token.label.length) !=
              token.label) {
        continue;
      }
      result.add(token.personaId);
    }
    return result.toList();
  }

  void _resetInputState() {
    _input.clear();
    _mentionTokens.clear();
    _previousInput = TextEditingValue.empty;
    _mentionQuery = null;
    _mentionStart = -1;
  }

  Future<void> _send() async {
    final state = context.read<AppState>();
    final input = _validateInput(state);
    if (input == null) return;

    _resetInputState();
    setState(() {});
    await state.sendMessage(input.text, mentionedPersonaIds: input.mentions);
  }

  /// 群聊中从浮层选择候选角色
  void _selectCandidate(Persona p) {
    final text = _input.text;
    final start = _mentionStart;
    final sel = _input.selection;
    final cursor = sel.isValid ? sel.baseOffset : text.length;
    if (start < 0 || start > cursor) return;
    _insertMention(p, start: start, end: cursor);
  }

  void _insertMention(Persona persona, {int? start, int? end}) {
    HapticFeedback.mediumImpact();
    final value = _input.value;
    final selection = value.selection;
    final replaceStart =
        start ?? (selection.isValid ? selection.start : value.text.length);
    final replaceEnd =
        end ?? (selection.isValid ? selection.end : value.text.length);
    final label = '@${persona.name}';
    final insert = '$label ';
    final removedLength = replaceEnd - replaceStart;
    final delta = insert.length - removedLength;
    _mentionTokens.removeWhere((token) {
      final overlaps = token.start < replaceEnd && token.end > replaceStart;
      if (!overlaps && token.start >= replaceEnd) {
        token.start += delta;
        token.end += delta;
      }
      return overlaps;
    });
    _mentionTokens.add(
      _MentionToken(
        personaId: persona.id,
        label: label,
        start: replaceStart,
        end: replaceStart + insert.length,
      ),
    );
    _mentionTokens.sort((a, b) => a.start.compareTo(b.start));
    final newText = value.text.replaceRange(replaceStart, replaceEnd, insert);
    _applyingMentionEdit = true;
    _input.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: replaceStart + insert.length),
    );
    _applyingMentionEdit = false;
    _previousInput = _input.value;
    _mentionQuery = null;
    _mentionStart = -1;
    _focusNode.requestFocus();
    setState(() {});
  }

  void _showSessionInfo() {
    final state = context.read<AppState>();
    final session = state.currentSession;
    if (session == null) return;
    final isGroup = session.isGroup;
    final group = isGroup ? state.groupOf(session) : null;
    final persona = isGroup ? null : state.personaOf(session);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGroup && group != null) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _GroupAvatarSmall(group: group),
                    const SizedBox(height: 8),
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              ...group.personaIds.map((pid) {
                final p = state.personaById(pid);
                if (p == null) return const SizedBox.shrink();
                return ListTile(
                  leading: GestureDetector(
                    onLongPress: () {
                      Navigator.pop(context);
                      _insertMention(p);
                    },
                    child: PersonaAvatar(persona: p, radius: 20),
                  ),
                  title: Text(p.name),
                  subtitle: Text(
                    p.useRawPrompt ? '完整提示词模式' : p.personality,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
              ListTile(
                leading: _UserAvatarSmall(
                  path: state.userProfile.avatarPath,
                  name: state.userProfile.name,
                ),
                title: Text(state.userProfile.name),
                subtitle: const Text('我'),
              ),
            ] else if (persona != null) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    PersonaAvatar(persona: persona, radius: 32),
                    const SizedBox(height: 8),
                    Text(
                      persona.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (persona.personality.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          persona.personality,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('当前模型'),
              subtitle: Text(state.activeApi?.model ?? '未配置'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final session = state.currentSession;
    final isGroup = session?.isGroup ?? false;
    final group = isGroup && session != null ? state.groupOf(session) : null;
    final persona = session == null
        ? state.activePersona
        : (isGroup ? null : state.personaOf(session));
    _autoFollow(state);

    // 维护"已知消息 id"集合：用于区分首屏历史消息 vs 运行时新追加的消息。
    // 仅对运行时新追加的消息播放入场动画，避免首屏/切会话时满屏闪。
    if (_knownSessionId != session?.id) {
      // 切换/首次进入会话：把当前所有 message id 视为"已知"，不播动画
      _knownSessionId = session?.id;
      _knownMessageIds
        ..clear()
        ..addAll(session?.messages.map((m) => m.id) ?? const []);
      _knownMessageCount = session?.messages.length ?? 0;
    }
    final messages = session?.messages ?? const <ChatMessage>[];
    final messageTimeAnchorIds = session == null
        ? const <String>{}
        : _resolveMessageTimeAnchors(session.id, messages);
    if (messages.length < _knownMessageCount) {
      _knownMessageIds
        ..clear()
        ..addAll(messages.map((message) => message.id));
      _knownMessageCount = messages.length;
    } else {
      final currentIds = messages.map((message) => message.id).toSet();
      _knownMessageIds.removeWhere((id) => !currentIds.contains(id));
      for (final message in messages) {
        if (!_knownMessageIds.contains(message.id) &&
            !_pendingEntranceIds.contains(message.id)) {
          if (message.role == 'assistant') {
            _pendingEntranceIds.add(message.id);
          } else {
            _knownMessageIds.add(message.id);
          }
        }
      }
      if (messages.length != _knownMessageCount) {
        _knownMessageCount = messages.length;
      }
      if (_pendingEntranceIds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _pendingEntranceIds.isEmpty) return;
          _knownMessageIds.addAll(_pendingEntranceIds);
          _pendingEntranceIds.clear();
        });
      }
    }

    // 群聊始终使用当前群名，单聊始终使用对方角色名
    final title = isGroup ? (group?.name ?? '群聊') : (persona?.name ?? '新对话');
    final subtitle = isGroup
        ? '${(group?.personaIds.length ?? 0) + 1} 位成员 · ${state.activeApi?.model ?? '未配置'}'
        : (state.activeApi?.model ?? '未配置');
    final markdownStyleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(
          p: TextStyle(color: scheme.onSurface, height: 1.5, fontSize: 15),
          code: TextStyle(
            backgroundColor: scheme.surfaceContainerHighest,
            color: scheme.primary,
            fontSize: 13.5,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          blockquoteDecoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showSessionInfo,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                if (isGroup && group != null)
                  _MiniGroupAvatar(group: group, size: 38)
                else if (persona != null)
                  PersonaAvatar(persona: persona, radius: 19)
                else
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: '设置',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (v) {
              if (v == 'settings') {
                if (isGroup && group != null) {
                  Navigator.push(
                    context,
                    FastRoute(builder: (_) => GroupSettingsPage(group: group)),
                  );
                } else if (persona != null) {
                  Navigator.push(
                    context,
                    FastRoute(
                      builder: (_) => PersonaEditorPage(persona: persona),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('对话设置'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _WelcomeView(
                    persona: persona,
                    isGroup: isGroup,
                    groupName: group?.name,
                    groupMembers: isGroup && group != null
                        ? group.personaIds
                              .map((id) => state.personaById(id))
                              .whereType<Persona>()
                              .toList()
                        : [],
                    userName: state.userProfile.name,
                    userAvatarPath: state.userProfile.avatarPath,
                    onLongPressMember: _insertMention,
                  )
                : ListView.builder(
                    key: ValueKey(session.id),
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    // 增加 cacheExtent 让滚动更流畅，预渲染更多项
                    cacheExtent: 160,
                    itemCount: session.messages.length,
                    itemBuilder: (context, i) {
                      final originalIndex = session.messages.length - 1 - i;
                      final msg = session.messages[originalIndex];
                      final isAI = msg.role == 'assistant';
                      final playEntrance =
                          isAI &&
                          (_pendingEntranceIds.contains(msg.id) ||
                              !_knownMessageIds.contains(msg.id));
                      return RepaintBoundary(
                        key: ValueKey(msg.id),
                        child: Column(
                          children: [
                            if (messageTimeAnchorIds.contains(msg.id))
                              _MessageTimeDivider(time: msg.timestamp),
                            _MessageBlock(
                              message: msg,
                              persona: persona,
                              isGroup: isGroup,
                              speaker: isGroup
                                  ? state.personaById(msg.speakerId)
                                  : null,
                              isStreaming: msg.isStreaming,
                              isSegmented: msg.isSegmented,
                              playEntrance: playEntrance,
                              markdownStyleSheet: markdownStyleSheet,
                              userAvatarPath: state.userProfile.avatarPath,
                              userName: state.userProfile.name,
                              onLongPressSpeaker: isGroup
                                  ? (speaker) => _insertMention(speaker)
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          _InputArea(
            controller: _input,
            focusNode: _focusNode,
            onSend: _send,
            onStop: () => context.read<AppState>().stopGeneration(),
            isSending: state.isSending,
            isGroup: isGroup,
            mentionCandidates: isGroup && group != null && _mentionQuery != null
                ? group.personaIds
                      .map((id) => state.personaById(id))
                      .whereType<Persona>()
                      .where(
                        (p) => p.name.toLowerCase().contains(
                          _mentionQuery!.toLowerCase(),
                        ),
                      )
                      .toList()
                : const [],
            mentionQuery: _mentionQuery,
            onSelectCandidate: _selectCandidate,
          ),
        ],
      ),
    );
  }
}

/// 底部输入区
class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool isSending;
  final bool isGroup;
  final List<Persona> mentionCandidates;
  final String? mentionQuery;
  final ValueChanged<Persona> onSelectCandidate;

  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onStop,
    required this.isSending,
    required this.isGroup,
    required this.mentionCandidates,
    required this.mentionQuery,
    required this.onSelectCandidate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSend = controller.text.trim().isNotEmpty;
    const hintText = '输入消息…';
    final showCandidates =
        isGroup && mentionQuery != null && mentionCandidates.isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 候选角色浮层（直接显隐，避免 AnimatedSize 不可打断）
            if (showCandidates)
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: mentionCandidates.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: scheme.outlineVariant),
                  itemBuilder: (_, i) {
                    final p = mentionCandidates[i];
                    return InkWell(
                      onTap: () => onSelectCandidate(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            PersonaAvatar(persona: p, radius: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.alternate_email_rounded,
                              size: 16,
                              color: scheme.outline,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(color: scheme.outline),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 发送按钮：保持常态展示
                  AnimatedOpacity(
                    opacity: canSend ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: !canSend,
                      child: Material(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: onSend,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.arrow_upward_rounded,
                              size: 20,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final Persona? persona;
  final bool isGroup;
  final String? groupName;
  final List<Persona> groupMembers;
  final String userName;
  final String userAvatarPath;
  final ValueChanged<Persona>? onLongPressMember;

  const _WelcomeView({
    this.persona,
    this.isGroup = false,
    this.groupName,
    this.groupMembers = const [],
    this.userName = '我',
    this.userAvatarPath = '',
    this.onLongPressMember,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isGroup) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WelcomeGroupAvatar(
                members: groupMembers,
                userName: userName,
                userAvatarPath: userAvatarPath,
                onLongPressMember: onLongPressMember,
              ),
              const SizedBox(height: 18),
              Text(
                groupName ?? '群聊',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${groupMembers.length + 1} 位成员',
                style: TextStyle(fontSize: 14, color: scheme.outline),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '群聊使用说明',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _GuideLine(
                      icon: Icons.alternate_email_rounded,
                      text: '长按成员头像，可以快速 @ 对方',
                    ),
                    const SizedBox(height: 8),
                    const _GuideLine(
                      icon: Icons.reply_rounded,
                      text: '被 @ 的人格才会参与回复',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PersonaAvatar(persona: persona, radius: 44, fallbackEmoji: '💬'),
          const SizedBox(height: 18),
          Text(
            persona == null ? '有什么可以帮你的？' : '与「${persona!.name}」聊聊吧',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '输入消息开始对话',
            style: TextStyle(fontSize: 14, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _GuideLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _GuideLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _WelcomeGroupAvatar extends StatelessWidget {
  final List<Persona> members;
  final String userName;
  final String userAvatarPath;
  final ValueChanged<Persona>? onLongPressMember;

  const _WelcomeGroupAvatar({
    required this.members,
    required this.userName,
    required this.userAvatarPath,
    required this.onLongPressMember,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = members.take(8).toList();
    final people = <Widget>[
      _UserAvatarSmall(path: userAvatarPath, name: userName),
      ...visible.map(
        (persona) => GestureDetector(
          onLongPress: () => onLongPressMember?.call(persona),
          child: _PersonaGroupAvatar(
            persona: persona,
            radius: 19,
            borderColor: scheme.surface,
          ),
        ),
      ),
    ];
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: people,
      ),
    );
  }
}

/// 消息块
class _MessageBlock extends StatelessWidget {
  final ChatMessage message;
  final Persona? persona;
  final bool isGroup;
  final Persona? speaker;
  final bool isStreaming;
  final bool isSegmented;
  final bool playEntrance;
  final MarkdownStyleSheet markdownStyleSheet;
  final String? userAvatarPath;
  final String? userName;
  final ValueChanged<Persona>? onLongPressSpeaker;

  const _MessageBlock({
    required this.message,
    this.persona,
    this.isGroup = false,
    this.speaker,
    this.isStreaming = false,
    this.isSegmented = false,
    this.playEntrance = false,
    required this.markdownStyleSheet,
    this.userAvatarPath,
    this.userName,
    this.onLongPressSpeaker,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final isTool = message.role == 'tool';
    final sticker = context.read<AppState>().stickerById(message.stickerId);
    final stickerUnavailable = message.stickerId != null && sticker == null;

    if (isTool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          elevation: 0,
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ExpansionTile(
            dense: true,
            shape: const Border(),
            leading: Icon(
              Icons.build_circle_outlined,
              size: 18,
              color: scheme.tertiary,
            ),
            title: Text(
              '工具调用：${message.toolName ?? ''}',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.tertiary),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    message.content,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, top: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.74,
                    ),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        height: 1.4,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _UserAvatarSmall(path: userAvatarPath ?? '', name: userName ?? '我'),
          ],
        ),
      );
    }

    // AI 消息
    final displayPersona = isGroup ? speaker : persona;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: displayPersona == null
                ? null
                : () => Navigator.push(
                    context,
                    FastRoute(
                      builder: (_) =>
                          PersonaEditorPage(persona: displayPersona),
                    ),
                  ),
            onLongPress: displayPersona == null
                ? null
                : () => onLongPressSpeaker?.call(displayPersona),
            child: PersonaAvatar(persona: displayPersona, radius: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isGroup && speaker != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      speaker!.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                _SegmentedBubble(
                  key: ValueKey(message.id),
                  enabled:
                      playEntrance ||
                      (isSegmented &&
                          (message.content.isNotEmpty ||
                              sticker != null ||
                              stickerUnavailable)),
                  emphasis: isSegmented,
                  child: sticker != null
                      ? ChatImagePreview(
                          filePath: sticker.filePath,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 72,
                                minHeight: 72,
                                maxWidth: 160,
                                maxHeight: 160,
                              ),
                              child: Image.file(
                                File(sticker.filePath),
                                fit: BoxFit.contain,
                                cacheWidth: 480,
                                errorBuilder: (_, __, ___) =>
                                    const StickerUnavailablePlaceholder(),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(20),
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                          ),
                          child: stickerUnavailable
                              ? const StickerUnavailablePlaceholder()
                              : isStreaming && message.content.isEmpty
                              ? _TypingDots(color: scheme.primary)
                              : _StreamingMarkdown(
                                  content: message.content,
                                  active: isStreaming && !isSegmented,
                                  child: StickerMessageBody(
                                    content: message.content,
                                    personaId: displayPersona?.id,
                                    styleSheet: markdownStyleSheet,
                                  ),
                                ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingMarkdown extends StatelessWidget {
  final String content;
  final bool active;
  final Widget child;

  const _StreamingMarkdown({
    required this.content,
    required this.active,
    required this.child,
  });

  @override
  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// 气泡出现动画：在 widget 首次创建时播一次入场。
/// - `enabled=false`：完全不播（历史消息或非新追加消息）
/// - `enabled=true` + `emphasis=true`（分段态）：更明显的淡入 + 上移 + 缩放
/// - `enabled=true` + `emphasis=false`（普通流式/新追加）：更轻快的淡入 + 微上移
class _SegmentedBubble extends StatefulWidget {
  final bool enabled;
  final bool emphasis;
  final Widget child;
  const _SegmentedBubble({
    super.key,
    required this.enabled,
    this.emphasis = false,
    required this.child,
  });

  @override
  State<_SegmentedBubble> createState() => _SegmentedBubbleState();
}

class _SegmentedBubbleState extends State<_SegmentedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.emphasis ? 330 : 280),
  );
  late final Animation<double> _curve = _controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  late final Animation<double> _fade = _controller
      .drive(
        CurveTween(curve: const Interval(0.0, 0.62, curve: Curves.easeOut)),
      )
      .drive(Tween<double>(begin: 0.0, end: 1.0));
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(widget.emphasis ? -0.008 : 0, widget.emphasis ? 0.045 : 0.02),
    end: Offset.zero,
  ).animate(_curve);
  late final Animation<double> _scale = Tween<double>(
    begin: widget.emphasis ? 0.98 : 0.99,
    end: 1.0,
  ).animate(_curve);

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _SegmentedBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.topLeft,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 加载中的三个跳动圆点（AI 正在思考）
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              final t = (_controller.value + i * 0.18) % 1.0;
              final phase = (t * 2 * pi);
              final scale = 0.55 + 0.45 * (0.5 + 0.5 * sin(phase));
              final alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: alpha),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 群聊小头像（用于顶栏）
class _MiniGroupAvatar extends StatelessWidget {
  final GroupChat group;
  final double size;
  const _MiniGroupAvatar({required this.group, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final radius = size / 2;

    if (group.avatarPath.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundImage: FileImage(File(group.avatarPath)),
        onForegroundImageError: (_, __) {},
        child: Icon(
          Icons.group_rounded,
          size: radius,
          color: scheme.onPrimaryContainer,
        ),
      );
    }
    final members = group.personaIds
        .map((id) => state.personaById(id))
        .whereType<Persona>()
        .take(3)
        .toList();
    if (members.isEmpty) {
      return _UserGroupAvatar(
        profile: state.userProfile,
        radius: radius,
        borderColor: scheme.surface,
      );
    }
    return _ChatGroupAvatarGrid(
      size: size,
      members: members,
      profile: state.userProfile,
    );
  }
}

/// 群聊小头像（用于信息面板）
class _GroupAvatarSmall extends StatelessWidget {
  final GroupChat group;
  const _GroupAvatarSmall({required this.group});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = group.personaIds
        .map((id) => state.personaById(id))
        .whereType<Persona>()
        .take(3)
        .toList();
    if (members.isEmpty) {
      return _UserGroupAvatar(
        profile: state.userProfile,
        radius: 32,
        borderColor: Theme.of(context).colorScheme.surface,
      );
    }
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          if (members.length + 1 == 3)
            for (int i = 0; i < members.length; i++)
              Positioned(
                left: i == 0 ? 10 : 34,
                top: 34,
                child: _PersonaGroupAvatar(
                  persona: members[i],
                  radius: 13,
                  borderColor: Theme.of(context).colorScheme.surface,
                ),
              ),
          if (members.length + 1 == 2)
            Positioned(
              left: 10,
              top: 8,
              child: _PersonaGroupAvatar(
                persona: members.first,
                radius: 15,
                borderColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          if (members.length + 1 == 4)
            for (int i = 0; i < members.length; i++)
              Positioned(
                left: i % 2 == 0 ? 5 : 35,
                top: i < 2 ? 5 : 35,
                child: _PersonaGroupAvatar(
                  persona: members[i],
                  radius: 13,
                  borderColor: Theme.of(context).colorScheme.surface,
                ),
              ),
          Positioned(
            left: members.length + 1 == 3
                ? 22
                : (members.length + 1 == 4 ? 35 : 35),
            top: members.length + 1 == 3
                ? 5
                : (members.length + 1 == 4 ? 35 : 35),
            child: _UserGroupAvatar(
              profile: state.userProfile,
              radius: members.length + 1 == 4 ? 13 : 15,
              borderColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatGroupAvatarGrid extends StatelessWidget {
  final double size;
  final List<Persona> members;
  final UserProfile profile;

  const _ChatGroupAvatarGrid({
    required this.size,
    required this.members,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = (members.length + 1).clamp(1, 4).toInt();
    final radius = size * (total == 3 ? 0.19 : 0.18);
    final centers = total == 3
        ? [
            Offset(size * .5, size * .22),
            Offset(size * .25, size * .72),
            Offset(size * .75, size * .72),
          ]
        : [
            Offset(size * .25, size * .25),
            Offset(size * .75, size * .25),
            Offset(size * .25, size * .75),
            Offset(size * .75, size * .75),
          ];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < total; i++)
            Positioned(
              left: centers[i].dx - radius,
              top: centers[i].dy - radius,
              child: i == 0
                  ? _UserGroupAvatar(
                      profile: profile,
                      radius: radius,
                      borderColor: scheme.surface,
                    )
                  : _PersonaGroupAvatar(
                      persona: members[i - 1],
                      radius: radius,
                      borderColor: scheme.surface,
                    ),
            ),
        ],
      ),
    );
  }
}

class _PersonaGroupAvatar extends StatelessWidget {
  final Persona persona;
  final double radius;
  final Color borderColor;

  const _PersonaGroupAvatar({
    required this.persona,
    required this.radius,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: PersonaAvatar(persona: persona, radius: radius),
    );
  }
}

class _UserGroupAvatar extends StatelessWidget {
  final UserProfile profile;
  final double radius;
  final Color borderColor;

  const _UserGroupAvatar({
    required this.profile,
    required this.radius,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = profile.avatarPath;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: path.isNotEmpty && File(path).existsSync()
          ? CircleAvatar(radius: radius, backgroundImage: FileImage(File(path)))
          : CircleAvatar(
              radius: radius,
              backgroundColor: scheme.secondaryContainer,
              child: Text(
                profile.name.isEmpty ? '我' : profile.name.characters.first,
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: radius * 0.72,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

/// 用户小头像
class _UserAvatarSmall extends StatelessWidget {
  final String path;
  final String name;
  const _UserAvatarSmall({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (path.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: scheme.secondaryContainer,
        foregroundImage: FileImage(File(path)),
        onForegroundImageError: (_, __) {},
        child: Text(
          name.isEmpty ? '我' : name.characters.first,
          style: TextStyle(fontSize: 14, color: scheme.onSecondaryContainer),
        ),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        name.isEmpty ? '我' : name.characters.first,
        style: TextStyle(fontSize: 14, color: scheme.onSecondaryContainer),
      ),
    );
  }
}
