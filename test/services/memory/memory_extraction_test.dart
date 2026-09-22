import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/services/memory/memory_extraction.dart';
import 'package:mewmew/services/memory/memory_prompts.dart';

void main() {
  group('对话格式化', () {
    test('助手消息带 Bot 前缀，用户消息带昵称前缀', () {
      final text = formatConversationForExtraction(
        [
          ExtractionMessage(
            role: 'user',
            content: '明天记得开会',
            timestamp: DateTime(2025, 11, 19, 14, 30),
            speakerName: '张三',
          ),
          ExtractionMessage(
            role: 'assistant',
            content: '好的',
            timestamp: DateTime(2025, 11, 19, 14, 31),
            speakerName: '小雪',
          ),
        ],
        botDisplayName: '小雪',
      );
      expect(
        text,
        contains('[张三 | ID: user | 2025-11-19 14:30:00] 明天记得开会'),
      );
      expect(text, contains('[Bot: 小雪 |'));
    });
  });

  group('提取解析级联', () {
    test('标准 JSON 直接解析', () {
      final r = parseExtractionResponse(
        '{"summary":"我和张三讨论了会议安排","topics":["会议"],"key_facts":["张三明天开会"],'
        '"sentiment":"neutral","importance":0.8}',
        isGroup: false,
      );
      expect(r.summary, contains('张三'));
      expect(r.topics, ['会议']);
      expect(r.importance, 0.8);
      expect(r.quality, 'normal');
    });

    test('带代码栅栏的 JSON', () {
      final r = parseExtractionResponse(
        '```json\n{"summary":"讨论了项目进度与发布计划","topics":["项目"],"key_facts":["周五发布"],"sentiment":"positive","importance":0.7}\n```',
        isGroup: false,
      );
      expect(r.summary, contains('项目'));
      expect(r.sentiment, 'positive');
    });

    test('未闭合 JSON 被修复', () {
      final r = parseExtractionResponse(
        '{"summary":"张三喜欢科幻电影","topics":["电影"],"key_facts":["张三喜欢科幻"],'
        '"sentiment":"neutral","importance":0.6',
        isGroup: false,
      );
      expect(r.summary, contains('张三'));
    });

    test('正则兜底提取', () {
      final r = parseExtractionResponse(
        '一些杂乱文本 "summary": "张三约了明天午餐" 还有 "importance": 0.55 其余内容',
        isGroup: false,
      );
      expect(r.summary, contains('张三'));
      expect(r.importance, 0.55);
    });

    test('完全失败时返回默认值', () {
      final r = parseExtractionResponse('这根本不是 JSON', isGroup: false);
      expect(r.summary, '对话记录');
      expect(r.importance, 0.5);
      expect(r.sentiment, 'neutral');
      expect(r.quality, 'low');
    });

    test('列表截断到 5 项、非法情感回退 neutral、重要性夹取', () {
      final r = parseExtractionResponse(
        '{"summary":"总结总结总结总结","topics":["1","2","3","4","5","6","7"],'
        '"key_facts":["a","b","c","d","e","f"],"sentiment":"angry","importance":9}',
        isGroup: false,
      );
      expect(r.topics.length, 5);
      expect(r.keyFacts.length, 5);
      expect(r.sentiment, 'neutral');
      expect(r.importance, 1.0);
    });

    test('群聊模板解析 participants', () {
      final r = parseExtractionResponse(
        '{"summary":"张三和李四讨论团建","topics":["团建"],"key_facts":["去滑雪"],'
        '"participants":["张三","李四","我"],"sentiment":"positive","importance":0.75}',
        isGroup: true,
      );
      expect(r.participants, contains('张三'));
    });
  });

  group('质量门', () {
    test('短摘要 / 无事实 / 泛化称呼 → low', () {
      expect(validateSummaryQuality(summary: '太短', keyFacts: ['有'], importance: 0.5), 'low');
      expect(
        validateSummaryQuality(summary: '这是一段足够长的摘要文本', keyFacts: [], importance: 0.5),
        'low',
      );
      expect(
        validateSummaryQuality(
          summary: '用户说明天要出门办事，还说了一些其他的事情，内容比较长一些',
          keyFacts: ['事实'],
          importance: 0.5,
        ),
        'low',
      );
    });

    test('合格内容 → normal', () {
      expect(
        validateSummaryQuality(
          summary: '张三提醒我明天下午三点在会议室A开会，需要带项目文档',
          keyFacts: ['张三安排明天开会'],
          importance: 0.85,
        ),
        'normal',
      );
    });
  });

  group('时间标签', () {
    test('从消息时间戳生成确定性标签', () {
      final info = buildSourceTimeTags([
        ExtractionMessage(
          role: 'user',
          content: 'a',
          timestamp: DateTime(2025, 11, 19, 10),
        ),
        ExtractionMessage(
          role: 'assistant',
          content: 'b',
          timestamp: DateTime(2025, 11, 20, 11),
        ),
      ]);
      expect(info.timeTags, ['2025-11-19', '2025-11-20']);
      expect(info.sourceTimeLabel, '2025-11-19 - 2025-11-20');
    });
  });

  group('提示词模板', () {
    test('占位符替换不受内容花括号影响', () {
      final out = replaceVars('A {conversation} B', {
        'conversation': '包含 {伪造} 的内容',
      });
      expect(out, 'A 包含 {伪造} 的内容 B');
    });

    test('私聊/群聊模板内容不同且含 schema 字段', () {
      expect(privateChatPrompt, contains('"summary"'));
      expect(privateChatPrompt, isNot(contains('"participants"')));
      expect(groupChatPrompt, contains('"participants"'));
      expect(groupChatPrompt, contains('群成员'));
    });

    test('带人格系统提示词包含人格内容', () {
      final sys = buildExtractionSystemPrompt(
        currentDate: '2025-11-19 14:00',
        personaPrompt: '你是活泼的助手小雪',
      );
      expect(sys, contains('小雪'));
      expect(sys, contains('2025-11-19'));
    });

    test('合并提示词包含条目 JSON', () {
      final user = buildConsolidationUserPrompt([
        {'id': 0, 'summary': '记忆A', 'key_facts': ['a'], 'topics': ['t']},
        {'id': 1, 'summary': '记忆B', 'key_facts': ['b'], 'topics': []},
      ]);
      expect(user, contains('共 2 条'));
      expect(user, contains('记忆A'));
      expect(user, contains('key_facts'));
    });
  });
}
