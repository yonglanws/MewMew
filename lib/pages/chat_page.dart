import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min, pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ClipRectLayer, LayerHandle, PaintingContext, RenderAligningShiftedBox;
import 'package:flutter/scheduler.dart' show Ticker;
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

/// 气泡伸展与跟随滚动共用的恒定像素速度：距离越长动画越久，
/// 保证不同高度的消息把列表顶上去的视觉速度一致。
const double _kMorphPxPerMs = 0.65;
const Duration _kMinSizeMorphDuration = Duration(milliseconds: 180);
const Duration _kMaxSizeMorphDuration = Duration(milliseconds: 460);
// 跟随滚动的最短时长：太短时 easeOutCubic 的减速尾巴感知不到，
// 会显得生硬；长距离仍按恒速 0.65px/ms 线性拉长。
const Duration _kMinScrollDuration = Duration(milliseconds: 260);
const Duration _kMaxScrollDuration = Duration(milliseconds: 460);

/// 新气泡第一次布局的高度种子：列表高度从这里长到真实值，
/// 绘制时按高度比例等比缩放整个气泡，中间态始终是完整的迷你对话框。
const double _kEntranceSeedHeight = 40;

Duration _speedDuration(double distancePx, Duration min, Duration max) {
  final ms = (distancePx / _kMorphPxPerMs).round();
  final clamped = ms.clamp(min.inMilliseconds, max.inMilliseconds);
  return Duration(milliseconds: clamped);
}

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

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  AppState? _appState;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();
  final List<_MentionToken> _mentionTokens = [];
  String? _mentionQuery; // 非 null 表示正在 @ 检索中
  int _mentionStart = -1; // @ 起始偏移
  TextEditingValue _previousInput = TextEditingValue.empty;
  bool _applyingMentionEdit = false;
  bool _scrollScheduled = false;
  bool _scrollAnimating = false;
  bool _followBottom = true;
  String? _followSessionId;
  int _lastMsgCount = 0;
  int _lastContentLen = 0;
  // 已"已知"的消息 id 集合：用于区分"首屏历史消息"与"运行时新追加的消息"，
  // 仅对后者播放入场动画，避免首屏满屏闪。
  final Set<String> _knownMessageIds = {};
  final Set<String> _pendingEntranceIds = {};
  final Map<String, Timer> _entranceTimers = {};
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState ??= context.read<AppState>();
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
    _appState?.resumeMergeTimerForTyping();
    _input.dispose();
    _scroll.removeListener(_onScrollChanged);
    _scroll.dispose();
    _focusNode.dispose();
    for (final timer in _entranceTimers.values) {
      timer.cancel();
    }
    _entranceTimers.clear();
    super.dispose();
  }

  /// 跟随滚动到底部：按剩余距离以恒定像素速度滚动，
  /// 动画进行中不重启，避免流式期间反复从头缓入。
  void _scrollToBottom({bool settle = true}) {
    if (_scrollAnimating || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients || _scrollAnimating) return;
      if (!_followBottom) return;
      final distance = _scroll.position.pixels;
      if (distance <= 1) return;
      _scrollAnimating = true;
      _scroll
          .animateTo(
            0,
            duration: _speedDuration(
              distance,
              _kMinScrollDuration,
              _kMaxScrollDuration,
            ),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            _scrollAnimating = false;
            if (!mounted ||
                !settle ||
                !_followBottom ||
                !_scroll.hasClients ||
                _scroll.position.pixels <= 1) {
              return;
            }
            Future<void>.delayed(const Duration(milliseconds: 80), () {
              if (!mounted ||
                  !_followBottom ||
                  !_scroll.hasClients ||
                  _scroll.position.pixels <= 1) {
                return;
              }
              _scrollToBottom(settle: false);
            });
          });
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
        _scrollToBottom();
      }
    } else if (state.isSending && lastLen != _lastContentLen) {
      _lastContentLen = lastLen;
      if (_followBottom) {
        _scrollToBottom();
      }
    }
  }

  /// Keep a newly appended message in its entrance phase long enough for the
  /// slower bubble and scroll animations to be visible.
  void _holdEntranceAnimation(String messageId) {
    _entranceTimers[messageId]?.cancel();
    _entranceTimers[messageId] = Timer(const Duration(milliseconds: 720), () {
      _entranceTimers.remove(messageId);
      if (!mounted) return;
      _pendingEntranceIds.remove(messageId);
      _knownMessageIds.add(messageId);
      setState(() {});
    });
  }

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
      for (final timer in _entranceTimers.values) {
        timer.cancel();
      }
      _entranceTimers.clear();
      _pendingEntranceIds.clear();
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
      for (final id in _entranceTimers.keys.toList()) {
        if (!currentIds.contains(id)) {
          _entranceTimers.remove(id)?.cancel();
          _pendingEntranceIds.remove(id);
        }
      }
      for (final message in messages) {
        if (!_knownMessageIds.contains(message.id) &&
            !_pendingEntranceIds.contains(message.id)) {
          if (message.role == 'assistant' || message.role == 'user') {
            _pendingEntranceIds.add(message.id);
            _holdEntranceAnimation(message.id);
          } else {
            _knownMessageIds.add(message.id);
          }
        }
      }
      if (messages.length != _knownMessageCount) {
        _knownMessageCount = messages.length;
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
                      final canAnimateEntrance =
                          msg.role == 'assistant' || msg.role == 'user';
                      final playEntrance =
                          canAnimateEntrance &&
                          (_pendingEntranceIds.contains(msg.id) ||
                              !_knownMessageIds.contains(msg.id));
                      return RepaintBoundary(
                        key: ValueKey(msg.id),
                        child: Column(
                          children: [
                            if (messageTimeAnchorIds.contains(msg.id))
                              _EntranceFade(
                                enabled: playEntrance,
                                child: _MessageTimeDivider(time: msg.timestamp),
                              ),
                            // 行级入场：整条消息（含内边距）从几像素匀速长开。
                            // 没有它，新条目会以种子高度瞬间插入，列表内容
                            // 先瞬跳一下再平滑生长——这就是发送/接收时的闪。
                            // 入场结束后组件常驻，只翻 enabled，避免子树重挂载。
                            _SpeedAnimatedSize(
                              key: ValueKey('row-entrance-${msg.id}'),
                              vsync: this,
                              enabled: playEntrance,
                              seedHeight: 6,
                              alignment: msg.role == 'user'
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft,
                              child: _MessageBlock(
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
            AnimatedSize(
              // 发送后输入框从多行塌回单行；不加缓动会让列表视口
              // 一帧内变高，内容全体跳一下（发送时"闪一下"的来源）。
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: Container(
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
    final isLoading =
        isStreaming &&
        message.content.isEmpty &&
        sticker == null &&
        !stickerUnavailable;

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
      final userBubbleMaxWidth = MediaQuery.of(context).size.width * 0.74;
      Widget userBubble(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
        ),
        constraints: BoxConstraints(maxWidth: userBubbleMaxWidth),
        child: child,
      );
      final userTextStyle = TextStyle(
        color: scheme.onPrimary,
        height: 1.4,
        fontSize: 15,
      );
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
                  _BubbleSizeMorph(
                    key: ValueKey('bubble-morph-${message.id}'),
                    animationId: message.id,
                    alignment: Alignment.bottomRight,
                    enabled: playEntrance,
                    loadingChild: const SizedBox.shrink(),
                    child: userBubble(
                      SelectableText(message.content, style: userTextStyle),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _AvatarEntrance(
              enabled: playEntrance,
              child: _UserAvatarSmall(
                path: userAvatarPath ?? '',
                name: userName ?? '我',
              ),
            ),
          ],
        ),
      );
    }

    // AI 消息
    final displayPersona = isGroup ? speaker : persona;
    Widget assistantTextBubble(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: child,
    );
    final loadingBubble = assistantTextBubble(
      _TypingDots(color: scheme.primary),
    );
    // 固定占位，避免图片解码完成后再把气泡撑一次。淡入放在
    // frameBuilder 里：解码未就绪时不可见，首帧就绪才开始淡入，
    // 否则图片会以当前透明度瞬间砸出来（概率性闪一下的根源）。
    final imageContent = sticker == null
        ? null
        : ChatImagePreview(
            filePath: sticker.filePath,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 120,
                height: 120,
                child: Image.file(
                  File(sticker.filePath),
                  fit: BoxFit.contain,
                  cacheWidth: 480,
                  frameBuilder: (context, child, frame, wasSync) {
                    // frame == null：还没解出首帧，保持不可见；
                    // wasSync：图在缓存里，直接显示。
                    if (frame == null) return const SizedBox.shrink();
                    if (wasSync) return child;
                    return _EntranceFade(enabled: true, child: child);
                  },
                  errorBuilder: (_, __, ___) =>
                      const StickerUnavailablePlaceholder(),
                ),
              ),
            ),
          );
    // 正文渐变由 _BubbleSizeMorph 在"加载→正文"到达时刻统一处理；
    // 这里不额外包淡入，避免双重淡入拖慢呈现。
    final contentBubble =
        imageContent ??
        assistantTextBubble(
          stickerUnavailable
              ? const StickerUnavailablePlaceholder()
              : _StreamingMarkdown(
                  content: message.content,
                  active: isStreaming && !isSegmented,
                  child: StickerMessageBody(
                    content: message.content,
                    personaId: displayPersona?.id,
                    styleSheet: markdownStyleSheet,
                  ),
                ),
        );
    final messageBubble = _SegmentedBubble(
      key: ValueKey(message.id),
      animationId: message.id,
      enabled:
          playEntrance ||
          (isSegmented &&
              (message.content.isNotEmpty ||
                  sticker != null ||
                  stickerUnavailable)),
      loading: isLoading,
      loadingChild: loadingBubble,
      child: contentBubble,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarEntrance(
            enabled: playEntrance,
            child: GestureDetector(
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
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isGroup && speaker != null)
                  _EntranceFade(
                    enabled: playEntrance,
                    child: Padding(
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
                  ),
                messageBubble,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 尺寸变化时按恒定像素速度插值的 AnimatedSize 替代品。
/// 时长由本次尺寸差计算（clamp 到 [_kMinSizeMorphDuration, _kMaxSizeMorphDuration]），
/// 使高矮不同的气泡伸展速度一致；动画中断时从当前显示尺寸续接新段。
class _SpeedAnimatedSize extends SingleChildRenderObjectWidget {
  const _SpeedAnimatedSize({
    super.key,
    required this.vsync,
    required this.enabled,
    this.seedHeight = _kEntranceSeedHeight,
    this.seedOnMount = true,
    this.alignment = Alignment.topLeft,
    this.clipBehavior = Clip.hardEdge,
    super.child,
  });

  final TickerProvider vsync;
  final bool enabled;
  final double seedHeight;
  final bool seedOnMount;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSpeedAnimatedSize(
      vsync: vsync,
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
      enabled: enabled,
      seedHeight: seedHeight,
      seedOnMount: seedOnMount,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSpeedAnimatedSize renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..enabled = enabled
      ..seedHeight = seedHeight
      ..seedOnMount = seedOnMount
      ..clipBehavior = clipBehavior;
  }
}

class _RenderSpeedAnimatedSize extends RenderAligningShiftedBox {
  _RenderSpeedAnimatedSize({
    required TickerProvider vsync,
    required bool enabled,
    double seedHeight = _kEntranceSeedHeight,
    bool seedOnMount = true,
    super.alignment = Alignment.topLeft,
    super.textDirection,
    Clip clipBehavior = Clip.hardEdge,
  }) : _enabled = enabled,
       _seedHeight = seedHeight,
       _seedOnMount = seedOnMount,
       _clipBehavior = clipBehavior {
    _ticker = vsync.createTicker(_onTick);
  }

  late Ticker _ticker;
  bool _enabled;
  Clip _clipBehavior;
  double _seedHeight;
  bool _seedOnMount;
  bool _initialized = false;
  bool _animating = false;
  bool _hasVisualOverflow = false;
  Size _fromSize = Size.zero;
  Size _targetSize = Size.zero;
  Duration _segmentStart = Duration.zero;
  Duration _segmentDuration = Duration.zero;
  Duration _elapsed = Duration.zero;
  final LayerHandle<ClipRectLayer> _clipRectLayer = LayerHandle<ClipRectLayer>();

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _stopSegment();
    markNeedsLayout();
  }

  set seedHeight(double value) {
    if (_seedHeight == value) return;
    _seedHeight = value;
    markNeedsLayout();
  }

  set seedOnMount(bool value) {
    if (_seedOnMount == value) return;
    _seedOnMount = value;
    markNeedsLayout();
  }

  set clipBehavior(Clip value) {
    if (_clipBehavior == value) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    if (elapsed - _segmentStart >= _segmentDuration) {
      _stopSegment();
    }
    markNeedsLayout();
  }

  void _stopSegment() {
    if (_ticker.isActive) _ticker.stop();
    _animating = false;
  }

  void _beginSegment(Size from, Size target) {
    _fromSize = from;
    _targetSize = target;
    final px = max((target.width - from.width).abs(), (target.height - from.height).abs());
    _segmentDuration = _speedDuration(px, _kMinSizeMorphDuration, _kMaxSizeMorphDuration);
    _segmentStart = _ticker.isActive ? _elapsed : Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    _animating = true;
  }

  double get _progress {
    if (!_animating) return 1.0;
    final t =
        (_elapsed - _segmentStart).inMicroseconds /
        max(_segmentDuration.inMicroseconds, 1);
    return Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  }

  @override
  void performLayout() {
    _hasVisualOverflow = false;
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    final Size desired = constraints.constrain(child.size);

    // 宽度直接落位（横向没有可动画的位移），只有高度参与伸展；
    // 宽度的视觉过渡由 paint 里的等比缩放完成，气泡形状保持完整。
    if (!_initialized) {
      _initialized = true;
      final seedHeight = min(desired.height, _seedHeight);
      if (_seedOnMount && _enabled && desired.height - seedHeight >= 8) {
        _beginSegment(Size(desired.width, seedHeight), desired);
        size = Size(desired.width, seedHeight);
      } else {
        size = desired;
      }
    } else if (!_enabled) {
      _stopSegment();
      size = desired;
    } else if (_animating && desired == _targetSize) {
      size = Size.lerp(_fromSize, _targetSize, _progress)!;
    } else if (desired == size) {
      _stopSegment();
    } else {
      _beginSegment(size, desired);
      size = Size.lerp(_fromSize, _targetSize, 0.0)!;
    }

    _hasVisualOverflow =
        size.width < child.size.width || size.height < child.size.height;
    alignChild();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? child = this.child;
    if (child == null) return;

    // 动画中把气泡按高度比例等比缩小绘制：中间态是形状完整的迷你
    // 对话框（圆角一起缩放），而不是固定圆角被直角裁出的方块。
    final double scale = _animating
        ? (size.height / max(child.size.height, 1.0)).clamp(0.0, 1.0)
        : 1.0;
    if (scale < 0.999) {
      final resolvedAlignment = alignment.resolve(textDirection);
      final anchor = resolvedAlignment.alongSize(size);
      // M(x) = s*x + A*(1-s)：把已按 alignChild 摆位的子气泡绕锚点等比缩放，
      // 对齐角（用户右下 / AI 左上）在动画全程保持钉住。
      final matrix = Matrix4.identity()
        ..translate(anchor.dx * (1 - scale), anchor.dy * (1 - scale))
        ..scale(scale, scale, 1.0);
      _clipRectLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (ctx, off) =>
            ctx.pushTransform(needsCompositing, off, matrix, super.paint),
        clipBehavior: _clipBehavior,
        oldLayer: _clipRectLayer.layer,
      );
      return;
    }

    if (!_hasVisualOverflow || _clipBehavior == Clip.none) {
      _clipRectLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    _clipRectLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      super.paint,
      clipBehavior: _clipBehavior,
      oldLayer: _clipRectLayer.layer,
    );
  }

  @override
  void dispose() {
    _stopSegment();
    _ticker.dispose();
    _clipRectLayer.layer = null;
    super.dispose();
  }
}

class _BubbleSizeMorph extends StatefulWidget {
  final String animationId;
  final bool enabled;
  final bool loading;
  final Alignment alignment;
  final Widget loadingChild;
  final Widget child;

  const _BubbleSizeMorph({
    super.key,
    required this.animationId,
    required this.enabled,
    required this.loadingChild,
    required this.child,
    this.loading = false,
    this.alignment = Alignment.topLeft,
  });

  @override
  State<_BubbleSizeMorph> createState() => _BubbleSizeMorphState();
}

class _BubbleSizeMorphState extends State<_BubbleSizeMorph>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 460);

  bool _sizeMorphActive = false;
  // 正文渐显与入场窗口解耦：只要经历"加载→正文"的到达时刻就淡入，
  // 否则回复超过 720ms 入场窗口时正文会瞬间砸出来（接收时闪一下）。
  bool _revealContent = false;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );
  // 过冲幅度刻意收敛在 0.5% 内：过大会把气泡画出自身槽位，
  // 在屏幕边缘和相邻消息上产生可见的溢出/硬切。
  late final Animation<double> _scaleX = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.975,
        end: 0.995,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.995,
        end: 1.005,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 56,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.005,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 22,
    ),
  ]).animate(_controller);
  late final Animation<double> _scaleY = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.982,
        end: 0.997,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.997,
        end: 1.004,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 56,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.004,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 22,
    ),
  ]).animate(_controller);
  late final Animation<double> _lift = Tween<double>(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _beginInitialPhase();
  }

  @override
  void didUpdateWidget(covariant _BubbleSizeMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _beginInitialPhase();
      return;
    }
    if (widget.loading != oldWidget.loading) {
      _revealContent = !widget.loading;
      if (widget.loading) {
        _continueLoadingMorph();
      } else {
        _startContentMorph();
      }
    }
  }

  void _beginInitialPhase() {
    if (!widget.enabled) {
      _revealContent = false;
      _sizeMorphActive = false;
      _controller.value = 1.0;
      return;
    }

    _revealContent = true;
    _sizeMorphActive = true;
    _controller.value = 0.0;
    _controller.forward();
  }

  void _continueLoadingMorph() {
    _sizeMorphActive = true;
    if (!_controller.isAnimating && _controller.value < 1.0) {
      _controller.forward();
    }
  }

  void _startContentMorph() {
    _sizeMorphActive = true;
    if (!_controller.isAnimating && _controller.value < 1.0) {
      _controller.forward();
    }
  }

  Widget _visibleChild() {
    if (widget.loading) return widget.loadingChild;
    // 打字圆点必须立即出现，不参与淡入；正文一律带透明渐变。
    return _EntranceFade(
      enabled: widget.enabled || _revealContent,
      scaleFrom: 0.92,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return widget.loading ? widget.loadingChild : widget.child;
    }

    // 尺寸组件与缩放层都必须常驻：动画结束时若把内容子树换回裸节点，
    // 子树会被拆掉重建（图片流、选择器状态全丢），正是"动画结束的
    // 瞬间闪一下"的来源。结束后只是控制器停在恒等值，不再有布局开销。
    return _SpeedAnimatedSize(
      key: ValueKey('bubble-morph-size-${widget.animationId}'),
      vsync: this,
      enabled: _sizeMorphActive,
      seedOnMount: false,
      alignment: widget.alignment,
      clipBehavior: Clip.hardEdge,
      child: AnimatedBuilder(
        animation: _controller,
        child: _visibleChild(),
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _lift.value),
          child: Transform(
            key: ValueKey('bubble-morph-transform-${widget.animationId}'),
            alignment: widget.alignment,
            transform: Matrix4.diagonal3Values(
              _scaleX.value,
              _scaleY.value,
              1.0,
            ),
            child: child,
          ),
        ),
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
  Widget build(BuildContext context) {
    return child;
  }
}

/// 文字和表情包共用的入场与尺寸形变。
/// 已经有正文或图片时直接从紧凑尺寸长出来，不再先闪一帧加载圆点。
class _SegmentedBubble extends StatelessWidget {
  final String animationId;
  final bool enabled;
  final bool loading;
  final Widget loadingChild;
  final Widget child;

  const _SegmentedBubble({
    super.key,
    required this.animationId,
    required this.enabled,
    required this.loadingChild,
    required this.child,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return _BubbleSizeMorph(
      key: ValueKey('bubble-morph-$animationId'),
      animationId: animationId,
      enabled: enabled,
      loading: loading,
      loadingChild: loadingChild,
      child: child,
    );
  }
}

/// 入场淡入。用 tween 切换代替子树切换：enabled 翻转只改起点值，
/// 内容子树永远不重建（重建会让图片流、选择器状态丢失，结束时闪一下）。
/// 历史消息从 (1→1) 挂载，无动画；入场结束翻 false 时从当前值续到 1，
/// 不会打断在途的淡入。[scaleFrom] 大于 0 时附带轻微放大。
class _EntranceFade extends StatelessWidget {
  final bool enabled;
  final double scaleFrom;
  final Widget child;

  const _EntranceFade({
    required this.enabled,
    required this.child,
    this.scaleFrom = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final scaled = scaleFrom < 0.999;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: enabled ? 0.0 : 1.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) {
        final t = value.clamp(0.0, 1.0);
        final opacity = Opacity(opacity: t, child: child);
        return scaled
            ? Transform.scale(
                scale: scaleFrom + (1 - scaleFrom) * t,
                child: opacity,
              )
            : opacity;
      },
      child: child,
    );
  }
}

/// 头像入场：淡入 + easeOutBack 轻微过冲放大，与气泡伸展同帧开始。
/// 结构同 [_EntranceFade]：enabled 翻转不重建子树。
class _AvatarEntrance extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _AvatarEntrance({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: enabled ? 0.0 : 1.0, end: 1.0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(
          // easeOutBack 的过冲压到 +3% 以内，避免头像画出消息行。
          scale: 0.62 + 0.38 * Curves.easeOutBack.transform(value.clamp(0, 1)),
          child: child,
        ),
      ),
      child: child,
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
