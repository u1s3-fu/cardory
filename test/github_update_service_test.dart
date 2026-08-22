// GithubUpdateService 的版本解析、版本比较与平台资产过滤单元测试。

import 'dart:io' show Platform;

import 'package:cardory/services/github_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVersion', () {
    test('解析常规版本号', () {
      expect(parseVersion('0.0.5'), [0, 0, 5]);
      expect(parseVersion('1.2.3'), [1, 2, 3]);
    });

    test('忽略 v 前缀', () {
      expect(parseVersion('v0.0.5'), [0, 0, 5]);
    });

    test('忽略 + 构建号与 - 预发布后缀', () {
      expect(parseVersion('0.0.4+1'), [0, 0, 4]);
      expect(parseVersion('0.0.5-beta.1'), [0, 0, 5]);
    });

    test('无法解析时返回 null', () {
      expect(parseVersion('abc'), isNull);
      expect(parseVersion('0.0.5.x'), isNull);
      expect(parseVersion(''), isNull);
    });
  });

  group('compareVersions', () {
    test('远端更新 / 相同 / 本地更新', () {
      expect(compareVersions('0.0.4', '0.0.5'), VersionComparison.newer);
      expect(compareVersions('0.0.5', '0.0.5'), VersionComparison.equal);
      expect(compareVersions('0.0.6', '0.0.5'), VersionComparison.older);
    });

    test('处理 v 前缀与构建号', () {
      expect(
        compareVersions('0.0.4+1', 'v0.0.5'),
        VersionComparison.newer,
      );
      expect(
        compareVersions('v0.0.5', '0.0.5+1'),
        VersionComparison.equal,
      );
    });

    test('位数不一致时按语义补零比较', () {
      expect(compareVersions('1.0', '0.9.9'), VersionComparison.newer);
      expect(compareVersions('1', '1.0.0'), VersionComparison.equal);
    });

    test('版本无法解析时返回 invalid', () {
      expect(compareVersions('0.0.4', 'abc'), VersionComparison.invalid);
    });
  });

  group('GithubReleaseInfo.fromJson', () {
    test('解析 latest release 响应', () {
      final info = GithubReleaseInfo.fromJson({
        'tag_name': 'v0.0.5',
        'name': 'Cardory 0.0.5',
        'body': '更新说明',
        'html_url': 'https://github.com/u1s3-fu/cardory/releases/tag/v0.0.5',
        'assets': [
          {
            'name': 'cardory-windows-x64-0.0.5.zip',
            'browser_download_url':
                'https://github.com/u1s3-fu/cardory/releases/download/v0.0.5/cardory-windows-x64-0.0.5.zip',
            'size': 1024,
          },
        ],
      });

      expect(info.version, '0.0.5');
      expect(info.tagName, 'v0.0.5');
      expect(info.assets, hasLength(1));
      expect(info.assets.first.name, 'cardory-windows-x64-0.0.5.zip');
      expect(info.assets.first.sizeBytes, 1024);
    });

    test('缺字段时安全降级', () {
      final info = GithubReleaseInfo.fromJson({});
      expect(info.tagName, isEmpty);
      expect(info.assets, isEmpty);
      expect(info.version, isEmpty);
    });
  });

  group('isAssetForCurrentPlatform', () {
    test('只匹配当前平台的安装包', () {
      final windows = GithubReleaseAsset(
        name: 'cardory-windows-x64-0.0.5.zip',
        downloadUrl: 'https://example.com/win.zip',
      );
      final android = GithubReleaseAsset(
        name: 'cardory-android-arm64-0.0.5.apk',
        downloadUrl: 'https://example.com/android.apk',
      );
      final macos = GithubReleaseAsset(
        name: 'cardory-macos-arm64-0.0.5.zip',
        downloadUrl: 'https://example.com/macos.zip',
      );

      if (Platform.isWindows) {
        expect(isAssetForCurrentPlatform(windows), isTrue);
        expect(isAssetForCurrentPlatform(android), isFalse);
        expect(isAssetForCurrentPlatform(macos), isFalse);
      } else if (Platform.isAndroid) {
        expect(isAssetForCurrentPlatform(android), isTrue);
        expect(isAssetForCurrentPlatform(windows), isFalse);
      } else if (Platform.isMacOS) {
        expect(isAssetForCurrentPlatform(macos), isTrue);
        expect(isAssetForCurrentPlatform(windows), isFalse);
      }
    });

    test('Windows 安装版优先于便携版', () {
      final release = GithubReleaseInfo.fromJson({
        'tag_name': 'v0.0.5',
        'assets': [
          {
            'name': 'cardory-windows-x64-v0.0.5-portable.zip',
            'browser_download_url': 'https://example.com/portable.zip',
          },
          {
            'name': 'cardory-windows-x64-v0.0.5-setup.exe',
            'browser_download_url': 'https://example.com/setup.exe',
          },
        ],
      });

      if (Platform.isWindows) {
        expect(
          preferredAssetForCurrentPlatform(release)?.name,
          endsWith('-setup.exe'),
        );
      }
    });
  });
}
