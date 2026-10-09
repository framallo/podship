import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Saves [text] as [fileName] in the browser's downloads (INT-11).
void downloadText(String fileName, String text) {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
