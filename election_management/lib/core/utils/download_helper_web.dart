import 'dart:html' as html;

void downloadFileFromBase64(String base64String, String filename) {
  final anchor = html.AnchorElement(
      href: 'data:text/csv;base64,$base64String')
    ..target = 'blank'
    ..download = filename;
  
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
