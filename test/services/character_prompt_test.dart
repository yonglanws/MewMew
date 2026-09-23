import 'package:flutter_test/flutter_test.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/character_prompt.dart';

Persona _fullPersona() => Persona(
  id: 'p1',
  name: '小林玖奈',
  appearance: '身高160cm，黑长直，常穿连帽衫',
  personality: '慵懒的高中少女，情绪驱动，嘴硬心软',
  backstory: '高强度网络使用者，喜欢熬夜打游戏',
  languageStyle: '爱用空格代替逗号，句尾偶尔加"喵~"',
);

void main() {
  group('角色卡模板拼接', () {
    test('结构化字段全部进入拟人模板', () {
      final prompt = CharacterPrompt.buildCharacterPrompt(_fullPersona());
      expect(prompt, contains('小林玖奈'));
      expect(prompt, contains('身高160cm，黑长直'));
      expect(prompt, contains('慵懒的高中少女'));
      expect(prompt, contains('高强度网络使用者'));
      expect(prompt, contains('爱用空格代替逗号'));
      // 高度拟人模板的关键段落
      expect(prompt, contains('基本要求'));
      expect(prompt, contains('Role_Profile'));
      expect(prompt, contains('错误格式'));
      expect(prompt, contains('特殊场景'));
      expect(prompt, contains('对话安全'));
      expect(prompt, contains('初始化'));
      expect(prompt, contains('社交软件'));
      // 明确禁止动作描写等非聊天形态
      expect(prompt, contains('动作描写'));
    });

    test('空字段不产生空占位行', () {
      final prompt = CharacterPrompt.buildCharacterPrompt(
        Persona(id: 'p2', name: '只有名字'),
      );
      expect(prompt, contains('只有名字'));
      expect(prompt, isNot(contains(':  ')));
      expect(prompt, isNot(contains('**外貌特征**: ')));
    });

    test('完整提示词模式直接透传自定义内容', () {
      final p = _fullPersona()
        ..useRawPrompt = true
        ..rawPrompt = '你是自定义角色，完全不同的设定。';
      expect(CharacterPrompt.buildCharacterPrompt(p), '你是自定义角色，完全不同的设定。');
    });

    group('角色专属模板（每个角色可不同）', () {
      test('专属模板整体替换默认模板并替换占位符', () {
        final p = _fullPersona()
          ..promptTemplate = '我是{name}，{personality}。口头禅藏在{languageStyle}里。';
        final prompt = CharacterPrompt.buildCharacterPrompt(p);
        expect(prompt, '我是小林玖奈，慵懒的高中少女，情绪驱动，嘴硬心软。口头禅藏在爱用空格代替逗号，句尾偶尔加"喵~"里。');
        // 不再包含默认模板段落
        expect(prompt, isNot(contains('Role_Profile')));
        expect(prompt, isNot(contains('基本要求')));
      });

      test('专属模板里空字段占位符清空并清理悬空行', () {
        final p = Persona(id: 'p3', name: '阿默')
          ..promptTemplate = '角色：{name}\n- **外貌特征**: {appearance}\n性格：{personality}';
        final prompt = CharacterPrompt.buildCharacterPrompt(p);
        expect(prompt, contains('角色：阿默'));
        expect(prompt, contains('性格：'));
        // 外貌为空 → 悬空的标签行被清理
        expect(prompt, isNot(contains('**外貌特征**')));
      });

      test('不同角色用不同模板互不影响', () {
        final a = Persona(id: 'a', name: 'A', personality: '傲娇')
          ..promptTemplate = '模板A：{name}={personality}';
        final b = Persona(id: 'b', name: 'B', personality: '天然')
          ..promptTemplate = '模板B({name})性格是{personality}';
        expect(
          CharacterPrompt.buildCharacterPrompt(a),
          '模板A：A=傲娇',
        );
        expect(
          CharacterPrompt.buildCharacterPrompt(b),
          '模板B(B)性格是天然',
        );
      });

      test('默认模板包含占位符与完整拟人规则', () {
        final tpl = CharacterPrompt.defaultCharacterTemplate;
        expect(tpl, contains('{name}'));
        expect(tpl, contains('{appearance}'));
        expect(tpl, contains('{personality}'));
        expect(tpl, contains('{backstory}'));
        expect(tpl, contains('{languageStyle}'));
        expect(tpl, contains('基本要求'));
        expect(tpl, contains('对话安全'));
        // 用占位符填充后即可作为角色提示词
        final prompt = CharacterPrompt.buildCharacterPrompt(
          _fullPersona()..promptTemplate = tpl,
        );
        expect(prompt, contains('小林玖奈'));
        expect(prompt, contains('对话安全'));
      });

      test('专属模板为空时回退默认', () {
        final p = _fullPersona()..promptTemplate = '   ';
        expect(
          CharacterPrompt.buildCharacterPrompt(p),
          contains('Role_Profile'),
        );
      });
    });

    test('群聊成员一行式简介包含名字与性格', () {
      final line = CharacterPrompt.buildCondensedProfile(_fullPersona());
      expect(line, startsWith('小林玖奈：'));
      expect(line, contains('慵懒的高中少女'));
      expect(line, contains('说话风格'));
    });

    test('序列化兼容旧数据：无 appearance 字段时为空字符串', () {
      final p = Persona.fromJson({
        'id': 'legacy',
        'name': '旧角色',
        'personality': '温柔',
        // 旧版本会有 greeting 等字段，新模型直接忽略
        'greeting': '你好呀',
      });
      expect(p.appearance, '');
      expect(p.personality, '温柔');
      expect(p.hasNoStructuredFields, isFalse);
    });

    test('toJson/fromJson 保留外貌与专属模板字段', () {
      final p = _fullPersona()..promptTemplate = '自定义模板：{name}';
      final json = p.toJson();
      expect(json['appearance'], contains('黑长直'));
      expect(json['promptTemplate'], '自定义模板：{name}');
      expect(json.containsKey('greeting'), isFalse);
      final restored = Persona.fromJson(json);
      expect(restored.appearance, p.appearance);
      expect(restored.promptTemplate, '自定义模板：{name}');
    });
  });

  group('上下文感知', () {
    test('默认实时状态块包含时间/场景/对象', () {
      final now = DateTime(2026, 9, 23, 14, 30); // 周三 下午
      final block = CharacterPrompt.buildContextBlock(
        now: now,
        isGroup: false,
        userName: '阿伟',
      );
      expect(block, contains('2026年9月23日'));
      expect(block, contains('星期三'));
      expect(block, contains('14:30'));
      expect(block, contains('下午'));
      expect(block, contains('私聊'));
      expect(block, contains('阿伟'));
      // 提醒模型不要复述该块
      expect(block, contains('不要主动复述'));
    });

    test('群聊场景携带群名与其他成员', () {
      final block = CharacterPrompt.buildContextBlock(
        now: DateTime(2026, 9, 23, 2, 0),
        isGroup: true,
        userName: '阿伟',
        groupName: '摸鱼小分队',
        groupMemberNames: ['小林玖奈', '另一个角色'],
      );
      expect(block, contains('群聊'));
      expect(block, contains('摸鱼小分队'));
      expect(block, contains('小林玖奈、另一个角色'));
      expect(block, contains('深夜'));
    });

    test('用户的"我的设定"注入为对方设定行', () {
      final block = CharacterPrompt.buildContextBlock(
        now: DateTime(2026, 9, 23, 14, 0),
        isGroup: false,
        userName: '阿伟',
        userDescription: '大学宅男，喜欢游戏和撸猫',
      );
      expect(block, contains('对方的设定'));
      expect(block, contains('大学宅男，喜欢游戏和撸猫'));
    });

    test('自定义实时状态模板整体生效且占位符可用', () {
      final block = CharacterPrompt.buildContextBlock(
        now: DateTime(2026, 9, 23, 14, 30),
        isGroup: false,
        userName: '阿伟',
        customTemplate: '现在{period}了，和{partner}在{scene}。{date}',
      );
      expect(block, '现在下午了，和阿伟在社交软件私聊（1对1的文字聊天）。2026年9月23日');
    });
  });

  group('系统提示词总装（缓存友好：稳定前缀）', () {
    final injection = PromptInjectionSettings();
    final worldBook = WorldBookSettings();
    const stylePrompt = '';

    test('单聊：角色档案 + 私聊注入默认文案；实时状态不在系统提示词中', () {
      final prompt = CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: stylePrompt,
        recentMessageTexts: const [],
      );
      expect(prompt, contains('小林玖奈'));
      // 实时状态是易变内容，已移出系统提示词（由 buildContextInjection 尾部注入）
      expect(prompt, isNot(contains('实时状态')));
      expect(prompt, isNot(contains('阿伟')));
      expect(prompt, contains('私聊模式'));
      expect(prompt, isNot(contains('群聊模式')));
    });

    test('缓存稳定：不同时间的系统提示词逐字一致', () {
      String buildAt() => CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: stylePrompt,
        recentMessageTexts: const [],
      );
      // 前缀缓存的前提：系统提示词不随时间变化
      expect(buildAt(), buildAt());
    });

    test('自定义场景注入覆盖默认文案（实时状态自定义模板走尾部注入）', () {
      final prompt = CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: PromptInjectionSettings(
          contextPrompt: '自定义时间线：{time}',
          privatePrompt: '自定义私聊规则XYZ',
        ),
        worldBook: worldBook,
        stylePrompt: stylePrompt,
        recentMessageTexts: const [],
      );
      expect(prompt, isNot(contains('自定义时间线')));
      expect(prompt, contains('自定义私聊规则XYZ'));
      expect(prompt, isNot(contains('一对一私聊')));
    });

    test('群聊：成员名录 + 发言人完整档案 + 群聊注入', () {
      final mate = Persona(id: 'p2', name: '邻居小妹', personality: '活泼话痨');
      final group = GroupChat(id: 'g1', name: '摸鱼小分队', personaIds: ['p1', 'p2']);
      final prompt = CharacterPrompt.build(
        isGroup: true,
        group: group,
        persona: null,
        speaker: _fullPersona(),
        mentions: const [],
        allPersonas: [_fullPersona(), mate],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: stylePrompt,
        recentMessageTexts: const [],
      );
      expect(prompt, contains('摸鱼小分队'));
      expect(prompt, contains('邻居小妹：活泼话痨'));
      expect(prompt, contains('小林玖奈'));
      // 发言人是完整档案，其他成员只有一行简介
      expect(prompt, contains('身高160cm'));
      expect(prompt, contains('群聊模式'));
    });

    test('群聊被 @ 时点名提及对象', () {
      final group = GroupChat(id: 'g1', name: '群', personaIds: ['p1']);
      final prompt = CharacterPrompt.build(
        isGroup: true,
        group: group,
        persona: null,
        speaker: _fullPersona(),
        mentions: const ['p1'],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: stylePrompt,
        recentMessageTexts: const [],
      );
      expect(prompt, contains('@ 了「小林玖奈」'));
    });

    test('用户自定义生成风格文本注入', () {
      final prompt = CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: '回复要非常简短，一般不超过 20 个字',
        recentMessageTexts: const [],
      );
      expect(prompt, contains('生成风格'));
      expect(prompt, contains('回复要非常简短，一般不超过 20 个字'));
    });

    test('生成风格留空则不注入', () {
      final prompt = CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: worldBook,
        stylePrompt: '   ',
        recentMessageTexts: const [],
      );
      expect(prompt, isNot(contains('生成风格')));
    });

    test('世界书 depth 位置时不进系统提示词，由 worldBookDepthBlock 输出', () {
      final wb = WorldBookSettings(
        enabled: true,
        injectionPosition: 'depth',
        entries: [
          WorldBookEntry(
            id: 'e1',
            keywords: ['月见'],
            content: '月见高中的设定内容。',
          ),
        ],
      );
      final prompt = CharacterPrompt.build(
        isGroup: false,
        group: null,
        persona: _fullPersona(),
        speaker: null,
        mentions: const [],
        allPersonas: [_fullPersona()],
        injection: injection,
        worldBook: wb,
        stylePrompt: stylePrompt,
        recentMessageTexts: const ['去月见高中看看'],
      );
      expect(prompt, isNot(contains('世界书设定')));

      final depthBlock = CharacterPrompt.worldBookDepthBlock(
        settings: wb,
        recentMessageTexts: const ['去月见高中看看'],
      );
      expect(depthBlock, isNotNull);
      expect(depthBlock, contains('月见高中的设定内容。'));

      // system 位置时 depth 输出为 null
      expect(
        CharacterPrompt.worldBookDepthBlock(
          settings: wb.copyWith(injectionPosition: 'system'),
          recentMessageTexts: const ['去月见高中看看'],
        ),
        isNull,
      );
    });

    test('实时状态尾部注入消息：占位符替换、自定义角色', () {
      final injection = CharacterPrompt.buildContextInjection(
        now: DateTime(2026, 9, 23, 14, 30),
        isGroup: false,
        userName: '阿伟',
        userDescription: '大学宅男',
        customTemplate: '现在{period}，和{partner}聊天',
      );
      expect(injection, isNotNull);
      expect(injection!['role'], 'system');
      expect(injection['content'], '现在下午，和阿伟聊天');

      // 默认模板携带"对方的设定"与"实时状态"标题
      final defaultInjection = CharacterPrompt.buildContextInjection(
        now: DateTime(2026, 9, 23, 14, 30),
        isGroup: false,
        userName: '阿伟',
        userDescription: '大学宅男，喜欢游戏和撸猫',
      );
      expect(defaultInjection!['content'], contains('实时状态'));
      expect(defaultInjection['content'], contains('对方的设定'));
      expect(defaultInjection['content'], contains('大学宅男，喜欢游戏和撸猫'));

      // 群聊：成员名录进入注入块
      final groupInjection = CharacterPrompt.buildContextInjection(
        now: DateTime(2026, 9, 23, 14, 30),
        isGroup: true,
        userName: '阿伟',
        groupName: '摸鱼群',
        groupMemberNames: ['小林玖奈', '邻居小妹'],
      );
      expect(groupInjection!['content'], contains('小林玖奈、邻居小妹'));
      expect(groupInjection['content'], contains('摸鱼群'));
    });
  });

  group('世界书激活', () {
    final settings = WorldBookSettings(
      enabled: true,
      scanDepth: 4,
      maxChars: 1000,
    );

    test('关键词命中触发注入，未命中不注入', () {
      final hit = WorldBookEntry(
        id: 'e1',
        title: '月见高中',
        keywords: ['月见', '高中'],
        content: '角色们就读于月见高中。',
        order: 10,
      );
      final miss = WorldBookEntry(
        id: 'e2',
        title: '便利店',
        keywords: ['便利店'],
        content: '街角有家便利店。',
        order: 20,
      );
      final activated = CharacterPrompt.activateWorldBookEntries(
        settings,
        [hit, miss],
        ['今天去了月见高中参加祭典'],
      );
      expect(activated.map((e) => e.id), ['e1']);
    });

    group('次级关键词（AND 逻辑）', () {
      test('主关键词命中但次级未命中 → 不激活', () {
        final e = WorldBookEntry(
          id: 'and1',
          keywords: ['月见'],
          secondaryKeywords: ['祭典'],
          content: '月见祭典的设定。',
        );
        expect(
          CharacterPrompt.activateWorldBookEntries(settings, [e], ['月见很好看']),
          isEmpty,
        );
      });

      test('主次同时命中 → 激活', () {
        final e = WorldBookEntry(
          id: 'and2',
          keywords: ['月见'],
          secondaryKeywords: ['祭典'],
          content: '月见祭典的设定。',
        );
        final activated = CharacterPrompt.activateWorldBookEntries(
          settings,
          [e],
          ['月见的祭典开始了'],
        );
        expect(activated.map((e) => e.id), ['and2']);
      });

      test('次级关键词为空时仅主关键词生效', () {
        final e = WorldBookEntry(
          id: 'and3',
          keywords: ['月见'],
          content: '设定。',
        );
        expect(
          CharacterPrompt.activateWorldBookEntries(settings, [e], ['月见']),
          hasLength(1),
        );
      });
    });

    test('常驻条目无视关键词始终激活', () {
      final constant = WorldBookEntry(
        id: 'c1',
        title: '世界观',
        keywords: const [],
        content: '这是一个架空现代世界。',
        constant: true,
      );
      final activated = CharacterPrompt.activateWorldBookEntries(
        settings,
        [constant],
        ['完全无关的内容'],
      );
      expect(activated, hasLength(1));
    });

    test('递归扫描：被激活条目的内容可触发其它条目', () {
      final a = WorldBookEntry(
        id: 'a',
        keywords: ['祭典'],
        content: '提到祭典就会想起烟火大会。',
      );
      final b = WorldBookEntry(
        id: 'b',
        keywords: ['烟火大会'],
        content: '烟火大会在河畔举行。',
      );
      final activated = CharacterPrompt.activateWorldBookEntries(
        settings,
        [a, b],
        ['去看祭典吗'],
      );
      expect(activated.map((e) => e.id), containsAll(['a', 'b']));
    });

    test('关闭递归时不连锁触发', () {
      final noRecursion = settings.copyWith(recursiveScanning: false);
      final a = WorldBookEntry(
        id: 'a',
        keywords: ['祭典'],
        content: '提到烟火大会。',
      );
      final b = WorldBookEntry(
        id: 'b',
        keywords: ['烟火大会'],
        content: '烟火大会在河畔举行。',
      );
      final activated = CharacterPrompt.activateWorldBookEntries(
        noRecursion,
        [a, b],
        ['去看祭典吗'],
      );
      expect(activated.map((e) => e.id), ['a']);
    });

    test('字符预算按 order 优先保留', () {
      final tight = settings.copyWith(maxChars: 12);
      final first = WorldBookEntry(
        id: 'f',
        keywords: ['关键词'],
        content: 'A' * 10,
        order: 10,
      );
      final second = WorldBookEntry(
        id: 's',
        keywords: ['关键词'],
        content: 'B' * 10,
        order: 20,
      );
      final activated = CharacterPrompt.activateWorldBookEntries(
        tight,
        [second, first],
        ['关键词'],
      );
      expect(activated.map((e) => e.id), ['f']);
    });

    test('禁用条目与禁用总开关都不注入', () {
      final e = WorldBookEntry(
        id: 'x',
        keywords: ['关键词'],
        content: '内容',
        enabled: false,
      );
      expect(
        CharacterPrompt.activateWorldBookEntries(settings, [e], ['关键词']),
        isEmpty,
      );
      expect(
        CharacterPrompt.activateWorldBookEntries(
          settings.copyWith(enabled: false),
          [e.copyWith(enabled: true)],
          ['关键词'],
        ),
        isEmpty,
      );
    });

    test('世界书块带标题包裹', () {
      final block = CharacterPrompt.buildWorldBookBlock([
        WorldBookEntry(id: 'e', title: '月见高中', content: '内容', order: 1),
      ]);
      expect(block, contains('【世界书设定】'));
      expect(block, contains('<lore title="月见高中">'));
      expect(block, contains('内容'));
      expect(block, contains('</lore>'));
    });

    test('命中关键词的大小写不敏感', () {
      final e = WorldBookEntry(id: 'e', keywords: ['MewMew'], content: '内容');
      final activated = CharacterPrompt.activateWorldBookEntries(
        settings,
        [e],
        ['我发现了 mewmew'],
      );
      expect(activated, hasLength(1));
    });
  });

  group('模式注入 @Depth', () {
    test('system 模式不产生深度注入文本', () {
      expect(
        CharacterPrompt.depthInjectionText(
          settings: PromptInjectionSettings(mode: 'system'),
          isGroup: false,
        ),
        isNull,
      );
    });

    test('depth 模式返回对应场景文本（自定义优先）', () {
      final custom = PromptInjectionSettings(
        mode: 'depth',
        privatePrompt: '自定义深度注入',
      );
      expect(
        CharacterPrompt.depthInjectionText(settings: custom, isGroup: false),
        '自定义深度注入',
      );
      expect(
        CharacterPrompt.depthInjectionText(
          settings: PromptInjectionSettings(mode: 'depth'),
          isGroup: true,
        ),
        contains('群聊模式'),
      );
    });

    test('深度注入插入位置：depth 0 在最末尾', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'u1'},
      ];
      CharacterPrompt.insertDepthInjection(messages, {
        'role': 'system',
        'content': 'inject',
      }, depth: 0);
      expect(messages.last['content'], 'inject');
      expect(messages, hasLength(3));
    });

    test('深度注入插入位置：depth N 插在倒数第 N 条之前', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'u1'},
        {'role': 'assistant', 'content': 'a1'},
        {'role': 'user', 'content': 'u2'},
      ];
      CharacterPrompt.insertDepthInjection(messages, {
        'role': 'user',
        'content': 'inject',
      }, depth: 1);
      // depth 1 = 插在最后一条（u2）之前
      expect(messages[3]['content'], 'inject');
      expect(messages[4]['content'], 'u2');
    });

    test('深度超出消息数时插到最前面', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'u1'},
      ];
      CharacterPrompt.insertDepthInjection(messages, {
        'role': 'system',
        'content': 'inject',
      }, depth: 99);
      expect(messages.first['content'], 'inject');
    });
  });

  group('设置模型序列化', () {
    test('PromptInjectionSettings 往返（无开关，纯内容字段）', () {
      final s = PromptInjectionSettings(
        contextPrompt: '自定义实时状态 {time}',
        privatePrompt: '私聊文案',
        groupPrompt: '群聊文案',
        mode: 'depth',
        depth: 3,
        role: 'user',
      );
      final restored = PromptInjectionSettings.fromJson(s.toJson());
      expect(restored.contextPrompt, '自定义实时状态 {time}');
      expect(restored.privatePrompt, '私聊文案');
      expect(restored.groupPrompt, '群聊文案');
      expect(restored.mode, 'depth');
      expect(restored.depth, 3);
      expect(restored.role, 'user');
    });

    test('PromptInjectionSettings 兼容旧版布尔字段（直接忽略）', () {
      final restored = PromptInjectionSettings.fromJson({
        'enabled': false,
        'contextAwareness': false,
        'privateEnabled': false,
        'groupEnabled': false,
        'mode': 'system',
      });
      expect(restored.mode, 'system');
      expect(restored.privatePrompt, '');
    });

    test('WorldBookSettings 与条目（含次级关键词/注入位置）往返', () {
      final s = WorldBookSettings(
        enabled: true,
        scanDepth: 8,
        maxChars: 2000,
        recursiveScanning: false,
        injectionPosition: 'depth',
        injectionDepth: 2,
        injectionRole: 'user',
        entries: [
          WorldBookEntry(
            id: 'e1',
            title: '标题',
            keywords: ['a', 'b'],
            secondaryKeywords: ['c'],
            content: '内容',
            constant: true,
            order: 5,
          ),
        ],
      );
      final restored = WorldBookSettings.fromJson(s.toJson());
      expect(restored.enabled, true);
      expect(restored.scanDepth, 8);
      expect(restored.maxChars, 2000);
      expect(restored.recursiveScanning, false);
      expect(restored.injectionPosition, 'depth');
      expect(restored.injectionDepth, 2);
      expect(restored.injectionRole, 'user');
      expect(restored.entries, hasLength(1));
      expect(restored.entries.first.keywords, ['a', 'b']);
      expect(restored.entries.first.secondaryKeywords, ['c']);
      expect(restored.entries.first.constant, true);
      expect(restored.entries.first.order, 5);
    });

    test('GenerationStyleSettings 往返（纯自定义文本）', () {
      final s = GenerationStyleSettings(stylePrompt: '回复要短，多用空格');
      final restored = GenerationStyleSettings.fromJson(s.toJson());
      expect(restored.stylePrompt, '回复要短，多用空格');
      expect(GenerationStyleSettings.fromJson({}).stylePrompt, '');
    });

    test('用户设定风格注入包装', () {
      expect(CharacterPrompt.styleInjection('  '), isNull);
      expect(
        CharacterPrompt.styleInjection('回复要短'),
        contains('回复要短'),
      );
    });
  });
}
