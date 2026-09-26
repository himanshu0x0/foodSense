import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/inventory_repository.dart';

/// Phase 1 screen for creating an inventory item.
///
/// The screen intentionally collects only operational information needed for
/// inventory tracking and later forecasting:
/// - item name/category
/// - quantity and unit
/// - purchase/expiry dates
/// - storage type
/// - optional supplier/cost/reorder level
class AddInventoryScreen extends StatefulWidget {
  const AddInventoryScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  State<AddInventoryScreen> createState() => _AddInventoryScreenState();
}

class _AddInventoryScreenState extends State<AddInventoryScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _supplierController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _reorderLevelController = TextEditingController();

  final InventoryRepository _inventoryRepository = InventoryRepository();

  static const List<String> _categories = [
    'Grains',
    'Pulses',
    'Dairy',
    'Vegetables',
    'Fruits',
    'Protein',
    'Oils',
    'Spices',
    'Beverages',
    'Packaged Food',
    'Other',
  ];

  static const List<String> _units = [
    'kg',
    'g',
    'litre',
    'ml',
    'piece',
    'pack',
    'tray',
    'box',
  ];

  static const List<String> _storageTypes = [
    'ambient',
    'refrigerated',
    'frozen',
    'dry storage',
    'other',
  ];

  String? _selectedCategory;
  String _selectedUnit = 'kg';
  String _selectedStorageType = 'ambient';

  DateTime? _purchaseDate;
  DateTime? _expiryDate;

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _supplierController.dispose();
    _unitCostController.dispose();
    _reorderLevelController.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final DateTime now = DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select purchase date',
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _purchaseDate = picked;

      if (_expiryDate != null && _expiryDate!.isBefore(picked)) {
        _expiryDate = null;
      }
    });
  }

  Future<void> _pickExpiryDate() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = _purchaseDate ?? now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate != null && !_expiryDate!.isBefore(firstDate)
          ? _expiryDate!
          : firstDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10),
      helpText: 'Select expiry date',
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _expiryDate = picked;
    });
  }

  Future<void> _saveItem() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;
      context.go('/login');
      return;
    }

    final double? quantity =
        double.tryParse(_quantityController.text.trim());

    final double? unitCost = _unitCostController.text.trim().isEmpty
        ? null
        : double.tryParse(_unitCostController.text.trim());

    final int? reorderLevel =
        _reorderLevelController.text.trim().isEmpty
            ? null
            : int.tryParse(_reorderLevelController.text.trim());

    if (quantity == null || quantity < 0) {
      _showMessage('Enter a valid quantity.');
      return;
    }

    if (_unitCostController.text.trim().isNotEmpty &&
        (unitCost == null || unitCost < 0)) {
      _showMessage('Enter a valid non-negative unit cost.');
      return;
    }

    if (_reorderLevelController.text.trim().isNotEmpty &&
        (reorderLevel == null || reorderLevel < 0)) {
      _showMessage('Enter a valid non-negative reorder level.');
      return;
    }

    if (_expiryDate != null &&
        _purchaseDate != null &&
        _expiryDate!.isBefore(_purchaseDate!)) {
      _showMessage('Expiry date cannot be before the purchase date.');
      return;
    }

    if (widget.organizationId.trim().isEmpty) {
      _showMessage('Organization information is missing.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _inventoryRepository.createItem(
        organizationId: widget.organizationId,
        name: _nameController.text,
        category: _selectedCategory!,
        quantity: quantity,
        unit: _selectedUnit,
        purchaseDate: _purchaseDate,
        expiryDate: _expiryDate,
        storageType: _selectedStorageType,
        supplierName: _supplierController.text.trim().isEmpty
            ? null
            : _supplierController.text.trim(),
        unitCost: unitCost,
        reorderLevel: reorderLevel,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Inventory item added successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      context.pop();
    } catch (error) {
      if (!mounted) return;

      debugPrint('Add inventory error: $error');

      _showMessage(
        _friendlyErrorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _friendlyErrorMessage(Object error) {
    final String message = error.toString();

    if (message.contains('do not have access')) {
      return 'You do not have permission to manage this inventory.';
    }

    if (message.contains('Manager access is required')) {
      return 'Manager permission is required to add inventory.';
    }

    if (message.contains('does not exist')) {
      return 'The selected organization could not be found.';
    }

    if (message.contains('signed in')) {
      return 'Please sign in again.';
    }

    return 'Unable to add inventory item. Please try again.';
  }

  String? _requiredTextValidator(
    String? value, {
    required String label,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }

    return null;
  }

  String? _quantityValidator(String? value) {
    final String text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Quantity is required.';
    }

    final double? number = double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid non-negative quantity.';
    }

    return null;
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Widget _buildDateField({
    required String label,
    required String hint,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSaving ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          value == null ? hint : _formatDate(value),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: value == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Inventory Item'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add stock',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Record the ingredient or food item so FoodSense can '
                      'track stock and expiry information.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Item name',
                        hintText: 'e.g. Rice',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) => _requiredTextValidator(
                        value,
                        label: 'Item name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: _categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                _selectedCategory = value;
                              });
                            },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Category is required.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _quantityController,
                            enabled: !_isSaving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              hintText: 'e.g. 50',
                              prefixIcon: Icon(
                                Icons.scale_outlined,
                              ),
                            ),
                            validator: _quantityValidator,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedUnit,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                            ),
                            items: _units
                                .map(
                                  (unit) => DropdownMenuItem<String>(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedUnit = value;
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedStorageType,
                      decoration: const InputDecoration(
                        labelText: 'Storage type',
                        prefixIcon: Icon(
                          Icons.kitchen_outlined,
                        ),
                      ),
                      items: _storageTypes
                          .map(
                            (type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(_capitalize(type)),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedStorageType = value;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    _buildDateField(
                      label: 'Purchase date',
                      hint: 'Select purchase date',
                      value: _purchaseDate,
                      onTap: _pickPurchaseDate,
                    ),
                    const SizedBox(height: 16),
                    _buildDateField(
                      label: 'Expiry date',
                      hint: 'Select expiry date',
                      value: _expiryDate,
                      onTap: _pickExpiryDate,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _supplierController,
                      enabled: !_isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Supplier name (optional)',
                        hintText: 'e.g. ABC Foods',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _unitCostController,
                      enabled: !_isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Unit cost (optional)',
                        hintText: 'e.g. 55',
                        prefixIcon: Icon(Icons.currency_rupee_outlined),
                        suffixText: 'per unit',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _reorderLevelController,
                      enabled: !_isSaving,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Reorder level (optional)',
                        hintText: 'e.g. 10',
                        prefixIcon: Icon(Icons.warning_amber_outlined),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveItem,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Save Inventory Item'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed:
                          _isSaving ? null : () => context.pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;

    return value[0].toUpperCase() + value.substring(1);
  }
}
