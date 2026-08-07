import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mewmew/services/segmented_delivery_scheduler.dart';
import 'package:mewmew/services/storage_service.dart';
import 'package:mewmew/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('停止生成会取消当前会话的分段批次', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final gates = <Completer<void>>[];
    Future<void> wait(Duration _) {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    }

    final scheduler = SegmentedDeliveryScheduler(wait: wait);
    final state = AppState(storage, segmentedDeliveryScheduler: scheduler);
    addTearDown(state.dispose);

    final done = scheduler.deliver(
      sessionId: 'session-1',
      itemCount: 2,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: (_) {},
    );
    await pumpEventQueue();

    state.stopGeneration();

    expect(await done, SegmentedDeliveryResult.cancelled);
  });
}
