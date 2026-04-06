import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/startup_service.dart';
import 'forgot_password_dialog.dart';

class LoginTab extends StatefulWidget {
  final ApiService apiService;
  final TextEditingController mitgliedernummerController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final bool autoLogin;
  final bool startWithWindows;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<bool> onRememberMeChanged;
  final ValueChanged<bool> onAutoLoginChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final VoidCallback onLogin;
  final Function(List activeSessions, String mitgliedernummer, String password) onMaxDevices;
  final Function(Map<String, dynamic> loginData)? onPasswordlessLogin;

  const LoginTab({
    super.key,
    required this.apiService,
    required this.mitgliedernummerController,
    required this.passwordController,
    required this.rememberMe,
    required this.autoLogin,
    required this.startWithWindows,
    required this.isLoading,
    this.errorMessage,
    required this.onRememberMeChanged,
    required this.onAutoLoginChanged,
    required this.onStartWithWindowsChanged,
    required this.onLogin,
    required this.onMaxDevices,
    this.onPasswordlessLogin,
  });

  @override
  State<LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<LoginTab> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isRequestingLogin = false;
  String? _passwordlessStatus;
  bool _passwordlessIsError = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error message
            if (widget.errorMessage != null)
              _buildMessageBox(widget.errorMessage!, isError: true),

            // Benutzernummer field
            TextFormField(
              controller: widget.mitgliedernummerController,
              decoration: InputDecoration(
                labelText: 'Benutzernummer',
                prefixIcon: const Icon(Icons.badge),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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

            // Password field
            TextFormField(
              controller: widget.passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Passwort',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Bitte Passwort eingeben';
                }
                return null;
              },
              onFieldSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 12),

            // Remember Me checkbox
            Row(
              children: [
                Checkbox(
                  value: widget.rememberMe,
                  onChanged: (value) {
                    widget.onRememberMeChanged(value ?? false);
                  },
                  activeColor: const Color(0xFF4a90d9),
                ),
                const Text('Anmeldedaten speichern'),
              ],
            ),

            // Auto Login checkbox
            Row(
              children: [
                Checkbox(
                  value: widget.autoLogin,
                  onChanged: widget.rememberMe
                      ? (value) {
                          widget.onAutoLoginChanged(value ?? false);
                        }
                      : null,
                  activeColor: const Color(0xFF4a90d9),
                ),
                Text(
                  'Automatisch anmelden',
                  style: TextStyle(
                    color: widget.rememberMe ? Colors.black : Colors.grey,
                  ),
                ),
              ],
            ),

            // Start with Windows checkbox
            Row(
              children: [
                Checkbox(
                  value: widget.startWithWindows,
                  onChanged: (value) async {
                    final newValue = value ?? false;
                    final success = await StartupService().setEnabled(newValue);
                    if (success) {
                      widget.onStartWithWindowsChanged(newValue);
                    }
                  },
                  activeColor: const Color(0xFF4a90d9),
                ),
                const Expanded(
                  child: Text('Mit Windows starten'),
                ),
                Tooltip(
                  message: 'App startet automatisch beim Windows-Login',
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Login button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: widget.isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4a90d9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Anmelden',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Forgot Password link
            TextButton(
              onPressed: _showForgotPasswordDialog,
              child: const Text(
                'Passwort vergessen?',
                style: TextStyle(
                  color: Color(0xFF4a90d9),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Divider(height: 24),
            // Ohne Passwort anmelden
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.key_off, size: 18),
                label: const Text('Ohne Passwort anmelden'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isRequestingLogin ? null : _requestPasswordlessLogin,
              ),
            ),
            if (_passwordlessStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildMessageBox(_passwordlessStatus!, isError: _passwordlessIsError),
              ),
          ],
        ),
      ),
    );
  }

  void _handleLogin() {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }
    widget.onLogin();
  }

  Future<void> _requestPasswordlessLogin() async {
    final mitgliedernummer = widget.mitgliedernummerController.text.trim();
    if (mitgliedernummer.isEmpty) {
      setState(() {
        _passwordlessStatus = 'Bitte Benutzernummer eingeben';
        _passwordlessIsError = true;
      });
      return;
    }

    setState(() {
      _isRequestingLogin = true;
      _passwordlessStatus = 'Anfrage wird gesendet...';
      _passwordlessIsError = false;
    });

    try {
      final response = await widget.apiService.requestPasswordlessLogin(mitgliedernummer);
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _passwordlessStatus = 'Anfrage gesendet! Ein Admin muss Ihre Anmeldung genehmigen. Bitte warten...';
            _passwordlessIsError = false;
            _isRequestingLogin = false;
          });
          // Start polling for approval
          _pollForApproval(response['request_token'] ?? '');
        } else {
          setState(() {
            _passwordlessStatus = response['message'] ?? 'Anfrage fehlgeschlagen';
            _passwordlessIsError = true;
            _isRequestingLogin = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _passwordlessStatus = 'Verbindungsfehler';
          _passwordlessIsError = true;
          _isRequestingLogin = false;
        });
      }
    }
  }

  Future<void> _pollForApproval(String requestToken) async {
    for (int i = 0; i < 60; i++) { // 5 min max (60 x 5s)
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;

      try {
        final result = await widget.apiService.checkLoginApproval(requestToken);
        if (!mounted) return;

        if (result['success'] == true) {
          final status = result['status'] ?? '';
          if (status == 'approved') {
            setState(() {
              _passwordlessStatus = 'Genehmigt! Anmeldung wird durchgeführt...';
              _passwordlessIsError = false;
            });
            // Auto-login with approval token
            final approvalToken = result['approval_token'] ?? '';
            final loginResult = await widget.apiService.loginWithApproval(approvalToken, mitgliedernummer: widget.mitgliedernummerController.text.trim());
            if (mounted && loginResult['success'] == true) {
              if (widget.onPasswordlessLogin != null) {
                widget.onPasswordlessLogin!(loginResult);
              } else {
                widget.onLogin();
              }
            } else if (mounted) {
              setState(() {
                _passwordlessStatus = loginResult['message'] ?? 'Anmeldung fehlgeschlagen';
                _passwordlessIsError = true;
              });
            }
            return;
          } else if (status == 'denied') {
            setState(() {
              _passwordlessStatus = 'Anfrage wurde abgelehnt';
              _passwordlessIsError = true;
            });
            return;
          } else if (status == 'expired') {
            setState(() {
              _passwordlessStatus = 'Anfrage abgelaufen (5 Minuten)';
              _passwordlessIsError = true;
            });
            return;
          }
          // status == 'pending' -> continue polling
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _passwordlessStatus = 'Zeitüberschreitung - keine Genehmigung erhalten';
        _passwordlessIsError = true;
      });
    }
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => ForgotPasswordDialog(apiService: widget.apiService),
    );
  }

  Widget _buildMessageBox(String message, {required bool isError}) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade700 : Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
