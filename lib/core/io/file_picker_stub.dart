import 'package:intellipilot/core/io/file_picker.dart';

class _StubFilePicker implements FilePicker {
  const _StubFilePicker();

  @override
  bool get isSupported => false;

  @override
  Future<PickedFile?> pickSingleFile() async => null;
}

FilePicker createFilePicker() => const _StubFilePicker();
