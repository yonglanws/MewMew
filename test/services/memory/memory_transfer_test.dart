import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/memory_transfer.dart';

void main() {
  group('导出', () {
    test('信封包含格式标记与条目', () {
      final json = exportMemoriesJson(
        memories: [
          MemoryEntry(
            id: 'm1',
            content: '内容',
            createdAt: DateTime(2025, 11, 19),
            importance: 0.7,
          ),
        ],
        atoms: const [],
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], 'mewmew-memory');
      expect(decoded['compatibleFormat'], 'livingmemory');
      expect(decoded['memoryCount'], 1);
      expect((decoded['memories'] as List).length, 1);
    });
  });

  group('导入', () {
    test('去重：相同内容+会话+人格跳过', () {
      final existing = [
        MemoryEntry(
          id: 'existing',
          content: '用户喜欢猫',
          createdAt: DateTime(2025, 11, 19),
          sessionId: 's1',
        ),
      ];
      final raw = jsonEncode({
        'memories': [
          {
            'id': 'x1',
            'content': '用户喜欢猫',
            'createdAt': DateTime(2025, 11, 19).toIso8601String(),
            'sessionId': 's1',
          },
          {
            'id': 'x2',
            'content': '用户喜欢狗',
            'createdAt': DateTime(2025, 11, 19).toIso8601String(),
            'sessionId': 's1',
          },
        ],
      });
      final report = importMemoriesJson(raw, existingMemories: existing);
      expect(report.imported, 1);
      expect(report.skipped, 1);
      expect(report.newMemories.first.content, '用户喜欢狗');
    });

    test('外来格式（缺 createdAt）自动补齐', () {
      final raw = jsonEncode({
        'memories': [
          {'content': '外来记忆'},
        ],
      });
      final report = importMemoriesJson(raw, existingMemories: const []);
      expect(report.imported, 1);
      expect(report.newMemories.first.createdAt, isNotNull);
    });

    test('非信封内容抛 FormatException', () {
      expect(
        () => importMemoriesJson('不是 JSON', existingMemories: const []),
        throwsFormatException,
      );
    });

    test('空内容条目跳过', () {
      final raw = jsonEncode({
        'memories': [
          {'id': 'a', 'content': ''},
          {'id': 'b'},
        ],
      });
      final report = importMemoriesJson(raw, existingMemories: const []);
      expect(report.imported, 0);
      expect(report.skipped, 2);
    });
  });
}
