import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/memory_settings_page.dart';
import 'package:mewmew/pages/message_debounce_settings_page.dart';
import 'package:mewmew/pages/segmented_send_settings_page.dart';
import 'package:mewmew/pages/settings_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('设置页用右下角 FAB 切换流式输出', (tester) async {
    final state = await _createState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const SettingsPage()));

    expect(find.byType(Switch), findsNothing);
    expect(find.text('关闭流式输出'), findsOneWidget);

    await tester.tap(find.text('关闭流式输出'));
    await tester.pumpAndSettle();

    expect(state.streamOutputEnabled, isFalse);
  });

  testWidgets('记忆页用右下角 FAB 切换记忆系统', (tester) async {
    final state = await _createState();
    state.embeddingApiConfig = EmbeddingApiConfig(
      baseUrl: 'https://embedding.example.com',
      apiKey: 'test-key',
      model: 'embedding-model',
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const MemorySettingsPage()));

    expect(find.byType(Switch), findsNothing);
    expect(find.text('关闭记忆系统'), findsOneWidget);

    await tester.tap(find.text('关闭记忆系统'));
    await tester.pumpAndSettle();

    expect(state.injectMemories, isFalse);
  });

  testWidgets('消息防抖动页把两个开关收进右下角面板', (tester) async {
    final state = await _createState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const MessageDebounceSettingsPage()));

    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.text('防抖开关'));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('分段发送页把三个开关收进右下角面板', (tester) async {
    final state = await _createState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_host(state, const SegmentedSendSettingsPage()));

    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.text('分段开关'));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsNWidgets(3));
  });
}

Future<AppState> _createState() async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  return AppState(storage);
}

Widget _host(AppState state, Widget child) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
);
