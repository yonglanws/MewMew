import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/persona_page.dart';
import 'package:mewmew/pages/sticker_management_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('人格设定把创建角色移到右下角 FAB', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaPage()));

    expect(find.byTooltip('创建角色'), findsNothing);
    expect(find.text('创建角色'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('创建人格页面把保存移到右下角 FAB', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaEditorPage()));

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('表情包组详情把右上角操作移到右下角操作面板', (tester) async {
    final state = AppState(StorageService())
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常', createdAt: DateTime(2026)),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      _host(state, StickerGroupPage(group: state.stickerGroups.single)),
    );

    expect(find.byTooltip('编辑组名'), findsNothing);
    expect(find.byTooltip('绑定人格'), findsNothing);
    expect(find.byTooltip('新建文件夹'), findsNothing);
    expect(find.text('管理表情包组'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('管理表情包组'));
    await tester.pumpAndSettle();

    expect(find.text('编辑组名'), findsOneWidget);
    expect(find.text('绑定人格'), findsOneWidget);
    expect(find.text('新建文件夹'), findsOneWidget);
  });

  testWidgets('表情包文件夹把导入移到右下角 FAB', (tester) async {
    final folder = StickerFolder(
      id: 'folder-1',
      groupId: 'group-1',
      name: '开心',
      description: '',
      createdAt: DateTime(2026),
    );
    final state = AppState(StorageService())..stickerFolders = [folder];
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, StickerFolderPage(folder: folder)));

    expect(find.byTooltip('导入表情包'), findsNothing);
    expect(find.text('导入表情包'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Widget _host(AppState state, Widget child) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
);
