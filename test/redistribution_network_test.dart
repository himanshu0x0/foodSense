import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/features/redistribution/redistribution_request.dart';
import 'package:foodsense/features/redistribution/redistribution_status_service.dart';

void main() {
  final RedistributionStatusService service = RedistributionStatusService();

  test('pending can be accepted', () {
    expect(
      service.canTransition(
        RedistributionStatus.pending,
        RedistributionStatus.accepted,
      ),
      isTrue,
    );
  });

  test('accepted can be scheduled for pickup', () {
    expect(
      service.canTransition(
        RedistributionStatus.accepted,
        RedistributionStatus.pickupScheduled,
      ),
      isTrue,
    );
  });

  test('pickup scheduled can become collected', () {
    expect(
      service.canTransition(
        RedistributionStatus.pickupScheduled,
        RedistributionStatus.collected,
      ),
      isTrue,
    );
  });

  test('collected can become delivered', () {
    expect(
      service.canTransition(
        RedistributionStatus.collected,
        RedistributionStatus.delivered,
      ),
      isTrue,
    );
  });

  test('delivered can become completed', () {
    expect(
      service.canTransition(
        RedistributionStatus.delivered,
        RedistributionStatus.completed,
      ),
      isTrue,
    );
  });

  test('completed is terminal', () {
    expect(
      service.allowedNextStatuses(RedistributionStatus.completed),
      isEmpty,
    );
  });

  test('pending cannot jump directly to completed', () {
    expect(
      () => service.validateTransition(
        RedistributionStatus.pending,
        RedistributionStatus.completed,
      ),
      throwsStateError,
    );
  });

  test('rejected is terminal', () {
    expect(service.allowedNextStatuses(RedistributionStatus.rejected), isEmpty);
  });

  test('cancelled is terminal', () {
    expect(
      service.allowedNextStatuses(RedistributionStatus.cancelled),
      isEmpty,
    );
  });
}
