import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/sync/application/merka_sync_configured_bootstrap_runner.dart';
import 'package:merka_erp/sync/application/merka_sync_configured_pull_runner.dart';
import 'package:merka_erp/sync/application/merka_sync_configured_push_runner.dart';
import 'package:merka_erp/sync/application/merka_sync_inbox_apply_service.dart';
import 'package:merka_erp/sync/application/merka_sync_now_runner.dart';
import 'package:merka_erp/sync/application/merka_sync_pull_service.dart';
import 'package:merka_erp/sync/application/merka_sync_push_service.dart';

void main() {
  test('syncNow ejecuta push, pull y apply en orden', () async {
    final calls = <String>[];
    final result = await MerkaSyncNowRunner(
      bootstrapStep: () async {
        calls.add('bootstrap');
        return const MerkaSyncConfiguredBootstrapResult(queued: 3);
      },
      pushStep: ({int limit = 50}) async {
        calls.add('push:$limit');
        return MerkaSyncConfiguredPushResult.attempted(
          const MerkaSyncPushResult(pushed: 1, failed: 0, terminalErrors: 0),
        );
      },
      pullStep: ({int limit = 100}) async {
        calls.add('pull:$limit');
        return MerkaSyncConfiguredPullResult.attempted(
          const MerkaSyncPullResult(
            received: 2,
            duplicates: 0,
            cursor: '2',
            hasMore: false,
          ),
        );
      },
      applyStep: ({int limit = 50}) async {
        calls.add('apply:$limit');
        return const MerkaSyncInboxApplyResult(
          applied: 2,
          skipped: 0,
          failed: 0,
          terminalErrors: 0,
        );
      },
    ).syncNow(pushLimit: 10, pullLimit: 20, applyLimit: 30);

    expect(calls, ['bootstrap', 'push:10', 'pull:20', 'apply:30']);
    expect(result.completed, isTrue);
    expect(result.bootstrap.queued, 3);
    expect(result.push.pushResult.pushed, 1);
    expect(result.pull.pullResult.received, 2);
    expect(result.apply.applied, 2);
    expect(result.toMap()['completed'], isTrue);
  });

  test('syncNow se detiene si push fue omitido por configuración', () async {
    final calls = <String>[];
    final result = await MerkaSyncNowRunner(
      bootstrapStep: () async {
        calls.add('bootstrap');
        return const MerkaSyncConfiguredBootstrapResult(queued: 1);
      },
      pushStep: ({int limit = 50}) async {
        calls.add('push');
        return MerkaSyncConfiguredPushResult.skipped('sin endpoint');
      },
      pullStep: ({int limit = 100}) async {
        calls.add('pull');
        return MerkaSyncConfiguredPullResult.attempted(
          const MerkaSyncPullResult(
            received: 1,
            duplicates: 0,
            cursor: '1',
            hasMore: false,
          ),
        );
      },
      applyStep: ({int limit = 50}) async {
        calls.add('apply');
        return const MerkaSyncInboxApplyResult(
          applied: 1,
          skipped: 0,
          failed: 0,
          terminalErrors: 0,
        );
      },
    ).syncNow();

    expect(calls, ['bootstrap', 'push']);
    expect(result.completed, isFalse);
    expect(result.stopReason, 'sin endpoint');
    expect(result.pull.attempted, isFalse);
    expect(result.apply.processed, 0);
  });

  test('syncNow se detiene si pull fue omitido por token/device', () async {
    final calls = <String>[];
    final result = await MerkaSyncNowRunner(
      bootstrapStep: () async {
        calls.add('bootstrap');
        return const MerkaSyncConfiguredBootstrapResult(queued: 0);
      },
      pushStep: ({int limit = 50}) async {
        calls.add('push');
        return MerkaSyncConfiguredPushResult.attempted(
          const MerkaSyncPushResult(pushed: 0, failed: 0, terminalErrors: 0),
        );
      },
      pullStep: ({int limit = 100}) async {
        calls.add('pull');
        return MerkaSyncConfiguredPullResult.skipped('sin token');
      },
      applyStep: ({int limit = 50}) async {
        calls.add('apply');
        return const MerkaSyncInboxApplyResult(
          applied: 1,
          skipped: 0,
          failed: 0,
          terminalErrors: 0,
        );
      },
    ).syncNow();

    expect(calls, ['bootstrap', 'push', 'pull']);
    expect(result.completed, isFalse);
    expect(result.stopReason, 'sin token');
    expect(result.apply.processed, 0);
  });

  test('syncNow completa y expone errores de apply', () async {
    final result = await MerkaSyncNowRunner(
      bootstrapStep: () async =>
          const MerkaSyncConfiguredBootstrapResult(queued: 0),
      pushStep: ({int limit = 50}) async =>
          MerkaSyncConfiguredPushResult.attempted(
            const MerkaSyncPushResult(pushed: 0, failed: 1, terminalErrors: 0),
          ),
      pullStep: ({int limit = 100}) async =>
          MerkaSyncConfiguredPullResult.attempted(
            const MerkaSyncPullResult(
              received: 1,
              duplicates: 0,
              cursor: '9',
              hasMore: false,
            ),
          ),
      applyStep: ({int limit = 50}) async => const MerkaSyncInboxApplyResult(
        applied: 0,
        skipped: 0,
        failed: 1,
        terminalErrors: 0,
      ),
    ).syncNow();

    expect(result.completed, isTrue);
    expect(result.push.pushResult.failed, 1);
    expect(result.apply.failed, 1);
  });
}
