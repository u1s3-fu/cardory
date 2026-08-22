// 关于对话框：展示应用名称、版本、简介、开源许可证与仓库信息。

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cardory_theme.dart';

/// Cardory 开源仓库地址（与更新检查服务保持一致）。
const String kCardoryRepositoryUrl = 'https://github.com/u1s3-fu/cardory';

/// 弹出"关于 Cardory"对话框。
///
/// 展示应用名称、版本号、功能简介、开源许可证（GPL-3.0）
/// 以及 GitHub 开源仓库链接，点击链接在系统浏览器中打开。
Future<void> showAboutCardoryDialog(
  BuildContext context, {
  VoidCallback? onCheckForUpdate,
}) async {
  final version = await _appVersion();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.view_kanban_rounded,
        size: 36,
        color: Theme.of(dialogContext).colorScheme.primary,
      ),
      title: const Text('板记 Cardory'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(label: '版本', value: version),
                  const _InfoChip(label: '许可证', value: 'GPL-3.0'),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '以项目看板与待办为核心的个人进度管理应用。'
                '数据以加密容器持久化，支持本地、目录、WebDAV 与 S3 兼容存储同步。',
                style: TextStyle(fontSize: 13.5, height: 1.55),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CardoryColors.gray50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '开源地址',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CardoryColors.gray500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () =>
                          _launchUrl(dialogContext, kCardoryRepositoryUrl),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 15,
                              color: CardoryColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'github.com/u1s3-fu/cardory',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: CardoryColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Copyright © 2026 u1s3-fu · 基于 GPL-3.0 许可证发布',
                style: TextStyle(fontSize: 12, color: CardoryColors.gray400),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (onCheckForUpdate != null)
          TextButton.icon(
            icon: const Icon(Icons.system_update_alt_rounded, size: 18),
            label: const Text('检查更新'),
            onPressed: () {
              Navigator.pop(dialogContext);
              onCheckForUpdate();
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 读取应用版本号（读取失败时兜底为 0.0.0）。
Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
  } catch (_) {
    return '0.0.0';
  }
}

/// 在系统浏览器中打开链接；失败时提示。
Future<void> _launchUrl(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('无法打开链接：$url')),
    );
  }
}

/// 信息小标签（版本 / 许可证）。
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: CardoryColors.primarySoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: CardoryColors.primary,
      ),
    ),
  );
}
