import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/food_record_repository.dart';
import '../models/daily_food_record.dart';

/// Phase 1 screen for editing an existing daily food record.
///
/// Firestore access is handled by [FoodRecordRepository]; this screen only
/// manages presentation state, form input, and validation.
///
/// Route parameters:
/// - organizationId
/// - recordId
class EditDailyRecordScreen extends StatefulWidget {
  const EditDailyRecordScreen({
    super.key,
    required this.organizationId,
    required this.recordId,
  });

  final String organizationId;
  final String recordId;

  @override
  State<EditDailyRecordScreen> createState() => _EditDailyRecordScreenState();
}

class _EditDailyRecordScreenState extends State<EditDailyRecordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final FoodRecordRepository _repository = FoodRecordRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _menuController = TextEditingController();
  final TextEditingController _expectedPeopleController =
      TextEditingController();
  final TextEditingController _actualPeopleController =
      TextEditingController();
  final TextEditingController _mealsPreparedController =
      TextEditingController();
  final TextEditingController _mealsConsumedController =
      TextEditingController();
  final TextEditingController _wasteKgController = TextEditingController();

  static const List<String> _mealTypes = <String>[
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Other',
  ];

  DailyFoodRecord? _record;
  DateTime _recordDate = DateTime.now();
  String _selectedMealType = 'Lunch';
  bool _specialEvent = false;

  bool _isLoadingRecord = true;
  bool _isSaving = false;

  String? _loadError;

  @override
  void initState() {
    super.initState();

    _mealsPreparedController.addListener(_refreshRemainingPreview);
    _mealsConsumedController.addListener(_refreshRemainingPreview);

    _loadRecord();
  }

  @override
  void dispose() {
    _mealsPreparedController.removeListener(_refreshRemainingPreview);
    _mealsConsumedController.removeListener(_refreshRemainingPreview);

    _menuController.dispose();
    _expectedPeopleController.dispose();
    _actualPeopleController.dispose();
    _mealsPreparedController.dispose();
    _mealsConsumedController.dispose();
    _wasteKgController.dispose();

    super.dispose();
  }

  void _refreshRemainingPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadRecord() async {
    if (widget.organizationId.trim().isEmpty ||
        widget.recordId.trim().isEmpty) {
      setState(() {
        _isLoadingRecord = false;
        _loadError = 'Organization ID and record ID are required.';
      });
      return;
    }

    try {
      final DailyFoodRecord? record = await _repository.getRecord(
        organizationId: widget.organizationId,
        recordId: widget.recordId,
      );

      if (!mounted) {
        return;
      }

      if (record == null) {
        setState(() {
          _isLoadingRecord = false;
          _loadError = 'This food record could not be found.';
        });
        return;
      }

      _populateForm(record);

      setState(() {
        _record = record;
        _isLoadingRecord = false;
      });
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingRecord = false;
        _loadError = _firebaseErrorMessage(error);
      });
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingRecord = false;
        _loadError =
            error.message?.toString() ?? 'Invalid record information.';
      });
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingRecord = false;
        _loadError = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Edit daily record load error: $error');

      setState(() {
        _isLoadingRecord = false;
        _loadError = 'Unable to load this food record.';
      });
    }
  }

  void _populateForm(DailyFoodRecord record) {
    _recordDate = DateTime(
      record.recordDate.year,
      record.recordDate.month,
      record.recordDate.day,
    );

    _selectedMealType = _mealTypes.contains(record.mealType)
        ? record.mealType
        : 'Other';

    _menuController.text = record.menu;
    _expectedPeopleController.text = record.expectedPeople.toString();
    _actualPeopleController.text = record.actualPeople.toString();
    _mealsPreparedController.text = record.mealsPrepared.toString();
    _mealsConsumedController.text = record.mealsConsumed.toString();
    _wasteKgController.text = record.wasteKg.toString();
    _specialEvent = record.specialEvent;
  }

  Future<void> _pickRecordDate() async {
    final DateTime now = DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      helpText: 'Select record date',
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _recordDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
      );
    });
  }

  int _parseIntOrZero(String value) {
    return int.tryParse(value.trim()) ?? 0;
  }

  double _parseDoubleOrZero(String value) {
    return double.tryParse(value.trim()) ?? 0;
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

  String? _nonNegativeIntValidator(
    String? value, {
    required String label,
  }) {
    final String text = value?.trim() ?? '';

    if (text.isEmpty) {
      return '$label is required.';
    }

    final int? number = int.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid non-negative whole number.';
    }

    return null;
  }

  String? _nonNegativeDoubleValidator(
    String? value, {
    required String label,
  }) {
    final String text = value?.trim() ?? '';

    if (text.isEmpty) {
      return '$label is required.';
    }

    final double? number = double.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid non-negative number.';
    }

    return null;
  }

  int get _previewRemainingMeals {
    final int prepared =
        _parseIntOrZero(_mealsPreparedController.text);
    final int consumed =
        _parseIntOrZero(_mealsConsumedController.text);

    final int remaining = prepared - consumed;

    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _updateRecord() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_record == null) {
      _showMessage(
        'The food record is not loaded yet.',
        isError: true,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    final int expectedPeople =
        _parseIntOrZero(_expectedPeopleController.text);
    final int actualPeople =
        _parseIntOrZero(_actualPeopleController.text);
    final int mealsPrepared =
        _parseIntOrZero(_mealsPreparedController.text);
    final int mealsConsumed =
        _parseIntOrZero(_mealsConsumedController.text);
    final double wasteKg =
        _parseDoubleOrZero(_wasteKgController.text);

    if (actualPeople > expectedPeople) {
      _showMessage(
        'Actual people cannot be greater than expected people.',
        isError: true,
      );
      return;
    }

    if (mealsConsumed > mealsPrepared) {
      _showMessage(
        'Meals consumed cannot be greater than meals prepared.',
        isError: true,
      );
      return;
    }

    final DailyFoodRecord updatedRecord = _record!.copyWith(
      organizationId: widget.organizationId,
      recordDate: _recordDate,
      mealType: _selectedMealType,
      menu: _menuController.text.trim(),
      expectedPeople: expectedPeople,
      actualPeople: actualPeople,
      mealsPrepared: mealsPrepared,
      mealsConsumed: mealsConsumed,
      mealsRemaining: mealsPrepared - mealsConsumed,
      wasteKg: wasteKg,
      specialEvent: _specialEvent,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      final DailyFoodRecord savedRecord =
          await _repository.updateRecord(updatedRecord);

      if (!mounted) {
        return;
      }

      setState(() {
        _record = savedRecord;
      });

      _showMessage(
        'Food record updated successfully.',
        isError: false,
      );

      context.pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint(
        'Edit daily record Firebase error: '
        '${error.code} ${error.message}',
      );

      _showMessage(
        _firebaseErrorMessage(error),
        isError: true,
      );
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message?.toString() ?? 'Invalid record data.',
        isError: true,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message,
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Edit daily record error: $error');

      _showMessage(
        'Unable to update the food record. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _firebaseErrorMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied. Please check your organization access and Firestore rules.';
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'unavailable':
        return 'Firebase is temporarily unavailable. Check your connection.';
      case 'failed-precondition':
        return 'Firebase requires an additional configuration step.';
      default:
        return error.message ?? 'Firebase could not complete the request.';
    }
  }

  void _showMessage(
    String message, {
    required bool isError,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.error : null,
        ),
      );
  }

  String _formatDate(DateTime date) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}';
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildError() {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.errorContainer,
              foregroundColor: colors.onErrorContainer,
              child: const Icon(
                Icons.error_outline_rounded,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load food record',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? 'Something went wrong.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadRecord,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSaving ? null : _pickRecordDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Record date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(_formatDate(_recordDate)),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String suffix,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_isSaving,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixText: suffix,
      ),
      validator: validator,
    );
  }

  Widget _buildForm() {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Edit daily record',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update the operational values recorded for this meal.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _buildDateField(),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedMealType,
                    decoration: const InputDecoration(
                      labelText: 'Meal type',
                      prefixIcon: Icon(
                        Icons.restaurant_menu_outlined,
                      ),
                    ),
                    items: _mealTypes
                        .map(
                          (String mealType) =>
                              DropdownMenuItem<String>(
                            value: mealType,
                            child: Text(mealType),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _isSaving
                        ? null
                        : (String? value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _selectedMealType = value;
                            });
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _menuController,
                    enabled: !_isSaving,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Menu',
                      hintText: 'e.g. Rice, Dal, Paneer',
                      prefixIcon: Icon(Icons.menu_book_outlined),
                      alignLabelWithHint: true,
                    ),
                    validator: (String? value) =>
                        _requiredTextValidator(
                      value,
                      label: 'Menu',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'People and production',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildNumberField(
                    controller: _expectedPeopleController,
                    label: 'Expected people',
                    hint: 'e.g. 850',
                    icon: Icons.people_outline_rounded,
                    suffix: 'people',
                    validator: (String? value) =>
                        _nonNegativeIntValidator(
                      value,
                      label: 'Expected people',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNumberField(
                    controller: _actualPeopleController,
                    label: 'Actual people',
                    hint: 'e.g. 820',
                    icon: Icons.groups_2_outlined,
                    suffix: 'people',
                    validator: (String? value) =>
                        _nonNegativeIntValidator(
                      value,
                      label: 'Actual people',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNumberField(
                    controller: _mealsPreparedController,
                    label: 'Meals prepared',
                    hint: 'e.g. 850',
                    icon: Icons.restaurant_outlined,
                    suffix: 'meals',
                    validator: (String? value) =>
                        _nonNegativeIntValidator(
                      value,
                      label: 'Meals prepared',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNumberField(
                    controller: _mealsConsumedController,
                    label: 'Meals consumed',
                    hint: 'e.g. 810',
                    icon: Icons.restaurant_rounded,
                    suffix: 'meals',
                    validator: (String? value) =>
                        _nonNegativeIntValidator(
                      value,
                      label: 'Meals consumed',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNumberField(
                    controller: _wasteKgController,
                    label: 'Food waste',
                    hint: 'e.g. 8.5',
                    icon: Icons.delete_outline_rounded,
                    suffix: 'kg',
                    validator: (String? value) =>
                        _nonNegativeDoubleValidator(
                      value,
                      label: 'Food waste',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.calculate_outlined,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Meals remaining: $_previewRemainingMeals',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme
                                  .colorScheme
                                  .onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Special event'),
                    subtitle: const Text(
                      'Attendance or consumption may be different because '
                      'of an event.',
                    ),
                    value: _specialEvent,
                    onChanged: _isSaving
                        ? null
                        : (bool value) {
                            setState(() {
                              _specialEvent = value;
                            });
                          },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _updateRecord,
                    child: _isSaving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Food Record'),
      ),
      body: _isLoadingRecord
          ? _buildLoading()
          : _loadError != null
              ? _buildError()
              : _buildForm(),
    );
  }
}
