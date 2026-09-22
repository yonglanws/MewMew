/// 文本清洗与分词（移植自 LivingMemory core/processors/text_processor.py）。
///
/// 原版使用 jieba 分词 + SQLite FTS5 unicode61；此处改为纯 Dart 实现：
/// 中文按一元字符 + 二元组切分（近似 jieba 的搜索模式召回），拉丁文按连续词切分。
/// 停用词表照抄自 core/models/default_stopwords.py（229 词）。
library;

/// 默认中文停用词（照抄 LivingMemory default_stopwords.py）
const Set<String> defaultStopwords = {
  // 代词
  '我', '你', '他', '她', '它', '我们', '你们', '他们', '她们', '它们',
  '自己', '自家', '咱', '咱们', '这', '那', '这个', '那个', '这些', '那些',
  '哪', '哪个', '哪些', '谁', '什么', '怎么', '怎样', '多少',
  // 助词
  '的', '了', '着', '过', '地', '得', '呢', '吗', '吧', '啊', '呀', '哇',
  '哦', '嗯', '啦', '嘛', '呗',
  // 连词
  '和', '与', '及', '以及', '或', '或者', '还是', '而', '且', '并', '但',
  '但是', '然而', '可是', '不过', '而且', '并且', '因此', '所以', '因为',
  '由于', '如果', '假如', '虽然', '尽管', '除非',
  // 介词
  '在', '从', '向', '往', '到', '由', '为', '对', '关于', '按照', '根据',
  '通过', '经过', '沿着', '朝', '朝着', '沿', '用', '以', '按', '依', '凭',
  '靠', '当', '于', '比',
  // 副词
  '很', '太', '非常', '极', '十分', '最', '更', '挺', '特别', '尤其', '都',
  '也', '还', '再', '又', '就', '才', '已', '曾', '已经', '正在', '将',
  '将要', '总是', '一直', '从来', '刚', '刚才', '马上', '立刻', '顿时',
  '忽然', '突然', '渐渐', '逐渐', '慢慢',
  // 量词
  '个', '只', '件', '条', '张', '块', '片', '次', '遍', '些', '点',
  '下', '回', '趟', '番', '场', '阵', '样', '种',
  // 叹词
  '哎', '唉', '哼', '嘿', '哈',
  // 常见低信息动词与否定词
  '是', '有', '没', '没有', '不', '别', '莫', '勿', '非', '未', '无', '成',
  '做', '看', '说', '让', '给', '被', '把', '能', '会', '要', '想',
  // 其他虚词
  '之', '所', '其', '此', '该', '各', '每', '某', '另', '等', '等等',
  '如此', '这样', '那样', '如何', '多么',
  // 常见低信息名词短语
  '一下', '一点', '一些', '一切', '一样', '一般', '一起', '一边', '上下',
  '左右', '前后', '里外', '东西', '方面', '时候', '地方', '样子', '起来',
  '出来', '进去', '过去', '过来', '下去', '上来',
  // 兜底符号
  '、', '，', '。', '！', '？', '；', '：', '……', '—',
};

/// 需要清除的标点/符号（ASCII + 常用中英文标点）
final RegExp _punctPattern = RegExp(
  r'[!"#\$%&\(\)\*\+,\-\.\/:;<=>\?@\[\\\]^_`\{\|\}~'
  r'！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞＠［＼］＾＿｀｛｜｝～'
  r'、。，．：；？！""''「」『』（）《》〈〉【】〔〕［］｛｝…—·～｜]',
);

final RegExp _urlPattern = RegExp(r'https?://\S+|www\.\S+');
final RegExp _mentionPattern = RegExp(r'[@＠][\w\u4e00-\u9fff-]+');
// 话题标签只吃字母数字与中文，避免吞掉后续中文正文（\S+ 会连标点一起吞）
final RegExp _hashtagPattern = RegExp(r'[#＃][\w\u4e00-\u9fff]+');
final RegExp _wsPattern = RegExp(r'\s+');

bool _isCjk(int codeUnit) =>
    (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
    (codeUnit >= 0x3400 && codeUnit <= 0x4DBF);

/// 清洗文本：去 URL/@提及/#话题/标点，压缩空白
String cleanText(String text) {
  var t = text;
  t = t.replaceAll(_urlPattern, ' ');
  t = t.replaceAll(_mentionPattern, ' ');
  t = t.replaceAll(_hashtagPattern, ' ');
  t = t.replaceAll(_punctPattern, ' ');
  t = t.replaceAll(_wsPattern, ' ').trim();
  return t;
}

/// 切词：CJK 字符逐字 + 相邻二元组；拉丁/数字连续段作为整词。
/// 原版 jieba cut_for_search 在移动端不可用，此为等效召回近似。
List<String> segment(String text) {
  final cleaned = cleanText(text);
  final tokens = <String>[];
  final buf = StringBuffer();
  var cjkRun = <String>[];

  void flushLatin() {
    if (buf.isNotEmpty) {
      tokens.add(buf.toString());
      buf.clear();
    }
  }

  void flushCjk() {
    if (cjkRun.length == 1) {
      tokens.add(cjkRun.first);
    } else if (cjkRun.length > 1) {
      tokens.addAll(cjkRun);
      for (var i = 0; i < cjkRun.length - 1; i++) {
        tokens.add('${cjkRun[i]}${cjkRun[i + 1]}');
      }
    }
    cjkRun = [];
  }

  for (final ch in cleaned.runes) {
    if (_isCjk(ch)) {
      flushLatin();
      cjkRun.add(String.fromCharCode(ch));
    } else if (ch == 0x20) {
      flushLatin();
      flushCjk();
    } else {
      flushCjk();
      buf.writeCharCode(ch);
    }
  }
  flushLatin();
  flushCjk();
  return tokens;
}

/// 分词 + 停用词/单字符 ASCII 过滤，返回用于 BM25 的 token 列表。
///
/// [extraStopwords] 允许调用方追加领域停用词。
List<String> tokenize(String text, {Set<String>? extraStopwords}) {
  final stop = extraStopwords;
  final result = <String>[];
  for (final token in segment(text)) {
    if (token.isEmpty) continue;
    var hasAlnum = false;
    for (final cu in token.runes) {
      final isAsciiAlnum = (cu >= 0x30 && cu <= 0x39) ||
          (cu >= 0x41 && cu <= 0x5A) ||
          (cu >= 0x61 && cu <= 0x7A);
      if (isAsciiAlnum || _isCjk(cu)) {
        hasAlnum = true;
        break;
      }
    }
    if (!hasAlnum) continue; // 纯标点
    if (token.length == 1 &&
        token.runes.first < 0x80) {
      continue; // 单个 ASCII 字符无区分度（单 CJK 字保留）
    }
    if (defaultStopwords.contains(token)) continue;
    if (stop != null && stop.contains(token)) continue;
    result.add(token);
  }
  return result;
}

/// tokenize 后以空格连接（用于展示/调试对齐原版 preprocess_for_bm25 输出）
String tokenizeForIndex(String text) => tokenize(text).join(' ');
