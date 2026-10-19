import 'package:conduit/features/hermes/services/hermes_a2ui_interaction_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizes valid Hermes A2UI actions', () {
    const payload =
        '[A2UI_INTERACTION]\n'
        '{"version":"v0.9","action":{"name":"immich.check_status",'
        '"sourceComponentId":"immich_btn","surfaceId":"status"}}';

    expect(hermesA2uiInteractionLabel(payload), 'Immich · Check status');
    expect(
      hermesA2uiInteractionLabel(
        '[A2UI_INTERACTION]\n'
        '{"version":"v0.9","action":{"name":"refresh"}}',
      ),
      'Refresh',
    );
  });

  test('leaves ordinary and malformed user messages untouched', () {
    expect(hermesA2uiInteractionLabel('Please check Immich'), isNull);
    expect(hermesA2uiInteractionLabel('[A2UI_INTERACTION]\nnot JSON'), isNull);
    expect(
      hermesA2uiInteractionLabel(
        '[A2UI_INTERACTION]\n'
        '{"version":"v1.0","action":{"name":"immich.check_status"}}',
      ),
      isNull,
    );
  });

  test('shows the automated approval wake notice as a one-line receipt', () {
    const notice =
        '[Hermes V2 - approval decided]\n'
        'Approval 70a164c5-7aff-43ec-b6df-f2f9510e0db6 for "pairing_test" '
        'was APPROVED by Kamran at 3:21 PM (via conduit).\n'
        'Request: Harmless pairing test.\n'
        'If APPROVED: continue the task you paused.';
    expect(
      hermesA2uiInteractionLabel(notice),
      'Approved \u00b7 pairing_test \u00b7 3:21 PM',
    );
    expect(
      hermesApprovalNoticeLabel(notice.replaceFirst('APPROVED', 'DENIED')),
      'Denied \u00b7 pairing_test \u00b7 3:21 PM',
    );
    expect(hermesApprovalNoticeLabel('Approval was approved'), isNull);
  });
}
