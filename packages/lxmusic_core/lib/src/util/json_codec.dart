import 'dart:convert';

String prettyJson(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
