import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/food_record_repository.dart';
import '../models/daily_food_record.dart';

/// Phase 1 screen for recording one food-operation event.
///
/// Persistence is handled by [FoodRecordRepository]. The screen contains
/// presentation and validation logic only.
///
/// Firestore path:
/// organizations/{organizationId}/food_records/{recordId}
class DailyRecordScreen extends StatefulWidget {
  const DailyRecordScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  State<DailyRecordScreen> createState() => _DailyRecordScreenState();
}

class _DailyRecordScreenState extends State<DailyRecordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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

  final FoodRecordRepository _repository = FoodRecordRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const List<String> _mealTypes = <String>[
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Other',
  ];

  DateTime _recordDate = DateTime.now();
  String _selectedMealType = 'Lunch';
  bool _specialEvent = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _mealsPreparedController.addListener(_refreshPreview);
    _mealsConsumedController.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _mealsPreparedController.removeListener(_refreshPreview);
    _mealsConsumedController.removeListener(_refreshPreview);

    _menuController.dispose();
    _expectedPeopleController.dispose();
    _actualPeopleController.dispose();
    _mealsPreparedController.dispose();
    _mealsConsumedController.dispose();
    _wasteKgController.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
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

  Future<void> _saveRecord() async {
    FocusManager.instance.primaryFocus?.unfocus();

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

    final String organizationId = widget.organizationId.trim();

    if (organizationId.isEmpty) {
      _showMessage(
        'Organization information is missing.',
        isError: true,
      );
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

    final DailyFoodRecord record = DailyFoodRecord(
      id: '',
      organizationId: organizationId,
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
      await _repository.createRecord(record);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Daily food record saved successfully.',
        isError: false,
      );

      _clearForm();
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint(
        'Daily food record Firebase error: '
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

      debugPrint('Daily food record error: $error');

      _showMessage(
        'Unable to save the food record. Please try again.',
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

  void _clearForm() {
    _menuController.clear();
    _expectedPeopleController.clear();
    _actualPeopleController.clear();
    _mealsPreparedController.clear();
    _mealsConsumedController.clear();
    _wasteKgController.clear();

    _formKey.currentState?.reset();

    setState(() {
      _recordDate = DateTime.now();
      _selectedMealType = 'Lunch';
      _specialEvent = false;
    });
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
        return error.message ?? 'Firebase could not save this record.';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  int get _previewRemainingMeals {
    final int prepared =
        _parseIntOrZero(_mealsPreparedController.text);
    final int consumed =
        _parseIntOrZero(_mealsConsumedController.text);

    final int remaining = prepared - consumed;
    return remaining < 0 ? 0 : remaining;
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

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildDateField() {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSaving ? null : _pickRecordDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Record date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          _formatDate(_recordDate),
          style: theme.textTheme.bodyLarge,
        ),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Food Record'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Record today’s operations',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These records become the historical dataset used for '
                      'future FoodSense demand forecasting.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      context,
                      'Meal information',
                    ),
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
                      maxLines: 2,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Menu',
                        hintText: 'e.g. Rice, Dal, Paneer',
                        prefixIcon: Icon(
                          Icons.menu_book_outlined,
                        ),
                        alignLabelWithHint: true,
                      ),
                      validator: (String? value) =>
                          _requiredTextValidator(
                        value,
                        label: 'Menu',
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      context,
                      'People and production',
                    ),
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
                                color:
                                    theme.colorScheme.onSecondaryContainer,
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
                        'Attendance or consumption may be different '
                        'because of an event.',
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
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.info_outline_rounded,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'FoodSense stores these operational facts as '
                              'historical data. AI forecasting and surplus '
                              'redistribution will use this data in later phases.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveRecord,
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Save Daily Record'),
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
      ),
    );
  }
}
