// 「跳过此版本」偏好存储。
//
// 记录用户在更新提示中明确跳过的版本号，属设备本地偏好，
// 不进入同步通道。

import 'package:shared_preferences/shared_preferences.dart';

class UpdateSkipStore {
  UpdateSkipStore();

  static const _storeKey = 'skipped_update_version';

  /// 返回用户跳过的版本号；存储不可用（如测试环境无插件实现）时返回
  /// null，跳过机制静默失效（每次启动仍会提示）。
  Future<String?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_storeKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storeKey, version);
    } catch (_) {
      // 存储不可用时跳过记录失效，属可接受的降级。
    }
  }
}
