import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/pages/segmented_send_settings_page.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设置页不显示额外的模式、预设和分段预览控件', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SegmentedSendSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('回复显示方式'), findsNothing);
    expect(find.text('实时流式'), findsNothing);
    expect(find.text('延迟预设'), findsNothing);
    expect(find.text('快速'), findsNothing);
    expect(find.text('自然'), findsNothing);
    expect(find.text('慢速'), findsNothing);
    expect(find.text('预览分段'), findsNothing);
    expect(find.textContaining('预计等待'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('正则输入不在设置页做格式校验', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final state = AppState(storage);
    addTearDown(state.dispose);

    await state.setAssistantOutputMode(AssistantOutputMode.segmented);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: SegmentedSendSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await state.setSegmentedSendSettings(
      state.segmentedSendSettings.copyWith(enabled: true),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('前置清理正则'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.text('前置清理正则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前置清理正则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '[');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(state.segmentedSendSettings.preCleanRegex, '[');
    await tester.pump(const Duration(milliseconds: 500));
  });
}
