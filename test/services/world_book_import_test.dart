import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/character_prompt.dart';
import 'package:mewmew/services/world_book_import.dart';

void main() {
  group('世界书导入：酒馆 World Info 格式', () {
    test('标准 ST 导出格式（entries 为对象映射）', () {
      const raw = '''
{
  "entries": {
    "0": {
      "uid": 0,
      "key": ["月见", "高中"],
      "keysecondary": ["祭典"],
      "content": "角色们就读于月见高中。",
      "comment": "月见高中",
      "constant": false,
      "disable": false,
      "order": 30
    },
    "1": {
      "uid": 1,
      "key": ["世界观"],
      "content": "架空现代世界。",
      "comment": "世界观",
      "constant": true,
      "disable": false,
      "order": 10
    },
    "2": {
      "uid": 2,
      "key": ["被禁用"],
      "content": "不该被导入的内容。",
      "comment": "禁用条目",
      "constant": false,
      "disable": true,
      "order": 50
    }
  }
}''';
      final entries = parseWorldBookJson(raw);
      expect(entries, hasLength(3));

      final first = entries.first;
      expect(first.title, '月见高中');
      expect(first.keywords, ['月见', '高中']);
      expect(first.secondaryKeywords, ['祭典']);
      expect(first.content, '角色们就读于月见高中。');
      expect(first.constant, isFalse);
      expect(first.enabled, isTrue);
      expect(first.order, 30);
      // 导入的条目 id 重新生成，避免与本应用现有条目冲突
      expect(first.id, isNot('0'));

      final constantEntry = entries[1];
      expect(constantEntry.constant, isTrue);
      expect(constantEntry.order, 10);

      expect(entries[2].enabled, isFalse);
    });

    test('entries 为数组的老格式变体', () {
      const raw = '''
{
  "entries": [
    {"key": ["A"], "content": "内容A", "comment": "条目A"},
    {"key": ["B"], "content": "内容B"}
  ]
}''';
      final entries = parseWorldBookJson(raw);
      expect(entries, hasLength(2));
      expect(entries[0].keywords, ['A']);
      expect(entries[0].order, 100); // 缺省 order
    });

    test('顶层直接是条目数组', () {
      const raw = '''
[
  {"key": ["火車", "列车"], "content": "开往北方的列车。", "constant": true}
]''';
      final entries = parseWorldBookJson(raw);
      expect(entries, hasLength(1));
      expect(entries.first.constant, isTrue);
      expect(entries.first.content, contains('列车'));
    });

    test('次级关键词为空数组时不启用 AND 逻辑', () {
      const raw = '''
{"entries": {"0": {"key": ["A"], "keysecondary": [], "content": "内容"}}}''';
      final entries = parseWorldBookJson(raw);
      expect(entries.first.secondaryKeywords, isEmpty);
      expect(entries.first.matches('只要A出现'), isTrue);
    });
  });

  group('世界书导入：本应用格式', () {
    test('exportWorldBookJson 导出的内容可以直接再导入', () {
      final original = [
        WorldBookEntry(
          id: 'e1',
          title: '月见高中',
          keywords: ['月见'],
          secondaryKeywords: ['文化祭'],
          content: '设定内容。',
          constant: true,
          order: 7,
        ),
      ];
      final exported = exportWorldBookJson(original);
      final imported = parseWorldBookJson(exported);
      expect(imported, hasLength(1));
      expect(imported.first.title, '月见高中');
      expect(imported.first.keywords, ['月见']);
      expect(imported.first.secondaryKeywords, ['文化祭']);
      expect(imported.first.content, '设定内容。');
      expect(imported.first.constant, isTrue);
      expect(imported.first.order, 7);
      // id 重新生成
      expect(imported.first.id, isNot('e1'));
    });

    test('导入条目与现有条目触发行为一致', () {
      const raw = '''
{"entries": {"0": {"key": ["月见"], "content": "月见设定。"}}}''';
      final imported = parseWorldBookJson(raw);
      final activated = CharacterPrompt.activateWorldBookEntries(
        WorldBookSettings(enabled: true),
        imported,
        ['今晚去月见吗'],
      );
      expect(activated, hasLength(1));
    });
  });

  group('世界书导入：容错', () {
    test('空结构抛 FormatException', () {
      expect(() => parseWorldBookJson('{}'), throwsFormatException);
      expect(() => parseWorldBookJson('{"entries": {}}'), throwsFormatException);
    });

    test('非法 JSON 抛异常', () {
      expect(() => parseWorldBookJson('not json'), throwsA(anything));
    });

    test('条目缺 content 与 key 时被跳过', () {
      const raw = '''
{"entries": {"0": {"comment": "空条目"}, "1": {"key": ["A"], "content": "有内容"}}}''';
      final entries = parseWorldBookJson(raw);
      expect(entries, hasLength(1));
      expect(entries.first.keywords, ['A']);
    });
  });
}
