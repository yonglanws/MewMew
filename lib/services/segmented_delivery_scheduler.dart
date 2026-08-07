import 'dart:async';

typedef SegmentWait = Future<void> Function(Duration delay);

enum SegmentedDeliveryResult { completed, flushed, cancelled }

/// 可取消的分段投递调度器。
///
/// 调度器只负责等待和顺序，不知道聊天消息模型；调用方通过 onDeliver
/// 把已经到时的下标写入自己的状态。每个会话有独立批次，设置参数应在
/// deliver 前计算为不可变的 delayFor 结果。
class SegmentedDeliveryScheduler {
  SegmentedDeliveryScheduler({SegmentWait? wait})
    : _wait = wait ?? ((delay) => Future<void>.delayed(delay));

  final SegmentWait _wait;
  final Map<String, _DeliveryRun> _runs = {};
  bool _disposed = false;

  bool isActive(String sessionId) => _runs[sessionId]?.isActive ?? false;

  int deliveredCount(String sessionId) => _runs[sessionId]?.deliveredCount ?? 0;

  int totalCount(String sessionId) => _runs[sessionId]?.itemCount ?? 0;

  Future<void> whenIdle(String sessionId) async {
    final run = _runs[sessionId];
    if (run == null) return;
    await run.done.future;
  }

  Future<SegmentedDeliveryResult> deliver({
    required String sessionId,
    required int itemCount,
    required Duration Function(int index) delayFor,
    required FutureOr<void> Function(int index) onDeliver,
  }) {
    if (_disposed) {
      throw StateError('SegmentedDeliveryScheduler 已释放');
    }
    if (itemCount <= 0) return Future.value(SegmentedDeliveryResult.completed);

    _runs[sessionId]?.cancel();
    final run = _DeliveryRun(
      sessionId: sessionId,
      delays: [for (var i = 0; i < itemCount; i++) delayFor(i)],
      onDeliver: onDeliver,
    );
    _runs[sessionId] = run;
    unawaited(_run(run));
    return run.done.future;
  }

  void flushSession(String sessionId) {
    _runs[sessionId]?.flush();
  }

  void cancelSession(String sessionId) {
    _runs[sessionId]?.cancel();
  }

  void cancelAll() {
    for (final run in _runs.values.toList()) {
      run.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelAll();
  }

  Future<void> _run(_DeliveryRun run) async {
    var result = SegmentedDeliveryResult.completed;
    try {
      for (var i = 0; i < run.delays.length; i++) {
        if (run.cancelled) {
          result = SegmentedDeliveryResult.cancelled;
          break;
        }
        if (!run.flushRequested) {
          await Future.any<void>([_wait(run.delays[i]), run.wake.future]);
        }
        if (run.cancelled) {
          result = SegmentedDeliveryResult.cancelled;
          break;
        }
        await run.onDeliver(i);
        run.deliveredCount++;
      }
      if (run.cancelled) {
        result = SegmentedDeliveryResult.cancelled;
      } else if (run.flushRequested) {
        result = SegmentedDeliveryResult.flushed;
      }
    } catch (error, stackTrace) {
      run.done.completeError(error, stackTrace);
      return;
    } finally {
      run.complete(result);
      if (identical(_runs[run.sessionId], run)) {
        _runs.remove(run.sessionId);
      }
    }
  }
}

class _DeliveryRun {
  _DeliveryRun({
    required this.sessionId,
    required List<Duration> delays,
    required this.onDeliver,
  }) : delays = List.unmodifiable(delays),
       wake = Completer<void>(),
       done = Completer<SegmentedDeliveryResult>();

  final String sessionId;
  final List<Duration> delays;
  final FutureOr<void> Function(int index) onDeliver;
  final Completer<void> wake;
  final Completer<SegmentedDeliveryResult> done;
  int deliveredCount = 0;
  bool flushRequested = false;
  bool cancelled = false;

  int get itemCount => delays.length;
  bool get isActive => !done.isCompleted;

  void flush() {
    if (!isActive || cancelled) return;
    flushRequested = true;
    _wake();
  }

  void cancel() {
    if (!isActive) return;
    cancelled = true;
    _wake();
  }

  void _wake() {
    if (!wake.isCompleted) wake.complete();
  }

  void complete(SegmentedDeliveryResult result) {
    if (!done.isCompleted) done.complete(result);
  }
}
