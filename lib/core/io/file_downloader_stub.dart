import 'package:flutter/services.dart';
import 'package:intellipilot/core/io/file_downloader.dart';

class _ClipboardDownloader implements FileDownloader {
  const _ClipboardDownloader();

  @override
  bool get canDownload => false;

  @override
  Future<bool> download({
    required String filename,
    required String mimeType,
    required String contents,
  }) async {
    await Clipboard.setData(ClipboardData(text: contents));
    return true;
  }

  @override
  Future<bool> downloadBytes({
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async => false;
}

FileDownloader createFileDownloader() => const _ClipboardDownloader();
