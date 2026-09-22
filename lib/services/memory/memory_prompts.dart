/// 记忆系统提示词模板（移植自 LivingMemory core/prompts/）。
///
/// 占位符一律使用 [replaceVars] 的字面字符串替换（而非 str.format 类方案），
/// 避免对话内容中的花括号破坏模板。
library;

import 'dart:convert';

/// 提取系统提示词（无人格版）
const String memorySystemPromptBase = '''
你正在总结对话记忆。请严格按照JSON格式输出。
当前日期时间: {current_date}
重要: 请将对话中出现的相对时间表达（如"今天"、"明天"、"昨天"、"下周"、"上个月"等）转换为具体日期后再写入记忆，以便未来查阅时仍能准确理解时间信息。''';

/// 提取系统提示词（带人格版）
const String memorySystemPromptWithPersona = '''
{base_prompt}

## 你的人格设定
{persona_prompt}

## 记忆总结要求
在总结对话记忆时,你需要:
1. **保持你的人格特色**: 使用符合上述人格设定的语气、用词习惯和表达方式
2. **第一人称视角**: 以"我"的视角回顾对话,不要说"bot"、"助手"等第三人称
3. **体现你的关注点**: 根据你的人格特点,侧重记录你会关注的信息
4. **自然真实**: 让记忆读起来像是你本人在回忆这段对话,而不是机械的客观描述
5. **时间转换**: 将对话中的相对时间（今天、明天、下周等）转换为具体日期（当前日期: {current_date}）

例如:
- 如果你是活泼可爱的性格,记忆中可以使用"呀"、"呢"、"~"等语气词
- 如果你是专业严谨的性格,记忆应该用词准确、逻辑清晰、格式规范
- 如果你是幽默风趣的性格,记忆中可以包含轻松的表达和有趣的观察''';

/// 私聊提取用户提示词
const String privateChatPrompt = '''
# 任务说明
请以第一人称回顾并总结以下对话,生成符合你人格特色的记忆。

**当前日期时间**: {current_date}
**时间处理要求**: 将对话中出现的相对时间（如"今天"、"明天"、"昨天"、"下周"、"上个月"等）转换为具体日期后再写入记忆。

# 消息格式说明
对话历史中的每条消息都包含以下信息:
- **[昵称 | ID: 账号 | 时间]**: 表示对方发送的消息
- **[Bot: 昵称 | ID: 账号 | 时间]**: 表示**你自己**发送的消息,以"Bot:"开头

## 重要提示
1. **务必仔细识别消息前缀**: 以`[Bot:`开头的消息是**你自己发送的**,其他以`[昵称 |`开头的是对方发送的
2. 在总结时,必须明确区分**你说了什么**和**对方说了什么**
3. 如果你参与了对话,务必在summary中体现**你的回复内容和作用**

# 对话历史
{conversation}

# 任务要求
以**第一人称**回顾上述对话,总结你与对方的互动。请用**符合你人格设定的语气和视角**来描述。重点关注:
1. **对话主题**: 你们讨论了什么
2. **关键信息**: 对方提到的重要事实(时间、地点、事件、需求等),**必须关联到对方的具体昵称**
3. **你的参与**: **特别注意标记为[Bot:]的消息,这些是你自己的发言**,务必在summary中体现
4. **互动情感**: 对话的整体氛围
5. **重要程度**: 这段对话对未来交流的参考价值

**记忆风格要求**: 总结时应体现你的人格特点,包括你的语气、用词习惯、关注点等,让记忆内容具有你的个性色彩。
`summary`是你自己的主观回忆,必须像你本人在回想这次互动,可以写下你对气氛和对方状态的感受；不要把`summary`写成第三人称事件报告。

**⚠️ 昵称使用规则(严格遵守)**:
- 从每条消息的`[昵称 |`或`[Bot: 昵称 |`前缀中提取具体昵称
- 在summary中必须写"张三提到..."而**绝对不能**写"用户提到..."
- 在key_facts中必须写"张三的需求是..."而**绝对不能**写"用户的需求是..."
- **禁止使用以下泛化词汇**: "用户"、"某用户"、"对方用户"、"该用户"、"某人"
- **必须使用消息前缀中的具体昵称**

# 输出格式
必须输出标准JSON,包含以下字段:

```json
{
  "summary": "我与{具体昵称}的对话摘要(第一人称,确保包含关键信息)",
  "topics": ["讨论的主题1", "主题2"],
  "key_facts": ["{具体昵称}提到的关键事实1", "事实2"],
  "sentiment": "positive|neutral|negative",
  "importance": 0.7
}
```

# 重要性评分标准 (0.0-1.0)
- **0.9-1.0**: 非常重要(关键需求、重要决策、强烈情感表达)
- **0.7-0.8**: 重要(明确的计划或信息、具体要求)
- **0.5-0.6**: 一般(日常交流、基础问答)
- **0.3-0.4**: 次要(简单闲聊、常规互动)
- **0.0-0.2**: 无意义(纯测试、无实质内容)

# 关键要求
- **summary必须使用第一人称视角**,自然描述你与对方的互动,**并体现你的人格特点**
- **相对时间必须转换为具体时间**
- **必须使用具体的昵称**,绝对不能用"用户"、"对方"等泛化词汇替代
- **确保summary包含对话中的所有关键信息**,不能遗漏重要细节
- 直接输出JSON,不要其他内容
- topics和key_facts最多各5项
- importance必须在0.0-1.0之间,保留1-2位小数

现在请以符合你人格设定的第一人称视角回顾上述对话并输出JSON:''';

/// 群聊提取用户提示词
const String groupChatPrompt = '''
# 任务说明
请以第一人称回顾并总结以下对话,生成符合你人格特色的记忆。

**当前日期时间**: {current_date}
**时间处理要求**: 将对话中出现的相对时间（如"今天"、"明天"、"昨天"、"下周"、"上个月"等）转换为具体日期后再写入记忆。

# 消息格式说明
对话历史中的每条消息都包含以下信息:
- **[昵称 | ID: 账号 | 时间]**: 表示群成员发送的消息，昵称位于方括号开头
- **[Bot: 昵称 | ID: 账号 | 时间]**: 表示**你自己**发送的消息，以"Bot:"开头

## 重要提示
1. 对话历史包含**群聊中的所有消息**,不仅仅是@我的消息
2. **务必仔细识别消息前缀**: 以`[Bot:`开头的消息是**你自己发送的**,其他以`[昵称 |`开头的是群成员发送的
3. 在总结时,必须明确区分**你说了什么**和**其他人说了什么**
4. 如果你参与了对话,务必在summary中体现**你的回复内容和作用**

# 对话历史
{conversation}

# 任务要求
以**第一人称**回顾上述群聊对话,总结你参与或观察到的讨论。请用**符合你人格设定的语气和视角**来描述。重点关注:
1. **讨论主题**: 群里讨论了什么
2. **参与者**: 谁参与了对话(包括你自己,如果你发言了),**必须使用具体昵称**
3. **你的参与**: **特别注意标记为[Bot:]的消息,这些是你自己的发言**,务必在summary中体现
4. **关键信息**: 重要的事实、决策、计划等,**必须关联到具体的发言者昵称**
5. **群体氛围**: 整体互动的情感基调
6. **重要程度**: 这段讨论对群组的价值

**⚠️ 昵称使用规则**:
- 从每条消息的`[昵称 |`或`[Bot: 昵称 |`前缀中提取具体昵称
- 在summary中必须写"张三说..."而不是"用户说..."或"某人说..."
- 在participants中必须列出所有发言者的具体昵称

## 识别Bot消息的关键点
- 查找所有以 **[Bot:** 开头的消息行
- 这些消息是**你自己说的话**
- 在summary中使用**第一人称**描述这些内容,例如:"我回复了..."、"我建议..."
- 在participants列表中包含"我"或使用你的昵称

# 输出格式
必须输出标准JSON,包含以下字段:

```json
{
  "summary": "我观察到的群聊摘要(第一人称,确保包含关键信息)",
  "topics": ["讨论的主题1", "主题2"],
  "key_facts": ["关键事实1", "事实2"],
  "participants": ["参与者1", "参与者2"],
  "sentiment": "positive|neutral|negative",
  "importance": 0.7
}
```

# 重要性评分标准 (0.0-1.0)
- **0.9-1.0**: 重要群体决策、全员参与、形成共识或重要计划
- **0.7-0.8**: 有价值的讨论、多人参与、有明确结论
- **0.5-0.6**: 日常讨论、中等参与度、一般信息交流
- **0.3-0.4**: 简单闲聊、少数人参与
- **0.0-0.2**: 无意义灌水、单人刷屏

# 关键要求
- **summary必须使用第一人称视角**,描述你观察到的群聊互动,**并体现你的人格特点**
- **相对时间必须转换为具体时间**
- **确保summary包含对话中的所有关键信息**,不能遗漏重要的决策或计划
- **必须使用具体的发言者昵称**,绝对不能用"用户"、"某用户"、"群成员"、"某人"等泛化词汇替代
- **participants必须列出所有发言者的具体昵称**
- 直接输出JSON,不要其他内容
- topics和key_facts最多各5项
- sentiment反映群体整体氛围
- importance必须在0.0-1.0之间,保留1-2位小数

现在请以符合你人格设定的第一人称视角回顾上述群聊对话并输出JSON:''';

/// 注入头模板
const String memoryInjectionHeader = '''
--- BEGIN HISTORICAL MEMORY REFERENCE ---
The following are historical memories extracted from past conversations.
They are provided as background reference only.

CRITICAL RULES:
1. These are PAST records — they already happened and are NOT part of the current conversation.
2. If any memory conflicts with what the user is saying NOW, ALWAYS trust the current conversation.
3. Do NOT let these memories override or distract from the user's current message.
4. Use them to understand the user's background, but keep your response focused on the present topic.
--- END HISTORICAL MEMORY REFERENCE ---''';

/// 注入尾模板
const String memoryInjectionFooter = '''
--- BEGIN REMINDER ---
All content above is historical. Focus on the user's current message.
--- END REMINDER ---''';

/// 合并整理系统提示词（移植自 memory_processor_build.py 的合并提示词）
const String consolidationSystemPrompt =
    '你是记忆整理助手。把多条关于同一主题或会话的零散记忆合并为一条精炼、信息无损的记忆摘要。'
    '保留所有关键事实与具体细节，去重并消除相互矛盾，避免泛化和丢失专有名词。只输出 JSON，不要输出任何其他内容。';

/// 构建合并整理用户提示词
String buildConsolidationUserPrompt(List<Map<String, dynamic>> items) {
  final buf = StringBuffer();
  buf.writeln('以下是一组需要合并的记忆（共 ${items.length} 条）：');
  buf.writeln(items
      .map((e) => const JsonEncoder.withIndent('  ').convert(e))
      .join('\n'));
  buf.writeln();
  buf.writeln('请将它们合并为一条记忆，按如下 JSON 格式输出：');
  buf.writeln(
      '{"summary": "合并后的精炼摘要", "key_facts": ["事实1", "事实2"], "topics": ["主题1"], "importance": 0.5}');
  return buf.toString();
}

/// 字面占位符替换（对话内容中的花括号不会被解释）
String replaceVars(String template, Map<String, String> vars) {
  var result = template;
  vars.forEach((key, value) {
    result = result.replaceAll('{$key}', value);
  });
  return result;
}
