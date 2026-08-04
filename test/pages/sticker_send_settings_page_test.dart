import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/pages/settings_page.dart';
import 'package:mewmew/pages/sticker_send_settings_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('表情包发送频率页显示当前值并可调整', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pump(const Duration(milliseconds: 500));
    final state = AppState(storage)..stickerSendProbability = 35;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const StickerSendSettingsPage(),
        ),
      ),
    );

    expect(find.text('35%'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining('开启流式输出时不会发送表情包'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(80);
    await tester.pump();
    expect(state.stickerSendProbability, 80);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('设置页提供表情包发送频率入口', (tester) async {
    final state = AppState(StorageService());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const SettingsPage(),
        ),
      ),
    );

    expect(find.text('表情包发送频率'), findsOneWidget);
  });
}
