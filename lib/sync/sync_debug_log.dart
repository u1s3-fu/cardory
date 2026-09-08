// 同步链路调试日志（诊断用）。
//
// 用于在同步失败、且界面只给出「同步未完成，请稍后重试」等通用提示时，
// 通过落盘日志还原真实异常：哪个阶段、什么类型、什么消息、完整堆栈。
// 采用「启动即重置 + 会话内追加」的单文件策略；文件不可写时自动降级为
// 仅输出到控制台（debug / flutter run 可见），绝不阻断业务。

import 'dart:io';

String? _logFilePath;
bool _logReady = false;

/// 当前会话调试日志文件完整路径；未启用文件输出时为 null。
String? get syncDebugLogFilePath => _logFilePath;

/// 启用文件输出。传入目标目录，日志写入
/// `<目录>/cardory-sync-debug.log`；新会话从空文件开始。
/// 目录不存在时自动创建；创建或写入失败时静默降级，不影响业务。
void initSyncDebugLog(String directoryPath) {
  try {
    final directory = Directory(directoryPath);
    directory.createSync(recursive: true);
    final file = File(
      '$directoryPath${Platform.pathSeparator}cardory-sync-debug.log',
    );
    file.writeAsStringSync('', flush: true);
    _logFilePath = file.path;
    _logReady = true;
  } catch (_) {
    _logReady = false;
    _logFilePath = null;
  }
}

/// 记录一条同步日志。
///
/// [message] 为阶段说明；[error] 与 [stackTrace] 为失败详情（可选）。
/// 日志同时输出到控制台与调试日志文件。
void logSync(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  final buffer = StringBuffer()
    ..write(_timestamp())
    ..write(' ')
    ..write(message);
  if (error != null) {
    buffer
      ..write(' → ')
      ..write(error.runtimeType)
      ..write(': ')
      ..write(error);
  }
  final text = buffer.toString();
  // 诊断日志在 debug / flutter run 控制台可见，便于即时查看。
  // ignore: avoid_print
  print(text);
  if (!_logReady) return;
  try {
    File(_logFilePath!).writeAsStringSync(
      stackTrace == null ? '$text\n' : '$text\n$stackTrace\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // 写盘失败（磁盘满、权限变化等）仅降级，不影响同步主流程。
    _logReady = false;
  }
}

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '.${now.millisecond.toString().padLeft(3, '0')}';
}
