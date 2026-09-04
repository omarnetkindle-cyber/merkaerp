import 'merka_sync_configured_bootstrap_runner.dart';
import 'merka_sync_configured_apply_runner.dart';
import 'merka_sync_configured_pull_runner.dart';
import 'merka_sync_configured_push_runner.dart';
import 'merka_sync_inbox_apply_service.dart';

typedef MerkaSyncBootstrapStep =
    Future<MerkaSyncConfiguredBootstrapResult> Function();
typedef MerkaSyncPushStep =
    Future<MerkaSyncConfiguredPushResult> Function({int limit});
typedef MerkaSyncPullStep =
    Future<MerkaSyncConfiguredPullResult> Function({int limit});
typedef MerkaSyncApplyStep =
    Future<MerkaSyncInboxApplyResult> Function({int limit});

class MerkaSyncNowResult {
  const MerkaSyncNowResult({
    required this.completed,
    required this.bootstrap,
    required this.push,
    required this.pull,
    required this.apply,
    this.stopReason,
  });

  final bool completed;
  final String? stopReason;
  final MerkaSyncConfiguredBootstrapResult bootstrap;
  final MerkaSyncConfiguredPushResult push;
  final MerkaSyncConfiguredPullResult pull;
  final MerkaSyncInboxApplyResult apply;

  Map<String, Object?> toMap() => {
    'completed': completed,
    'stop_reason': stopReason,
    'bootstrap': bootstrap.toMap(),
    'push': {
      'attempted': push.attempted,
      'skip_reason': push.skipReason,
      ...push.pushResult.toMap(),
    },
    'pull': {
      'attempted': pull.attempted,
      'skip_reason': pull.skipReason,
      ...pull.pullResult.toMap(),
    },
    'apply': apply.toMap(),
  };
}

class MerkaSyncNowRunner {
  MerkaSyncNowRunner({
    MerkaSyncBootstrapStep? bootstrapStep,
    MerkaSyncPushStep? pushStep,
    MerkaSyncPullStep? pullStep,
    MerkaSyncApplyStep? applyStep,
  }) : _bootstrapStep =
           bootstrapStep ??
           MerkaSyncConfiguredBootstrapRunner().enqueueCurrentCatalog,
       _pushStep = pushStep ?? MerkaSyncConfiguredPushRunner().pushPending,
       _pullStep = pullStep ?? MerkaSyncConfiguredPullRunner().pullPending,
       _applyStep = applyStep ?? MerkaSyncConfiguredApplyRunner().applyPending;

  final MerkaSyncBootstrapStep _bootstrapStep;
  final MerkaSyncPushStep _pushStep;
  final MerkaSyncPullStep _pullStep;
  final MerkaSyncApplyStep _applyStep;

  Future<MerkaSyncNowResult> syncNow({
    int pushLimit = 50,
    int pullLimit = 100,
    int applyLimit = 50,
  }) async {
    final bootstrap = await _bootstrapStep();
    final push = await _pushStep(limit: pushLimit);
    if (!push.attempted) {
      return MerkaSyncNowResult(
        completed: false,
        stopReason: push.skipReason,
        bootstrap: bootstrap,
        push: push,
        pull: MerkaSyncConfiguredPullResult.skipped(
          'Push omitido: ${push.skipReason ?? 'sin razón'}',
        ),
        apply: const MerkaSyncInboxApplyResult(
          applied: 0,
          skipped: 0,
          failed: 0,
          terminalErrors: 0,
        ),
      );
    }

    final pull = await _pullStep(limit: pullLimit);
    if (!pull.attempted) {
      return MerkaSyncNowResult(
        completed: false,
        stopReason: pull.skipReason,
        bootstrap: bootstrap,
        push: push,
        pull: pull,
        apply: const MerkaSyncInboxApplyResult(
          applied: 0,
          skipped: 0,
          failed: 0,
          terminalErrors: 0,
        ),
      );
    }

    final apply = await _applyStep(limit: applyLimit);
    return MerkaSyncNowResult(
      completed: true,
      bootstrap: bootstrap,
      push: push,
      pull: pull,
      apply: apply,
    );
  }
}
