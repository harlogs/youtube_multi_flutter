import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<List<html.File>> pickVideosWebImpl() async {
  final completer = Completer<List<html.File>>();
  final input = html.FileUploadInputElement()
    ..accept = 'video/*'
    ..multiple = true;
  html.document.body!.append(input);
  input.onChange.listen((event) {
    final files = input.files;
    completer.complete(files?.toList() ?? []);
    input.remove();
  });
  input.click();
  return completer.future;
}

Future<Uint8List?> readVideoBytesImpl(html.File file) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;
  return reader.result as Uint8List?;
}
