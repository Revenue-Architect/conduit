import 'dart:convert';
import 'dart:io';

import '../lib/features/hermes/services/hermes_openui_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/check_hermes_openui.dart file.openui [...]');
    exitCode = 2;
    return;
  }
  final covered = <String>{};
  void walk(HermesOpenuiNode node) { covered.add(node.type); for(final child in node.children) { walk(child); } }
  for(final path in args) {
    try { walk(parseHermesOpenui(File(path).readAsStringSync())); stdout.writeln(jsonEncode({'file':path,'valid':true})); }
    on FormatException catch (e) { stderr.writeln(jsonEncode({'file':path,'valid':false,'error':e.message})); exitCode=1; }
  }
  stdout.writeln(jsonEncode({'components':covered.length,'missing':hermesOpenuiComponentNames.difference(covered).toList()}));
}
