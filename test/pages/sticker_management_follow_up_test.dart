import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/sticker_management_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('组列表用组名和表情包组副标题，并把新建放到 FAB', (tester) async {
    final state = AppState(StorageService())
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常反应', createdAt: DateTime(2026)),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const StickerGroupListPage()));

    expect(find.text('日常反应'), findsOneWidget);
    expect(find.text('表情包组'), findsNWidgets(2));
    expect(find.text('新建表情包组'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('新建表情包组'), findsNothing);
  });

  testWidgets('空组列表通过右下角 FAB 创建，不重复显示中心按钮', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const StickerGroupListPage()));

    expect(find.text('还没有表情包组'), findsOneWidget);
    expect(find.text('新建表情包组'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('组详情可以编辑组名并立即更新状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final group = StickerGroup(
      id: 'group-1',
      name: '旧名称',
      createdAt: DateTime(2026),
    );
    final state = AppState(storage)..stickerGroups = [group];
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, StickerGroupPage(group: group)));
    await tester.tap(find.text('管理表情包组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑组名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新的组名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.stickerGroups.single.name, '新的组名');
    expect(find.text('新的组名'), findsOneWidget);
  });

  testWidgets('人格绑定通过人格列表进入，不显示独立绑定 FAB', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaStickerBindingPage()));

    expect(find.text('绑定人格'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('文件夹使用子表情包图片作为缩略图', (tester) async {
    final state = AppState(StorageService())
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-1',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickers = [
        StickerItem(
          id: 'sticker-1',
          folderId: 'folder-1',
          name: 'legacy-name',
          description: '',
          filePath: 'screen1.png',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _host(
        state,
        StickerGroupPage(
          group: StickerGroup(
            id: 'group-1',
            name: '日常',
            createdAt: DateTime(2026),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('表情网格不显示历史表情包名称', (tester) async {
    final folder = StickerFolder(
      id: 'folder-1',
      groupId: 'group-1',
      name: '开心',
      description: '',
      createdAt: DateTime(2026),
    );
    final state = AppState(StorageService())
      ..stickerFolders = [folder]
      ..stickers = [
        StickerItem(
          id: 'sticker-1',
          folderId: 'folder-1',
          name: 'legacy-name',
          description: '',
          filePath: 'screen1.png',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, StickerFolderPage(folder: folder)));

    expect(find.text('legacy-name'), findsNothing);
  });
}

Widget _host(AppState state, Widget child) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
);
