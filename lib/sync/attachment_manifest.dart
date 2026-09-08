// 附件同步 manifest。
//
// 云端在加密数据库快照之外维护一份附件清单文档，声明该快照所引用的全部
// 附件加密对象（storageKey + 长度 + SHA-256）。同步每次成功后都重写该清单，
// 使云端始终存在一份「当前快照附件集合」的权威枚举，供新设备/云端恢复
// 逐文件抓取、完整性校验与孤儿清理使用；拉取侧发现快照引用清单之外的
// 附件时按 fail-closed 处理（附件缺失 ≠ 静默导入为损坏本地数据）。

import 'dart:convert';

import '../domain/cardory_models.dart';

/// 附件加密对象的云端 key（与同步器上传路径保持一致）。
String attachmentFileKey(String storageKey) => 'attachments/v1/$storageKey';

/// 附件清单文档的云端 key（固定、无修订号、由每次成功同步幂等重写）。
const String attachmentManifestKey = 'attachments/manifest.json';

/// 附件清单中单条附件的元数据。
class AttachmentManifestEntry {
  const AttachmentManifestEntry({
    required this.storageKey,
    required this.sha256,
    required this.size,
  });

  /// 由数据库附件元数据构造清单条目（storageKey 为空表示尚未落盘的附件，跳过）。
  factory AttachmentManifestEntry.fromAttachment(AttachmentData attachment) =>
      AttachmentManifestEntry(
        storageKey: attachment.storageKey,
        sha256: attachment.sha256,
        size: attachment.size,
      );

  final String storageKey;
  final String sha256;
  final int size;

  factory AttachmentManifestEntry.fromJson(Map<String, dynamic> json) {
    final storageKey = json['storageKey'];
    final sha256 = json['sha256'];
    final size = json['size'];
    if (storageKey is! String ||
        storageKey.isEmpty ||
        sha256 is! String ||
        sha256.isEmpty ||
        size is! int) {
      throw const FormatException('附件清单条目字段不完整');
    }
    return AttachmentManifestEntry(
      storageKey: storageKey,
      sha256: sha256,
      size: size,
    );
  }

  Map<String, dynamic> toJson() => {
    'storageKey': storageKey,
    'sha256': sha256,
    'size': size,
  };
}

/// 附件清单文档。
///
/// 序列化是确定性的（条目按 storageKey 排序），相同附件集合产生相同字节，
/// 便于幂等重写与内容对比。
class AttachmentManifest {
  const AttachmentManifest({required this.entries});

  factory AttachmentManifest.build(Iterable<AttachmentData> attachments) =>
      AttachmentManifest(
        entries:
            attachments
                .where((attachment) => attachment.storageKey.isNotEmpty)
                .map(AttachmentManifestEntry.fromAttachment)
                .toList()
              ..sort((a, b) => a.storageKey.compareTo(b.storageKey)),
      );

  static const int formatVersion = 1;

  final List<AttachmentManifestEntry> entries;

  bool contains(String storageKey) =>
      entries.any((entry) => entry.storageKey == storageKey);

  List<int> toBytes() => utf8.encode(
    jsonEncode({
      'formatVersion': formatVersion,
      'attachments': entries.map((entry) => entry.toJson()).toList(),
    }),
  );

  /// 从字节解析清单。格式非法（含版本不支持）时抛出 [FormatException]，
  /// 调用方决定是跳过（云端可能由更老版本写入）还是按损坏处理。
  factory AttachmentManifest.fromBytes(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('附件清单格式无效');
    }
    if (decoded['formatVersion'] != formatVersion) {
      throw FormatException('不支持附件清单版本：${decoded['formatVersion']}');
    }
    final list = decoded['attachments'];
    if (list is! List) throw const FormatException('附件清单缺少 attachments');
    final entries = <AttachmentManifestEntry>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('附件清单条目格式无效');
      }
      entries.add(AttachmentManifestEntry.fromJson(item));
    }
    return AttachmentManifest(entries: entries);
  }
}
