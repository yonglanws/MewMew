import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/services/memory/text_tokenizer.dart';

void main() {
  group('分词器（移植 LivingMemory text_processor）', () {
    test('中文字符产生一元与二元组', () {
      final tokens = tokenize('我喜欢吃苹果');
      // '我' 是停用词，会被过滤（照抄原版停用词表）
      expect(tokens, isNot(contains('我')));
      expect(tokens, contains('苹果'));
      expect(tokens, contains('喜欢')); // 二元组
    });

    test('停用词被过滤', () {
      final tokens = tokenize('我是一个非常喜欢猫的人');
      expect(tokens, isNot(contains('的')));
      expect(tokens, isNot(contains('非常'))); // 停用词副词（二元组命中）
      expect(tokens, isNot(contains('我')));
      expect(tokens, contains('喜欢'));
      expect(tokens, contains('猫'));
    });

    test('拉丁词保持完整且转小写外的形态', () {
      final tokens = tokenize('I love Flutter development');
      expect(tokens, contains('Flutter'));
      expect(tokens, contains('development'));
      expect(tokens, isNot(contains('I'))); // 单 ASCII 字符被过滤
    });

    test('URL、@提及、#话题、标点被清除', () {
      final tokens = tokenize('看看这个 https://example.com/a?q=1 @张三 #话题，真不错！');
      final joined = tokens.join(' ');
      expect(joined.contains('example'), isFalse);
      expect(joined.contains('张三'), isFalse);
      expect(joined.contains('话题'), isFalse);
      expect(tokens, contains('不错'));
    });

    test('数字序列作为一个 token', () {
      final tokens = tokenize('会议在2025年11月20日');
      expect(tokens.any((t) => t.contains('2025')), isTrue);
    });

    test('纯标点输入返回空', () {
      expect(tokenize('。，！？'), isEmpty);
    });
  });
}
