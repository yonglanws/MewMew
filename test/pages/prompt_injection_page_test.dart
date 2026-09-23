import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/prompt_injection_page.dart';
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
    home: ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const PromptInjectionPage(),
    ),
  );

  testWidgets('页面没有任何开关，全部为可编辑内容槽位', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    expect(find.byType(Switch), findsNothing);
    expect(find.text('实时状态模板'), findsOneWidget);
    expect(find.text('私聊注入'), findsOneWidget);
    expect(find.text('群聊注入'), findsOneWidget);
    expect(find.text('生成风格'), findsNWidgets(2));
    // 默认（未自定义）时副标题展示内置默认文案首行
    expect(find.textContaining('一对一私聊'), findsOneWidget);
    // 生成风格未设置时副标题提示
    expect(find.textContaining('未设置'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('生成风格槽位编辑并保存到 AppState', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('生成风格').last);
    await tester.pumpAndSettle();
    // 生成风格没有"恢复默认"（留空即不注入），只有"清空"
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('恢复默认'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '回复要非常简短');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.generationStyleSettings.stylePrompt, '回复要非常简短');
  });

  testWidgets('编辑实时状态模板：占位符模板保存后生效', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('实时状态模板'));
    await tester.pumpAndSettle();
    // 弹层内预填默认模板（条目副标题也展示默认文案首行，故用 findsWidgets）
    expect(find.textContaining('实时状态（系统注入'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, '当前{period}，和{partner}聊天');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.promptInjectionSettings.contextPrompt, '当前{period}，和{partner}聊天');
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('占位符以芯片呈现，点按插入到光标处', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('实时状态模板'));
    await tester.pumpAndSettle();

    // 芯片展示中文名 + token 徽标
    expect(find.text('时段'), findsOneWidget);
    expect(find.text('{period}'), findsOneWidget);
    expect(find.text('聊天对象'), findsOneWidget);

    // 光标在末尾（enterText 后），点「时段」芯片把 {period} 追加进去
    await tester.enterText(find.byType(TextField).last, '现在是');
    await tester.tap(find.text('时段'));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(
      find.byType(TextField).last,
    ).controller!;
    expect(controller.text, '现在是{period}');
    expect(controller.selection.baseOffset, controller.text.length);

    // 不再以裸文本长串说明占位符
    expect(find.textContaining('{date} 日期 · {weekday} 星期'), findsNothing);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('编辑私聊注入并保存（自定义覆盖默认）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('私聊注入'));
    await tester.pumpAndSettle();
    expect(find.text('私聊注入文案'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '这是我自定义的私聊规则');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.promptInjectionSettings.privatePrompt, '这是我自定义的私聊规则');
    // 弹层关闭后副标题显示自定义文案
    expect(find.textContaining('这是我自定义的私聊规则'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('恢复默认后保存会重置为内置默认（存空串）', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.promptInjectionSettings = PromptInjectionSettings(
      privatePrompt: '旧的自定义',
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));
    await tester.tap(find.text('私聊注入'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.promptInjectionSettings.privatePrompt, '');
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('模式注入：切换到 @Depth 并调整深度', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    expect(state.promptInjectionSettings.mode, 'system');
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));

    await tester.tap(find.text('注入方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊天记录深处 @Depth'));
    await tester.pumpAndSettle();
    expect(state.promptInjectionSettings.mode, 'depth');

    // depth 专属条目出现
    expect(find.text('注入深度'), findsOneWidget);
    expect(find.text('注入角色'), findsOneWidget);

    await tester.tap(find.text('注入深度'));
    await tester.pumpAndSettle();
    final sliderCenter = tester.getCenter(find.byType(Slider));
    final sliderLeft = tester.getTopLeft(find.byType(Slider)).dx;
    final sliderRight = tester.getTopRight(find.byType(Slider)).dx;
    await tester.tapAt(
      Offset(sliderLeft + (sliderRight - sliderLeft) * 0.5, sliderCenter.dy),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(state.promptInjectionSettings.depth, greaterThan(0));
  await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('注入角色选择 user', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    state.promptInjectionSettings = PromptInjectionSettings(mode: 'depth');
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));

    await tester.pumpWidget(host(state));
    await tester.tap(find.text('注入角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('user（伪装成用户消息）'));
    await tester.pumpAndSettle();

    expect(state.promptInjectionSettings.role, 'user');
  await tester.pump(const Duration(seconds: 2));
  });
}
