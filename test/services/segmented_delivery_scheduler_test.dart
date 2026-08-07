import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mewmew/services/segmented_delivery_scheduler.dart';

void main() {
  test('按顺序投递并在 flush 后立即完成剩余段', () async {
    final gates = <Completer<void>>[];
    final delivered = <int>[];
    Future<void> wait(Duration _) {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    }

    final scheduler = SegmentedDeliveryScheduler(wait: wait);
    final done = scheduler.deliver(
      sessionId: 's1',
      itemCount: 3,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: delivered.add,
    );

    await pumpEventQueue();
    expect(gates, hasLength(1));
    expect(delivered, isEmpty);

    gates.removeAt(0).complete();
    await pumpEventQueue();
    expect(delivered, [0]);
    expect(scheduler.deliveredCount('s1'), 1);
    expect(scheduler.totalCount('s1'), 3);

    scheduler.flushSession('s1');
    expect(await done, SegmentedDeliveryResult.flushed);
    expect(delivered, [0, 1, 2]);
    expect(scheduler.isActive('s1'), isFalse);
  });

  test('取消只保留已投递段并完成等待 future', () async {
    final gates = <Completer<void>>[];
    final delivered = <int>[];
    Future<void> wait(Duration _) {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    }

    final scheduler = SegmentedDeliveryScheduler(wait: wait);
    final done = scheduler.deliver(
      sessionId: 's1',
      itemCount: 2,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: delivered.add,
    );

    await pumpEventQueue();
    scheduler.cancelSession('s1');

    expect(await done, SegmentedDeliveryResult.cancelled);
    expect(delivered, isEmpty);
    await scheduler.whenIdle('s1');
    expect(scheduler.isActive('s1'), isFalse);
  });

  test('同一会话的新批次会取消并替换旧批次', () async {
    final firstDelivered = <int>[];
    final secondDelivered = <int>[];
    final scheduler = SegmentedDeliveryScheduler(
      wait: (_) => Future<void>.value(),
    );

    final first = scheduler.deliver(
      sessionId: 's1',
      itemCount: 2,
      delayFor: (_) => Duration.zero,
      onDeliver: firstDelivered.add,
    );
    final second = scheduler.deliver(
      sessionId: 's1',
      itemCount: 1,
      delayFor: (_) => Duration.zero,
      onDeliver: secondDelivered.add,
    );

    expect(await first, SegmentedDeliveryResult.cancelled);
    expect(await second, SegmentedDeliveryResult.completed);
    expect(firstDelivered, isEmpty);
    expect(secondDelivered, [0]);
  });

  test('cancelAll 会完成所有会话的等待 future', () async {
    final scheduler = SegmentedDeliveryScheduler(
      wait: (_) => Completer<void>().future,
    );
    final first = scheduler.deliver(
      sessionId: 's1',
      itemCount: 1,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: (_) {},
    );
    final second = scheduler.deliver(
      sessionId: 's2',
      itemCount: 1,
      delayFor: (_) => const Duration(seconds: 1),
      onDeliver: (_) {},
    );

    scheduler.cancelAll();

    expect(await first, SegmentedDeliveryResult.cancelled);
    expect(await second, SegmentedDeliveryResult.cancelled);
    expect(scheduler.isActive('s1'), isFalse);
    expect(scheduler.isActive('s2'), isFalse);
  });

  test('delayFor 只在批次启动时读取一次', () async {
    var calls = 0;
    final delivered = <int>[];
    final scheduler = SegmentedDeliveryScheduler(
      wait: (_) => Future<void>.value(),
    );

    final done = scheduler.deliver(
      sessionId: 's1',
      itemCount: 3,
      delayFor: (_) {
        calls++;
        return Duration.zero;
      },
      onDeliver: delivered.add,
    );

    expect(await done, SegmentedDeliveryResult.completed);
    expect(calls, 3);
    expect(delivered, [0, 1, 2]);
  });
}
