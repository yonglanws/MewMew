import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/sticker_management_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('首页在窄屏显示概览和两类管理入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState(StorageService())
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常', createdAt: DateTime(2026)),
      ]
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
          name: '笑脸',
          description: '',
          filePath: '',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const StickerManagementPage(),
        ),
      ),
    );

    expect(find.text('表情包概览'), findsOneWidget);
    expect(find.text('资源管理'), findsOneWidget);
    expect(find.text('使用关系'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空表情包文件夹显示说明和导入操作', (tester) async {
    final state = AppState(StorageService())
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-1',
          groupId: 'group-1',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: StickerFolderPage(
            folder: StickerFolder(
              id: 'folder-1',
              groupId: 'group-1',
              name: '开心',
              description: '',
              createdAt: DateTime(2026),
            ),
          ),
        ),
      ),
    );

    expect(find.text('导入图片后会显示在这里。'), findsOneWidget);
    expect(find.text('导入表情包'), findsOneWidget);
  });
}
