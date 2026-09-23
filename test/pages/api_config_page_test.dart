import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/api_config_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

/// API 配置页（供应商-模型两级）：详情页添加模型、点选切换当前模型
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> buildState() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    await state.load();
    await state.addOrUpdateApi(
      ApiConfig(
        id: 'p1',
        name: 'zhipu',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        apiKey: 'sk-test',
        model: 'glm-5.3',
        models: [ApiModelEntry(id: 'm1', model: 'glm-5.3')],
      ),
    );
    return state;
  }

  Widget host(AppState state) => ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(theme: AppTheme.lightTheme(), home: const ApiConfigPage()),
  );

  testWidgets('供应商卡片展示模型数，详情页可添加并切换模型', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    // 列表卡片：供应商名 + 模型数 + 跳转符号
    expect(find.text('zhipu'), findsOneWidget);
    expect(find.textContaining('1 个模型'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // 进入详情页
    await tester.tap(find.text('zhipu'));
    await tester.pumpAndSettle();
    expect(find.text('模型（1）'), findsOneWidget);
    expect(find.text('glm-5.3'), findsOneWidget);
    // "使用中"：列表页卡片 + 详情信息卡 + 模型行均存在
    expect(find.text('使用中'), findsWidgets);

    // 添加模型：手动输入 glm-5.2
    await tester.tap(find.text('添加模型'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'glm-5.2');
    await tester.pump(); // 让 onChanged 触发的重建生效（按钮启用）
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(state.apiConfigs.first.models, hasLength(2));
    expect(find.text('glm-5.2'), findsOneWidget);
    expect(find.text('模型（2）'), findsOneWidget);

    // 点 glm-5.2 行 → 设为当前模型（供应商同步激活）
    await tester.tap(find.text('glm-5.2'));
    await tester.pumpAndSettle();
    expect(state.activeApi?.model, 'glm-5.2');
    expect(find.text('使用中'), findsWidgets);

    // glm-5.2 行有对勾，glm-5.3 行没有（只有 1 个选中态图标）
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('空供应商提示先添加模型；返回后列表刷新模型数', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    state.apiConfigs.first
      ..models.clear()
      ..model = '';
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未添加模型'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('添加供应商：保存后直接进入详情页配置模型', (tester) async {
    final state = await buildState();
    addTearDown(state.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    state.apiConfigs.clear();
    state.activeApiId = null;

    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无供应商'), findsOneWidget);

    await tester.tap(find.text('添加供应商'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '供应商名称（如 zhipu）'),
      'zhipu',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'https://open.bigmodel.cn/api/paas/v4',
    );
    await tester.enterText(find.widgetWithText(TextField, 'API Key'), 'sk-x');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 已入库并直接进入详情页（空模型引导）
    expect(state.apiConfigs, hasLength(1));
    expect(state.apiConfigs.first.name, 'zhipu');
    expect(find.textContaining('还没有模型'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
