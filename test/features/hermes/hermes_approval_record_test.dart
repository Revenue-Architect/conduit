import 'package:conduit/features/hermes/widgets/hermes_approval_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: an answered approval stays in the run as who decided and when.
  test('an answered approval records who decided and when', () {
    final at = DateTime(2026, 10, 30, 7, 44);
    expect(
      approvalRecordLead(approved: true, at: at),
      'Approved by you · 7:44',
    );
    expect(
      approvalRecordLead(approved: false, at: DateTime(2026, 10, 30, 19, 5)),
      'Denied by you · 7:05',
    );
    expect(approvalRecordLead(approved: true), 'Approved by you');
  });
}
