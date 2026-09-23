import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

/// 系统提示词组装的状态层集成测试：
/// 角色卡拟人模板 + 实时状态 + 世界书 + 场景注入 + 生成风格 + 记忆工具。
void main() {
  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    return state;
  }

  testWidgets('单聊系统提示词：拟人模板+私聊注入+记忆工具（实时状态已移出）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [
      Persona(
        id: 'p1',
        name: '小林玖奈',
        appearance: '黑长直',
        personality: '慵懒',
        backstory: '宅家打游戏',
        languageStyle: '爱用空格',
      ),
    ];
    state.userProfile.name = '阿伟';
    final session = ChatSession(
      id: 's1',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);

    expect(prompt, contains('小林玖奈'));
    expect(prompt, contains('黑长直'));
    expect(prompt, contains('基本要求')); // 拟人模板
    expect(prompt, contains('私聊模式'));
    expect(prompt, contains('【记忆工具】'));
    // 缓存友好：实时状态/用户昵称是易变内容，不再进系统提示词
    expect(prompt, isNot(contains('实时状态')));
    expect(prompt, isNot(contains('阿伟')));
    // 单聊不应出现群聊注入与群聊场景
    expect(prompt, isNot(contains('群聊模式')));
    expect(prompt, isNot(contains('【群聊场景】')));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('实时状态注入在聊天记录末尾附近（缓存友好尾部注入）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.userProfile.name = '阿伟';
    state.userProfile.description = '大学宅男，喜欢游戏和撸猫';
    final session = ChatSession(
      id: 's1b',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [
        ChatMessage(
          id: 'm1',
          role: 'assistant',
          content: '在干嘛',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'm2',
          role: 'user',
          content: '刚打游戏回来',
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final messages = state.debugAssembleApiMessages(session);
    // 结构：[system, assistant, user, ...尾部注入]，实时状态 depth 1
    // → 紧邻最新一条用户消息之前；记忆注入会改写末条用户消息，不在此列。
    expect(messages.first['role'], 'system');
    final ctx = messages[messages.length - 2];
    expect(ctx['role'], 'system');
    expect(ctx['content'], contains('实时状态'));
    expect(ctx['content'], contains('阿伟'));
    expect(ctx['content'], contains('对方的设定'));
    expect(ctx['content'], contains('大学宅男，喜欢游戏和撸猫'));
    // 最新一条用户消息保持在最末，AI 正常从它继续生成
    expect(messages.last['role'], 'user');
    expect(messages.last['content'], '刚打游戏回来');
    // 系统提示词保持稳定：两次装配 system 内容一致
    final again = state.debugAssembleApiMessages(session);
    expect(again.first['content'], messages.first['content']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('群聊系统提示词：成员名录+发言人档案+群聊注入', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [
      Persona(id: 'p1', name: '小林玖奈', personality: '慵懒'),
      Persona(id: 'p2', name: '邻居小妹', personality: '活泼话痨'),
    ];
    state.groupChats = [
      GroupChat(id: 'g1', name: '摸鱼小分队', personaIds: ['p1', 'p2']),
    ];
    state.userProfile.name = '阿伟';
    final session = ChatSession(
      id: 's2',
      title: '摸鱼小分队',
      groupChatId: 'g1',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(
      session,
      speaker: state.personas.first,
    );

    expect(prompt, contains('【群聊场景】'));
    expect(prompt, contains('摸鱼小分队'));
    expect(prompt, contains('邻居小妹：活泼话痨'));
    expect(prompt, contains('小林玖奈'));
    expect(prompt, contains('群聊模式'));
    expect(prompt, contains('【记忆工具】'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('世界书默认 depth 注入聊天记录深处，不再进系统提示词', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    // 默认 WorldBookSettings：injectionPosition = depth（缓存友好默认）
    state.worldBookSettings = WorldBookSettings(
      enabled: true,
      entries: [
        WorldBookEntry(
          id: 'e1',
          title: '月见高中',
          keywords: ['月见'],
          content: '角色们就读于月见高中。',
        ),
      ],
    );
    final session = ChatSession(
      id: 's3',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [
        ChatMessage(
          id: 'm1',
          role: 'user',
          content: '今天月见高中的祭典你去吗',
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    // 动态激活的世界书块不再进系统提示词（会破坏前缀缓存）
    expect(prompt, isNot(contains('【世界书设定】')));

    final messages = state.debugAssembleApiMessages(session);
    // 世界书 depth 默认 2 → 插入在聊天记录深处
    final loreMessages = messages
        .where((m) => (m['content'] as String).contains('角色们就读于月见高中。'))
        .toList();
    expect(loreMessages, isNotEmpty);
    expect(loreMessages.first['role'], 'system');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('世界书 system 位置时仍进系统提示词（用户可自选）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.worldBookSettings = WorldBookSettings(
      enabled: true,
      injectionPosition: 'system',
      entries: [
        WorldBookEntry(
          id: 'e1',
          title: '月见高中',
          keywords: ['月见'],
          content: '角色们就读于月见高中。',
        ),
      ],
    );
    final session = ChatSession(
      id: 's3b',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [
        ChatMessage(
          id: 'm1',
          role: 'user',
          content: '今天月见高中的祭典你去吗',
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, contains('【世界书设定】'));
    expect(prompt, contains('角色们就读于月见高中。'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('depth 模式注入文本不出现在系统提示词中', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.promptInjectionSettings = PromptInjectionSettings(mode: 'depth');
    final session = ChatSession(
      id: 's4',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, isNot(contains('私聊模式')));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('用户自定义生成风格文本注入系统提示词', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.generationStyleSettings = GenerationStyleSettings(
      stylePrompt: '回复要非常简短，像随手回消息',
    );
    final session = ChatSession(
      id: 's5',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, contains('生成风格'));
    expect(prompt, contains('回复要非常简短，像随手回消息'));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('用户"我的设定"随实时状态尾部注入', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [Persona(id: 'p1', name: '小林玖奈')];
    state.userProfile.description = '大学宅男，喜欢游戏和撸猫';
    final session = ChatSession(
      id: 's7',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [
        ChatMessage(
          id: 'm1',
          role: 'user',
          content: '嗨',
          timestamp: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, isNot(contains('对方的设定')));
    final messages = state.debugAssembleApiMessages(session);
    expect(messages[messages.length - 2]['content'], contains('对方的设定'));
    expect(
      messages[messages.length - 2]['content'],
      contains('大学宅男，喜欢游戏和撸猫'),
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('角色专属模板生效（每个角色不同）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    state.personas = [
      Persona(id: 'p1', name: '小林玖奈', personality: '慵懒')
        ..promptTemplate = '专属模板：我是{name}，{personality}',
    ];
    final session = ChatSession(
      id: 's8',
      title: '小林玖奈',
      personaId: 'p1',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, contains('专属模板：我是小林玖奈，慵懒'));
    // 专属模板替换掉默认模板段落
    expect(prompt, isNot(contains('Role_Profile')));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('无角色卡时保持默认助手提示词', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    final session = ChatSession(
      id: 's6',
      title: '新对话',
      messages: [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final prompt = state.debugBuildSystemPrompt(session);
    expect(prompt, contains('乐于助人的 AI 助手'));
    expect(prompt, contains('【记忆工具】'));
    await tester.pump(const Duration(seconds: 2));
  });
}
