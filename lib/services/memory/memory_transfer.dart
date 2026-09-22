/// 记忆导入导出（移植自 LivingMemory core/memory_transfer.py 的 JSON 信封）。
library;

import 'dart:convert';

import '../../models/models.dart';

/// 导出为 JSON 字符串（格式兼容原版信封的字段命名习惯）
String exportMemoriesJson({
  required List<MemoryEntry> memories,
  required List<MemoryAtom> atoms,
}) {
  final envelope = {
    'format': 'mewmew-memory',
    'compatibleFormat': 'livingmemory',
    'schemaVersion': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'memoryCount': memories.length,
    'memories': memories.map((m) => m.toJson()).toList(),
    'atoms': atoms.map((a) => a.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(envelope);
}

/// 导入结果
class ImportReport {
  final int imported;
  final int skipped; // 重复或无效
  final List<MemoryEntry> newMemories;
  final List<MemoryAtom> newAtoms;

  const ImportReport({
    required this.imported,
    required this.skipped,
    required this.newMemories,
    required this.newAtoms,
  });
}

/// 导入（去重键 = 归一化内容 + session + persona；上限 10000 条）
ImportReport importMemoriesJson(
  String raw, {
  required List<MemoryEntry> existingMemories,
  String Function(String content, String? sessionId, String? personaId)?
      newIdGenerator,
}) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('导入文件不是有效的记忆信封');
  }
  final list = decoded['memories'];
  if (list is! List) throw const FormatException('信封缺少 memories 数组');
  if (list.length > 10000) throw const FormatException('单次导入上限 10000 条');

  String newId() => newIdGenerator != null
      ? newIdGenerator('', null, null)
      : DateTime.now().microsecondsSinceEpoch.toString();

  final existingKeys = <String>{
    for (final m in existingMemories)
      '${_normalizeKey(m.content)}|${m.sessionId ?? ''}|${m.personaId ?? ''}',
  };

  final newMemories = <MemoryEntry>[];
  var skipped = 0;
  for (final item in list) {
    if (item is! Map<String, dynamic>) {
      skipped++;
      continue;
    }
    final content = (item['content'] ?? item['summary'] ?? item['text'] ?? '')
        .toString()
        .trim();
    if (content.isEmpty) {
      skipped++;
      continue;
    }
    final key =
        '${_normalizeKey(content)}|${item['sessionId'] ?? ''}|${item['personaId'] ?? ''}';
    if (existingKeys.contains(key)) {
      skipped++;
      continue;
    }
    existingKeys.add(key);
    // 重新生成 id，避免与现有数据冲突；外来格式补齐必需字段
    item['id'] = newId();
    if (item['createdAt'] == null) {
      item['createdAt'] = DateTime.now().toIso8601String();
    }
    newMemories.add(MemoryEntry.fromJson(item));
  }
  return ImportReport(
    imported: newMemories.length,
    skipped: skipped,
    newMemories: newMemories,
    newAtoms: const [],
  );
}

String _normalizeKey(String content) {
  return content.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
