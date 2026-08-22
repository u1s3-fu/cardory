// 更新提示对话框：展示 GitHub 最新版本与当前平台可下载的安装包。

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/cardory_utils.dart';
import '../../services/github_update_service.dart';
import '../cardory_theme.dart';

/// 弹出"发现新版本"对话框。
///
/// [release] 为 GitHub 最新 Release 信息，[currentVersion] 为本地应用版本号。
/// 对话框按当前平台列出可下载的安装包，点击后调用系统浏览器直接下载，
/// 底部另提供"打开 GitHub Releases"入口查看完整发布说明。
Future<void> showUpdateDialog(
  BuildContext context, {
  required GithubReleaseInfo release,
  required String currentVersion,
}) async {
  final assets = assetsForCurrentPlatform(release);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.system_update_alt_rounded,
        size: 34,
        color: Theme.of(dialogContext).colorScheme.primary,
      ),
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _VersionChip(label: '当前', value: currentVersion),
                  const SizedBox(width: 10),
                  _VersionChip(
                    label: '最新',
                    value: release.version,
                    highlight: true,
                  ),
                ],
              ),
              if (release.body.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  '更新说明',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CardoryColors.gray50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(
                        _cleanMarkdown(release.body.trim()),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
              if (assets.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  '立即下载',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...assets.map(
                  (asset) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _launchUrl(dialogContext, asset.downloadUrl),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        asset.sizeBytes > 0
                            ? '${asset.name}（${formatFileSize(asset.sizeBytes)}）'
                            : asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('稍后'),
        ),
        OutlinedButton.icon(
          onPressed: () => _launchUrl(dialogContext, release.htmlUrl),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('打开 GitHub Releases'),
        ),
      ],
    ),
  );
}

/// 在系统浏览器中打开链接；失败时提示。
Future<void> _launchUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
  }
}

/// 将 GitHub Markdown 原文做最小清洗，去掉标题/引用/列表标记后作为纯文本展示。
String _cleanMarkdown(String text) {
  final lines = text.split('\n').map((line) {
    var cleaned = line.trimRight();
    cleaned = cleaned.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^>\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^[-*+]\s+'), '• ');
    cleaned = cleaned.replaceFirst(RegExp(r'^\d+\.\s+'), '• ');
    return cleaned;
  });
  return lines.join('\n').trim();
}

/// 版本信息小标签（当前 / 最新）。
class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: highlight ? CardoryColors.primarySoft : CardoryColors.gray100,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: highlight ? CardoryColors.primary : CardoryColors.gray700,
      ),
    ),
  );
}
