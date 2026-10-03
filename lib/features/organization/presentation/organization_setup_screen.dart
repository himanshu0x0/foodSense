import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/models/user_model.dart';
import '../data/organization_repository.dart';
import '../models/organization_model.dart';

/// Phase 1 organization onboarding screen.
///
/// Collects the minimum organization information required before the user
/// can manage inventory and record daily food operations.
///
/// Data is stored cleanly in separate documents:
///
/// users/{uid}
/// organizations/{organizationId}
///
/// The user's `organizationId` field references the organization's document.
/// Operational datasets remain in their own organization-scoped collections.
class OrganizationSetupScreen extends StatefulWidget {
  const OrganizationSetupScreen({super.key});

  @override
  State<OrganizationSetupScreen> createState() =>
      _OrganizationSetupScreenState();
}

class _OrganizationSetupScreenState extends State<OrganizationSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _peopleServedController = TextEditingController();

  final OrganizationRepository _organizationRepository =
      OrganizationRepository();
  final AuthRepository _authRepository = AuthRepository();

  static const List<String> _organizationTypes = <String>[
    'College / University',
    'School',
    'Factory / Industrial Canteen',
    'Corporate Cafeteria',
    'Hotel',
    'Restaurant',
    'Hospital',
    'Catering Service',
    'Other',
  ];

  String? _selectedOrganizationType;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingOrganization();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _peopleServedController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingOrganization() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    try {
      final OrganizationModel? existing = await _organizationRepository
          .getMyOrganization();

      if (existing != null) {
        _nameController.text = existing.name;
        _addressController.text = existing.address;
        _cityController.text = existing.city;
        _stateController.text = existing.state;
        _peopleServedController.text = existing.peopleServed.toString();

        _selectedOrganizationType = _organizationTypes.contains(existing.type)
            ? existing.type
            : 'Other';
      }
    } on FirebaseException catch (error) {
      debugPrint(
        'Load organization Firebase error: '
        '${error.code} ${error.message}',
      );

      if (mounted) {
        _showMessage(_firebaseErrorMessage(error), isError: true);
      }
    } catch (error) {
      debugPrint('Load organization error: $error');

      if (mounted) {
        _showMessage('Unable to load organization details.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveOrganization() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    final int? peopleServed = int.tryParse(_peopleServedController.text.trim());

    if (peopleServed == null || peopleServed < 0) {
      _showMessage('Enter a valid number of people served.', isError: true);
      return;
    }

    final String? organizationType = _selectedOrganizationType;

    if (organizationType == null || organizationType.isEmpty) {
      _showMessage('Please select an organization type.', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final OrganizationModel? existing = await _organizationRepository
          .getMyOrganization();

      late final OrganizationModel organization;

      if (existing == null) {
        organization = await _organizationRepository.createOrganization(
          name: _nameController.text,
          type: organizationType,
          address: _addressController.text,
          city: _cityController.text,
          state: _stateController.text,
          country: 'India',
          peopleServed: peopleServed,
        );
      } else {
        organization = existing.copyWith(
          name: _nameController.text.trim(),
          type: organizationType,
          address: _addressController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          country: 'India',
          peopleServed: peopleServed,
        );

        await _organizationRepository.updateOrganization(organization);
      }

      // Keep the relationship explicit and small:
      // users/{uid}.organizationId -> organizations/{organizationId}
      final UserModel? userProfile = await _authRepository.getUserProfile(
        currentUser.uid,
      );

      if (userProfile == null) {
        // This should normally never happen because registration creates the
        // user profile. Do not silently continue with inconsistent data.
        throw StateError(
          'User profile was not found. Please sign out and register again.',
        );
      }

      await _authRepository.updateUserProfile(
        userProfile.copyWith(organizationId: organization.id),
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        existing == null
            ? 'Organization created successfully.'
            : 'Organization updated successfully.',
        isError: false,
      );

      // Existing dashboard state is refreshed when it is rebuilt. Returning
      // to the dashboard keeps the Phase 1 onboarding flow simple.
      context.go('/dashboard');
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint(
        'Save organization Firebase error: '
        '${error.code} ${error.message}',
      );

      _showMessage(_firebaseErrorMessage(error), isError: true);
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message.toString(), isError: true);
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message, isError: true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Save organization error: $error');

      _showMessage(
        'Unable to save the organization. Please try again.',
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
        return 'Permission denied. Please check your Firestore security rules.';
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'unavailable':
        return 'Firebase is temporarily unavailable. Check your connection.';
      case 'failed-precondition':
        return 'Firebase requires an additional configuration step.';
      case 'deadline-exceeded':
        return 'The request took too long. Please try again.';
      case 'not-found':
        return 'The requested Firebase document was not found.';
      case 'already-exists':
        return 'This organization record already exists.';
      default:
        return error.message ?? 'Firebase could not complete this operation.';
    }
  }

  String? _requiredValidator(String? value, {required String fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }

    return null;
  }

  String? _peopleValidator(String? value) {
    final String text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'People served is required.';
    }

    final int? number = int.tryParse(text);

    if (number == null || number < 0) {
      return 'Enter a valid non-negative number.';
    }

    return null;
  }

  void _showMessage(String message, {required bool isError}) {
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

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Organization Setup')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.business_rounded,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Set up your organization',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tell us about the kitchen or organization '
                            'where FoodSense will collect food-operation '
                            'data.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),

                          _buildSectionTitle(context, 'Organization details'),

                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Organization name',
                              hintText: 'e.g. ABC College',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                            validator: (value) => _requiredValidator(
                              value,
                              fieldName: 'Organization name',
                            ),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String>(
                            value: _selectedOrganizationType,
                            decoration: const InputDecoration(
                              labelText: 'Organization type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _organizationTypes
                                .map(
                                  (type) => DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(type),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedOrganizationType = value;
                                    });
                                  },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Organization type is required.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          _buildSectionTitle(context, 'Location'),

                          TextFormField(
                            controller: _addressController,
                            enabled: !_isSaving,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              hintText: 'Enter organization address',
                              prefixIcon: Icon(Icons.location_on_outlined),
                              alignLabelWithHint: true,
                            ),
                            validator: (value) =>
                                _requiredValidator(value, fieldName: 'Address'),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _cityController,
                            enabled: !_isSaving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'City',
                              hintText: 'e.g. Meerut',
                              prefixIcon: Icon(Icons.location_city_outlined),
                            ),
                            validator: (value) =>
                                _requiredValidator(value, fieldName: 'City'),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _stateController,
                            enabled: !_isSaving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'State',
                              hintText: 'e.g. Uttar Pradesh',
                              prefixIcon: Icon(Icons.map_outlined),
                            ),
                            validator: (value) =>
                                _requiredValidator(value, fieldName: 'State'),
                          ),
                          const SizedBox(height: 24),

                          _buildSectionTitle(context, 'Kitchen capacity'),

                          TextFormField(
                            controller: _peopleServedController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'People served per day',
                              hintText: 'e.g. 1000',
                              prefixIcon: Icon(Icons.groups_outlined),
                              suffixText: 'people',
                            ),
                            validator: _peopleValidator,
                          ),
                          const SizedBox(height: 28),

                          ElevatedButton(
                            onPressed: _isSaving ? null : _saveOrganization,
                            child: _isSaving
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text('Save and Continue'),
                          ),
                          const SizedBox(height: 10),

                          OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => context.go('/dashboard'),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(height: 12),

                          Text(
                            'Only basic organization information is '
                            'stored here. Operational data such as '
                            'inventory and food records is stored '
                            'separately.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
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
