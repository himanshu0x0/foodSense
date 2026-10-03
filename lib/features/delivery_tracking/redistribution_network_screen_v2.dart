import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'delivery_job.dart';
import 'delivery_location_service.dart';
import 'delivery_partner.dart';
import 'delivery_repository.dart';
import 'delivery_route.dart';
import 'delivery_routing_api_service.dart';
import 'delivery_route_map.dart';
import 'location_picker_screen.dart';
import 'place_search.dart';

class RedistributionNetworkScreenV2 extends StatefulWidget {
  const RedistributionNetworkScreenV2({
    required this.organizationId,
    super.key,
  });

  final String organizationId;

  @override
  State<RedistributionNetworkScreenV2> createState() =>
      _RedistributionNetworkScreenV2State();
}

class _RedistributionNetworkScreenV2State
    extends State<RedistributionNetworkScreenV2> {
  final DeliveryRepository _repository = DeliveryRepository();
  final DeliveryLocationService _locationService =
      DeliveryLocationService();

  late final DeliveryRoutingApiService _routingService;

  bool? _isManager;
  DeliveryPartner? _myPartner;
  List<DeliveryPartner> _partners = <DeliveryPartner>[];

  DeliveryJob? _selectedJob;
  DeliveryRouteResult? _toPickupRoute;
  DeliveryRouteResult? _deliveryRoute;
  int _selectedDeliveryRouteIndex = 0;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<DeliveryPartner>>? _partnerSubscription;

  DateTime? _lastRouteRefresh;
  bool _refreshingRoute = false;

  @override
  void initState() {
    super.initState();

    _routingService = DeliveryRoutingApiService(
      baseUrl: const String.fromEnvironment(
        'FOODSENSE_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      ),
    );

    _loadRoleAndPartner();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _partnerSubscription?.cancel();
    _routingService.dispose();
    super.dispose();
  }

  Future<void> _loadRoleAndPartner() async {
    try {
      final bool manager = await _repository.isManager(
        widget.organizationId,
      );
      final DeliveryPartner? partner =
          await _repository.getMyPartner(
        organizationId: widget.organizationId,
      );

      if (!mounted) return;

      setState(() {
        _isManager = manager;
        _myPartner = partner;
      });

      if (manager) {
        _partnerSubscription = _repository
            .watchPartners(organizationId: widget.organizationId)
            .listen((List<DeliveryPartner> partners) {
          if (!mounted) return;
          setState(() {
            _partners = partners;
          });
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isManager = false;
      });
      _showMessage('Unable to load delivery access: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.organizationId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Redistribution Network'),
        ),
        body: const Center(
          child: Text('Organization information is required.'),
        ),
      );
    }

    if (_isManager == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Redistribution Network'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return StreamBuilder<List<DeliveryJob>>(
      stream: _repository.watchJobs(
        organizationId: widget.organizationId,
        manager: _isManager!,
      ),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<DeliveryJob>> snapshot,
      ) {
        if (snapshot.hasError) {
          return _scaffold(
            const Center(
              child: Text(
                'Unable to load delivery jobs. Check Firebase permissions.',
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _scaffold(
            const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final List<DeliveryJob> jobs =
            snapshot.data ?? <DeliveryJob>[];

        DeliveryJob? selected = _selectedJob;

        if (selected != null) {
          final int index =
              jobs.indexWhere((DeliveryJob job) => job.id == selected!.id);
          if (index >= 0) {
            selected = jobs[index];
            _selectedJob = selected;
          } else {
            selected = null;
            _selectedJob = null;
          }
        }

        if (selected == null && jobs.isNotEmpty) {
          selected = jobs.first;
          _selectedJob = selected;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _refreshRoutes(selected!);
            }
          });
        }

        return _scaffold(
          _buildBody(
            jobs: jobs,
            selectedJob: selected,
          ),
        );
      },
    );
  }

  Scaffold _scaffold(Widget body) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Redistribution Network'),
        actions: <Widget>[
          if (_isManager == true)
            IconButton(
              tooltip: 'Create delivery',
              onPressed: _showCreateDeliveryDialog,
              icon: const Icon(Icons.add_road_rounded),
            ),
          IconButton(
            tooltip: 'Delivery profile',
            onPressed: _showPartnerProfileDialog,
            icon: const Icon(Icons.badge_outlined),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody({
    required List<DeliveryJob> jobs,
    required DeliveryJob? selectedJob,
  }) {
    if (jobs.isEmpty) {
      return _buildEmpty();
    }

    final DeliveryRouteOption? route =
        selectedJob == null ? null : _activeRoute(selectedJob);

    return Column(
      children: <Widget>[
        Expanded(
          flex: 6,
          child: selectedJob == null
              ? _buildEmpty()
              : DeliveryRouteMap(
                  job: selectedJob,
                  route: route,
                  showCurrentLocation:
                      selectedJob.currentLocation != null,
                ),
        ),
        Expanded(
          flex: 7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: <Widget>[
              _buildJobSelector(jobs, selectedJob),
              const SizedBox(height: 12),
              if (selectedJob != null) ...<Widget>[
                _buildMonitoringCard(selectedJob),
                const SizedBox(height: 12),
                _buildRouteCard(selectedJob),
                const SizedBox(height: 12),
                _buildStopsCard(selectedJob),
                const SizedBox(height: 12),
                _buildControlsCard(selectedJob),
                const SizedBox(height: 12),
                _buildTimeline(selectedJob),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJobSelector(
    List<DeliveryJob> jobs,
    DeliveryJob? selectedJob,
  ) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final DeliveryJob job = jobs[index];
          final bool selected = job.id == selectedJob?.id;

          return SizedBox(
            width: 255,
            child: Card(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _selectJob(job),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              job.foodName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _statusChip(job.status),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${job.quantity.toStringAsFixed(1)} ${job.unit} • '
                        '${job.deliveryPartnerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        job.dropoffAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonitoringCard(DeliveryJob job) {
    final DeliveryRouteOption? route = _activeRoute(job);
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.monitor_heart_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live delivery monitoring',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _statusChip(job.status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metric(
                    Icons.schedule_rounded,
                    'ETA',
                    route == null
                        ? '--'
                        : _formatDuration(route.durationSeconds),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metric(
                    Icons.route_rounded,
                    'Distance',
                    route == null
                        ? '--'
                        : _formatDistance(route.distanceMeters),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metric(
                    Icons.traffic_rounded,
                    'Traffic',
                    route == null
                        ? '--'
                        : _trafficLabel(route.trafficLevel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.update_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    job.currentLocationUpdatedAt == null
                        ? 'Waiting for live GPS location'
                        : 'Last GPS update: '
                            '${_formatDateTime(job.currentLocationUpdatedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (job.currentLocation?.speedMps != null) ...<Widget>[
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.speed_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Current speed: '
                    '${(job.currentLocation!.speedMps! * 3.6).toStringAsFixed(1)} km/h',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 19),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(DeliveryJob job) {
    final DeliveryRouteOption? route = _activeRoute(job);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.navigation_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.status == DeliveryStatus.enRoutePickup
                        ? 'Route to pickup'
                        : 'Pickup → drop-off route',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh route',
                  onPressed: _refreshingRoute
                      ? null
                      : () => _refreshRoutes(job),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (route == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Route not calculated yet. Tap refresh to calculate '
                  'the traffic-aware route.',
                ),
              )
            else ...<Widget>[
              Text(
                '${_formatDistance(route.distanceMeters)} • '
                '${_formatDuration(route.durationSeconds)} • '
                '${_trafficLabel(route.trafficLevel)} traffic',
              ),
              if (route.delaySeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Traffic delay: '
                    '${_formatDuration(route.delaySeconds)}',
                  ),
                ),
            ],
            if (_deliveryRoute != null &&
                _deliveryRoute!.options.length > 1 &&
                job.status != DeliveryStatus.enRoutePickup) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Alternative routes',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              ..._deliveryRoute!.options.asMap().entries.map(
                (MapEntry<int, DeliveryRouteOption> entry) {
                  final int index = entry.key;
                  final DeliveryRouteOption option = entry.value;
                  final bool selected =
                      index == _selectedDeliveryRouteIndex;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _selectedDeliveryRouteIndex = index;
                      });
                    },
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      '${_formatDuration(option.durationSeconds)} • '
                      '${_formatDistance(option.distanceMeters)}',
                    ),
                    subtitle: Text(
                      '${_trafficLabel(option.trafficLevel)} traffic • '
                      '${option.delaySeconds == 0 ? 'Low delay' : '+${_formatDuration(option.delaySeconds)} delay'}',
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStopsCard(DeliveryJob job) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Trip details',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _stop(
              number: '1',
              title: 'Pickup',
              address: job.pickupAddress,
              icon: Icons.storefront_outlined,
            ),
            _connector(),
            _stop(
              number: '2',
              title: 'Drop-off',
              address: job.dropoffAddress,
              icon: Icons.location_on_outlined,
            ),
            const Divider(height: 24),
            _infoLine(
              Icons.person_outline,
              'Delivery partner',
              job.deliveryPartnerName,
            ),
            _infoLine(
              Icons.two_wheeler_outlined,
              'Vehicle',
              '${job.vehicleType}'
              '${job.vehicleNumber.isEmpty ? '' : ' • ${job.vehicleNumber}'}',
            ),
            _infoLine(
              Icons.inventory_2_outlined,
              'Food',
              '${job.foodName} • '
              '${job.quantity.toStringAsFixed(2)} ${job.unit}',
            ),
            if (job.sourceSurplusId.isNotEmpty)
              _infoLine(
                Icons.link_outlined,
                'Surplus',
                job.sourceSurplusId,
              ),
            if (job.redistributionRequestId.isNotEmpty)
              _infoLine(
                Icons.assignment_outlined,
                'Redistribution request',
                job.redistributionRequestId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _stop({
    required String number,
    required String title,
    required String address,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          child: Text(number),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 21),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(address),
            ],
          ),
        ),
      ],
    );
  }

  Widget _connector() {
    return const Padding(
      padding: EdgeInsets.only(left: 15, top: 3, bottom: 3),
      child: SizedBox(
        height: 16,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
        ),
      ),
    );
  }

  Widget _infoLine(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 19),
          const SizedBox(width: 9),
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Not recorded' : value)),
        ],
      ),
    );
  }

  Widget _buildControlsCard(DeliveryJob job) {
    final List<DeliveryStatus> statuses = _nextStatuses(job.status);

    if (statuses.isEmpty && job.status == DeliveryStatus.delivered) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.verified_rounded),
          title: const Text(
            'Delivery completed',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'The food has been confirmed as delivered.',
          ),
        ),
      );
    }

    if (statuses.isEmpty && job.status == DeliveryStatus.cancelled) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cancel_outlined),
          title: const Text(
            'Delivery cancelled',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Delivery controls',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...statuses.map(
              (DeliveryStatus status) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: () => _handleStatus(job, status),
                  icon: Icon(_statusIcon(status)),
                  label: Text(_statusAction(status)),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _reportIssue(job),
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Report delivery issue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(DeliveryJob job) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<DeliveryEvent>>(
          stream: _repository.watchEvents(
            organizationId: widget.organizationId,
            deliveryId: job.id,
          ),
          builder: (
            BuildContext context,
            AsyncSnapshot<List<DeliveryEvent>> snapshot,
          ) {
            final List<DeliveryEvent> events =
                snapshot.data ?? <DeliveryEvent>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Monitoring timeline',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (events.isEmpty)
                  const Text('No monitoring events yet.')
                else
                  ...events.take(10).map(
                    (DeliveryEvent event) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.circle, size: 9),
                      title: Text(event.message),
                      subtitle: event.createdAt == null
                          ? null
                          : Text(_formatDateTime(event.createdAt!)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusChip(DeliveryStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        deliveryStatusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.route_outlined, size: 56),
            const SizedBox(height: 14),
            Text(
              _isManager == true
                  ? 'No delivery jobs yet'
                  : 'No deliveries assigned to you',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'A delivery job connects a prepared surplus pickup with '
              'the recipient drop-off and its delivery partner.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_isManager == true)
              FilledButton.icon(
                onPressed: _showCreateDeliveryDialog,
                icon: const Icon(Icons.add_road_rounded),
                label: const Text('Create delivery'),
              )
            else
              OutlinedButton.icon(
                onPressed: _showPartnerProfileDialog,
                icon: const Icon(Icons.badge_outlined),
                label: Text(
                  _myPartner == null
                      ? 'Register as delivery partner'
                      : 'Update delivery profile',
                ),
              ),
          ],
        ),
      ),
    );
  }

  DeliveryRouteOption? _activeRoute(DeliveryJob job) {
    if (job.status == DeliveryStatus.enRoutePickup) {
      return _toPickupRoute?.recommended;
    }

    if (_deliveryRoute != null && _deliveryRoute!.options.isNotEmpty) {
      final int index = _selectedDeliveryRouteIndex.clamp(
        0,
        _deliveryRoute!.options.length - 1,
      );

      return _deliveryRoute!.options[index];
    }

    // Keep a previously saved route visible when the live Google request is
    // temporarily unavailable (for example, during a short network outage).
    final DeliveryRouteSnapshot? snapshot = job.route;
    if (snapshot == null || snapshot.encodedPolyline.isEmpty) {
      return null;
    }

    return DeliveryRouteOption(
      label: 'SAVED_ROUTE',
      distanceMeters: snapshot.distanceMeters,
      durationSeconds: snapshot.durationSeconds,
      staticDurationSeconds: snapshot.staticDurationSeconds,
      trafficLevel: snapshot.trafficLevel,
      encodedPolyline: snapshot.encodedPolyline,
      trafficIntervals: const <TrafficInterval>[],
    );
  }

  Future<void> _selectJob(DeliveryJob job) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    setState(() {
      _selectedJob = job;
      _toPickupRoute = null;
      _deliveryRoute = null;
      _selectedDeliveryRouteIndex = 0;
      _lastRouteRefresh = null;
    });

    await _refreshRoutes(job);

    if (_isManager != true &&
        (job.status == DeliveryStatus.enRoutePickup ||
            job.status == DeliveryStatus.enRouteDelivery)) {
      await _startLocationTracking(job);
    }
  }

  Future<void> _refreshRoutes(DeliveryJob job) async {
    if (_refreshingRoute) return;

    setState(() {
      _refreshingRoute = true;
    });

    try {
      final GeoPointData? current = job.currentLocation;

      if (job.status == DeliveryStatus.enRoutePickup &&
          current != null) {
        _toPickupRoute = await _routingService.computeRoute(
          organizationId: widget.organizationId,
          originLatitude: current.latitude,
          originLongitude: current.longitude,
          destinationLatitude: job.pickup.latitude,
          destinationLongitude: job.pickup.longitude,
        );
      } else {
        _toPickupRoute = null;
      }

      if (job.status != DeliveryStatus.cancelled &&
          job.status != DeliveryStatus.delivered) {
        _deliveryRoute = await _routingService.computeRoute(
          organizationId: widget.organizationId,
          originLatitude: job.pickup.latitude,
          originLongitude: job.pickup.longitude,
          destinationLatitude: job.dropoff.latitude,
          destinationLongitude: job.dropoff.longitude,
        );

        _selectedDeliveryRouteIndex =
            _deliveryRoute!.recommendedIndex.clamp(
          0,
          _deliveryRoute!.options.length - 1,
        );

        await _repository.saveRouteSnapshot(
          organizationId: widget.organizationId,
          deliveryId: job.id,
          snapshot: _snapshotFromRoute(
            _deliveryRoute!.recommended,
          ),
        );
      }

      _lastRouteRefresh = DateTime.now();
    } catch (error) {
      if (mounted) {
        _showMessage('Route update failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingRoute = false;
        });
      }
    }
  }

  DeliveryRouteSnapshot _snapshotFromRoute(
    DeliveryRouteOption route,
  ) {
    return DeliveryRouteSnapshot(
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      staticDurationSeconds: route.staticDurationSeconds,
      delaySeconds: route.delaySeconds,
      trafficLevel: route.trafficLevel,
      encodedPolyline: route.encodedPolyline,
    );
  }

  Future<void> _startLocationTracking(DeliveryJob job) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final bool allowed =
        await _locationService.ensurePermission();

    if (!allowed || !mounted) {
      _showMessage(
        'Location permission is required for live delivery tracking.',
      );
      return;
    }

    final Position? current =
        await _locationService.getCurrentPosition();

    if (current != null) {
      await _pushPosition(job, current);
    }

    _positionSubscription =
        _locationService.positionStream().listen(
      (Position position) {
        _pushPosition(job, position);
      },
    );
  }

  Future<void> _pushPosition(
    DeliveryJob job,
    Position position,
  ) async {
    final GeoPointData location = GeoPointData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      heading: position.heading,
      speedMps: position.speed,
    );

    try {
      await _repository.updateCurrentLocation(
        organizationId: widget.organizationId,
        deliveryId: job.id,
        location: location,
      );

      final DateTime now = DateTime.now();

      if (_lastRouteRefresh == null ||
          now.difference(_lastRouteRefresh!).inSeconds >= 60) {
        final DeliveryJob currentJob =
            await _repository.getDelivery(
              organizationId: widget.organizationId,
              deliveryId: job.id,
            ) ??
            job;

        final DeliveryJob withLocation = DeliveryJob(
          id: currentJob.id,
          organizationId: currentJob.organizationId,
          redistributionRequestId:
              currentJob.redistributionRequestId,
          sourceSurplusId: currentJob.sourceSurplusId,
          status: currentJob.status,
          deliveryPartnerId:
              currentJob.deliveryPartnerId,
          deliveryPartnerName:
              currentJob.deliveryPartnerName,
          vehicleType: currentJob.vehicleType,
          vehicleNumber: currentJob.vehicleNumber,
          pickupAddress: currentJob.pickupAddress,
          pickup: currentJob.pickup,
          dropoffAddress: currentJob.dropoffAddress,
          dropoff: currentJob.dropoff,
          foodName: currentJob.foodName,
          quantity: currentJob.quantity,
          unit: currentJob.unit,
          scheduledAt: currentJob.scheduledAt,
          createdBy: currentJob.createdBy,
          currentLocation: location,
          currentLocationUpdatedAt: now,
          route: currentJob.route,
          createdAt: currentJob.createdAt,
          updatedAt: now,
        );

        await _refreshRoutes(withLocation);
      }
    } catch (_) {
      // Location failures must not crash the delivery screen.
    }
  }

  Future<void> _handleStatus(
    DeliveryJob job,
    DeliveryStatus status,
  ) async {
    try {
      await _repository.updateStatus(
        organizationId: widget.organizationId,
        deliveryId: job.id,
        status: status,
      );

      if (status == DeliveryStatus.enRoutePickup ||
          status == DeliveryStatus.enRouteDelivery) {
        final DeliveryJob refreshed =
            await _repository.getDelivery(
              organizationId: widget.organizationId,
              deliveryId: job.id,
            ) ??
            job;

        if (_isManager != true) {
          await _startLocationTracking(refreshed);
        }

        await _refreshRoutes(refreshed);
      }

      if (status == DeliveryStatus.delivered ||
          status == DeliveryStatus.cancelled) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }

      if (mounted) {
        _showMessage(
          'Delivery updated: ${deliveryStatusLabel(status)}',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    }
  }

  Future<void> _reportIssue(DeliveryJob job) async {
    final TextEditingController controller =
        TextEditingController();

    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Report delivery issue'),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                hintText:
                    'e.g. recipient unavailable, vehicle issue...',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(true),
                child: const Text('Report'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) return;

      final String issue = controller.text.trim();

      if (issue.isEmpty) {
        _showMessage('Describe the delivery issue first.');
        return;
      }

      await _repository.addEvent(
        organizationId: widget.organizationId,
        deliveryId: job.id,
        type: 'issue_reported',
        message: 'Issue reported: $issue',
      );

      if (mounted) {
        _showMessage('Delivery issue recorded.');
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showPartnerProfileDialog() async {
    final TextEditingController name =
        TextEditingController(text: _myPartner?.name ?? '');
    final TextEditingController phone =
        TextEditingController(text: _myPartner?.phone ?? '');
    final TextEditingController vehicleNumber =
        TextEditingController(
      text: _myPartner?.vehicleNumber ?? '',
    );

    String vehicleType =
        _myPartner?.vehicleType ?? 'Two wheeler';

    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setLocalState,
            ) {
              Future<void> save() async {
                if (saving || name.text.trim().isEmpty) {
                  return;
                }

                setLocalState(() {
                  saving = true;
                });

                try {
                  await _repository.saveMyPartner(
                    organizationId: widget.organizationId,
                    name: name.text,
                    phone: phone.text,
                    vehicleType: vehicleType,
                    vehicleNumber: vehicleNumber.text,
                  );

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }

                  await _loadRoleAndPartner();
                } catch (error) {
                  if (!context.mounted) return;

                  setLocalState(() {
                    saving = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              }

              return AlertDialog(
                title: const Text('Delivery partner profile'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: name,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Partner name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phone,
                        enabled: !saving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: vehicleType,
                        items: const <String>[
                          'Two wheeler',
                          'Bike',
                          'Scooter',
                          'Van',
                          'Car',
                        ]
                            .map(
                              (String value) =>
                                  DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (String? value) {
                                if (value == null) return;
                                setLocalState(() {
                                  vehicleType = value;
                                });
                              },
                        decoration: const InputDecoration(
                          labelText: 'Vehicle type',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: vehicleNumber,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle number',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(
                      saving ? 'Saving…' : 'Save profile',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      name.dispose();
      phone.dispose();
      vehicleNumber.dispose();
    }
  }

  String get _apiBaseUrl => const String.fromEnvironment(
        'FOODSENSE_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      );

  Future<void> _showCreateDeliveryDialog() async {
    if (_partners.isEmpty) {
      await _showPartnerRequiredDialog();
      return;
    }

    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    final TextEditingController food =
        TextEditingController();
    final TextEditingController quantity =
        TextEditingController();
    final TextEditingController pickupAddress =
        TextEditingController();
    final TextEditingController dropoffAddress =
        TextEditingController();
    final TextEditingController redistributionId =
        TextEditingController();
    final TextEditingController surplusId =
        TextEditingController();

    final TextEditingController pickupLat =
        TextEditingController();
    final TextEditingController pickupLng =
        TextEditingController();
    final TextEditingController dropLat =
        TextEditingController();
    final TextEditingController dropLng =
        TextEditingController();

    DeliveryPartner partner = _partners.first;
    String unit = 'kg';
    DateTime? scheduledAt;

    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder: (
              BuildContext context,
              void Function(void Function()) setLocalState,
            ) {
              Future<void> pickLocation({
                required bool pickup,
              }) async {
                final TextEditingController lat =
                    pickup ? pickupLat : dropLat;
                final TextEditingController lng =
                    pickup ? pickupLng : dropLng;

                final double? parsedLat =
                    double.tryParse(lat.text.trim());
                final double? parsedLng =
                    double.tryParse(lng.text.trim());

                final LatLng? initial =
                    parsedLat == null || parsedLng == null
                        ? null
                        : LatLng(parsedLat, parsedLng);

                final LocationSelection? selection =
                    await Navigator.of(context).push(
                  MaterialPageRoute<LocationSelection>(
                    builder: (_) => LocationPickerScreen(
                      title: pickup
                          ? 'Select pickup location'
                          : 'Select drop-off location',
                      organizationId: widget.organizationId,
                      apiBaseUrl: _apiBaseUrl,
                      initialPoint: initial,
                      initialAddress: pickup
                          ? pickupAddress.text
                          : dropoffAddress.text,
                    ),
                  ),
                );

                if (selection == null || !context.mounted) {
                  return;
                }

                setLocalState(() {
                  lat.text = selection.position.latitude.toStringAsFixed(6);
                  lng.text = selection.position.longitude.toStringAsFixed(6);

                  final TextEditingController addressController =
                      pickup ? pickupAddress : dropoffAddress;
                  final String selectedAddress =
                      selection.address.trim().isNotEmpty
                          ? selection.address.trim()
                          : 'Pinned map location';
                  addressController.text = selectedAddress;
                });
              }

              Future<void> pickSchedule() async {
                final DateTime now = DateTime.now();

                final DateTime? date =
                    await showDatePicker(
                  context: context,
                  firstDate: now,
                  lastDate: DateTime(now.year + 1),
                  initialDate: scheduledAt ?? now,
                );

                if (date == null || !context.mounted) {
                  return;
                }

                final TimeOfDay? time =
                    await showTimePicker(
                  context: context,
                  initialTime: scheduledAt == null
                      ? TimeOfDay.now()
                      : TimeOfDay.fromDateTime(
                          scheduledAt!,
                        ),
                );

                if (time == null || !context.mounted) {
                  return;
                }

                setLocalState(() {
                  scheduledAt = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              }

              Future<void> save() async {
                if (saving ||
                    !formKey.currentState!.validate()) {
                  return;
                }

                final double? parsedQuantity =
                    double.tryParse(quantity.text.trim());
                final double? pLat =
                    double.tryParse(pickupLat.text.trim());
                final double? pLng =
                    double.tryParse(pickupLng.text.trim());
                final double? dLat =
                    double.tryParse(dropLat.text.trim());
                final double? dLng =
                    double.tryParse(dropLng.text.trim());

                if (parsedQuantity == null ||
                    parsedQuantity <= 0 ||
                    pLat == null ||
                    pLng == null ||
                    dLat == null ||
                    dLng == null) {
                  return;
                }

                setLocalState(() {
                  saving = true;
                });

                try {
                  await _repository.createDelivery(
                    organizationId: widget.organizationId,
                    deliveryPartnerId: partner.userId,
                    deliveryPartnerName: partner.name,
                    vehicleType: partner.vehicleType,
                    vehicleNumber: partner.vehicleNumber,
                    pickup: GeoPointData(
                      latitude: pLat,
                      longitude: pLng,
                    ),
                    pickupAddress: pickupAddress.text,
                    dropoff: GeoPointData(
                      latitude: dLat,
                      longitude: dLng,
                    ),
                    dropoffAddress: dropoffAddress.text,
                    foodName: food.text,
                    quantity: parsedQuantity,
                    unit: unit,
                    redistributionRequestId:
                        redistributionId.text,
                    sourceSurplusId: surplusId.text,
                    scheduledAt: scheduledAt,
                  );

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } catch (error) {
                  if (!context.mounted) return;

                  setLocalState(() {
                    saving = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              }

              return AlertDialog(
                title: const Text('Create delivery job'),
                content: SizedBox(
                  width: 540,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DropdownButtonFormField<String>(
                            initialValue: partner.userId,
                            items: _partners
                                .map(
                                  (DeliveryPartner value) =>
                                      DropdownMenuItem<String>(
                                    value: value.userId,
                                    child: Text(
                                      '${value.name} • '
                                      '${value.vehicleType}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (String? value) {
                                    if (value == null) return;

                                    setLocalState(() {
                                      partner = _partners.firstWhere(
                                        (DeliveryPartner item) =>
                                            item.userId == value,
                                      );
                                    });
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Delivery partner',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: food,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Food',
                              hintText: 'Cooked rice',
                              prefixIcon:
                                  Icon(Icons.restaurant_outlined),
                            ),
                            validator: (String? value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Food is required.'
                                    : null,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextFormField(
                                  controller: quantity,
                                  enabled: !saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Quantity',
                                  ),
                                  validator: (String? value) {
                                    final double? parsed =
                                        double.tryParse(value?.trim() ?? '');
                                    return parsed == null || parsed <= 0
                                        ? 'Enter quantity.'
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: unit,
                                  items: const <String>[
                                    'kg',
                                    'g',
                                    'litre',
                                    'ml',
                                    'piece',
                                    'pack',
                                  ]
                                      .map(
                                        (String value) =>
                                            DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: saving
                                      ? null
                                      : (String? value) {
                                          if (value == null) return;
                                          setLocalState(() {
                                            unit = value;
                                          });
                                        },
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _locationField(
                            controller: pickupAddress,
                            label: 'Pickup location',
                            icon: Icons.storefront_outlined,
                            lat: pickupLat,
                            lng: pickupLng,
                            enabled: !saving,
                            onPick: () => pickLocation(pickup: true),
                          ),
                          const SizedBox(height: 10),
                          _locationField(
                            controller: dropoffAddress,
                            label: 'Drop-off location',
                            icon: Icons.location_on_outlined,
                            lat: dropLat,
                            lng: dropLng,
                            enabled: !saving,
                            onPick: () => pickLocation(pickup: false),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: redistributionId,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText:
                                  'Redistribution request ID (optional)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: surplusId,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText:
                                  'Source surplus ID (optional)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: saving ? null : pickSchedule,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText:
                                    'Scheduled handoff (optional)',
                                prefixIcon:
                                    Icon(Icons.event_available_outlined),
                              ),
                              child: Text(
                                scheduledAt == null
                                    ? 'Not scheduled'
                                    : _formatDateTime(
                                        scheduledAt!,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () =>
                            Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.add_road_rounded),
                    label: Text(
                      saving
                          ? 'Creating…'
                          : 'Create delivery',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      food.dispose();
      quantity.dispose();
      pickupAddress.dispose();
      dropoffAddress.dispose();
      redistributionId.dispose();
      surplusId.dispose();
      pickupLat.dispose();
      pickupLng.dispose();
      dropLat.dispose();
      dropLng.dispose();
    }
  }

  Widget _locationField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextEditingController lat,
    required TextEditingController lng,
    required bool enabled,
    required VoidCallback onPick,
  }) {
    Theme.of(context);
    final bool hasCoordinates =
        double.tryParse(lat.text.trim()) != null &&
        double.tryParse(lng.text.trim()) != null;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      readOnly: true,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Search or select on map',
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          tooltip: 'Search or select on map',
          onPressed: enabled ? onPick : null,
          icon: const Icon(Icons.map_outlined),
        ),
      ),
      validator: (_) {
        if (controller.text.trim().isEmpty || !hasCoordinates) {
          return 'Select $label on the map.';
        }
        return null;
      },
      onTap: enabled ? onPick : null,
    );
  }

  Future<void> _showPartnerRequiredDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add a delivery partner first'),
          content: const Text(
            'Register at least one active delivery partner before '
            'creating a delivery job.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showPartnerProfileDialog();
              },
              child: const Text('Register partner'),
            ),
          ],
        );
      },
    );
  }

  List<DeliveryStatus> _nextStatuses(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.assigned:
        return <DeliveryStatus>[
          DeliveryStatus.enRoutePickup,
        ];
      case DeliveryStatus.enRoutePickup:
        return <DeliveryStatus>[
          DeliveryStatus.arrivedPickup,
        ];
      case DeliveryStatus.arrivedPickup:
        return <DeliveryStatus>[
          DeliveryStatus.pickedUp,
        ];
      case DeliveryStatus.pickedUp:
        return <DeliveryStatus>[
          DeliveryStatus.enRouteDelivery,
        ];
      case DeliveryStatus.enRouteDelivery:
        return <DeliveryStatus>[
          DeliveryStatus.arrivedDropoff,
        ];
      case DeliveryStatus.arrivedDropoff:
        return <DeliveryStatus>[
          DeliveryStatus.delivered,
        ];
      case DeliveryStatus.delivered:
      case DeliveryStatus.cancelled:
        return <DeliveryStatus>[];
    }
  }

  IconData _statusIcon(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.enRoutePickup:
      case DeliveryStatus.enRouteDelivery:
        return Icons.navigation_rounded;
      case DeliveryStatus.arrivedPickup:
        return Icons.storefront_outlined;
      case DeliveryStatus.pickedUp:
        return Icons.inventory_2_outlined;
      case DeliveryStatus.arrivedDropoff:
        return Icons.location_on_outlined;
      case DeliveryStatus.delivered:
        return Icons.check_circle_outline_rounded;
      case DeliveryStatus.cancelled:
        return Icons.cancel_outlined;
      case DeliveryStatus.assigned:
        return Icons.assignment_outlined;
    }
  }

  String _statusAction(DeliveryStatus status) {
    switch (status) {
      case DeliveryStatus.enRoutePickup:
        return 'Start trip to pickup';
      case DeliveryStatus.arrivedPickup:
        return 'Arrived at pickup';
      case DeliveryStatus.pickedUp:
        return 'Confirm food picked up';
      case DeliveryStatus.enRouteDelivery:
        return 'Start trip to drop-off';
      case DeliveryStatus.arrivedDropoff:
        return 'Arrived at drop-off';
      case DeliveryStatus.delivered:
        return 'Confirm delivered';
      case DeliveryStatus.cancelled:
        return 'Cancel delivery';
      case DeliveryStatus.assigned:
        return 'Assigned';
    }
  }

  String _trafficLabel(String value) {
    switch (value.toLowerCase()) {
      case 'low':
      case 'normal':
        return 'Low';
      case 'moderate':
      case 'slow':
        return 'Moderate';
      case 'heavy':
      case 'traffic_jam':
        return 'Heavy';
      default:
        return 'Unknown';
    }
  }

  String _formatDistance(int meters) {
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';

    final int minutes = (seconds / 60).round();

    if (minutes < 60) return '$minutes min';

    final int hours = minutes ~/ 60;
    final int remaining = minutes % 60;

    return '${hours}h ${remaining}m';
  }

  String _formatDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month =
        value.month.toString().padLeft(2, '0');
    final String hour =
        value.hour.toString().padLeft(2, '0');
    final String minute =
        value.minute.toString().padLeft(2, '0');

    return '$day/$month/${value.year} $hour:$minute';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
