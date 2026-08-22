// GitHub 更新检查服务：从 GitHub Releases 获取最新版本，并与本地版本比较。
//
// 数据来源为 GitHub Releases API 的 latest 端点（不含预发布版本），
// 匿名限额 60 次/小时/IP，对个人应用足够。

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// GitHub Release 中的单个可下载资产（安装包）。
class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeBytes = 0,
  });

  /// 资产文件名，如 `cardory-windows-x64-0.0.5.zip`。
  final String name;

  /// 直接下载地址（浏览器打开即可下载）。
  final String downloadUrl;

  /// 文件大小（字节），未知时为 0。
  final int sizeBytes;

  factory GithubReleaseAsset.fromJson(Map<String, dynamic> json) =>
      GithubReleaseAsset(
        name: json['name'] as String? ?? '',
        downloadUrl: json['browser_download_url'] as String? ?? '',
        sizeBytes: json['size'] as int? ?? 0,
      );
}

/// GitHub 最新 Release 信息。
class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  /// 版本标签，如 `v0.0.5`。
  final String tagName;

  /// Release 标题。
  final String name;

  /// 更新说明（GitHub Markdown 原文）。
  final String body;

  /// Release 页面地址。
  final String htmlUrl;

  /// 该 Release 的全部资产。
  final List<GithubReleaseAsset> assets;

  /// 去掉 `v` 前缀后的版本号，如 `0.0.5`。
  String get version => tagName.startsWith('v') ? tagName.substring(1) : tagName;

  factory GithubReleaseInfo.fromJson(Map<String, dynamic> json) =>
      GithubReleaseInfo(
        tagName: json['tag_name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        body: json['body'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ?? '',
        assets: (json['assets'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GithubReleaseAsset.fromJson)
            .toList(),
      );
}

/// 版本比较结果（相对于本地版本，远端 Release 是更新 / 相同 / 更旧）。
enum VersionComparison { newer, equal, older, invalid }

/// 解析版本字符串为数字段列表（如 `0.0.5+1` → [0, 0, 5]）。
///
/// 会忽略 `v` 前缀、`+` 构建号与 `-` 预发布后缀；无法解析时返回 null。
List<int>? parseVersion(String version) {
  var text = version.trim().toLowerCase();
  if (text.startsWith('v')) text = text.substring(1);
  final plus = text.indexOf('+');
  if (plus >= 0) text = text.substring(0, plus);
  final dash = text.indexOf('-');
  if (dash >= 0) text = text.substring(0, dash);
  if (text.isEmpty) return null;
  final parts = <int>[];
  for (final part in text.split('.')) {
    final value = int.tryParse(part);
    if (value == null) return null;
    parts.add(value);
  }
  return parts;
}

/// 比较本地版本 [local] 与远端版本 [remote] 的关系。
///
/// 返回 [VersionComparison.newer] 表示远端版本更高（有更新），
/// [VersionComparison.older] 表示本地版本更高，[VersionComparison.invalid]
/// 表示任一版本号无法解析。
VersionComparison compareVersions(String local, String remote) {
  final a = parseVersion(local);
  final b = parseVersion(remote);
  if (a == null || b == null) return VersionComparison.invalid;
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av < bv) return VersionComparison.newer;
    if (av > bv) return VersionComparison.older;
  }
  return VersionComparison.equal;
}

/// 判断资产是否为当前平台可下载的安装包。
///
/// 依据 CI 构建命名规则 `cardory-平台-架构-版本号` 匹配文件名关键词。
bool isAssetForCurrentPlatform(GithubReleaseAsset asset) {
  if (kIsWeb) return false;
  final name = asset.name.toLowerCase();
  if (Platform.isWindows) {
    return name.contains('windows') &&
        (name.endsWith('.zip') || name.endsWith('.exe'));
  }
  if (Platform.isAndroid) {
    return name.contains('android') && name.endsWith('.apk');
  }
  if (Platform.isIOS) {
    return name.contains('ios') && name.endsWith('.ipa');
  }
  if (Platform.isMacOS) {
    return (name.contains('macos') || name.contains('darwin')) &&
        name.endsWith('.zip');
  }
  return false;
}

/// 过滤出当前平台可下载的资产列表。
///
/// Windows 安装版排在便携版之前，调用方可将第一项作为默认更新资产。
List<GithubReleaseAsset> assetsForCurrentPlatform(GithubReleaseInfo release) {
  final assets = release.assets.where(isAssetForCurrentPlatform).toList();
  if (!Platform.isWindows) return assets;
  assets.sort((a, b) {
    final aInstaller = a.name.toLowerCase().endsWith('-setup.exe');
    final bInstaller = b.name.toLowerCase().endsWith('-setup.exe');
    if (aInstaller == bInstaller) return 0;
    return aInstaller ? -1 : 1;
  });
  return assets;
}

/// 返回当前平台推荐的更新资产；Windows 优先返回安装程序。
GithubReleaseAsset? preferredAssetForCurrentPlatform(
  GithubReleaseInfo release,
) {
  final assets = assetsForCurrentPlatform(release);
  return assets.isEmpty ? null : assets.first;
}

/// 基于 GitHub Releases 的更新检查服务。
class GithubUpdateService {
  GithubUpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// GitHub 仓库（所有者/仓库名）。
  static const String repository = 'u1s3-fu/cardory';

  static const String _releasesApi =
      'https://api.github.com/repos/$repository/releases/latest';

  final http.Client _client;

  /// 请求 GitHub 上最新 Release。
  ///
  /// 仓库无 Release、网络异常或响应异常时返回 null（由调用方决定是否提示）。
  Future<GithubReleaseInfo?> fetchLatestRelease() async {
    try {
      final response = await _client.get(
        Uri.parse(_releasesApi),
        headers: const {
          // GitHub API 要求携带 User-Agent，否则返回 403。
          'User-Agent': 'Cardory-update-check',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final info = GithubReleaseInfo.fromJson(decoded);
      if (info.tagName.isEmpty) return null;
      return info;
    } catch (_) {
      // 离线、超时或响应解析失败均视为"检查失败"，不抛出。
      return null;
    }
  }
}
