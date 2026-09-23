/// 记忆注入格式化（移植自 LivingMemory core/utils/formatting.py +
/// constants.py 的包装约定 + engine 的原子注入策略）。
library;

import 'package:characters/characters.dart';

import '../../models/models.dart';
import 'memory_prompts.dart';

/// 注入包装标记（照抄原版 `<RAG-Faiss-Memory>` 常量）
const String injectionOpenTag = '<RAG-Faiss-Memory>';
const String injectionCloseTag = '</RAG-Faiss-Memory>';

/// 构建注入块（照抄 format_memories_for_injection）。
///
/// [atomsOf] 提供记忆对应的原子列表；启用原子策略时：
/// - 只注入 active 且未过期的原子事实
/// - 拥有原子的记忆若全部原子失效，整条不注入
/// 展示内容优先 personaSummary（人格口吻）。
String formatMemoriesForInjection({
  required List<MemoryEntry> memories,
  required List<MemoryAtom> Function(MemoryEntry) atomsOf,
  required bool atomPolicyEnabled,
  DateTime? now,
  bool includeMetadataRow = true,
}) {
  final current = now ?? DateTime.now();
  final blocks = <String>[];
  var index = 0;

  for (final m in memories) {
    final atoms = atomsOf(m);
    String displayContent;

    if (atomPolicyEnabled && atoms.isNotEmpty) {
      final live = atoms
          .where((a) => a.status == AtomStatus.active && !a.isExpired(current))
          .map((a) => a.content)
          .toSet()
          .toList();
      if (live.isEmpty) continue; // 全部原子失效 → 整条不注入
      displayContent = live.join('\n');
    } else {
      displayContent = m.displayContent;
    }

    index++;
    final buf = StringBuffer();
    buf.write('记忆 #$index');
    final imp = m.importance.toStringAsFixed(2);
    final timeStr =
        '${m.createdAt.year.toString().padLeft(4, '0')}-${m.createdAt.month.toString().padLeft(2, '0')}-${m.createdAt.day.toString().padLeft(2, '0')} ${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
    buf.write('（重要性: $imp），写入时间: $timeStr');

    if (includeMetadataRow) {
      final metaParts = <String>[];
      if (m.topics.isNotEmpty) metaParts.add('主题: ${m.topics.join('、')}');
      if (m.participants.isNotEmpty) {
        metaParts.add('参与者: ${m.participants.join('、')}');
      }
      if (m.keyFacts.isNotEmpty)
        metaParts.add('关键事实: ${m.keyFacts.join('; ')}');
      if (m.sourceTimeLabel != null && m.sourceTimeLabel!.isNotEmpty) {
        metaParts.add('来源时间: ${m.sourceTimeLabel}');
      }
      if (metaParts.isNotEmpty) {
        buf.write('\n${metaParts.join(' | ')}');
      }
    }
    buf.write('\n$displayContent');
    blocks.add(buf.toString());
  }

  if (blocks.isEmpty) return '';
  final body = blocks.join('\n\n');
  return '$injectionOpenTag\n$memoryInjectionHeader\n\n$body\n\n$memoryInjectionFooter\n$injectionCloseTag';
}

/// 从历史 API 消息中剥离已注入的记忆块：
/// 新格式 `<RAG-Faiss-Memory>...</RAG-Faiss-Memory>` 与旧格式【长期记忆】块。
final RegExp _ragBlockPattern = RegExp(
  r'<RAG-Faiss-Memory>[\s\S]*?</RAG-Faiss-Memory>',
);
final RegExp _legacyMemoryPattern = RegExp(r'【长期记忆】[\s\S]*?(?=\n\S|\n*$|$)');
final RegExp _legacyTrailingPattern = RegExp(r'\n?【长期记忆】[\s\S]*$');
final RegExp _excessNewlinesPattern = RegExp(r'\n{3,}');

/// 剥离并返回是否发生了修改
bool stripInjectedMemories(List<Map<String, dynamic>> apiMessages) {
  var changed = false;
  for (var i = 0; i < apiMessages.length; i++) {
    final msg = apiMessages[i];
    if (msg['role'] != 'user') continue;
    final content = msg['content'];
    if (content is! String) continue;
    if (!content.contains(injectionOpenTag) && !content.contains('【长期记忆】')) {
      continue;
    }
    var cleaned = content.replaceAll(_ragBlockPattern, '');
    cleaned = cleaned.replaceAll(_legacyMemoryPattern, '');
    cleaned = cleaned.replaceAll(_legacyTrailingPattern, '');
    cleaned = cleaned.replaceAll(_excessNewlinesPattern, '\n\n').trim();
    if (cleaned != content) {
      apiMessages[i] = {'role': 'user', 'content': cleaned};
      changed = true;
    }
  }
  return changed;
}

/// 截断到字符数上限（按 grapheme 计，避免截断 emoji）
String truncateByChars(String text, int maxChars) {
  if (text.characters.length <= maxChars) return text;
  return text.characters.take(maxChars).toString();
}
