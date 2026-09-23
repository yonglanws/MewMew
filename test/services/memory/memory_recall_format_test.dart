import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/memory/memory_recall_format.dart';

MemoryEntry _memory({
  String id = 'm1',
  String content = '张三提醒明天开会',
  String personaSummary = '',
  List<String> topics = const [],
  List<String> keyFacts = const [],
  List<String> participants = const [],
  double importance = 0.8,
  String status = 'active',
}) => MemoryEntry(
  id: id,
  content: content,
  createdAt: DateTime(2025, 11, 19, 14, 30),
  importance: importance,
  personaSummary: personaSummary,
  topics: topics,
  keyFacts: keyFacts,
  participants: participants,
  status: status,
);

void main() {
  group('注入格式化', () {
    test('包装标签 + 头尾模板 + 编号条目', () {
      final block = formatMemoriesForInjection(
        memories: [_memory(personaSummary: '张三提醒我开会')],
        atomsOf: (_) => const [],
        atomPolicyEnabled: false,
      );
      expect(block, startsWith('<RAG-Faiss-Memory>'));
      expect(block, endsWith('</RAG-Faiss-Memory>'));
      expect(block, contains('BEGIN HISTORICAL MEMORY REFERENCE'));
      expect(block, contains('END REMINDER'));
      expect(block, contains('记忆 #1'));
      expect(block, contains('重要性: 0.80'));
      expect(block, contains('张三提醒我开会')); // personaSummary 优先展示
    });

    test('元数据行：主题/参与者/关键事实/来源时间', () {
      final block = formatMemoriesForInjection(
        memories: [
          _memory(topics: ['会议'], participants: ['张三'], keyFacts: ['明天开会']),
        ],
        atomsOf: (_) => const [],
        atomPolicyEnabled: false,
      );
      expect(block, contains('主题: 会议'));
      expect(block, contains('参与者: 张三'));
      expect(block, contains('关键事实: 明天开会'));
    });

    test('原子策略：有原子时展示原子事实', () {
      final memory = _memory(content: '整段摘要', keyFacts: const []);
      final atoms = [
        MemoryAtom(
          id: 'a1',
          parentMemoryId: memory.id,
          content: '事实A',
          createdAt: DateTime(2025, 11, 19),
          ttlDays: 30,
          expiresAt: DateTime(2025, 12, 19),
        ),
        MemoryAtom(
          id: 'a2',
          parentMemoryId: memory.id,
          content: '事实B',
          createdAt: DateTime(2025, 11, 19),
          ttlDays: 1,
          expiresAt: DateTime(2025, 11, 15), // 已过期
          status: AtomStatus.expired,
        ),
      ];
      final block = formatMemoriesForInjection(
        memories: [memory],
        atomsOf: (_) => atoms,
        atomPolicyEnabled: true,
        now: DateTime(2025, 11, 20),
      );
      expect(block, contains('事实A'));
      expect(block, isNot(contains('事实B')));
      expect(block, isNot(contains('整段摘要')));
    });

    test('原子策略：全部原子失效的记忆整条不注入', () {
      final memory = _memory(keyFacts: ['事实']);
      final atoms = [
        MemoryAtom(
          id: 'a1',
          parentMemoryId: memory.id,
          content: '事实',
          createdAt: DateTime(2025, 11, 1),
          ttlDays: 1,
          expiresAt: DateTime(2025, 11, 2),
          status: AtomStatus.expired,
        ),
      ];
      final block = formatMemoriesForInjection(
        memories: [memory],
        atomsOf: (_) => atoms,
        atomPolicyEnabled: true,
        now: DateTime(2025, 11, 20),
      );
      expect(block, isEmpty);
    });

    test('归档记忆可通过手动传入出现（由检索层过滤，此处不重复过滤）', () {
      final block = formatMemoriesForInjection(
        memories: [_memory(status: 'archived')],
        atomsOf: (_) => const [],
        atomPolicyEnabled: false,
      );
      expect(block, isNotEmpty);
    });
  });

  group('注入剥离', () {
    test('剥离新格式 RAG 块', () {
      final messages = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content':
              '<RAG-Faiss-Memory>\n头\n\n记忆 #1\n内容\n\n尾\n</RAG-Faiss-Memory>\n你好',
        },
      ];
      expect(stripInjectedMemories(messages), isTrue);
      expect(messages.first['content'], '你好');
    });

    test('剥离旧格式【长期记忆】块', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': '【长期记忆】\n- 旧记忆\n今天天气如何'},
      ];
      expect(stripInjectedMemories(messages), isTrue);
      expect(messages.first['content'], contains('今天天气如何'));
      expect(messages.first['content'], isNot(contains('【长期记忆】')));
    });

    test('无注入块时返回 false', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': '普通消息'},
      ];
      expect(stripInjectedMemories(messages), isFalse);
    });
  });
}
