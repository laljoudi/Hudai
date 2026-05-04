import 'package:flutter_test/flutter_test.dart';
import 'package:gp_hudai/core/services/inference_throttler.dart';

void main() {
  group('InferenceThrottler', () {

    test('first frame is always accepted', () {
      final throttler = InferenceThrottler();

      expect(throttler.shouldProcess(), true,
          reason: 'First frame should pass through');
    });

    test('second frame is rejected if AI is still busy', () {
      final throttler = InferenceThrottler();

      // First frame accepted, AI marked busy
      throttler.shouldProcess();

      // Second frame arrives while busy
      expect(throttler.shouldProcess(), false,
          reason: 'Should reject while busy');
    });

    test('frame is rejected if interval has not passed', () {
      final throttler = InferenceThrottler();

      // First frame accepted
      throttler.shouldProcess();

      // AI finishes immediately
      throttler.markDone();

      // Second frame arrives 0ms later — way too soon
      expect(throttler.shouldProcess(), false,
          reason: 'Should reject too-soon frames');
    });

    test('frame is accepted after enough time has passed', () async {
      final throttler = InferenceThrottler();

      // First frame
      throttler.shouldProcess();
      throttler.markDone();

      // Wait longer than the throttle interval (333ms + buffer)
      await Future.delayed(const Duration(milliseconds: 400));

      // Now should be accepted
      expect(throttler.shouldProcess(), true,
          reason: 'Should accept after interval');
    });

    test('reset clears all state', () {
      final throttler = InferenceThrottler();

      throttler.shouldProcess();
      expect(throttler.isBusy, true);

      throttler.reset();

      expect(throttler.isBusy, false,
          reason: 'Reset should clear busy state');
      expect(throttler.shouldProcess(), true,
          reason: 'After reset, next frame should pass');
    });

    test('forgetting to call markDone blocks all future frames', () async {
      final throttler = InferenceThrottler();

      // First frame accepted, but we DON'T call markDone (simulating bug)
      throttler.shouldProcess();

      // Wait long enough for the interval
      await Future.delayed(const Duration(milliseconds: 400));

      // This proves the busy check works — even after time, still rejected
      expect(throttler.shouldProcess(), false,
          reason: 'Without markDone, throttler stays blocked');
    });
  });
}