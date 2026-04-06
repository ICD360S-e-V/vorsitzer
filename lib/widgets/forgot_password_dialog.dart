import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class ForgotPasswordDialog extends StatefulWidget {
  final ApiService apiService;

  const ForgotPasswordDialog({super.key, required this.apiService});

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _mitgliedernummerController = TextEditingController();
  final _recoveryCodeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _mitgliedernummerController.dispose();
    _recoveryCodeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwörter stimmen nicht überein';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await widget.apiService.recoverPassword(
        _mitgliedernummerController.text.trim(),
        _recoveryCodeController.text.trim(),
        _newPasswordController.text,
      );

      if (result['success'] == true) {
        setState(() {
          _successMessage = 'Passwort erfolgreich zurückgesetzt!\n\nSie können sich jetzt mit Ihrem neuen Passwort anmelden.';
          _mitgliedernummerController.clear();
          _recoveryCodeController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Passwort-Zurücksetzung fehlgeschlagen';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verbindungsfehler: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.lock_reset,
                      size: 32,
                      color: Color(0xFF4a90d9),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Passwort vergessen',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Geben Sie Ihre Benutzernummer und den Wiederherstellungscode ein, den Sie bei der Registrierung erstellt haben.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const Divider(height: 24),

                // Error/Success messages
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Benutzernummer field
                TextFormField(
                  controller: _mitgliedernummerController,
                  decoration: InputDecoration(
                    labelText: 'Benutzernummer',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bitte Benutzernummer eingeben';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Recovery Code field
                TextFormField(
                  controller: _recoveryCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Wiederherstellungscode (6 Ziffern)',
                    prefixIcon: const Icon(Icons.security),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bitte Wiederherstellungscode eingeben';
                    }
                    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                      return 'Code muss genau 6 Ziffern haben';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // New Password field
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    labelText: 'Neues Passwort',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bitte neues Passwort eingeben';
                    }
                    if (value.length < 6) {
                      return 'Passwort muss mindestens 6 Zeichen haben';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Passwort bestätigen',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Bitte Passwort bestätigen';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwörter stimmen nicht überein';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Reset Password button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4a90d9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Passwort zurücksetzen',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
