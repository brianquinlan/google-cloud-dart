import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

void main() {
  final req = http.StreamedRequest('POST', Uri.parse('http://example.com'));
  final sink = IOSink(req.sink);
  print(sink.runtimeType);
}
