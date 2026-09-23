import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/world_book_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    return state;
  }

  Widget host(AppState state) => MaterialApp(
    theme: AppTheme.lightTheme(),
    home: ChangeNotifierProvider<AppState>.value(value: state, child: const WorldBookPage()),
  );

  testWidgets('启用世界书与递归扫描开关持久化', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    expect(state.worldBookSettings.enabled, false);

    await tester.pumpWidget(host(state));

    // 未启用时递归扫描开关禁用
    expect(tester.widgetList<Switch>(find.byType(Switch)).last.onChanged, isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.enabled, true);
    // 启用后递归扫描开关可交互
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).last.onChanged,
      isNotNull,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('扫描深度与字符预算弹窗调整', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.worldBookSettings = WorldBookSettings(enabled: true);

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('扫描深度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.scanDepth, 4); // 默认值直接确定不变

    await tester.tap(find.text('字符预算'));
    await tester.pumpAndSettle();
    final sliderCenter = tester.getCenter(find.byType(Slider));
    final left = tester.getTopLeft(find.byType(Slider)).dx;
    final right = tester.getTopRight(find.byType(Slider)).dx;
    await tester.tapAt(Offset(left + (right - left) * 0.8, sliderCenter.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.maxChars, greaterThan(1200));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('添加条目：关键词解析、常驻开关与保存', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.worldBookSettings = WorldBookSettings(enabled: true);

    await tester.pumpWidget(host(state));
    await tester.tap(find.text('添加条目'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '条目名称').first,
      '月见高中',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '触发关键词').first,
      '月见，高中，校园',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '设定内容').first,
      '角色们就读于月见高中。',
    );
    await tester.tap(find.text('常驻条目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final wb = state.worldBookSettings;
    expect(wb.entries, hasLength(1));
    expect(wb.entries.first.title, '月见高中');
    // 中文逗号/英文逗号都能分隔
    expect(wb.entries.first.keywords, ['月见', '高中', '校园']);
    expect(wb.entries.first.content, '角色们就读于月见高中。');
    expect(wb.entries.first.constant, true);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('注入位置切换到 @Depth 并显示深度与角色条目', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    // 从 system 起步，验证可切换到 depth
    state.worldBookSettings = WorldBookSettings(
      enabled: true,
      injectionPosition: 'system',
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1800));

    await tester.pumpWidget(host(state));
    expect(find.text('注入位置'), findsOneWidget);
    // system 模式下页面上没有 depth 字样，弹窗选项不会撞车
    expect(find.text('聊天记录深处 @Depth'), findsNothing);

    await tester.tap(find.text('注入位置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天记录深处 @Depth'));
    await tester.pumpAndSettle();

    expect(state.worldBookSettings.injectionPosition, 'depth');
    expect(find.text('注入深度'), findsOneWidget);
    expect(find.text('注入角色'), findsOneWidget);

    await tester.tap(find.text('注入角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('user（伪装成用户消息）'));
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.injectionRole, 'user');
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('默认注入位置为聊天记录深处 @Depth（缓存友好默认）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.worldBookSettings = WorldBookSettings(enabled: true);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1800));

    expect(state.worldBookSettings.injectionPosition, 'depth');
    expect(state.worldBookSettings.injectionDepth, 2);

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    // depth 专属条目直接可见
    expect(find.text('注入深度'), findsOneWidget);
    expect(find.text('注入角色'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(' AppBar 提供导入与导出入口', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);

    await tester.pumpWidget(host(state));

    expect(find.byTooltip('导入条目'), findsOneWidget);
    expect(find.byTooltip('导出条目'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('条目编辑弹层支持次级关键词（AND）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.worldBookSettings = WorldBookSettings(enabled: true);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));
    await tester.tap(find.text('添加条目'));
    await tester.pumpAndSettle();

    expect(find.text('次级关键词（可选）'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '触发关键词').first, '月见');
    await tester.enterText(
      find.widgetWithText(TextField, '次级关键词（可选）').first,
      '祭典',
    );
    await tester.enterText(find.widgetWithText(TextField, '设定内容').first, '内容');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final entry = state.worldBookSettings.entries.single;
    expect(entry.keywords, ['月见']);
    expect(entry.secondaryKeywords, ['祭典']);
    // AND 逻辑：只出现"月见"不触发
    expect(entry.matches('月见很美'), isFalse);
    expect(entry.matches('月见办祭典'), isTrue);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('编辑、禁用与删除条目', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.worldBookSettings = WorldBookSettings(
      enabled: true,
      entries: [
        WorldBookEntry(
          id: 'e1',
          title: '旧条目',
          keywords: ['关键词'],
          content: '内容',
        ),
      ],
    );

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(host(state));
    expect(find.text('旧条目'), findsOneWidget);

    // 禁用条目
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.entries.first.enabled, false);

    // 删除条目（走确认弹窗）
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除条目'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(state.worldBookSettings.entries, isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });
}
