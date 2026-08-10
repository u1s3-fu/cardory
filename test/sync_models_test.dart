import 'package:cardory/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes and restores sync status', () {
    final status = SyncStatus(
      phase: SyncPhase.success,
      providerId: 'webdav',
      message: '同步完成',
      lastSyncedAt: DateTime.utc(2026, 7, 29, 8),
    );

    expect(SyncStatus.fromJson(status.toJson()), status);
    expect(status.isRunning, isFalse);
    expect(status.copyWith(phase: SyncPhase.pushing).isRunning, isTrue);
    expect(status.copyWith(clearMessage: true).message, isNull);
  });

  test('falls back to idle for unknown phase', () {
    final status = SyncStatus.fromJson({'phase': 'future-phase'});

    expect(status.phase, SyncPhase.idle);
  });
}
