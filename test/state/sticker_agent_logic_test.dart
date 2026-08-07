import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/sticker_selection.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('表情包发送方式默认低频并支持持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    expect(state.stickerSendMode, StickerSendMode.low);

    await state.setStickerSendMode(StickerSendMode.high);
    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    expect(reloadedStorage.stickerSendMode, StickerSendMode.high);
  });

  test('按人格绑定和情绪文件夹名称筛选表情包并随机抽取', () {
    final groups = [
      StickerGroup(id: 'group-bound', name: '日常', createdAt: DateTime(2026)),
      StickerGroup(id: 'group-other', name: '其他', createdAt: DateTime(2026)),
    ];
    final folders = [
      StickerFolder(
        id: 'folder-bound',
        groupId: 'group-bound',
        name: '开心',
        description: '开心时使用',
        createdAt: DateTime(2026),
      ),
      StickerFolder(
        id: 'folder-other',
        groupId: 'group-other',
        name: '开心',
        description: '不应被当前人格使用',
        createdAt: DateTime(2026),
      ),
    ];
    final stickers = [
      StickerItem(
        id: 'sticker-1',
        folderId: 'folder-bound',
        name: '文件一',
        description: '',
        filePath: 'one.png',
        createdAt: DateTime(2026),
      ),
      StickerItem(
        id: 'sticker-2',
        folderId: 'folder-bound',
        name: '文件二',
        description: '',
        filePath: 'two.png',
        createdAt: DateTime(2026),
      ),
      StickerItem(
        id: 'sticker-other',
        folderId: 'folder-other',
        name: '文件三',
        description: '',
        filePath: 'other.png',
        createdAt: DateTime(2026),
      ),
    ];
    final bindings = [
      PersonaStickerBinding(
        personaId: 'persona-1',
        groupId: 'group-bound',
        createdAt: DateTime(2026),
      ),
    ];

    final candidates = StickerSelection.stickersForFolderName(
      personaId: 'persona-1',
      folderName: '开心',
      stickerGroups: groups,
      stickerFolders: folders,
      stickers: stickers,
      bindings: bindings,
    );

    expect(
      candidates.map((item) => item.id),
      containsAll(['sticker-1', 'sticker-2']),
    );
    expect(candidates.map((item) => item.id), isNot(contains('sticker-other')));

    final selectedIds = <String>{};
    for (var seed = 0; seed < 100; seed++) {
      final selected = StickerSelection.pickSticker(
        candidates,
        random: Random(seed),
      );
      if (selected != null) selectedIds.add(selected.id);
    }
    expect(selectedIds, containsAll(['sticker-1', 'sticker-2']));
  });

  test('表情包发送方式按不发送、低频和高频控制放行', () {
    expect(
      StickerSelection.allowsStickerForMode(
        mode: StickerSendMode.off,
        random: Random(0),
      ),
      isFalse,
    );
    expect(
      StickerSelection.allowsStickerForMode(
        mode: StickerSendMode.high,
        random: _FixedRandom(0),
      ),
      isTrue,
    );
    expect(
      StickerSelection.allowsStickerForMode(
        mode: StickerSendMode.high,
        random: _FixedRandom(99),
      ),
      isTrue,
    );
    expect(
      StickerSelection.allowsStickerForMode(
        mode: StickerSendMode.low,
        random: _FixedRandom(24),
      ),
      isTrue,
    );
    expect(
      StickerSelection.allowsStickerForMode(
        mode: StickerSendMode.low,
        random: _FixedRandom(25),
      ),
      isFalse,
    );
  });

  test('高频发送方式要求每个非流式回复使用一个标签但不编造名称', () {
    final instruction = stickerSendModeInstruction(StickerSendMode.high);

    expect(instruction, contains('高频率发表情包'));
    expect(instruction, contains('每个非流式回复至少使用一个表情包标签'));
    expect(instruction, contains('不要编造情绪分组名称'));
    expect(instruction, contains('没有可用表情包时不要伪造'));
  });

  test('表情包提示词明确协议、名称匹配和自定义偏好的边界', () {
    final prompt = buildStickerPromptSection(
      maxStickersPerMessage: 2,
      sendMode: StickerSendMode.high,
      folderEntries: {'开心': '表达开心的情绪'},
      customPrompt: '开心时优先使用可爱的表情。',
    );

    expect(prompt, contains('高频率发表情包'));
    expect(prompt, contains('name 是情绪分组标签名，不是表情包文件名'));
    expect(prompt, contains('name 必须与清单中的名称逐字匹配'));
    expect(prompt, contains('不要把标签放在 Markdown 代码块、引号、示例或解释文字中'));
    expect(prompt, contains('不要提及表情包不可用'));
    expect(prompt, contains('不要输出内部占位文本'));
    expect(prompt, contains('不要输出助手发送了表情包或用户发送了表情包的内部历史描述'));
    expect(prompt, contains('【人格表情使用策略（用户自定义）】'));
    expect(prompt, contains('不能覆盖上面的协议、清单或数量限制'));
  });

  test('用户自定义提示词会控制发送时机、情绪偏好、回避条件和表达风格', () {
    final prompt = buildStickerPromptSection(
      maxStickersPerMessage: 2,
      sendMode: StickerSendMode.low,
      folderEntries: {'开心': '表达开心的情绪'},
      customPrompt: '被夸奖时优先使用开心，讨论严肃问题时不要发送。',
    );

    expect(prompt, contains('什么时候发送'));
    expect(prompt, contains('优先哪些情绪'));
    expect(prompt, contains('哪些情绪或场景应回避'));
    expect(prompt, contains('表达风格'));
    expect(prompt, contains('<sticker_preference>'));
    expect(prompt, contains('</sticker_preference>'));
    expect(prompt, contains('只有适合当前语境时才使用表情包标签'));
  });

  test('流式输出开启时保持禁用表情包，关闭后才允许使用', () {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    state.streamOutputEnabled = true;
    expect(state.stickersEnabled, isFalse);

    state.streamOutputEnabled = false;
    expect(state.stickersEnabled, isTrue);
  });

  test('历史表情包消息不会把内部发送标记注入下一轮 AI 上下文', () {
    final stickerMessage = ChatMessage(
      id: 'sticker-message',
      role: 'assistant',
      content: '',
      timestamp: DateTime(2026),
      stickerId: 'sticker-1',
    );
    final textMessage = ChatMessage(
      id: 'text-message',
      role: 'assistant',
      content: '普通回复',
      timestamp: DateTime(2026),
    );

    expect(shouldIncludeStickerHistoryInApiContext(stickerMessage), isFalse);
    expect(shouldIncludeStickerHistoryInApiContext(textMessage), isTrue);
  });

  test('历史文本中的表情包内部历史描述不会继续注入 AI 上下文', () {
    expect(stripStickerInternalMarkers('前文【助手发送了表情包：疑问】后文'), '前文后文');
    expect(stripStickerInternalMarkers('前文【用户发送了表情包：开心】后文'), '前文后文');
  });

  test('人格表情包发送方式按人格持久化并保持低频默认值', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    expect(
      state.personaStickerSettingsFor('persona-1').sendMode,
      StickerSendMode.low,
    );

    await state.setPersonaStickerSettings(
      PersonaStickerSettings(
        personaId: 'persona-1',
        sendMode: StickerSendMode.high,
        preferredFolderIds: ['folder-happy'],
        customPrompt: '开心时优先发送轻松可爱的表情。',
      ),
    );

    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    final saved = reloadedStorage.loadPersonaStickerSettings().single;
    expect(saved.sendMode, StickerSendMode.high);
    expect(saved.preferredFolderIds, ['folder-happy']);
    expect(saved.customPrompt, '开心时优先发送轻松可爱的表情。');
  });

  test('人格偏好情绪分组会限制可抽取的表情包', () {
    final state = AppState(StorageService())
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常', createdAt: DateTime(2026)),
      ]
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-happy',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
        StickerFolder(
          id: 'folder-sad',
          groupId: 'group-1',
          name: '难过',
          description: '',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickers = [
        StickerItem(
          id: 'sticker-happy',
          folderId: 'folder-happy',
          name: '',
          description: '',
          filePath: 'happy.png',
          createdAt: DateTime(2026),
        ),
        StickerItem(
          id: 'sticker-sad',
          folderId: 'folder-sad',
          name: '',
          description: '',
          filePath: 'sad.png',
          createdAt: DateTime(2026),
        ),
      ]
      ..personaStickerBindings = [
        PersonaStickerBinding(
          personaId: 'persona-1',
          groupId: 'group-1',
          createdAt: DateTime(2026),
        ),
      ]
      ..personaStickerSettings = [
        PersonaStickerSettings(
          personaId: 'persona-1',
          preferredFolderIds: ['folder-happy'],
        ),
      ];
    addTearDown(state.dispose);

    expect(state.stickersForPersonaFolder('persona-1', '开心').map((e) => e.id), [
      'sticker-happy',
    ]);
    expect(state.stickersForPersonaFolder('persona-1', '难过'), isEmpty);
  });

  test('删除情绪分组后清理人格失效偏好并回退到全部可用分组', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage)
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常', createdAt: DateTime(2026)),
      ]
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-deleted',
          groupId: 'group-1',
          name: '已删除',
          description: '',
          createdAt: DateTime(2026),
        ),
        StickerFolder(
          id: 'folder-remaining',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickers = [
        StickerItem(
          id: 'sticker-remaining',
          folderId: 'folder-remaining',
          name: '',
          description: '',
          filePath: 'remaining.png',
          createdAt: DateTime(2026),
        ),
      ]
      ..personaStickerBindings = [
        PersonaStickerBinding(
          personaId: 'persona-1',
          groupId: 'group-1',
          createdAt: DateTime(2026),
        ),
      ]
      ..personaStickerSettings = [
        PersonaStickerSettings(
          personaId: 'persona-1',
          preferredFolderIds: ['folder-deleted'],
        ),
      ];
    addTearDown(state.dispose);

    await state.removeStickerFolder('folder-deleted');

    expect(state.personaStickerSettings.single.preferredFolderIds, isEmpty);
    expect(state.stickersForPersonaFolder('persona-1', '开心').map((e) => e.id), [
      'sticker-remaining',
    ]);
  });
}

class _FixedRandom implements Random {
  final int value;

  _FixedRandom(this.value);

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => value / 100;

  @override
  int nextInt(int max) => value.clamp(0, max - 1);
}
