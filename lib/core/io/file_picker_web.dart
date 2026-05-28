import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:intellipilot/core/io/file_picker.dart';
import 'package:web/web.dart' as web;

class _WebFilePicker implements FilePicker {
  const _WebFilePicker();

  @override
  bool get isSupported => true;

  @override
  Future<PickedFile?> pickSingleFile() async {
    final completer = Completer<PickedFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..style.display = 'none';

    void cleanup() {
      input.remove();
    }

    input.onChange.listen((_) async {
      final files = input.files;
      if (files == null || files.length == 0) {
        cleanup();
        completer.complete(null);
        return;
      }
      final file = files.item(0)!;
      final buf = await file.arrayBuffer().toDart;
      final bytes = buf.toDart.asUint8List();
      cleanup();
      completer.complete(
        PickedFile(
          name: file.name,
          bytes: Uint8List.fromList(bytes),
          contentType: file.type.isEmpty ? null : file.type,
        ),
      );
    });

    web.document.body!.appendChild(input);
    input.click();
    return completer.future;
  }
}

FilePicker createFilePicker() => const _WebFilePicker();
