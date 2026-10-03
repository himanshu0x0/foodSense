import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'delivery_location_service.dart';
import 'place_search.dart';
import 'places_search_api_service.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    required this.title,
    required this.organizationId,
    required this.apiBaseUrl,
    this.initialPoint,
    this.initialAddress = '',
    super.key,
  });

  final String title;
  final String organizationId;
  final String apiBaseUrl;
  final LatLng? initialPoint;
  final String initialAddress;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  late final PlacesSearchApiService _placesService;
  final DeliveryLocationService _locationService = DeliveryLocationService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;

  LatLng? _selectedPoint;
  String _selectedAddress = '';
  String? _selectedPlaceName;
  String? _selectedPlaceId;
  List<PlaceSearchResult> _results = <PlaceSearchResult>[];
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();

    _placesService = PlacesSearchApiService(
      baseUrl: widget.apiBaseUrl,
    );

    _selectedPoint = widget.initialPoint;
    _selectedAddress = widget.initialAddress.trim();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _placesService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng target =
        _selectedPoint ?? const LatLng(28.9845, 77.7064);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Use my location',
            onPressed: _useCurrentLocation,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: target,
              zoom: 14,
            ),
            mapType: MapType.normal,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: true,
            markers: _selectedPoint == null
                ? <Marker>{}
                : <Marker>{
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedPoint!,
                      infoWindow: InfoWindow(
                        title: _selectedPlaceName ?? 'Selected location',
                        snippet: _selectedAddress.isEmpty
                            ? 'Tap "Use this location" to confirm'
                            : _selectedAddress,
                      ),
                    ),
                  },
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
            },
            onTap: _selectMapPoint,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _buildSearchPanel(context),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildSelectionPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchNow(),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search pickup/drop-off location',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _searchError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final PlaceSearchResult result = _results[index];

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      result.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectSearchResult(result),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.place_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedPoint == null
                        ? 'Search for a place or tap the map.'
                        : (_selectedAddress.isEmpty
                            ? 'Selected map point'
                            : _selectedAddress),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (_selectedPoint != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '${_selectedPoint!.latitude.toStringAsFixed(6)}, '
                '${_selectedPoint!.longitude.toStringAsFixed(6)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selectedPoint == null
                    ? null
                    : _confirmSelection,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use this location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchError = null;
    });

    _searchDebounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _results = <PlaceSearchResult>[];
        _searching = false;
      });
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 450),
      _searchNow,
    );
  }

  Future<void> _searchNow() async {
    final String query = _searchController.text.trim();

    if (query.length < 2) {
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      final List<PlaceSearchResult> results =
          await _placesService.searchPlaces(
        organizationId: widget.organizationId,
        query: query,
        latitude: _selectedPoint?.latitude,
        longitude: _selectedPoint?.longitude,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
        _searchError = results.isEmpty
            ? 'No matching places found. Try a fuller address or place name.'
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _results = <PlaceSearchResult>[];
        _searchError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _selectSearchResult(PlaceSearchResult result) async {
    setState(() {
      _selectedPoint = result.position;
      _selectedAddress = result.address;
      _selectedPlaceName = result.name;
      _selectedPlaceId = result.placeId;
      _results = <PlaceSearchResult>[];
      _searchController.text = result.name;
      _searchError = null;
    });

    final GoogleMapController controller = await _controller.future;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: result.position,
          zoom: 16,
        ),
      ),
    );
  }

  void _selectMapPoint(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _selectedAddress = '';
      _selectedPlaceName = null;
      _selectedPlaceId = null;
      _results = <PlaceSearchResult>[];
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _results = <PlaceSearchResult>[];
      _searchError = null;
    });
  }

  void _confirmSelection() {
    final LatLng? point = _selectedPoint;
    if (point == null) {
      return;
    }

    Navigator.of(context).pop(
      LocationSelection(
        position: point,
        address: _selectedAddress,
        placeName: _selectedPlaceName,
        placeId: _selectedPlaceId,
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    final Position? position =
        await _locationService.getCurrentPosition();

    if (position == null || !mounted) {
      return;
    }

    final LatLng point = LatLng(
      position.latitude,
      position.longitude,
    );

    setState(() {
      _selectedPoint = point;
      _selectedAddress = 'Current device location';
      _selectedPlaceName = 'Current location';
      _selectedPlaceId = null;
      _results = <PlaceSearchResult>[];
    });

    final GoogleMapController controller = await _controller.future;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: point,
          zoom: 17,
        ),
      ),
    );
  }
}
