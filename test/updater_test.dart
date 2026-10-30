import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kele_music_client/core/updater.dart';

/// 检查更新核心逻辑：版本比较、产物挑选、镜像回退顺序、错误翻译。
void main() {
  group('版本号比较', () {
    test('归一化：去 v 前缀与预发布后缀', () {
      expect(normalizeVersion('v1.2.3'), '1.2.3');
      expect(normalizeVersion('V1.2.3'), '1.2.3');
      expect(normalizeVersion('1.2.3-beta.1+7'), '1.2.3');
      expect(normalizeVersion('1.10'), '1.10');
    });

    test('按数字段比较，位数不足补 0', () {
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('v1.0.2', '1.0.1'), greaterThan(0));
      expect(compareVersions('1.0.1', '1.0.1'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.1', '1.1.0'), 0);
    });

    test('只在真正更新时提示（同版本与旧版本都不提示）', () {
      expect(isNewerVersion('v1.1.0', '1.0.1'), isTrue);
      expect(isNewerVersion('v1.0.1', '1.0.1'), isFalse);
      expect(isNewerVersion('v1.0.0', '1.0.1'), isFalse); // 永不降级
    });
  });

  group('下载源候选（国内镜像优先，官方兜底）', () {
    test('资源下载：镜像全部在官方之前，且按 `<镜像>/<完整 URL>` 拼接', () {
      const url = 'https://github.com/51www/kele-music/releases/download/'
          'v1.0.0/app-release.apk';
      final candidates = downloadUrlCandidates(url);
      expect(candidates.last, url, reason: '官方直连必须作为最后兜底');
      expect(candidates.length, kUpdateMirrorBases.length + 1);
      for (final m in kUpdateMirrorBases) {
        expect(candidates.contains('$m$url'), isTrue);
        expect(m.endsWith('/'), isTrue, reason: '镜像前缀必须以 / 结尾');
      }
      expect(candidates.indexOf(url),
          greaterThan(candidates.indexOf('${kUpdateMirrorBases.first}$url')));
    });

    test('检查接口：官方 api 优先，失败才走镜像', () {
      final candidates = apiUrlCandidates();
      expect(candidates.first, kUpdateApiLatest);
      expect(candidates.length, kUpdateMirrorBases.length + 1);
      expect(candidates[1], '${kUpdateMirrorBases.first}$kUpdateApiLatest');
    });
  });

  group('产物挑选', () {
    ReleaseAsset asset(String name) =>
        ReleaseAsset(name: name, downloadUrl: 'https://x/$name', size: 1);

    ReleaseInfo release(List<ReleaseAsset> assets) => ReleaseInfo(
          tagName: 'v1.0.0',
          name: '',
          body: '',
          htmlUrl: kUpdateReleasesPage,
          publishedAt: '',
          assets: assets,
        );

    test('优先 universal APK，排除 aab', () {
      final r = release([
        asset('kele-music-v1.0.0-android.aab'),
        asset('kele-music-v1.0.0-android-arm64-v8a.apk'),
        asset('kele-music-v1.0.0-android-universal.apk'),
      ]);
      expect(pickAndroidApk(r)!.name,
          'kele-music-v1.0.0-android-universal.apk');
    });

    test('兼容手动上传的任意 apk 命名（如 app-release.apk）', () {
      final r = release([
        asset('app-release.aab'),
        asset('app-release.apk'),
      ]);
      expect(pickAndroidApk(r)!.name, 'app-release.apk');
      expect(pickAndroidApk(release([asset('app-release.aab')])), isNull);
    });

    test('桌面端按平台关键字挑产物', () {
      final r = release([
        asset('kele-music-v1.0.0-android-universal.apk'),
        asset('kele-music-v1.0.0-windows-x64.zip'),
        asset('kele-music-v1.0.0-linux-x64.tar.gz'),
      ]);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(pickPlatformAsset(r)!.name, contains('-windows-'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(pickPlatformAsset(r)!.name, contains('-linux-'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Release 解析', () {
    test('digest 解析为小写 sha256，缺失时为 null（跳过校验）', () {
      final r = parseRelease({
        'tag_name': 'v1.0.0',
        'name': '',
        'body': '更新说明',
        'html_url': 'https://github.com/51www/kele-music/releases/tag/v1.0.0',
        'published_at': '2026-10-29T05:06:32Z',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/o/r/releases/download/v1.0.0/a.apk',
            'size': 57969595,
            'digest': 'sha256:ABC123def',
          },
          {
            'name': 'app-release.aab',
            'browser_download_url': 'https://github.com/o/r/a.aab',
            'size': 100,
          },
        ],
      });
      expect(r.tagName, 'v1.0.0');
      expect(r.version, '1.0.0');
      expect(r.assets.first.sha256, 'abc123def');
      expect(r.assets.last.sha256, isNull, reason: '无 digest → 不做校验');
      expect(r.assets.first.size, 57969595);
    });

    test('字段缺失时给默认值，不抛异常', () {
      final r = parseRelease({'tag_name': 'v1.1.0'});
      expect(r.version, '1.1.0');
      expect(r.assets, isEmpty);
      expect(r.htmlUrl, kUpdateReleasesPage);
    });
  });

  group('错误翻译与展示格式化', () {
    test('常见异常翻译为中文提示', () {
      expect(friendlyUpdateError(StateError('GitHub 未返回版本号')),
          'GitHub 未返回版本号');
      final notFound = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: RequestOptions(path: '/'), statusCode: 404),
      );
      expect(friendlyUpdateError(notFound), '仓库暂未发布任何版本');
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(friendlyUpdateError(timeout), contains('无法连接 GitHub'));
    });

    test('展示用格式化', () {
      expect(formatSize(0), '大小未知');
      expect(formatSize((12.3 * 1024 * 1024).round()), '12.3 MB');
      expect(publishedDate('2026-10-29T05:06:32Z'),
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(publishedDate(''), '');
    });
  });
}
