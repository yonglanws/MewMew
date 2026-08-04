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

  test('流式输出开启时保持禁用表情包，关闭后才允许使用', () {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    state.streamOutputEnabled = true;
    expect(state.stickersEnabled, isFalse);

    state.streamOutputEnabled = false;
    expect(state.stickersEnabled, isTrue);
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
