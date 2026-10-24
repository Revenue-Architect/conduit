import 'dart:convert';

import 'package:conduit/features/hermes/services/hermes_activity_presenter.dart';
import 'package:conduit/features/hermes/sheets/hermes_tool_inspector_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a todo call and its result read as indented fields, not JSON', () {
    final todos = [
      {'content': 'Create the plan', 'id': 'qa-plan', 'status': 'completed'},
      {'content': 'Ask Scout', 'id': 'qa-scout', 'status': 'pending'},
    ];
    final input = jsonEncode({
      'calls': [
        {
          'name': 'todo_list',
          'arguments': {'merge': true, 'todos': todos},
        },
      ],
    });

    expect(
      hermesReadableToolText(input),
      'merge: true\n'
      'todos:\n'
      '  - content: Create the plan\n'
      '    id: qa-plan\n'
      '    status: completed\n'
      '  - content: Ask Scout\n'
      '    id: qa-scout\n'
      '    status: pending',
    );
    expect(
      hermesReadableToolText(jsonEncode({'exit_code': 0, 'output': 'a\nb'})),
      'output:\na\nb\nexit_code: 0',
    );
  });

  test('a tool time too short to mean anything is not shown', () {
    expect(
      HermesActivityPresenter.durationLabel(const Duration(milliseconds: 20)),
      isNull,
    );
    expect(
      HermesActivityPresenter.durationLabel(const Duration(milliseconds: 1200)),
      '1.2s',
    );
  });
}
