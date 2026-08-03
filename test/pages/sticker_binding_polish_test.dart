import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/sticker_management_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';
import 'package:mewmew/widgets/persona_avatar.dart';

void main() {
  testWidgets('人格绑定页直接点击人格，不显示绑定 FAB 和分割线', (tester) async {
    final state = AppState(StorageService())
      ..personas = [
        Persona(id: 'persona-1', name: '小猫', emoji: '🐱'),
        Persona(id: 'persona-2', name: '小狗', emoji: '🐶'),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const PersonaStickerBindingPage()));

    expect(find.text('绑定人格'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PersonaAvatar), findsNWidgets(2));
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('表情包组列表使用组内表情包图片并移除分割线', (tester) async {
    final group = StickerGroup(
      id: 'group-1',
      name: '日常反应',
      createdAt: DateTime(2026),
    );
    final state = AppState(StorageService())
      ..stickerGroups = [
        group,
        StickerGroup(id: 'group-2', name: '工作状态', createdAt: DateTime(2026)),
      ]
      ..stickerFolders = [
        StickerFolder(
          id: 'folder-1',
          groupId: group.id,
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

    await tester.pumpWidget(_host(state, const StickerGroupListPage()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });
}

Widget _host(AppState state, Widget child) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
);
