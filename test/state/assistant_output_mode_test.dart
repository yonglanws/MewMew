import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final storage = StorageService();
    await storage.init();
    return storage;
  }

  test('旧配置迁移为唯一输出模式', () async {
    final cases = <Map<String, Object>, AssistantOutputMode>{
      {'stream_output_enabled': true}: AssistantOutputMode.streaming,
      {
        'stream_output_enabled': false,
        'segmented_send_settings': jsonEncode({'enabled': true}),
      }: AssistantOutputMode.segmented,
      {
        'stream_output_enabled': false,
        'segmented_send_settings': jsonEncode({'enabled': false}),
      }: AssistantOutputMode.complete,
      {
        'stream_output_enabled': true,
        'segmented_send_settings': jsonEncode({'enabled': true}),
      }: AssistantOutputMode.streaming,
      {
        'segmented_send_settings': jsonEncode({'enabled': true}),
      }: AssistantOutputMode.segmented,
    };

    for (final entry in cases.entries) {
      final storage = await storageWith(entry.key);
      expect(storage.loadAssistantOutputMode(), entry.value);
    }
  });

  test('输出模式持久化后重新加载保持一致', () async {
    final storage = await storageWith({});
    final state = AppState(storage);
    addTearDown(state.dispose);

    await state.setAssistantOutputMode(AssistantOutputMode.segmented);

    final reloaded = StorageService();
    await reloaded.init();
    expect(reloaded.loadAssistantOutputMode(), AssistantOutputMode.segmented);
  });
}
