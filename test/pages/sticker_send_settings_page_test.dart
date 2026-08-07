import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/pages/settings_page.dart';
import 'package:mewmew/pages/sticker_send_settings_page.dart';
import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';
import 'package:mewmew/theme/app_theme.dart';

void main() {
  testWidgets('表情包发送方式页显示当前选项并可调整', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pump(const Duration(milliseconds: 500));
    final state = AppState(storage)..stickerSendMode = StickerSendMode.low;
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

    expect(find.text('表情包发送方式'), findsWidgets);
    expect(find.text('不发送表情包'), findsOneWidget);
    expect(find.text('低频率发表情包'), findsOneWidget);
    expect(find.text('高频率发表情包'), findsOneWidget);
    expect(find.byType(RadioListTile<StickerSendMode>), findsNWidgets(3));

    final radios = tester
        .widgetList<RadioListTile<StickerSendMode>>(
          find.byType(RadioListTile<StickerSendMode>),
        )
        .toList();
    final high = radios.firstWhere(
      (radio) => radio.value == StickerSendMode.high,
    );
    high.onChanged!(StickerSendMode.high);
    await tester.pump();
    expect(state.stickerSendMode, StickerSendMode.high);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('设置页将表情包资源与人格偏好统一放入表情包页面', (tester) async {
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

    expect(find.text('表情包'), findsOneWidget);
    expect(find.text('表情包发送方式'), findsNothing);
  });
}
