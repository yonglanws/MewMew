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
  testWidgets('首页在窄屏显示资源和人格管理入口', (tester) async {
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
    expect(find.text('个性化设置'), findsOneWidget);
    expect(find.text('表情包组'), findsWidgets);
    expect(find.text('表情包管理器'), findsOneWidget);
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

  testWidgets('表情包页面提供人格表情包管理器入口', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = false
      ..personas = [Persona(id: 'persona-1', name: '小猫', emoji: '🐱')];
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

    expect(find.text('表情包'), findsWidgets);
    expect(find.text('表情包管理器'), findsWidgets);

    await tester.tap(find.text('表情包管理器'));
    await tester.pumpAndSettle();
    expect(find.text('表情包管理器'), findsWidgets);
    expect(find.text('小猫'), findsOneWidget);
    expect(find.text('10%'), findsNothing);
    expect(find.text('已绑定'), findsNothing);

    await tester.tap(find.text('小猫'));
    await tester.pumpAndSettle();
    expect(find.text('绑定的表情包组'), findsOneWidget);
  });

  testWidgets('人格详情优先显示发送方式并为组和情绪分组提供图标', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = false
      ..personas = [Persona(id: 'persona-1', name: '小猫', emoji: '🐱')]
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
          name: '',
          description: '',
          filePath: '',
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
          sendMode: StickerSendMode.high,
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const PersonaStickerSettingsPage(personaId: 'persona-1'),
        ),
      ),
    );

    expect(find.text('表情包发送方式'), findsOneWidget);
    expect(find.text('不发送表情包'), findsOneWidget);
    expect(find.text('低频率发表情包'), findsOneWidget);
    expect(find.text('高频率发表情包'), findsOneWidget);
    expect(find.byType(RadioListTile<StickerSendMode>), findsNWidgets(3));
    expect(find.text('绑定的表情包组'), findsOneWidget);
    expect(find.text('喜欢的情绪分组'), findsOneWidget);
    expect(find.text('表情使用策略'), findsOneWidget);
    expect(find.textContaining('可以直接描述什么时候发送'), findsOneWidget);
    final sections = ['绑定的表情包组', '喜欢的情绪分组', '表情包发送方式', '表情使用策略'];
    for (var i = 0; i < sections.length - 1; i++) {
      expect(
        tester.getTopLeft(find.text(sections[i])).dy,
        lessThan(tester.getTopLeft(find.text(sections[i + 1])).dy),
      );
    }
    expect(find.byType(PersonaAvatar), findsNothing);
    expect(
      tester
          .widgetList<RadioListTile<StickerSendMode>>(
            find.byType(RadioListTile<StickerSendMode>),
          )
          .every((radio) => radio.onChanged != null),
      isTrue,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .every((chip) => chip.showCheckmark == false),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未绑定表情包组时禁用人格的其他表情包设置', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = false
      ..personas = [Persona(id: 'persona-1', name: '小猫', emoji: '🐱')]
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
      ..personaStickerSettings = [
        PersonaStickerSettings(
          personaId: 'persona-1',
          sendMode: StickerSendMode.high,
          preferredFolderIds: ['folder-1'],
          customPrompt: '保持可爱',
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const PersonaStickerSettingsPage(personaId: 'persona-1'),
        ),
      ),
    );

    expect(find.text('绑定的表情包组'), findsOneWidget);
    expect(find.text('喜欢的情绪分组'), findsOneWidget);
    expect(find.text('表情包发送方式'), findsOneWidget);
    expect(find.text('表情使用策略'), findsOneWidget);
    expect(
      tester
          .widgetList<RadioListTile<StickerSendMode>>(
            find.byType(RadioListTile<StickerSendMode>),
          )
          .every((radio) => radio.onChanged == null),
      isTrue,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AnimatedOpacity && widget.opacity == 0.45,
      ),
      findsNWidgets(3),
    );

    await tester.tap(find.byType(FilterChip).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '开心')).selected,
      isTrue,
    );
    expect(
      tester
          .widgetList<RadioListTile<StickerSendMode>>(
            find.byType(RadioListTile<StickerSendMode>),
          )
          .every((radio) => radio.onChanged != null),
      isTrue,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('开启流式输出时表情包管理器显示互斥提示并禁用编辑', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = true
      ..personas = [Persona(id: 'persona-1', name: '小猫', emoji: '🐱')];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const StickerPersonaManagerPage(),
        ),
      ),
    );

    expect(find.textContaining('表情包发送和流式输出互斥'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.52,
      ),
      findsWidgets,
    );
    expect(find.text('小猫'), findsOneWidget);

    await tester.tap(find.text('小猫'));
    await tester.pumpAndSettle();
    expect(find.text('绑定的表情包组'), findsNothing);
  });

  testWidgets('流式输出开启时具体人格设置页不受管理器灰化影响', (tester) async {
    final state = AppState(StorageService())
      ..streamOutputEnabled = true
      ..personas = [Persona(id: 'persona-1', name: '小猫', emoji: '🐱')]
      ..stickerGroups = [
        StickerGroup(id: 'group-1', name: '日常', createdAt: DateTime(2026)),
      ]
      ..personaStickerBindings = [
        PersonaStickerBinding(
          personaId: 'persona-1',
          groupId: 'group-1',
          createdAt: DateTime(2026),
        ),
      ];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const PersonaStickerSettingsPage(personaId: 'persona-1'),
        ),
      ),
    );

    expect(find.textContaining('表情包发送和流式输出互斥'), findsNothing);
    final radios = tester
        .widgetList<RadioListTile<StickerSendMode>>(
          find.byType(RadioListTile<StickerSendMode>),
        )
        .toList();
    expect(radios, hasLength(3));
    expect(radios.every((radio) => radio.onChanged != null), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isNot(false),
    );
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
  });
}
