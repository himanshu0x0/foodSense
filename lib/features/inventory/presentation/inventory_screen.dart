import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data/inventory_repository.dart';
import '../models/inventory_item.dart';
import 'add_inventory_screen.dart';
import 'edit_inventory_screen.dart';

/// Phase 1 inventory list screen.
///
/// Inventory is always organization-scoped:
/// organizations/{organizationId}/inventory/{itemId}
///
/// This screen supports:
/// - realtime inventory listing
/// - search
/// - expiry/reorder filters
/// - add item
/// - edit item
/// - quantity updates
/// - delete
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    if (organizationId.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Organization information is missing.'),
        ),
      );
    }

    return _InventoryView(
      organizationId: organizationId,
    );
  }
}

class _InventoryView extends StatefulWidget {
  const _InventoryView({
    required this.organizationId,
  });

  final String organizationId;

  @override
  State<_InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<_InventoryView> {
  final InventoryRepository _repository = InventoryRepository();

  String _searchQuery = '';
  String _filter = 'all';

  bool get _isSignedIn => FirebaseAuth.instance.currentUser != null;

  @override
  Widget build(BuildContext context) {
    if (!_isSignedIn) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to view inventory.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filter inventory',
            initialValue: _filter,
            onSelected: (value) {
              setState(() {
                _filter = value;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'all',
                child: Text('All items'),
              ),
              PopupMenuItem<String>(
                value: 'expiring',
                child: Text('Expiring soon'),
              ),
              PopupMenuItem<String>(
                value: 'expired',
                child: Text('Expired'),
              ),
              PopupMenuItem<String>(
                value: 'reorder',
                child: Text('Needs reorder'),
              ),
            ],
            icon: const Icon(Icons.filter_list_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddInventory,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: StreamBuilder<List<InventoryItem>>(
              stream: _repository.watchItems(
                organizationId: widget.organizationId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState(
                    context,
                    snapshot.error,
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final List<InventoryItem> items =
                    snapshot.data ?? const <InventoryItem>[];

                final List<InventoryItem> filteredItems =
                    _applyFilters(items);

                if (items.isEmpty) {
                  return _buildEmptyState(context);
                }

                if (filteredItems.isEmpty) {
                  return _buildNoMatchState(context);
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      100,
                    ),
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final InventoryItem item = filteredItems[index];

                      return _InventoryCard(
                        item: item,
                        onEdit: () => _openEditInventory(item),
                        onDelete: () => _confirmDelete(item),
                        onUpdateQuantity: () =>
                            _showQuantityDialog(item),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search inventory',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.clear_rounded),
                ),
        ),
      ),
    );
  }

  List<InventoryItem> _applyFilters(List<InventoryItem> items) {
    return items.where((item) {
      final bool matchesSearch = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery) ||
          item.category.toLowerCase().contains(_searchQuery);

      if (!matchesSearch) {
        return false;
      }

      switch (_filter) {
        case 'expired':
          return item.isExpired;

        case 'expiring':
          final int? days = item.daysUntilExpiry;
          return days != null && days >= 0 && days <= 7;

        case 'reorder':
          return item.needsReorder;

        case 'all':
        default:
          return true;
      }
    }).toList(growable: false);
  }

  Future<void> _openAddInventory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddInventoryScreen(
          organizationId: widget.organizationId,
        ),
      ),
    );
  }

  Future<void> _openEditInventory(InventoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditInventoryScreen(
          item: item,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    // Firestore snapshots are already realtime. This delay simply provides
    // a small visual completion point for pull-to-refresh.
    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );
  }

  Future<void> _showQuantityDialog(InventoryItem item) async {
    final TextEditingController controller = TextEditingController(
      text: _formatQuantity(item.quantity),
    );

    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final double? newQuantity = await showDialog<double>(
      context: context,
      builder: (context) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }

              final double quantity =
                  double.parse(controller.text.trim());

              setDialogState(() {
                saving = true;
              });

              try {
                await _repository.updateQuantity(
                  organizationId: widget.organizationId,
                  itemId: item.id,
                  quantity: quantity,
                );

                if (context.mounted) {
                  Navigator.of(context).pop(quantity);
                }
              } catch (error) {
                if (!context.mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _friendlyErrorMessage(error),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );

                setDialogState(() {
                  saving = false;
                });
              }
            }

            return AlertDialog(
              title: Text('Update ${item.name}'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  enabled: !saving,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'New quantity',
                    suffixText: item.unit,
                  ),
                  validator: (value) {
                    final String text = value?.trim() ?? '';

                    if (text.isEmpty) {
                      return 'Quantity is required.';
                    }

                    final double? parsed = double.tryParse(text);

                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid non-negative quantity.';
                    }

                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (newQuantity != null && mounted) {
      _showMessage(
        'Quantity updated to ${_formatQuantity(newQuantity)} ${item.unit}.',
      );
    }
  }

  Future<void> _confirmDelete(InventoryItem item) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete inventory item?'),
          content: Text(
            'This will permanently remove "${item.name}" '
            "from this organization's inventory.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await _repository.deleteItem(
        organizationId: widget.organizationId,
        itemId: item.id,
      );

      if (!mounted) return;

      _showMessage('Inventory item deleted.');
    } catch (error) {
      if (!mounted) return;

      debugPrint('Delete inventory error: $error');

      _showMessage(
        _friendlyErrorMessage(error),
      );
    }
  }

  String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }

    return quantity.toStringAsFixed(2);
  }

  String _friendlyErrorMessage(Object error) {
    final String message = error.toString();

    if (message.contains('do not have access')) {
      return 'You do not have access to this organization.';
    }

    if (message.contains('Manager access is required')) {
      return 'Manager permission is required for this action.';
    }

    if (message.contains('does not exist')) {
      return 'The organization could not be found.';
    }

    if (message.contains('signed in')) {
      return 'Please sign in again.';
    }

    return 'Unable to complete the inventory action. Please try again.';
  }

  Widget _buildEmptyState(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 90),
          Icon(
            Icons.inventory_2_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'No inventory items yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add ingredients and stock items to start tracking '
            'quantity and expiry information.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openAddInventory,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first item'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatchState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching items',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a different search term or filter.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    Object? error,
  ) {
    final String message = _friendlyErrorMessage(
      error ?? 'Unknown inventory error',
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
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

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdateQuantity,
  });

  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onUpdateQuantity;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final String expiryText = _expiryText(item);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(_categoryIcon(item.category)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.category,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Item actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'quantity':
                        onUpdateQuantity();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'quantity',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.scale_outlined),
                        title: Text('Update quantity'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    icon: Icons.scale_outlined,
                    label: 'Quantity',
                    value:
                        '${_formatQuantity(item.quantity)} ${item.unit}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoChip(
                    icon: Icons.kitchen_outlined,
                    label: 'Storage',
                    value: _capitalize(item.storageType),
                  ),
                ),
              ],
            ),
            if (item.hasExpiryDate) ...[
              const SizedBox(height: 10),
              _StatusBanner(
                icon: item.isExpired
                    ? Icons.error_outline_rounded
                    : Icons.event_outlined,
                text: expiryText,
                isWarning: item.isExpired ||
                    (item.daysUntilExpiry != null &&
                        item.daysUntilExpiry! <= 7),
              ),
            ],
            if (item.needsReorder) ...[
              const SizedBox(height: 10),
              const _StatusBanner(
                icon: Icons.warning_amber_rounded,
                text: 'Stock is at or below reorder level.',
                isWarning: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _expiryText(InventoryItem item) {
    if (item.isExpired) {
      return 'Expired on ${_formatDate(item.expiryDate!)}';
    }

    final int? days = item.daysUntilExpiry;

    if (days == null) {
      return '';
    }

    if (days == 0) {
      return 'Expires today (${_formatDate(item.expiryDate!)})';
    }

    if (days == 1) {
      return 'Expires tomorrow (${_formatDate(item.expiryDate!)})';
    }

    return 'Expires in $days days (${_formatDate(item.expiryDate!)})';
  }

  static IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'grains':
        return Icons.rice_bowl_outlined;
      case 'pulses':
        return Icons.grass_outlined;
      case 'dairy':
        return Icons.local_drink_outlined;
      case 'vegetables':
        return Icons.eco_outlined;
      case 'fruits':
        return Icons.apple_outlined;
      case 'oils':
        return Icons.water_drop_outlined;
      case 'spices':
        return Icons.spa_outlined;
      case 'beverages':
        return Icons.local_cafe_outlined;
      case 'packaged food':
        return Icons.inventory_2_outlined;
      default:
        return Icons.restaurant_outlined;
    }
  }

  static String _formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }

    return quantity.toStringAsFixed(2);
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toUpperCase() + value.substring(1);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    this.isWarning = false,
  });

  final IconData icon;
  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final Color background = isWarning
        ? colors.errorContainer
        : colors.secondaryContainer;

    final Color foreground = isWarning
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
