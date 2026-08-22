// 领域通用工具函数。

/// 将进度值收敛到 0..1 区间。
double readProgress(Object? value) =>
    (value as num? ?? 0).clamp(0, 1).toDouble();

/// 格式化日期为 `yyyy-MM-dd`。
String formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// 格式化日期时间为 `yyyy-MM-dd HH:mm`。
String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// 以微秒时间戳生成全局唯一标识。
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

/// 日期选择器支持的最小日期（避免魔法数字重复）。
final DateTime minPickerDate = DateTime(2000);

/// 日期选择器支持的最大日期（避免魔法数字重复）。
final DateTime maxPickerDate = DateTime(2100);

/// 格式化文件大小为人类可读文本（B/KB/MB/GB）。
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

/// 去除文件名扩展名（“report.pdf” → “report”）。
String stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return fileName;
  return fileName.substring(0, dot);
}

/// 保留扩展名的重命名：仅替换文件名主体，原扩展名保持不变。
String applyRenameKeepingExtension(String input, String originalFileName) {
  final originalBody = stripExtension(originalFileName);
  final extension = originalBody == originalFileName
      ? ''
      : originalFileName.substring(originalBody.length + 1);
  var body = input.trim();
  if (extension.isNotEmpty &&
      body.toLowerCase().endsWith('.$extension'.toLowerCase())) {
    body = body.substring(0, body.length - extension.length - 1).trimRight();
  }
  if (body.isEmpty) return originalFileName;
  return extension.isEmpty ? body : '$body.$extension';
}
