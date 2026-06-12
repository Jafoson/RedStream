import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ReleaseInfo {
  final String tagName;
  final String version;
  final String name;
  final String body;
  final String? windowsDownloadUrl;
  final String? macosDownloadUrl;
  final String? androidDownloadUrl;

  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    this.windowsDownloadUrl,
    this.macosDownloadUrl,
    this.androidDownloadUrl,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class UpdateService {
  static const _owner = 'Jafoson';
  static const _repo = 'AniWorld-Downloader';
  static const _apiBase = 'https://api.github.com/repos/$_owner/$_repo';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 10),
    headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  ));

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<ReleaseInfo?> fetchLatestRelease() async {
    final resp =
        await _dio.get<Map<String, dynamic>>('$_apiBase/releases/latest');
    final data = resp.data!;
    final tagName = (data['tag_name'] as String?) ?? '';
    final version = tagName.replaceFirst(RegExp(r'^v'), '');
    final assets = (data['assets'] as List?) ?? [];

    String? windowsUrl, macosUrl, androidUrl;
    for (final a in assets) {
      final name = ((a['name'] as String?) ?? '').toLowerCase();
      final url = (a['browser_download_url'] as String?) ?? '';
      if (name.contains('windows') && name.endsWith('.zip')) windowsUrl = url;
      if (name.contains('macos') && name.endsWith('.zip')) macosUrl = url;
      if (name.contains('android') && name.endsWith('.apk')) androidUrl = url;
    }

    return ReleaseInfo(
      tagName: tagName,
      version: version,
      name: (data['name'] as String?) ?? tagName,
      body: (data['body'] as String?) ?? '',
      windowsDownloadUrl: windowsUrl,
      macosDownloadUrl: macosUrl,
      androidDownloadUrl: androidUrl,
    );
  }

  static bool isNewer(String current, String latest) {
    final c = _parseVer(current);
    final l = _parseVer(latest);
    for (int i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parseVer(String v) {
    final parts = v.replaceFirst(RegExp(r'^v'), '').split('.');
    return List.generate(
        3, (i) => int.tryParse(parts.elementAtOrNull(i) ?? '') ?? 0);
  }

  // ── Download & install ─────────────────────────────────────────────────────

  Future<void> downloadAndInstall(
    ReleaseInfo release, {
    required void Function(double) onProgress,
  }) async {
    final String? downloadUrl;
    final String fileName;

    if (Platform.isWindows) {
      downloadUrl = release.windowsDownloadUrl;
      fileName = 'rs_update_${release.version}.zip';
    } else if (Platform.isMacOS) {
      downloadUrl = release.macosDownloadUrl;
      fileName = 'rs_update_${release.version}.zip';
    } else if (Platform.isAndroid) {
      downloadUrl = release.androidDownloadUrl;
      fileName = 'rs_update_${release.version}.apk';
    } else {
      throw Exception('Auto-Update wird auf dieser Plattform nicht unterstützt.');
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('Kein Download-Asset für diese Plattform gefunden.');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}${Platform.pathSeparator}$fileName';

    await _dio.download(
      downloadUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );
    onProgress(1.0);

    if (Platform.isWindows) {
      await _installWindows(filePath, release.version);
    } else if (Platform.isMacOS) {
      await _installMacOS(filePath, release.version);
    } else if (Platform.isAndroid) {
      await _installAndroid(filePath);
    }
  }

  // ── Windows ────────────────────────────────────────────────────────────────

  Future<void> _installWindows(String zipPath, String version) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final tmpDir = await getTemporaryDirectory();
    final sep = Platform.pathSeparator;
    final extractDir = '${tmpDir.path}${sep}rs_extracted_$version';

    await compute(_extractZipIsolate, [zipPath, extractDir]);

    final scriptPath = '${tmpDir.path}${sep}rs_updater.ps1';
    await File(scriptPath).writeAsString('''
param(
  [string]\$ExtractDir,
  [string]\$AppDir,
  [string]\$ExePath,
  [string]\$ZipPath
)
Start-Sleep -Seconds 2
try {
  Copy-Item -Path "\$ExtractDir\\*" -Destination \$AppDir -Recurse -Force
  Start-Process \$ExePath
} catch {
  Write-Error \$_
} finally {
  Remove-Item -Path \$ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -Path \$ZipPath  -Force -ErrorAction SilentlyContinue
}
''');

    await Process.start(
      'powershell',
      [
        '-WindowStyle', 'Hidden',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-ExtractDir', extractDir,
        '-AppDir', appDir,
        '-ExePath', exePath,
        '-ZipPath', zipPath,
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  // ── macOS ──────────────────────────────────────────────────────────────────

  Future<void> _installMacOS(String zipPath, String version) async {
    final exePath = Platform.resolvedExecutable;
    // exePath = /Applications/RedStream.app/Contents/MacOS/aniworld
    // Go up 3 levels to reach the .app bundle
    final appBundle = File(exePath).parent.parent.parent.path;
    final appDir = File(appBundle).parent.path;
    final tmpDir = await getTemporaryDirectory();
    final extractDir = '${tmpDir.path}/rs_extracted_$version';

    await compute(_extractZipIsolate, [zipPath, extractDir]);

    final scriptPath = '${tmpDir.path}/rs_updater.sh';
    await File(scriptPath).writeAsString('''#!/bin/bash
sleep 2
APP=\$(find "$extractDir" -name "*.app" -maxdepth 1 | head -1)
if [ -z "\$APP" ]; then exit 1; fi
rm -rf "$appBundle"
cp -R "\$APP" "$appDir/"
open "$appBundle"
rm -rf "$extractDir"
rm -f "$zipPath"
''');
    await Process.run('chmod', ['+x', scriptPath]);
    await Process.start('bash', [scriptPath], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ── Android ────────────────────────────────────────────────────────────────

  Future<void> _installAndroid(String apkPath) async {
    final result = await OpenFile.open(apkPath);
    if (result.type != ResultType.done) {
      throw Exception('APK-Installation konnte nicht gestartet werden: ${result.message}');
    }
  }
}

// Top-level — required by compute()
void _extractZipIsolate(List<String> args) {
  final stream = InputFileStream(args[0]);
  final archive = ZipDecoder().decodeBuffer(stream);
  extractArchiveToDisk(archive, args[1]);
  stream.close();
}
