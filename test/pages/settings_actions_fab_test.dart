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
  testWidgets('角色卡把创建角色卡移到右下角 FAB', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaPage()));

    expect(find.byTooltip('创建角色卡'), findsNothing);
    expect(find.text('创建角色卡'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('创建角色卡页面把保存移到右下角 FAB', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaEditorPage()));

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('角色卡提示词模板弹层：占位符芯片点按插入', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(_host(state, const PersonaEditorPage()));

    // 打开提示词模板弹层
    await tester.tap(find.text('提示词模板'));
    await tester.pumpAndSettle();

    // 芯片展示中文名 + token 徽标，不再是裸文本说明
    expect(find.text('外貌'), findsOneWidget);
    expect(find.text('{appearance}'), findsOneWidget);
    expect(find.textContaining('占位符：{name}'), findsNothing);

    // 点「外貌」芯片 → {appearance} 插入到光标处
    await tester.enterText(find.byType(TextField).last, '她是');
    await tester.tap(find.text('外貌'));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(
      find.byType(TextField).last,
    ).controller!;
    expect(controller.text, '她是{appearance}');
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
    expect(find.text('新建文件夹'), findsOneWidget);
    expect(find.text('绑定人格'), findsNothing);
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
