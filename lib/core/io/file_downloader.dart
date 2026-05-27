import 'package:intellipilot/core/io/file_downloader_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/io/file_downloader_web.dart'
    as impl;

/// Tiny platform-conditional helper for "save a small JSON blob the user
/// just produced". Web triggers a real browser download via Blob; native
/// targets fall back to clipboard until `share_plus` lands in a later phase.
abstract interface class FileDownloader {
  factory FileDownloader() => impl.createFileDownloader();

  /// Whether [download] actually opens a Save dialog (true on web), or
  /// degrades to a clipboard copy (false on native).
  bool get canDownload;

  /// Trigger a Save-As dialog (web) or copy to the system clipboard (native).
  /// Returns true on success, false on user cancellation / error.
  Future<bool> download({
    required String filename,
    required String mimeType,
    required String contents,
  });
}
