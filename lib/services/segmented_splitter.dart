import 'dart:math';

import 'package:characters/characters.dart';

import '../models/models.dart';

/// 对话分段发送的纯算法工具
///
/// 职责：
/// 1. 前置/后置正则清理文本；
/// 2. 正向替换（AI 回复）与反向替换（用户输入）；
/// 3. 按主级标点（[。？！?!\n…]+）智能切分长文本，避免在引号/成对符号内部切分；
/// 4. 在尽量均匀的前提下，按 maxSegments 平均分配，超上限时只降到结构边界（如；）补切；
/// 5. 计算线性延迟：delay = linearBase + chars * linearCharFactor。
class SegmentedSplitter {
  /// 主切分符：。？！?!\n…
  static final RegExp _primarySplitRegex = RegExp(r'[。？！?!\n…]+');

  /// 结构性补切符：；;
  ///
  /// 逗号、顿号和冒号不作为自动断句点，避免把未完成的语义短语拆开。
  static final RegExp _secondarySplitRegex = RegExp(r'[；;]+');

  /// 成对符号：用于避免在内部切分。
  ///
  /// 直双引号是同一个字符同时充当开、闭符号，不能再用两个 contains
  /// 集合配合 depth 计数，否则每遇到一个引号都会先加深再减深。
  static const _pairClosers = <String, String>{
    '“': '”',
    '‘': '’',
    '「': '」',
    '『': '』',
    '〈': '〉',
    '《': '》',
    '【': '】',
    '〔': '〕',
    '［': '］',
    '｛': '｝',
    '（': '）',
    '(': ')',
    '[': ']',
    '"': '"',
  };

  /// Markdown 代码块 ```...```（含语言标识）
  static final RegExp _codeFenceRegex = RegExp(r'```[\s\S]*?```');

  /// Markdown 行内代码 `...`
  static final RegExp _inlineCodeRegex = RegExp(r'`[^`\n]+`');

  /// Markdown 链接 [text](url) 与图片 ![alt](url)：避免在 url/title 中切分
  static final RegExp _mdLinkRegex = RegExp(r'!?\[[^\]]*\]\([^)]*\)');

  /// Markdown 删除线 ~~...~~
  static final RegExp _mdDelRegex = RegExp(r'~~[^~\n]+~~');

  /// Markdown 加粗 **...**
  static final RegExp _mdBoldRegex = RegExp(r'\*\*[^*\n]+\*\*');

  /// Markdown 强调 __...__
  static final RegExp _mdStrongRegex = RegExp(r'__[^_\n]+__');

  /// 占位符格式：会把上述 Markdown 块替换成原子占位，确保切分时整体不会被切坏。
  /// 占位符被设计成"不会触发任意主/次级标点"，长度 1，避免影响字数考量过多偏差。
  /// 注意：split 完后会整体还原。
  static const _placeholderPrefix = '\uE000MD';
  static const _placeholderSuffix = '\uE001';

  /// 把所有"必须当原子保护的 Markdown 块"替换为短占位符
  /// 返回 (压缩后的文本, 占位符表)
  static (String, Map<String, String>) _protectMarkdown(String text) {
    final map = <String, String>{};
    var counter = 0;
    String protectOne(RegExp re) {
      return text.replaceAllMapped(re, (m) {
        final raw = m.group(0)!;
        final key = '$_placeholderPrefix${counter++}$_placeholderSuffix';
        map[key] = raw;
        return key;
      });
    }

    // 顺序：先代码块（避免被单反引号误吃），再行内代码、链接、删除线、加粗、强调
    text = protectOne(_codeFenceRegex);
    text = protectOne(_inlineCodeRegex);
    text = protectOne(_mdLinkRegex);
    text = protectOne(_mdDelRegex);
    text = protectOne(_mdBoldRegex);
    text = protectOne(_mdStrongRegex);
    return (text, map);
  }

  static String _restoreMarkdown(String text, Map<String, String> map) {
    if (map.isEmpty) return text;
    for (final entry in map.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  /// 对 AI 回复文本应用整套分段前置处理（清理 + 正向替换）。
  /// 返回处理后的纯文本，分段前调用。
  static String preprocessForSplit(String raw, SegmentedSendSettings s) {
    var text = raw;
    if (s.preCleanRegex.isNotEmpty) {
      try {
        text = text.replaceAll(RegExp(s.preCleanRegex), '');
      } catch (_) {}
    }
    // 正向替换：AI 回复中 find → replace
    for (final rule in s.replaceRules) {
      if (rule.find.isEmpty) continue;
      text = text.replaceAll(rule.find, rule.replace);
    }
    return text;
  }

  /// 对用户输入文本应用反向替换。
  /// 若 reverseReplace=false，原样返回。
  /// 若 reverseReplace=true，每条规则反向作用：replace → find。
  static String applyReverseReplace(String input, SegmentedSendSettings s) {
    if (!s.reverseReplace) return input;
    var text = input;
    for (final rule in s.replaceRules) {
      if (rule.replace.isEmpty) continue;
      // 仅替换非空结果端，避免空替换导致无意义全局删除
      text = text.replaceAll(rule.replace, rule.find);
    }
    return text;
  }

  /// 段尾清理（仅清理两端空行，不影响段内换行）；后置正则清理
  static String postCleanSegment(String seg, SegmentedSendSettings s) {
    var text = seg;
    if (s.trimBlankLines) {
      // 仅清理首尾的空白行（连续 \n 或前导/末尾空白），保留段内换行
      text = text.replaceAll(RegExp(r'^[\s\u3000]+'), '');
      text = text.replaceAll(RegExp(r'[\s\u3000]+$'), '');
    }
    if (s.postCleanRegex.isNotEmpty) {
      try {
        text = text.replaceAll(RegExp(s.postCleanRegex), '');
      } catch (_) {}
    }
    return text;
  }

  /// 主入口：将 AI 回复文本切分为多段
  ///
  /// 返回清理后的段列表。若不需分段（太短/被关闭），返回 length==1
  /// 即整段原文。
  static List<String> split(String raw, SegmentedSendSettings s) {
    final normalized = s.normalized();
    final lowerRatio = normalized.balanceLowerRatio;
    final upperRatio = normalized.balanceUpperRatio < lowerRatio
        ? lowerRatio
        : normalized.balanceUpperRatio;
    final safe = normalized.copyWith(balanceUpperRatio: upperRatio);
    const absoluteSafetyLimit = 50000;
    final processLimit = safe.maxProcessLength == 0
        ? absoluteSafetyLimit
        : safe.maxProcessLength;
    // 先检查原始 grapheme 数，超出安全边界时不执行用户自定义正则，
    // 既避免主 isolate 被复杂表达式拖住，也保证原文完整返回。
    if (safe.enabled && raw.characters.length > processLimit) {
      return [raw];
    }
    // 1. 前置清理与正向替换
    var text = preprocessForSplit(raw, safe);
    if (text.isEmpty) return [];

    // 超过最长处理字数时保留完整内容，不再截断或丢失尾部。
    // 0 代表不设业务上限，但仍保留绝对安全上限，避免异常输入拖垮分段算法。
    if (safe.enabled && text.characters.length > processLimit) {
      return [postCleanSegment(text, safe)];
    }

    // 2. 字数过短，直接后置清理后返回单段
    if (!safe.enabled || text.characters.length < safe.minTriggerLength) {
      return [postCleanSegment(text, safe)];
    }

    // 3.5 保护 Markdown 代码块/行内代码/链接为原子占位符，
    //     确保后续切分不会破坏其内部
    final (protected, placeholders) = _protectMarkdown(text);

    // 4. 主级标点切分（避开成对符号内部）
    final rawSegments = _tokenizeRespectingPairs(protected);
    if (rawSegments.isEmpty) {
      return [_restoreMarkdown(postCleanSegment(text, safe), placeholders)];
    }

    // 5. 段间归并与清洗（去除空段）
    final cleaned = <String>[];
    for (final seg in rawSegments) {
      final c = postCleanSegment(seg, safe);
      if (c.isNotEmpty) cleaned.add(c);
    }
    if (cleaned.isEmpty) {
      return [_restoreMarkdown(postCleanSegment(text, safe), placeholders)];
    }

    // 6. 均分算法：在 maxSegments 内尽量均匀分配；过短不切；过长降到次级标点切
    final balanced = _balanceSegments(cleaned, safe);

    // 7. 还原 Markdown 占位符
    return balanced.map((seg) => _restoreMarkdown(seg, placeholders)).toList();
  }

  /// 按 maxSegments 总数均分已切成"原始段"的结果
  ///
  /// 算法目标严格按配置语义：
  /// - `ideal = totalLen / target`，target 是不超过 maxSegments 的目标段数
  /// - `minSegmentLength`：段长 ≥ minSegmentLength（强制保留短段独立时也至少这么长）
  /// - `balanceLowerRatio`：低于 ideal × lowerRatio 的段不切分（应与相邻合并）
  /// - `balanceUpperRatio`：高于 ideal × upperRatio 时降级用次级标点补切
  /// - `trimBlankLines`：每段两端空行清理
  /// - 最终段数 ≤ maxSegments
  static List<String> _balanceSegments(
    List<String> segments,
    SegmentedSendSettings s,
  ) {
    if (segments.length <= 1) return segments;
    final totalLen = segments.fold<int>(
      0,
      (acc, e) => acc + e.characters.length,
    );
    if (totalLen == 0) return [];

    // 目标段数：先用 maxSegments 的上限，但如果总长不够均分多段，
    // 也至少保证每段 ≥ minSegmentLength
    final maxByLen = (totalLen / s.minSegmentLength).floor();
    var target = maxByLen > 0 ? min(s.maxSegments, maxByLen) : 1;
    if (target < 1) target = 1;
    final idealLen = (totalLen / target).floor();
    final lower = (idealLen * s.balanceLowerRatio).floor();
    final upper = (idealLen * s.balanceUpperRatio).floor();

    // 第 1 步：原始段过短（< minSegmentLength）的尝试与后续段合并，
    // 但若合并后超出 upper 太多就保留为独立段（不再继续吞）
    final coalesced = <String>[];
    var buf = StringBuffer();
    var bufLen = 0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final combined = bufLen + seg.characters.length;
      final needMore = bufLen < s.minSegmentLength || bufLen < lower;
      final wouldBurst =
          bufLen > 0 && combined > upper && bufLen >= s.minSegmentLength;
      if (bufLen > 0 && needMore && !wouldBurst) {
        buf.write(seg);
        bufLen = combined;
      } else if (bufLen > 0 && !needMore && wouldBurst) {
        // 收一个段，再以当前 seg 开启新段
        coalesced.add(buf.toString().trim());
        buf = StringBuffer(seg);
        bufLen = seg.characters.length;
      } else {
        // 继续累加，等下一段决定
        buf.write(seg);
        bufLen = combined;
        if (bufLen >= lower && bufLen <= upper) {
          // 已落到理想区间，先收一段，但不强制——保留更多灵活性给后续
        }
      }
    }
    if (bufLen > 0) coalesced.add(buf.toString().trim());

    // 第 2 步：贪心向 ideal 收拢一次。若某段仍显著短（< lower），尽量与后段合并
    final step2 = <String>[];
    var acc = StringBuffer();
    var accLen = 0;
    for (final seg in coalesced) {
      if (accLen == 0) {
        acc.write(seg);
        accLen = seg.characters.length;
        continue;
      }
      // 若当前 acc 不足下限，继续并入
      if (accLen < lower) {
        if (accLen + seg.characters.length <= upper) {
          acc.write(seg);
          accLen += seg.characters.length;
        } else {
          // 并入后超出上限太多：先把 acc 收尾，seg 开新段
          step2.add(acc.toString().trim());
          acc = StringBuffer(seg);
          accLen = seg.characters.length;
        }
      } else if (accLen >= upper) {
        // acc 已经偏长，先收尾
        step2.add(acc.toString().trim());
        acc = StringBuffer(seg);
        accLen = seg.characters.length;
      } else if (accLen + seg.characters.length <= upper) {
        acc.write(seg);
        accLen += seg.characters.length;
      } else {
        // 加入会超上限：收尾
        step2.add(acc.toString().trim());
        acc = StringBuffer(seg);
        accLen = seg.characters.length;
      }
    }
    if (accLen > 0) step2.add(acc.toString().trim());

    // 第 3 步：对仍过长（> upper）的段只用结构性标点补切；逗号、顿号和冒号
    // 永远不作为自动断句点。切完低于 minSegmentLength 的子段向后续子段合并。
    final out = <String>[];
    for (final seg in step2) {
      if (seg.characters.length > upper) {
        final sub = _tokenizeSecondaryRespectingPairs(seg);
        if (sub.length > 1) {
          out.addAll(_mergeShortSubs(sub, s.minSegmentLength));
          continue;
        }
      }
      out.add(seg);
    }

    // 第 4 步：再过一遍最小段长过滤——把过短孤立段并入下一段
    final merged2 = <String>[];
    for (final seg in out) {
      if (merged2.isEmpty) {
        merged2.add(seg);
        continue;
      }
      final last = merged2.last;
      if (last.characters.length < lower &&
          last.characters.length + seg.characters.length <= upper) {
        merged2[merged2.length - 1] = (last + seg).trim();
      } else if (seg.characters.length < lower &&
          merged2.length + 0 + 1 > target) {
        merged2[merged2.length - 1] = (last + seg).trim();
      } else {
        merged2.add(seg);
      }
    }

    // 第 5 步：兜底——段数仍超过 maxSegments：把超出部分并入倒数第二段
    if (merged2.length > target) {
      final head = merged2.sublist(0, target - 1).toList();
      final tail = merged2.sublist(target - 1).join('').trim();
      head.add(tail);
      return head;
    }
    return merged2;
  }

  static List<String> _mergeShortSubs(List<String> subs, int lower) {
    final out = <String>[];
    var buf = '';
    for (final sub in subs) {
      if (buf.isEmpty) {
        buf = sub;
      } else if (buf.characters.length < lower) {
        buf += sub;
      } else {
        out.add(buf);
        buf = sub;
      }
    }
    if (buf.isNotEmpty) out.add(buf);
    return out;
  }

  /// 在避免切到成对符号内部的前提下，按主级标点切分文本
  ///
  /// 只有所有成对符号闭合时才允许切分。
  static List<String> _tokenizeRespectingPairs(String text) {
    return _tokenizeAt(text, _primarySplitRegex);
  }

  static List<String> _tokenizeAt(String text, RegExp splitRegex) {
    final result = <String>[];
    final buf = StringBuffer();
    final expectedClosers = <String>[];
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      final escaped = _isEscaped(text, i);
      if (!escaped) {
        final closer = _pairClosers[ch];
        if (closer != null) {
          if (closer == ch &&
              expectedClosers.isNotEmpty &&
              expectedClosers.last == ch) {
            expectedClosers.removeLast();
          } else {
            expectedClosers.add(closer);
          }
        } else if (expectedClosers.isNotEmpty && expectedClosers.last == ch) {
          expectedClosers.removeLast();
        }
      }
      // 仅在所有成对符号闭合时检查切分点
      if (expectedClosers.isEmpty && splitRegex.matchAsPrefix(ch) != null) {
        buf.write(ch);
        // 吞掉后续连续的切分符
        while (i + 1 < text.length &&
            splitRegex.matchAsPrefix(text[i + 1]) != null) {
          i++;
          buf.write(text[i]);
        }
        result.add(buf.toString());
        buf.clear();
        i++;
        continue;
      }
      buf.write(ch);
      i++;
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }

  static bool _isEscaped(String text, int index) {
    var backslashes = 0;
    for (var i = index - 1; i >= 0 && text[i] == '\\'; i--) {
      backslashes++;
    }
    return backslashes.isOdd;
  }

  /// 在避免切到成对符号内部的前提下，按次级标点切分段（用于过长段的补救）
  static List<String> _tokenizeSecondaryRespectingPairs(String text) {
    return _tokenizeAt(text, _secondarySplitRegex);
  }

  /// 计算分段间的延迟（秒）：线性延迟 = base + 字数 * factor
  ///
  /// nextSegmentChars 为下一段字数（用于"模拟真人输入频率"）。
  static Duration segmentDelay({
    required int segmentChars,
    required SegmentedSendSettings s,
  }) {
    final seconds = max(
      0.0,
      max(0.0, s.linearBase) +
          max(0, segmentChars) * s.linearCharFactor.clamp(0.0, 0.3),
    );
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// 给一段长文本 + 设置 → 返回分段结果与每段对应的延迟
  static List<SegmentPlan> plan(String raw, SegmentedSendSettings s) {
    final segs = split(raw, s);
    return [
      for (var i = 0; i < segs.length; i++)
        SegmentPlan(
          text: segs[i],
          delay: i == 0
              ? Duration.zero
              : segmentDelay(segmentChars: segs[i].characters.length, s: s),
        ),
    ];
  }
}

/// 一次分段输出规划
class SegmentPlan {
  final String text;
  final Duration delay; // 在该段出现前的延迟
  const SegmentPlan({required this.text, required this.delay});
}
