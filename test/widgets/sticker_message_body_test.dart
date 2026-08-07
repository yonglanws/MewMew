import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';
import 'package:mewmew/widgets/sticker_message_body.dart';

void main() {
  testWidgets('表情包预览只解析当前人格绑定的同名情绪文件夹', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = false
      ..stickerGroups = [
        StickerGroup(id: 'bound-group', name: '日常', createdAt: DateTime(2026)),
        StickerGroup(id: 'other-group', name: '其他', createdAt: DateTime(2026)),
      ]
      ..stickerFolders = [
        StickerFolder(
          id: 'bound-folder',
          groupId: 'bound-group',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
        StickerFolder(
          id: 'other-folder',
          groupId: 'other-group',
          name: '开心',
          description: '',
          createdAt: DateTime(2026),
        ),
      ]
      ..stickers = [
        StickerItem(
          id: 'bound-sticker',
          folderId: 'bound-folder',
          name: '随便',
          description: '',
          filePath: 'bound.png',
          createdAt: DateTime(2026),
        ),
        StickerItem(
          id: 'other-sticker',
          folderId: 'other-folder',
          name: '随便',
          description: '',
          filePath: 'other.png',
          createdAt: DateTime(2026),
        ),
      ]
      ..personaStickerBindings = [
        PersonaStickerBinding(
          personaId: 'persona-1',
          groupId: 'bound-group',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => StickerMessageBody(
                content: '<sticker name="开心"/>',
                personaId: 'persona-1',
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, 'bound.png');
  });

  testWidgets('缺失表情包显示明确的不可用提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: StickerUnavailablePlaceholder()),
      ),
    );

    expect(find.text('表情包不可用'), findsOneWidget);
  });

  testWidgets('历史消息中的内部不可用占位词不会显示给用户', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: StickerMessageBody(
                content: '前文【发送了一个不可用的表情包】后文',
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('发送了一个不可用的表情包'), findsNothing);
    expect(find.textContaining('前文后文'), findsOneWidget);
  });
}
