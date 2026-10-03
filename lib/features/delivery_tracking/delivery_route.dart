class TrafficInterval {
  const TrafficInterval({
    required this.startPolylinePointIndex,
    required this.endPolylinePointIndex,
    required this.speed,
  });

  final int startPolylinePointIndex;
  final int endPolylinePointIndex;
  final String speed;

  factory TrafficInterval.fromMap(Map<String, dynamic> data) {
    return TrafficInterval(
      startPolylinePointIndex:
          (data['startPolylinePointIndex'] as num?)?.toInt() ?? 0,
      endPolylinePointIndex:
          (data['endPolylinePointIndex'] as num?)?.toInt() ?? 0,
      speed: (data['speed'] as String?) ?? 'NORMAL',
    );
  }
}

class DeliveryRouteOption {
  const DeliveryRouteOption({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.staticDurationSeconds,
    required this.trafficLevel,
    required this.encodedPolyline,
    required this.trafficIntervals,
  });

  final String label;
  final int distanceMeters;
  final int durationSeconds;
  final int staticDurationSeconds;
  final String trafficLevel;
  final String encodedPolyline;
  final List<TrafficInterval> trafficIntervals;

  int get delaySeconds {
    final int delay = durationSeconds - staticDurationSeconds;
    return delay < 0 ? 0 : delay;
  }

  factory DeliveryRouteOption.fromMap(Map<String, dynamic> data) {
    final List<dynamic> rawIntervals =
        data['trafficIntervals'] as List<dynamic>? ?? <dynamic>[];

    return DeliveryRouteOption(
      label: (data['label'] as String?) ?? 'ROUTE',
      distanceMeters: (data['distanceMeters'] as num?)?.toInt() ?? 0,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      staticDurationSeconds:
          (data['staticDurationSeconds'] as num?)?.toInt() ?? 0,
      trafficLevel: (data['trafficLevel'] as String?) ?? 'unknown',
      encodedPolyline: (data['encodedPolyline'] as String?) ?? '',
      trafficIntervals: rawIntervals
          .whereType<Map>()
          .map(
            (dynamic item) =>
                TrafficInterval.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class DeliveryRouteResult {
  const DeliveryRouteResult({
    required this.options,
    required this.recommendedIndex,
    required this.generatedAt,
  });

  final List<DeliveryRouteOption> options;
  final int recommendedIndex;
  final DateTime? generatedAt;

  DeliveryRouteOption get recommended {
    if (options.isEmpty) {
      throw StateError('No route options were returned.');
    }
    final int index = recommendedIndex.clamp(0, options.length - 1);
    return options[index];
  }

  factory DeliveryRouteResult.fromMap(Map<String, dynamic> data) {
    final List<dynamic> rawOptions =
        data['options'] as List<dynamic>? ?? <dynamic>[];

    DateTime? generatedAt;
    final dynamic rawGeneratedAt = data['generatedAt'];
    if (rawGeneratedAt is String) {
      generatedAt = DateTime.tryParse(rawGeneratedAt);
    }

    return DeliveryRouteResult(
      options: rawOptions
          .whereType<Map>()
          .map(
            (dynamic item) => DeliveryRouteOption.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      recommendedIndex: (data['recommendedIndex'] as num?)?.toInt() ?? 0,
      generatedAt: generatedAt,
    );
  }
}
