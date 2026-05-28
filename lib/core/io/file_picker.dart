import 'dart:typed_data';

import 'package:intellipilot/core/io/file_picker_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/io/file_picker_web.dart'
    as impl;

/// One file the user picked from the OS — bytes, the original name, and the
/// best-guess MIME type. The repository re-derives MIME from magic bytes
/// server-side, so [contentType] is purely advisory.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    this.contentType,
  });
  final String name;
  final Uint8List bytes;
  final String? contentType;
}

/// Platform-conditional file picker. Web uses `<input type=file>`; native
/// targets degrade to null (file uploads aren't part of the native build yet
/// in Phase 9). Tests substitute via DI.
abstract interface class FilePicker {
  factory FilePicker() => impl.createFilePicker();

  /// True when [pickSingleFile] can actually open a system picker. False on
  /// targets where we have no implementation; the UI should hide the upload
  /// affordance there.
  bool get isSupported;

  /// Opens a single-file picker. Returns null if the user cancelled or the
  /// platform doesn't support upload.
  Future<PickedFile?> pickSingleFile();
}
