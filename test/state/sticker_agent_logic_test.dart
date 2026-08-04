import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/sticker_selection.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('表情包发送频率默认 10% 并持久化且限制在 0 到 100', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    expect(state.stickerSendProbability, 10);

    await state.setStickerSendProbability(150);
    expect(state.stickerSendProbability, 100);

    await state.setStickerSendProbability(-1);
    expect(state.stickerSendProbability, 0);

    await state.setStickerSendProbability(42);
    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    expect(reloadedStorage.stickerSendProbability, 42);
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

  test('发送频率 0% 禁用，100% 放行，中间值按概率判断', () {
    expect(
      StickerSelection.allowsSticker(probability: 0, random: Random(0)),
      isFalse,
    );
    expect(
      StickerSelection.allowsSticker(probability: 100, random: Random(0)),
      isTrue,
    );
    expect(
      StickerSelection.allowsSticker(probability: 50, random: _FixedRandom(49)),
      isTrue,
    );
    expect(
      StickerSelection.allowsSticker(probability: 50, random: _FixedRandom(50)),
      isFalse,
    );
  });

  test('100%发送频率会要求 AI 在有合适情绪时输出标签并说明不会强制生成', () {
    final instruction = stickerFrequencyInstruction(100);

    expect(instruction, contains('需要使用表情包时必须使用标签'));
    expect(instruction, contains('不要为了满足概率凭空添加表情包'));
    expect(instruction, contains('不会替 AI 生成标签'));
  });

  test('表情包提示词明确协议、名称匹配和自定义偏好的边界', () {
    final prompt = buildStickerPromptSection(
      maxStickersPerMessage: 2,
      sendProbability: 50,
      folderEntries: {'开心': '表达开心的情绪'},
      customPrompt: '开心时优先使用可爱的表情。',
    );

    expect(prompt, contains('标签放行概率'));
    expect(prompt, contains('name 必须与清单中的名称逐字匹配'));
    expect(prompt, contains('不要把标签放在 Markdown 代码块、引号、示例或解释文字中'));
    expect(prompt, contains('【人格表情使用策略（用户自定义）】'));
    expect(prompt, contains('不能覆盖上面的协议、清单或数量限制'));
  });

  test('用户自定义提示词会控制发送时机、情绪偏好、回避条件和表达风格', () {
    final prompt = buildStickerPromptSection(
      maxStickersPerMessage: 2,
      sendProbability: 50,
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

  test('人格表情包设置按人格持久化并保持默认值', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    expect(state.personaStickerSettingsFor('persona-1').sendProbability, 10);

    await state.setPersonaStickerSettings(
      PersonaStickerSettings(
        personaId: 'persona-1',
        sendProbability: 65,
        preferredFolderIds: ['folder-happy'],
        customPrompt: '开心时优先发送轻松可爱的表情。',
      ),
    );

    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    final saved = reloadedStorage.loadPersonaStickerSettings().single;
    expect(saved.sendProbability, 65);
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
