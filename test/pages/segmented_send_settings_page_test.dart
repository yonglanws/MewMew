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

  testWidgets('设置页显示三态模式、预设和本地分段预览', (tester) async {
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

    expect(find.text('实时流式'), findsNWidgets(2));
    expect(find.text('延迟预设'), findsOneWidget);
    expect(find.text('预览分段'), findsOneWidget);
    expect(find.textContaining('预计等待'), findsOneWidget);

    await state.setAssistantOutputMode(AssistantOutputMode.segmented);
    await tester.pumpAndSettle();
    expect(find.text('分段发送'), findsWidgets);
  });
}
