import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'surplus_listing.dart';
import 'surplus_repository.dart';
import 'surplus_status_service.dart';

/// Phase 3: actual surplus management.
///
/// This feature records and manages real surplus after food production.
/// It intentionally does not attempt receiver matching or logistics yet.
class SurplusManagementScreen extends StatelessWidget {
  const SurplusManagementScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    if (organizationId.trim().isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Organization information is missing.')),
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to manage surplus.')),
      );
    }

    return _SurplusManagementView(organizationId: organizationId);
  }
}

class _SurplusManagementView extends StatefulWidget {
  const _SurplusManagementView({required this.organizationId});

  final String organizationId;

  @override
  State<_SurplusManagementView> createState() => _SurplusManagementViewState();
}

class _SurplusManagementViewState extends State<_SurplusManagementView> {
  final SurplusRepository _repository = SurplusRepository();
  final SurplusStatusService _statusService = const SurplusStatusService();

  String _filter = 'active';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surplus Management'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filter surplus',
            initialValue: _filter,
            onSelected: (String value) {
              setState(() {
                _filter = value;
              });
            },
            itemBuilder: (BuildContext context) => const [
              PopupMenuItem<String>(value: 'active', child: Text('Active')),
              PopupMenuItem<String>(
                value: 'available',
                child: Text('Available'),
              ),
              PopupMenuItem<String>(
                value: 'in_progress',
                child: Text('In progress'),
              ),
              PopupMenuItem<String>(
                value: 'completed',
                child: Text('Completed'),
              ),
              PopupMenuItem<String>(value: 'closed', child: Text('Closed')),
              PopupMenuItem<String>(value: 'all', child: Text('All')),
            ],
            icon: const Icon(Icons.filter_list_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Record surplus'),
      ),
      body: StreamBuilder<List<SurplusListing>>(
        stream: _repository.watchListings(
          organizationId: widget.organizationId,
        ),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<SurplusListing>> snapshot,
            ) {
              if (snapshot.hasError) {
                return _buildError(snapshot.error);
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<SurplusListing> listings =
                  snapshot.data ?? const <SurplusListing>[];

              final List<SurplusListing> visible = listings
                  .where(_matchesFilter)
                  .toList(growable: false);

              if (visible.isEmpty) {
                return _buildEmpty(listings.isEmpty);
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SurplusListing listing = visible[index];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SurplusCard(
                        listing: listing,
                        onTap: () => _showDetails(listing),
                      ),
                    );
                  },
                ),
              );
            },
      ),
    );
  }

  bool _matchesFilter(SurplusListing listing) {
    switch (_filter) {
      case 'available':
        return listing.status == SurplusStatus.available;
      case 'in_progress':
        return listing.status == SurplusStatus.reserved ||
            listing.status == SurplusStatus.collected;
      case 'completed':
        return listing.status == SurplusStatus.distributed;
      case 'closed':
        return listing.status == SurplusStatus.expired ||
            listing.status == SurplusStatus.wasted ||
            listing.status == SurplusStatus.cancelled;
      case 'all':
        return true;
      case 'active':
      default:
        return listing.status == SurplusStatus.available ||
            listing.status == SurplusStatus.reserved ||
            listing.status == SurplusStatus.collected;
    }
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildEmpty(bool hasNoData) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.volunteer_activism_outlined, size: 52),
            const SizedBox(height: 14),
            Text(
              hasNoData
                  ? 'No surplus has been recorded.'
                  : 'No surplus matches this filter.',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Record actual surplus after service so it can be '
              'managed, tracked and prepared for later redistribution.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    final String message = error?.toString() ?? '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to load surplus listings.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message.contains('permission-denied')
                  ? 'You do not have permission to view this '
                        'organization surplus.'
                  : 'Check your Firebase connection and try again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _CreateSurplusDialog(
          onCreate:
              ({
                required String foodName,
                required String mealType,
                required double quantity,
                required String unit,
                required SurplusQuality quality,
                required DateTime preparedAt,
                required DateTime availableUntil,
                required String notes,
              }) async {
                try {
                  await _repository.createListing(
                    organizationId: widget.organizationId,
                    foodName: foodName,
                    mealType: mealType,
                    quantity: quantity,
                    unit: unit,
                    quality: quality,
                    preparedAt: preparedAt,
                    availableUntil: availableUntil,
                    notes: notes,
                  );

                  if (!mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Surplus recorded successfully.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                } catch (error) {
                  throw StateError(_friendlyWriteError(error));
                }
              },
        );
      },
    );
  }

  String _friendlyWriteError(Object error) {
    final String message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Manager access is required to record surplus.';
    }

    if (message.contains('signed-in')) {
      return 'Please sign in again.';
    }

    return message.replaceFirst('Bad state: ', '');
  }

  Future<void> _showDetails(SurplusListing listing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: _SurplusDetailsSheet(
            listing: listing,
            allowedNextStatuses: _statusService.allowedNextStatuses(
              listing.status,
            ),
            onStatusSelected: (SurplusStatus nextStatus) async {
              Navigator.of(sheetContext).pop();

              try {
                if (nextStatus == SurplusStatus.expired &&
                    listing.status == SurplusStatus.available) {
                  await _repository.markExpired(
                    organizationId: widget.organizationId,
                    surplusId: listing.id,
                  );
                } else {
                  await _repository.updateStatus(
                    organizationId: widget.organizationId,
                    surplusId: listing.id,
                    nextStatus: nextStatus,
                  );
                }

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        'Surplus marked as '
                        '${surplusStatusLabel(nextStatus)}.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              } catch (error) {
                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        error.toString().replaceFirst('Bad state: ', ''),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              }
            },
          ),
        );
      },
    );
  }
}

class _CreateSurplusDialog extends StatefulWidget {
  const _CreateSurplusDialog({required this.onCreate});

  final Future<void> Function({
    required String foodName,
    required String mealType,
    required double quantity,
    required String unit,
    required SurplusQuality quality,
    required DateTime preparedAt,
    required DateTime availableUntil,
    required String notes,
  })
  onCreate;

  @override
  State<_CreateSurplusDialog> createState() => _CreateSurplusDialogState();
}

class _CreateSurplusDialogState extends State<_CreateSurplusDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _foodNameController = TextEditingController();
  final TextEditingController _mealTypeController = TextEditingController(
    text: 'Other',
  );
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  static const List<String> _units = <String>[
    'kg',
    'g',
    'portion',
    'meal',
    'tray',
    'pack',
  ];

  SurplusQuality _quality = SurplusQuality.good;
  String _unit = 'kg';
  DateTime _preparedAt = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _availableUntil = DateTime.now().add(const Duration(hours: 4));
  bool _saving = false;

  @override
  void dispose() {
    _foodNameController.dispose();
    _mealTypeController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record actual surplus'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _foodNameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Food name',
                    hintText: 'e.g. Vegetable pulao',
                    prefixIcon: Icon(Icons.restaurant_outlined),
                  ),
                  validator: (String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Food name is required.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mealTypeController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Meal / service',
                    hintText: 'e.g. Lunch',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _quantityController,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          hintText: 'e.g. 8.5',
                          prefixIcon: Icon(Icons.scale_outlined),
                        ),
                        validator: (String? value) {
                          final double? parsed = double.tryParse(
                            value?.trim() ?? '',
                          );

                          if (parsed == null || parsed <= 0) {
                            return 'Enter a quantity greater than zero.';
                          }

                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: _units
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _saving
                            ? null
                            : (String? value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() {
                                  _unit = value;
                                });
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SurplusQuality>(
                  initialValue: _quality,
                  decoration: const InputDecoration(
                    labelText: 'Quality / urgency',
                    prefixIcon: Icon(Icons.fact_check_outlined),
                  ),
                  items: SurplusQuality.values
                      .map(
                        (SurplusQuality quality) =>
                            DropdownMenuItem<SurplusQuality>(
                              value: quality,
                              child: Text(surplusQualityLabel(quality)),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (SurplusQuality? value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _quality = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                _DateTimeField(
                  label: 'Prepared at',
                  value: _preparedAt,
                  enabled: !_saving,
                  onTap: _pickPreparedAt,
                ),
                const SizedBox(height: 12),
                _DateTimeField(
                  label: 'Available until',
                  value: _availableUntil,
                  enabled: !_saving,
                  onTap: _pickAvailableUntil,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  enabled: !_saving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Add serving, storage or handling notes.',
                    prefixIcon: Icon(Icons.notes_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record surplus'),
        ),
      ],
    );
  }

  Future<void> _pickPreparedAt() async {
    final DateTime? value = await _pickDateTime(
      context: context,
      initial: _preparedAt,
    );

    if (value == null || !mounted) {
      return;
    }

    setState(() {
      _preparedAt = value;

      if (!_availableUntil.isAfter(value)) {
        _availableUntil = value.add(const Duration(hours: 4));
      }
    });
  }

  Future<void> _pickAvailableUntil() async {
    final DateTime? value = await _pickDateTime(
      context: context,
      initial: _availableUntil,
    );

    if (value == null || !mounted) {
      return;
    }

    if (!value.isAfter(_preparedAt)) {
      _showError('Available-until must be after prepared-at.');
      return;
    }

    setState(() {
      _availableUntil = value;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final double quantity = double.parse(_quantityController.text.trim());

    setState(() {
      _saving = true;
    });

    try {
      await widget.onCreate(
        foodName: _foodNameController.text.trim(),
        mealType: _mealTypeController.text.trim(),
        quantity: quantity,
        unit: _unit,
        quality: _quality,
        preparedAt: _preparedAt,
        availableUntil: _availableUntil,
        notes: _notesController.text.trim(),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<DateTime?> _pickDateTime({
    required BuildContext context,
    required DateTime initial,
  }) async {
    final DateTime now = DateTime.now();

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? initial : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (date == null || !mounted) {
      return null;
    }

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null || !mounted) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(_formatDateTime(value)),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');

    return '$day/$month/${value.year} $hour:$minute';
  }
}

class _SurplusCard extends StatelessWidget {
  const _SurplusCard({required this.listing, required this.onTap});

  final SurplusListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _SurplusVisual visual = _visualFor(listing.status, colors);

    final bool overdue = listing.isPastAvailabilityWindow;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(visual.icon, color: visual.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            listing.foodName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(
                          label: surplusStatusLabel(listing.status),
                          background: visual.background,
                          foreground: visual.foreground,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatQuantity(listing.quantity)} '
                      '${listing.unit} • ${listing.mealType}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Available until: '
                      '${_formatDateTime(listing.availableUntil)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: overdue ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                    if (overdue && listing.status == SurplusStatus.available)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Availability window has passed. '
                          'Review and update the status.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  static String _formatDateTime(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');

    return '$day/$month/${value.year} $hour:$minute';
  }

  _SurplusVisual _visualFor(SurplusStatus status, ColorScheme colors) {
    switch (status) {
      case SurplusStatus.available:
        return _SurplusVisual(
          icon: Icons.volunteer_activism_outlined,
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case SurplusStatus.reserved:
        return _SurplusVisual(
          icon: Icons.bookmark_border_rounded,
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        );
      case SurplusStatus.collected:
        return _SurplusVisual(
          icon: Icons.local_shipping_outlined,
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        );
      case SurplusStatus.distributed:
        return _SurplusVisual(
          icon: Icons.check_circle_outline_rounded,
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case SurplusStatus.expired:
        return _SurplusVisual(
          icon: Icons.schedule_outlined,
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case SurplusStatus.wasted:
        return _SurplusVisual(
          icon: Icons.delete_outline_rounded,
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case SurplusStatus.cancelled:
        return _SurplusVisual(
          icon: Icons.cancel_outlined,
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
    }
  }
}

class _SurplusVisual {
  const _SurplusVisual({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 112),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SurplusDetailsSheet extends StatelessWidget {
  const _SurplusDetailsSheet({
    required this.listing,
    required this.allowedNextStatuses,
    required this.onStatusSelected,
  });

  final SurplusListing listing;
  final List<SurplusStatus> allowedNextStatuses;
  final Future<void> Function(SurplusStatus) onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              listing.foodName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_formatQuantity(listing.quantity)} '
              '${listing.unit} • ${listing.mealType}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Status',
              value: surplusStatusLabel(listing.status),
            ),
            _DetailRow(
              label: 'Quality',
              value: surplusQualityLabel(listing.quality),
            ),
            _DetailRow(
              label: 'Prepared',
              value: _formatDateTime(listing.preparedAt),
            ),
            _DetailRow(
              label: 'Available until',
              value: _formatDateTime(listing.availableUntil),
            ),
            if (listing.notes.isNotEmpty)
              _DetailRow(label: 'Notes', value: listing.notes),
            const SizedBox(height: 20),
            Text(
              'Update lifecycle',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (allowedNextStatuses.isEmpty)
              Text(
                'This listing is in a final lifecycle state.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...allowedNextStatuses.map(
                (SurplusStatus status) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => onStatusSelected(status),
                    icon: Icon(_statusIcon(status)),
                    label: Text('Mark as ${surplusStatusLabel(status)}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(SurplusStatus status) {
    switch (status) {
      case SurplusStatus.available:
        return Icons.undo_rounded;
      case SurplusStatus.reserved:
        return Icons.bookmark_border_rounded;
      case SurplusStatus.collected:
        return Icons.local_shipping_outlined;
      case SurplusStatus.distributed:
        return Icons.check_circle_outline_rounded;
      case SurplusStatus.expired:
        return Icons.schedule_outlined;
      case SurplusStatus.wasted:
        return Icons.delete_outline_rounded;
      case SurplusStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  static String _formatDateTime(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');

    return '$day/$month/${value.year} $hour:$minute';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
