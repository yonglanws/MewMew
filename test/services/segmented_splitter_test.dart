import 'package:flutter_test/flutter_test.dart';
import 'package:characters/characters.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/segmented_splitter.dart';

SegmentedSendSettings settings({
  int maxProcessLength = 0,
  int maxSegments = 5,
  int minSegmentLength = 8,
}) => SegmentedSendSettings(
  enabled: true,
  minTriggerLength: 1,
  maxProcessLength: maxProcessLength,
  maxSegments: maxSegments,
  minSegmentLength: minSegmentLength,
  balanceLowerRatio: 0.4,
  balanceUpperRatio: 0.9,
  linearBase: 0,
  linearCharFactor: 0,
);

void main() {
  test('超过最长处理字数时保持整段且不丢失任何内容', () {
    final raw = List.filled(80, '这是完整回复。').join();

    final result = SegmentedSplitter.split(
      raw,
      settings(maxProcessLength: 100),
    );

    expect(result, [raw]);
    expect(result.join(), raw);
  });

  test('超过绝对安全边界的大文本仍完整返回', () {
    final raw = List.filled(9000, '这是长文本。').join();
    final result = SegmentedSplitter.split(raw, settings(maxProcessLength: 0));

    expect(result, [raw]);
  });

  test('英文直引号内部标点不作为切分点', () {
    final result = SegmentedSplitter.split(
      '他说 "wait. really?" 然后继续。最后一句。',
      settings(maxSegments: 2, minSegmentLength: 1),
    );

    expect(result.first, contains('"wait. really?"'));
  });

  test('emoji 和组合字符按用户可见字符处理', () {
    const raw = '👨‍👩‍👧‍👦 很好。继续写下去。';
    final result = SegmentedSplitter.split(
      raw,
      settings(maxSegments: 2, minSegmentLength: 2),
    );

    expect(result.join(), raw);
    expect(result.length, lessThanOrEqualTo(2));
  });

  test('代码块和 Markdown 链接不会被拆开', () {
    const raw = '说明一下。```dart\nprint("a.b");\n```继续看[文档](https://a.b/c)。';
    final result = SegmentedSplitter.split(
      raw,
      settings(maxSegments: 3, minSegmentLength: 1),
    );

    expect(result.join(), raw);
    expect(result.where((part) => part.contains('```')).length, 1);
    expect(
      result.where((part) => part.contains('[文档](https://a.b/c)')).length,
      1,
    );
  });

  test('同一句中优先在分号处断句，不在前面的逗号处过早切开', () {
    const raw = '第一部分先说明当前问题的背景，补充关键原因；第二部分给出处理方案，说明注意事项。补充一句。';
    final result = SegmentedSplitter.split(
      raw,
      settings(maxSegments: 2, minSegmentLength: 5),
    );

    expect(result, hasLength(2));
    expect(result.first, endsWith('；'));
    expect(result.join(), raw);
  });

  test('第一段立即显示，后续段才计算等待时间', () {
    final result = SegmentedSplitter.plan(
      '第一句。第二句。',
      settings(
        maxSegments: 2,
        minSegmentLength: 1,
      ).copyWith(linearBase: 1, linearCharFactor: 0),
    );

    expect(result, isNotEmpty);
    expect(result.first.delay, Duration.zero);
    expect(result.skip(1).every((part) => part.delay > Duration.zero), isTrue);
  });

  test('均分目标段数不会超过最小段长可容纳的数量', () {
    final raw = '第一句。第二句。第三句。第四句。第五句。';
    final s = settings(maxSegments: 5, minSegmentLength: 12);
    final result = SegmentedSplitter.split(raw, s);
    final target = (raw.characters.length / s.minSegmentLength).floor().clamp(
      1,
      s.maxSegments,
    );

    expect(result.length, lessThanOrEqualTo(target));
    expect(result.join(), raw);
  });

  test('总长度不足一个最小段时仍只返回一段', () {
    const raw = '一。二。三。';
    final result = SegmentedSplitter.split(
      raw,
      settings(maxSegments: 5, minSegmentLength: 100),
    );

    expect(result, [raw]);
  });

  test('缺省延迟配置与新配置默认值一致', () {
    final restored = SegmentedSendSettings.fromJson(const {});

    expect(restored.linearBase, 0.8);
    expect(restored.linearCharFactor, 0.09);
  });

  test('损坏的持久化字段只回退字段本身', () {
    final restored = SegmentedSendSettings.fromJson({
      'maxSegments': 'not-a-number',
      'minSegmentLength': null,
      'linearBase': 'not-a-number',
      'linearCharFactor': false,
      'replaceRules': 'not-a-list',
    });

    expect(restored.maxSegments, 5);
    expect(restored.minSegmentLength, 35);
    expect(restored.linearBase, 0.8);
    expect(restored.linearCharFactor, 0.09);
    expect(restored.replaceRules, isEmpty);
  });

  test('异常分段设置会归一化到安全范围', () {
    final normalized = SegmentedSendSettings(
      enabled: true,
      minTriggerLength: -1,
      maxProcessLength: -1,
      maxSegments: 999,
      minSegmentLength: 99999,
      balanceLowerRatio: 0.95,
      balanceUpperRatio: 0.2,
      linearBase: -1,
      linearCharFactor: 2,
    ).normalized();

    expect(normalized.minTriggerLength, 1);
    expect(normalized.maxProcessLength, 0);
    expect(normalized.maxSegments, 50);
    expect(normalized.minSegmentLength, 5000);
    expect(normalized.balanceLowerRatio, 0.95);
    expect(normalized.balanceUpperRatio, 0.95);
    expect(normalized.linearBase, 0);
    expect(normalized.linearCharFactor, 0.3);
  });

  test('损坏的替换规则字段不会阻塞设置加载', () {
    final restored = SegmentedSendSettings.fromJson({
      'replaceRules': [
        {'find': 123, 'replace': false},
        {'find': 'ok', 'replace': 'done'},
      ],
    });

    expect(restored.replaceRules, hasLength(2));
    expect(restored.replaceRules.first.find, isEmpty);
    expect(restored.replaceRules.first.replace, isEmpty);
    expect(restored.replaceRules.last.find, 'ok');
    expect(restored.replaceRules.last.replace, 'done');
  });
}
