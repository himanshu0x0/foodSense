import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/cloudinary_upload_service.dart';
import '../data/inventory_repository.dart';
import '../models/inventory_item.dart';

/// Phase 1 screen for editing an existing inventory item.
///
/// This screen updates the existing organization-scoped document instead of
/// creating another inventory record.
///
/// Firestore path:
/// organizations/{organizationId}/inventory/{itemId}
class EditInventoryScreen extends StatefulWidget {
  const EditInventoryScreen({super.key, required this.item});

  final InventoryItem item;

  @override
  State<EditInventoryScreen> createState() => _EditInventoryScreenState();
}

const String foodSenseApiBaseUrl = String.fromEnvironment(
  'FOODSENSE_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class _EditInventoryScreenState extends State<EditInventoryScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _supplierController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _reorderLevelController = TextEditingController();

  final InventoryRepository _inventoryRepository = InventoryRepository();
  final ImagePicker _imagePicker = ImagePicker();
  late final CloudinaryUploadService _cloudinaryService;

  File? _selectedImage;
  bool _isPickingImage = false;
  bool _removeExistingImage = false;

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

  late String _selectedCategory;
  late String _selectedUnit;
  late String _selectedStorageType;

  DateTime? _purchaseDate;
  DateTime? _expiryDate;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _cloudinaryService = CloudinaryUploadService(
      backendBaseUrl: foodSenseApiBaseUrl,
    );

    final InventoryItem item = widget.item;

    _nameController.text = item.name;
    _quantityController.text = _formatNumber(item.quantity);
    _supplierController.text = item.supplierName ?? '';
    _unitCostController.text = item.unitCost == null
        ? ''
        : _formatNumber(item.unitCost!);
    _reorderLevelController.text = item.reorderLevel?.toString() ?? '';

    _selectedCategory = _categories.contains(item.category)
        ? item.category
        : 'Other';

    _selectedUnit = _units.contains(item.unit) ? item.unit : 'kg';

    _selectedStorageType = _storageTypes.contains(item.storageType)
        ? item.storageType
        : 'other';

    _purchaseDate = item.purchaseDate;
    _expiryDate = item.expiryDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _supplierController.dispose();
    _unitCostController.dispose();
    _reorderLevelController.dispose();
    _cloudinaryService.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final DateTime now = DateTime.now();

    final DateTime initialDate = _purchaseDate ?? now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
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

  Future<void> _chooseImage() async {
    if (_isSaving || _isPickingImage) {
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (source == null || !mounted) {
      return;
    }

    setState(() {
      _isPickingImage = true;
      _removeExistingImage = false;
    });

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked != null && mounted) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (error) {
      debugPrint('Edit inventory image picker error: $error');
      if (mounted) {
        _showMessage('Unable to select the inventory photo.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  Widget _buildImageSection(ThemeData theme) {
    final File? newImage = _selectedImage;
    final String? currentImageUrl = _removeExistingImage
        ? null
        : widget.item.imageUrl;
    final bool hasCurrentImage =
        currentImageUrl != null && currentImageUrl.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Inventory photo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The image is stored in Cloudinary. Firestore keeps the URL and '
            'public ID.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (newImage != null) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.file(newImage, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            Text('New photo selected.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
          ] else if (hasCurrentImage) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  currentImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                          ),
                        );
                      },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Current inventory photo', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
          ] else if (_removeExistingImage) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'The current photo will be removed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: (_isSaving || _isPickingImage) ? null : _chooseImage,
                icon: _isPickingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  _isPickingImage
                      ? 'Selecting photo...'
                      : hasCurrentImage || newImage != null
                      ? 'Change photo'
                      : 'Add photo',
                ),
              ),
              if (newImage != null)
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _selectedImage = null;
                          });
                        },
                  child: const Text('Discard new'),
                ),
              if (hasCurrentImage)
                TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _removeExistingImage = true;
                          });
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
              if (_removeExistingImage)
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _removeExistingImage = false;
                          });
                        },
                  child: const Text('Keep current'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final double? quantity = double.tryParse(_quantityController.text.trim());

    final double? unitCost = _unitCostController.text.trim().isEmpty
        ? null
        : double.tryParse(_unitCostController.text.trim());

    final int? reorderLevel = _reorderLevelController.text.trim().isEmpty
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

    setState(() {
      _isSaving = true;
    });

    final InventoryItem originalItem = widget.item;
    final File? newImage = _selectedImage;
    final bool removeImage = _removeExistingImage && newImage == null;

    try {
      InventoryItem savedItem;

      if (newImage != null) {
        // Upload first. With the current signer, item ID is also the public
        // ID, so Cloudinary replaces an existing asset when appropriate.
        final CloudinaryUploadResult uploadResult = await _cloudinaryService
            .uploadInventoryImage(
              file: newImage,
              organizationId: originalItem.organizationId,
              itemId: originalItem.id,
            );

        final InventoryItem updatedItem = originalItem.copyWith(
          name: _nameController.text.trim(),
          category: _selectedCategory,
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
          imageUrl: uploadResult.secureUrl,
          imagePublicId: uploadResult.publicId,
        );

        await _inventoryRepository.updateItem(updatedItem);
        savedItem = updatedItem;
      } else {
        final InventoryItem updatedItem = originalItem.copyWith(
          name: _nameController.text.trim(),
          category: _selectedCategory,
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

        await _inventoryRepository.updateItem(updatedItem);
        savedItem = updatedItem;

        final String oldPublicId = originalItem.imagePublicId?.trim() ?? '';

        if (removeImage && oldPublicId.isNotEmpty) {
          await _cloudinaryService.deleteAsset(
            organizationId: originalItem.organizationId,
            mediaType: 'inventory',
            entityId: originalItem.id,
            publicId: oldPublicId,
            resourceType: 'image',
          );

          savedItem = await _inventoryRepository.clearImage(
            organizationId: originalItem.organizationId,
            itemId: originalItem.id,
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newImage != null
                  ? 'Inventory item and photo updated successfully.'
                  : removeImage
                  ? 'Inventory item updated and photo removed.'
                  : 'Inventory item updated successfully.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      context.pop(savedItem);
    } on CloudinaryUploadException catch (error) {
      if (!mounted) return;

      debugPrint('Edit inventory Cloudinary error: $error');
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;

      debugPrint('Edit inventory error: $error');

      _showMessage(_friendlyErrorMessage(error));
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
      return 'Manager permission is required to edit inventory.';
    }

    if (message.contains('does not exist')) {
      return 'The organization could not be found.';
    }

    if (message.contains('sign')) {
      return 'Please sign in again.';
    }

    return 'Unable to update the inventory item. Please try again.';
  }

  String? _requiredValidator(String? value, {required String fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
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

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toUpperCase() + value.substring(1);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
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
      appBar: AppBar(title: const Text('Edit Inventory Item')),
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
                      'Update stock',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Update the existing inventory record. The item '
                      'keeps the same organization and document ID.',
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
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) =>
                          _requiredValidator(value, fieldName: 'Item name'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
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
                              if (value == null) return;

                              setState(() {
                                _selectedCategory = value;
                              });
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
                              prefixIcon: Icon(Icons.scale_outlined),
                            ),
                            validator: _quantityValidator,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
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
                      value: _selectedStorageType,
                      decoration: const InputDecoration(
                        labelText: 'Storage type',
                        prefixIcon: Icon(Icons.kitchen_outlined),
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
                        prefixIcon: Icon(Icons.warning_amber_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildImageSection(theme),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _isSaving ? null : () => context.pop(),
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
}
