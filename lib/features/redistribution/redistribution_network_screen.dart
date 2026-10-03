import 'package:flutter/material.dart';

import 'redistribution_repository.dart';
import 'redistribution_request.dart';

class RedistributionNetworkScreen extends StatefulWidget {
  const RedistributionNetworkScreen({required this.organizationId, super.key});

  final String organizationId;

  @override
  State<RedistributionNetworkScreen> createState() =>
      _RedistributionNetworkScreenState();
}

class _RedistributionNetworkScreenState
    extends State<RedistributionNetworkScreen> {
  final RedistributionRepository _repository = RedistributionRepository();

  String _filter = 'active';

  bool get _hasOrganization => widget.organizationId.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (!_hasOrganization) {
      return Scaffold(
        appBar: AppBar(title: const Text('Redistribution Network')),
        body: const Center(
          child: Text('Organization information is required.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Redistribution Network'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Record redistribution request',
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.volunteer_activism_outlined),
        label: const Text('New request'),
      ),
      body: StreamBuilder<List<RedistributionRequest>>(
        stream: _repository.watchRequests(
          organizationId: widget.organizationId,
        ),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<RedistributionRequest>> snapshot,
            ) {
              if (snapshot.hasError) {
                return _buildError(theme);
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<RedistributionRequest> requests = _applyFilter(
                snapshot.data ?? <RedistributionRequest>[],
              );

              return Column(
                children: <Widget>[
                  _buildHeader(theme, snapshot.data?.length ?? 0),
                  _buildFilterBar(theme),
                  Expanded(
                    child: requests.isEmpty
                        ? _buildEmptyState(theme)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            itemCount: requests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) {
                              return _buildRequestCard(theme, requests[index]);
                            },
                          ),
                  ),
                ],
              );
            },
      ),
    );
  }

  List<RedistributionRequest> _applyFilter(List<RedistributionRequest> source) {
    switch (_filter) {
      case 'pending':
        return source
            .where(
              (RedistributionRequest request) =>
                  request.status == RedistributionStatus.pending,
            )
            .toList();
      case 'active':
        return source
            .where(
              (RedistributionRequest request) => <RedistributionStatus>{
                RedistributionStatus.pending,
                RedistributionStatus.accepted,
                RedistributionStatus.pickupScheduled,
                RedistributionStatus.collected,
                RedistributionStatus.delivered,
              }.contains(request.status),
            )
            .toList();
      case 'completed':
        return source
            .where(
              (RedistributionRequest request) =>
                  request.status == RedistributionStatus.completed,
            )
            .toList();
      case 'closed':
        return source
            .where(
              (RedistributionRequest request) => <RedistributionStatus>{
                RedistributionStatus.rejected,
                RedistributionStatus.cancelled,
                RedistributionStatus.expired,
              }.contains(request.status),
            )
            .toList();
      case 'all':
      default:
        return source;
    }
  }

  Widget _buildHeader(ThemeData theme, int totalCount) {
    final ColorScheme colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      color: colors.surfaceContainerLowest,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.volunteer_activism_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Redistribute usable surplus',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalCount request${totalCount == 1 ? '' : 's'} tracked',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
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

  Widget _buildFilterBar(ThemeData theme) {
    final List<MapEntry<String, String>> options = <MapEntry<String, String>>[
      const MapEntry<String, String>('active', 'Active'),
      const MapEntry<String, String>('pending', 'Pending'),
      const MapEntry<String, String>('completed', 'Completed'),
      const MapEntry<String, String>('closed', 'Closed'),
      const MapEntry<String, String>('all', 'All'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: options.map((MapEntry<String, String> option) {
          final bool selected = _filter == option.key;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option.value),
              selected: selected,
              onSelected: (bool value) {
                if (!value) {
                  return;
                }

                setState(() {
                  _filter = option.key;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRequestCard(ThemeData theme, RedistributionRequest request) {
    final ColorScheme colors = theme.colorScheme;
    final bool canAdvance = _repositoryStatusOptions(request.status).isNotEmpty;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(request),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      request.recipientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _buildStatusChip(theme, request.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${request.quantity.toStringAsFixed(2)} ${request.unit} • '
                '${request.foodName}',
                style: theme.textTheme.bodyLarge,
              ),
              if (request.recipientType.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  request.recipientType,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      request.address.isEmpty
                          ? 'Recipient address not recorded'
                          : request.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (request.requestedFor != null) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_outlined,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Planned: ${_formatDateTime(request.requestedFor!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (canAdvance) ...<Widget>[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showStatusDialog(request),
                    icon: const Icon(Icons.sync_alt_rounded),
                    label: const Text('Update lifecycle'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, RedistributionStatus status) {
    final ColorScheme colors = theme.colorScheme;

    final Color background;
    final Color foreground;

    switch (status) {
      case RedistributionStatus.completed:
        background = colors.primaryContainer;
        foreground = colors.onPrimaryContainer;
        break;
      case RedistributionStatus.rejected:
      case RedistributionStatus.cancelled:
      case RedistributionStatus.expired:
        background = colors.errorContainer;
        foreground = colors.onErrorContainer;
        break;
      case RedistributionStatus.pickupScheduled:
      case RedistributionStatus.collected:
      case RedistributionStatus.delivered:
        background = colors.secondaryContainer;
        foreground = colors.onSecondaryContainer;
        break;
      case RedistributionStatus.pending:
      case RedistributionStatus.accepted:
        background = colors.tertiaryContainer;
        foreground = colors.onTertiaryContainer;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        redistributionStatusLabel(status),
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.volunteer_activism_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              _filter == 'all'
                  ? 'No redistribution requests yet.'
                  : 'No $_filter redistribution requests.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a request when usable surplus is ready to be '
              'shared with a recipient organization.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 46),
            const SizedBox(height: 12),
            Text(
              'Unable to load redistribution requests.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Check organization access and your Firestore configuration.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  List<RedistributionStatus> _repositoryStatusOptions(
    RedistributionStatus status,
  ) {
    switch (status) {
      case RedistributionStatus.pending:
        return <RedistributionStatus>[
          RedistributionStatus.accepted,
          RedistributionStatus.rejected,
          RedistributionStatus.cancelled,
          RedistributionStatus.expired,
        ];
      case RedistributionStatus.accepted:
        return <RedistributionStatus>[
          RedistributionStatus.pickupScheduled,
          RedistributionStatus.rejected,
          RedistributionStatus.cancelled,
        ];
      case RedistributionStatus.pickupScheduled:
        return <RedistributionStatus>[
          RedistributionStatus.collected,
          RedistributionStatus.cancelled,
        ];
      case RedistributionStatus.collected:
        return <RedistributionStatus>[RedistributionStatus.delivered];
      case RedistributionStatus.delivered:
        return <RedistributionStatus>[RedistributionStatus.completed];
      case RedistributionStatus.completed:
      case RedistributionStatus.rejected:
      case RedistributionStatus.cancelled:
      case RedistributionStatus.expired:
        return <RedistributionStatus>[];
    }
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final TextEditingController recipientController = TextEditingController();
    final TextEditingController contactController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    final TextEditingController addressController = TextEditingController();
    final TextEditingController foodController = TextEditingController();
    final TextEditingController quantityController = TextEditingController();
    final TextEditingController sourceSurplusController =
        TextEditingController();
    final TextEditingController notesController = TextEditingController();

    String recipientType = 'NGO / food bank';
    String unit = 'kg';
    DateTime? requestedFor;

    try {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder:
                (
                  BuildContext context,
                  void Function(void Function()) setLocalState,
                ) {
                  Future<void> pickDateTime() async {
                    final DateTime now = DateTime.now();

                    final DateTime? date = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: DateTime(now.year + 1),
                      initialDate: requestedFor ?? now,
                      helpText: 'Select planned date',
                    );

                    if (date == null || !context.mounted) {
                      return;
                    }

                    final TimeOfDay? time = await showTimePicker(
                      context: context,
                      initialTime: requestedFor == null
                          ? TimeOfDay.now()
                          : TimeOfDay.fromDateTime(requestedFor!),
                    );

                    if (time == null || !context.mounted) {
                      return;
                    }

                    setLocalState(() {
                      requestedFor = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }

                  Future<void> submit() async {
                    if (saving || !formKey.currentState!.validate()) {
                      return;
                    }

                    setLocalState(() {
                      saving = true;
                    });

                    final double? quantity = double.tryParse(
                      quantityController.text.trim(),
                    );

                    if (quantity == null || quantity <= 0) {
                      setLocalState(() {
                        saving = false;
                      });
                      return;
                    }

                    try {
                      await _repository.createRequest(
                        organizationId: widget.organizationId,
                        recipientName: recipientController.text,
                        recipientType: recipientType,
                        contactName: contactController.text,
                        phone: phoneController.text,
                        email: emailController.text,
                        address: addressController.text,
                        foodName: foodController.text,
                        quantity: quantity,
                        unit: unit,
                        sourceSurplusId: sourceSurplusController.text,
                        notes: notesController.text,
                        requestedFor: requestedFor,
                      );

                      if (!context.mounted) {
                        return;
                      }

                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(this.context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Redistribution request created.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }

                      setLocalState(() {
                        saving = false;
                      });

                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(_repository.friendlyError(error)),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    }
                  }

                  return AlertDialog(
                    title: const Text('New redistribution request'),
                    content: SizedBox(
                      width: 520,
                      child: Form(
                        key: formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Create a manager-controlled handoff record for '
                                'usable surplus. It does not automatically '
                                'reserve or deliver the source surplus.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: recipientController,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Recipient organization',
                                  prefixIcon: Icon(Icons.business_outlined),
                                ),
                                validator: (String? value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Recipient organization is required.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: recipientType,
                                decoration: const InputDecoration(
                                  labelText: 'Recipient type',
                                  prefixIcon: Icon(Icons.groups_outlined),
                                ),
                                items:
                                    const <String>[
                                          'NGO / food bank',
                                          'Shelter',
                                          'Community kitchen',
                                          'School / hostel',
                                          'Charity',
                                          'Other',
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
                                        if (value == null) {
                                          return;
                                        }
                                        setLocalState(() {
                                          recipientType = value;
                                        });
                                      },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: contactController,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Contact person (optional)',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: phoneController,
                                enabled: !saving,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone (optional)',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: emailController,
                                enabled: !saving,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email (optional)',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: addressController,
                                enabled: !saving,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Recipient address',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: foodController,
                                enabled: !saving,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Food item',
                                  hintText: 'e.g. Cooked rice',
                                  prefixIcon: Icon(Icons.restaurant_outlined),
                                ),
                                validator: (String? value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Food item is required.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: TextFormField(
                                      controller: quantityController,
                                      enabled: !saving,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Quantity',
                                        prefixIcon: Icon(Icons.scale_outlined),
                                      ),
                                      validator: (String? value) {
                                        final double? parsed = double.tryParse(
                                          value?.trim() ?? '',
                                        );
                                        if (parsed == null || parsed <= 0) {
                                          return 'Enter a quantity.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: unit,
                                      decoration: const InputDecoration(
                                        labelText: 'Unit',
                                      ),
                                      items:
                                          const <String>[
                                                'kg',
                                                'g',
                                                'litre',
                                                'ml',
                                                'piece',
                                                'pack',
                                                'tray',
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
                                              if (value == null) {
                                                return;
                                              }
                                              setLocalState(() {
                                                unit = value;
                                              });
                                            },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: sourceSurplusController,
                                enabled: !saving,
                                decoration: const InputDecoration(
                                  labelText: 'Source surplus ID (optional)',
                                  hintText:
                                      'Link this request to a surplus record',
                                  prefixIcon: Icon(Icons.link_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              InkWell(
                                onTap: saving ? null : pickDateTime,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Planned handoff time (optional)',
                                    prefixIcon: Icon(
                                      Icons.event_available_outlined,
                                    ),
                                  ),
                                  child: Text(
                                    requestedFor == null
                                        ? 'Not scheduled'
                                        : _formatDateTime(requestedFor!),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: notesController,
                                enabled: !saving,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Notes (optional)',
                                  prefixIcon: Icon(Icons.notes_outlined),
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
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton.icon(
                        onPressed: saving ? null : submit,
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                        label: Text(saving ? 'Saving…' : 'Create request'),
                      ),
                    ],
                  );
                },
          );
        },
      );
    } finally {
      recipientController.dispose();
      contactController.dispose();
      phoneController.dispose();
      emailController.dispose();
      addressController.dispose();
      foodController.dispose();
      quantityController.dispose();
      sourceSurplusController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showStatusDialog(RedistributionRequest request) async {
    final List<RedistributionStatus> options = _repositoryStatusOptions(
      request.status,
    );

    if (options.isEmpty) {
      return;
    }

    final RedistributionStatus?
    selected = await showModalBottomSheet<RedistributionStatus>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              Text(
                'Update lifecycle',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${request.recipientName} • ${redistributionStatusLabel(request.status)}',
              ),
              const SizedBox(height: 14),
              ...options.map(
                (RedistributionStatus status) => ListTile(
                  leading: const Icon(Icons.arrow_forward_rounded),
                  title: Text(redistributionStatusLabel(status)),
                  onTap: () => Navigator.of(context).pop(status),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    try {
      await _repository.updateStatus(
        organizationId: widget.organizationId,
        requestId: request.id,
        status: selected,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Status updated to ${redistributionStatusLabel(selected)}.',
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
            content: Text(_repository.friendlyError(error)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _showDetails(RedistributionRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        request.recipientName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _buildStatusChip(Theme.of(context), request.status),
                  ],
                ),
                const SizedBox(height: 18),
                _detailRow(
                  context,
                  Icons.restaurant_outlined,
                  'Food',
                  '${request.foodName} • '
                      '${request.quantity.toStringAsFixed(2)} ${request.unit}',
                ),
                _detailRow(
                  context,
                  Icons.groups_outlined,
                  'Recipient type',
                  request.recipientType.isEmpty
                      ? 'Not specified'
                      : request.recipientType,
                ),
                _detailRow(
                  context,
                  Icons.person_outline,
                  'Contact',
                  request.contactName.isEmpty
                      ? 'Not specified'
                      : request.contactName,
                ),
                _detailRow(
                  context,
                  Icons.phone_outlined,
                  'Phone',
                  request.phone.isEmpty ? 'Not specified' : request.phone,
                ),
                _detailRow(
                  context,
                  Icons.email_outlined,
                  'Email',
                  request.email.isEmpty ? 'Not specified' : request.email,
                ),
                _detailRow(
                  context,
                  Icons.location_on_outlined,
                  'Address',
                  request.address.isEmpty ? 'Not specified' : request.address,
                ),
                _detailRow(
                  context,
                  Icons.link_outlined,
                  'Source surplus',
                  request.sourceSurplusId.isEmpty
                      ? 'Not linked'
                      : request.sourceSurplusId,
                ),
                _detailRow(
                  context,
                  Icons.event_available_outlined,
                  'Planned handoff',
                  request.requestedFor == null
                      ? 'Not scheduled'
                      : _formatDateTime(request.requestedFor!),
                ),
                if (request.notes.isNotEmpty)
                  _detailRow(
                    context,
                    Icons.notes_outlined,
                    'Notes',
                    request.notes,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');

    value.month.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');

    return '$day/${value.month.toString().padLeft(2, '0')}/${value.year} '
        '$hour:$minute';
  }
}
