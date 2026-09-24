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
}
