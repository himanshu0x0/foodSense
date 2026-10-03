import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/features/surplus_management/surplus_listing.dart';
import 'package:foodsense/features/surplus_management/surplus_status_service.dart';

void main() {
  const SurplusStatusService service = SurplusStatusService();

  group('SurplusStatusService', () {
    test('available can be reserved', () {
      expect(
        service.canTransition(SurplusStatus.available, SurplusStatus.reserved),
        isTrue,
      );
    });

    test('reserved can move back to available', () {
      expect(
        service.canTransition(SurplusStatus.reserved, SurplusStatus.available),
        isTrue,
      );
    });

    test('reserved can move to collected', () {
      expect(
        service.canTransition(SurplusStatus.reserved, SurplusStatus.collected),
        isTrue,
      );
    });

    test('collected can move to distributed', () {
      expect(
        service.canTransition(
          SurplusStatus.collected,
          SurplusStatus.distributed,
        ),
        isTrue,
      );
    });

    test('distributed is a final state', () {
      expect(service.allowedNextStatuses(SurplusStatus.distributed), isEmpty);
    });

    test('cannot move from available directly to distributed', () {
      expect(
        service.canTransition(
          SurplusStatus.available,
          SurplusStatus.distributed,
        ),
        isFalse,
      );
    });

    test('invalid transition throws StateError', () {
      expect(
        () => service.validateTransition(
          SurplusStatus.available,
          SurplusStatus.distributed,
        ),
        throwsStateError,
      );
    });
  });
}
