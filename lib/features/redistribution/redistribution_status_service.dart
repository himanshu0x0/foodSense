import 'redistribution_request.dart';

class RedistributionStatusService {
  static const Map<RedistributionStatus, Set<RedistributionStatus>>
  _transitions = <RedistributionStatus, Set<RedistributionStatus>>{
    RedistributionStatus.pending: <RedistributionStatus>{
      RedistributionStatus.accepted,
      RedistributionStatus.rejected,
      RedistributionStatus.cancelled,
      RedistributionStatus.expired,
    },
    RedistributionStatus.accepted: <RedistributionStatus>{
      RedistributionStatus.pickupScheduled,
      RedistributionStatus.rejected,
      RedistributionStatus.cancelled,
    },
    RedistributionStatus.pickupScheduled: <RedistributionStatus>{
      RedistributionStatus.collected,
      RedistributionStatus.cancelled,
    },
    RedistributionStatus.collected: <RedistributionStatus>{
      RedistributionStatus.delivered,
    },
    RedistributionStatus.delivered: <RedistributionStatus>{
      RedistributionStatus.completed,
    },
    RedistributionStatus.completed: <RedistributionStatus>{},
    RedistributionStatus.rejected: <RedistributionStatus>{},
    RedistributionStatus.cancelled: <RedistributionStatus>{},
    RedistributionStatus.expired: <RedistributionStatus>{},
  };

  bool canTransition(RedistributionStatus from, RedistributionStatus to) {
    return _transitions[from]?.contains(to) ?? false;
  }

  List<RedistributionStatus> allowedNextStatuses(RedistributionStatus from) {
    return List<RedistributionStatus>.unmodifiable(
      _transitions[from] ?? <RedistributionStatus>{},
    );
  }

  void validateTransition(RedistributionStatus from, RedistributionStatus to) {
    if (from == to) {
      return;
    }

    if (!canTransition(from, to)) {
      throw StateError(
        'Invalid redistribution status transition: '
        '${redistributionStatusLabel(from)} -> '
        '${redistributionStatusLabel(to)}.',
      );
    }
  }
}
