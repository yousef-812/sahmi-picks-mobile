import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'refresh.dart';

@pragma('vm:entry-point')
void startCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(RefreshTaskHandler());
}

class RefreshTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    String mode = 'fresh';
    try {
      mode = await readCmd();
    } catch (_) {}
    try {
      for (final u in ['egx33', 'all']) {
        final rep = await refreshUniverse(
          u,
          fresh: mode == 'fresh',
          onProgress: (d, t, tk) async {
            FlutterForegroundTask.sendDataToMain(
                {'type': 'progress', 'u': u, 'done': d, 'total': t, 'ticker': tk});
            try {
              await FlutterForegroundTask.updateService(
                notificationTitle: 'تحديث القوايم',
                notificationText: '$u: $tk ($d/$t)',
              );
            } catch (_) {}
          },
        );
        FlutterForegroundTask.sendDataToMain({
          'type': 'universe_done', 'u': u, 'ok': rep.ok, 'fail': rep.fail,
          'asof': rep.asof, 'consensus': rep.consensus,
          'resumed': rep.resumed, 'restartedFresh': rep.restartedFresh,
        });
      }
      FlutterForegroundTask.sendDataToMain({'type': 'done', 'ok': true});
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({'type': 'done', 'ok': false, 'error': '$e'});
    }
    await FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}
