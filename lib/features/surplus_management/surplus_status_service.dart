import 'surplus_listing.dart';

/// Validates lifecycle transitions for surplus listings.
///
/// Keeping transitions in one pure service makes the workflow predictable
/// and easy to test before logistics and receiver matching are added.
class SurplusStatusService {
  const SurplusStatusService();

  bool canTransition(SurplusStatus from, SurplusStatus to) {
    if (from == to) {
      return true;
    }

    switch (from) {
      case SurplusStatus.available:
        return to == SurplusStatus.reserved ||
            to == SurplusStatus.expired ||
            to == SurplusStatus.wasted ||
            to == SurplusStatus.cancelled;
      case SurplusStatus.reserved:
        return to == SurplusStatus.available ||
            to == SurplusStatus.collected ||
            to == SurplusStatus.cancelled;
      case SurplusStatus.collected:
        return to == SurplusStatus.distributed || to == SurplusStatus.wasted;
      case SurplusStatus.distributed:
      case SurplusStatus.expired:
      case SurplusStatus.wasted:
      case SurplusStatus.cancelled:
        return false;
    }
  }

  List<SurplusStatus> allowedNextStatuses(SurplusStatus status) {
    return SurplusStatus.values
        .where(
          (SurplusStatus candidate) =>
              candidate != status && canTransition(status, candidate),
        )
        .toList(growable: false);
  }

  void validateTransition(SurplusStatus from, SurplusStatus to) {
    if (!canTransition(from, to)) {
      throw StateError(
        'Cannot change surplus status from '
        '${surplusStatusLabel(from)} to ${surplusStatusLabel(to)}.',
      );
    }
  }
}
