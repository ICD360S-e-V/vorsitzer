import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../services/device_integrity_service.dart';
import '../services/diagnostic_service.dart';
import '../services/logger_service.dart';
import '../services/startup_service.dart';
import '../widgets/legal_footer.dart';
import '../widgets/diagnostic_consent_dialog.dart';
import '../widgets/login_tab.dart';
import 'dashboard_screen.dart';

final _log = LoggerService();

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _apiService = ApiService();
  final _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  // Login form controllers (shared with LoginTab)
  final _mitgliedernummerController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // State
  bool _rememberMe = false;
  bool _autoLogin = false;
  bool _startWithWindows = false;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _loginErrorMessage;

  // ✅ SECURITY FIX (2026-02-10): Rate limiting to prevent brute-force attacks
  int _failedLoginAttempts = 0;
  DateTime? _lastFailedAttempt;
  static const int _maxFailedAttempts = 5;
  static const Duration _cooldownDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  /// Best-effort secure read. Returns null on any failure (e.g. -34018 on unsigned macOS).
  /// We never fall back to plaintext storage — secrets stay secret or are not persisted.
  Future<String?> _safeRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      _log.warning('Secure read unavailable for $key (skipped): $e', tag: 'AUTH');
      return null;
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMitgliedernummer = await _safeRead('mitgliedernummer');
    final savedPassword = await _safeRead('password');
    final savedToken = await _safeRead('access_token');
    final rememberMe = prefs.getBool('remember_me') ?? true;
    final autoLogin = prefs.getBool('auto_login') ?? true;

    // Load startup with Windows state - default to enabled on first run
    bool startWithWindows = StartupService().isEnabled;
    if (!prefs.containsKey('startup_configured')) {
      await prefs.setBool('startup_configured', true);
      final success = await StartupService().setEnabled(true);
      if (success) {
        startWithWindows = true;
      }
    }

    // Can auto-login with password OR with saved token (passwordless)
    final canAutoLogin = autoLogin && savedMitgliedernummer != null && (savedPassword != null || savedToken != null);

    setState(() {
      _rememberMe = rememberMe;
      _autoLogin = autoLogin;
      _startWithWindows = startWithWindows;
      if (rememberMe && savedMitgliedernummer != null) {
        _mitgliedernummerController.text = savedMitgliedernummer;
        if (savedPassword != null) {
          _loginPasswordController.text = savedPassword;
        }
      }
      _isInitializing = false;
    });

    // Always show startup dialogs (update check, diagnostic consent)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartupDialogs(autoLoginAfter: canAutoLogin);
    });
  }

  Future<void> _showStartupDialogs({bool autoLoginAfter = false}) async {
    if (!mounted) return;

    // Small delay to ensure UI is stable
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // 1. Check for diagnostic consent
    await checkAndShowDiagnosticConsent(context);

    // Set diagnostic screen
    DiagnosticService().setScreen('login');

    // 2. Auto-login if enabled (after consent dialog)
    if (autoLoginAfter && mounted) {
      // If we have password, use normal login
      if (_loginPasswordController.text.isNotEmpty) {
        _login();
      } else {
        // Passwordless: use saved token to validate and get user data
        _autoLoginWithToken();
      }
    }
  }

  Future<void> _autoLoginWithToken() async {
    setState(() { _isLoading = true; });
    try {
      // Token is already loaded by ApiService from secure storage
      await _apiService.loadTokens();
      final result = await _apiService.getProfile(_mitgliedernummerController.text.trim());
      if (result['success'] == true && mounted) {
        final user = result['user'] ?? result['data'];
        if (user != null) {
          _log.info('Auto-login with token success!', tag: 'AUTH');
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (context) => DashboardScreen(
              userName: user['name'] ?? '',
              currentMitgliedernummer: user['mitgliedernummer'] ?? _mitgliedernummerController.text.trim(),
              currentEmail: user['email'] ?? '',
              currentRole: user['role'] ?? 'vorsitzer',
            ),
          ));
          return;
        }
      }
    } catch (e) {
      _log.error('Auto-login with token failed: $e', tag: 'AUTH');
    }
    if (mounted) setState(() { _isLoading = false; });
  }

  /// Best-effort secure write. On failure (e.g. -34018 on unsigned macOS) we silently
  /// drop the value — better than persisting secrets to plaintext disk storage.
  /// Side effect: "remember me" / auto-login becomes a no-op on such platforms.
  Future<void> _safeWrite(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      _log.warning('Secure write unavailable for $key (skipped, no plaintext fallback): $e', tag: 'AUTH');
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await _safeWrite('mitgliedernummer', _mitgliedernummerController.text.trim());
      await _safeWrite('password', _loginPasswordController.text);
      await prefs.setBool('remember_me', true);
      await prefs.setBool('auto_login', _autoLogin);
    } else {
      await _safeDelete('mitgliedernummer');
      await _safeDelete('password');
      await prefs.setBool('remember_me', false);
      await prefs.setBool('auto_login', false);
    }
  }

  @override
  void dispose() {
    _mitgliedernummerController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordlessLogin(Map<String, dynamic> loginData) async {
    final user = loginData['user'] as Map<String, dynamic>?;
    if (user == null) return;

    final role = user['role'] ?? 'vorsitzer';
    _log.info('Passwordless login success! Role=$role', tag: 'AUTH');

    // Save tokens for auto-login on restart
    final token = loginData['token'] as String?;
    final refreshToken = loginData['refresh_token'] as String?;
    if (token != null && refreshToken != null) {
      await _apiService.saveTokens(token, refreshToken);
    }

    // Save mitgliedernummer for auto-login
    final mitgliedernummer = user['mitgliedernummer'] ?? '';
    await _safeWrite('mitgliedernummer', mitgliedernummer);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', true);
    await prefs.setBool('auto_login', true);

    // Save approval token for passwordless re-login
    final approvalToken = loginData['approval_token'] as String?;
    if (approvalToken != null) {
      await _safeWrite('approval_token', approvalToken);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            userName: user['name'] ?? '',
            currentMitgliedernummer: mitgliedernummer,
            currentEmail: user['email'] ?? '',
            currentRole: role,
          ),
        ),
      );
    }
  }

  Future<void> _login() async {
    _log.info('Login: Attempting login', tag: 'AUTH');

    // ✅ SECURITY: Check device integrity (root/jailbreak detection)
    final integrityIssue = await DeviceIntegrityService().checkDeviceIntegrity();
    if (integrityIssue != null) {
      _log.warning('Login: BLOCKED - device compromised: $integrityIssue', tag: 'SECURITY');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loginErrorMessage = null;
        });
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.security, color: Colors.red, size: 48),
            title: const Text('Sicherheitswarnung'),
            content: Text(
              'Ihr Gerät wurde als unsicher erkannt:\n\n'
              '• $integrityIssue\n\n'
              'Aus Sicherheitsgründen kann die Anwendung auf modifizierten Geräten '
              'nicht verwendet werden.\n\n'
              'Bitte verwenden Sie ein nicht modifiziertes Gerät.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Verstanden'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // ✅ SECURITY FIX: Check rate limiting
    if (_failedLoginAttempts >= _maxFailedAttempts && _lastFailedAttempt != null) {
      final timeSinceLastFailed = DateTime.now().difference(_lastFailedAttempt!);
      if (timeSinceLastFailed < _cooldownDuration) {
        final remainingMinutes = (_cooldownDuration.inSeconds - timeSinceLastFailed.inSeconds) ~/ 60;
        final remainingSeconds = (_cooldownDuration.inSeconds - timeSinceLastFailed.inSeconds) % 60;
        setState(() {
          _loginErrorMessage = 'Zu viele Anmeldeversuche. Bitte warten Sie $remainingMinutes:${remainingSeconds.toString().padLeft(2, '0')} Minuten.';
        });
        return;
      } else {
        // Reset after cooldown
        _failedLoginAttempts = 0;
        _lastFailedAttempt = null;
      }
    }

    setState(() {
      _isLoading = true;
      _loginErrorMessage = null;
    });

    // Progressive delay based on failed attempts (exponential backoff)
    if (_failedLoginAttempts > 0) {
      final delaySeconds = (1 << _failedLoginAttempts).clamp(1, 8); // 2^n, max 8 seconds
      await Future.delayed(Duration(seconds: delaySeconds));
    }

    try {
      final result = await _apiService.login(
        _mitgliedernummerController.text.trim(),
        _loginPasswordController.text,
      );
      _log.debug('Login: API response success=${result['success']}', tag: 'AUTH');

      if (result['success'] == true) {
        // ✅ Reset failed attempts on successful login
        _failedLoginAttempts = 0;
        _lastFailedAttempt = null;
        final user = result['user'];
        final role = user['role'] ?? 'vorsitzer';
        _log.info('Login: Success! Role=$role', tag: 'AUTH');

        await _saveCredentials();

        if (mounted) {
          // All users go to admin dashboard (Vorsitzer app)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(
                userName: user['name'],
                currentMitgliedernummer: user['mitgliedernummer'],
                currentEmail: user['email'] ?? '',
                currentRole: role,
              ),
            ),
          );
        }
      } else {
        _log.warning('Login: Failed - ${result['message']}', tag: 'AUTH');

        // ✅ SECURITY FIX: Increment failed attempts counter
        _failedLoginAttempts++;
        _lastFailedAttempt = DateTime.now();

        // Check for "Maximum devices" error with active sessions list
        final errorCode = result['error_code'];
        if (errorCode == 'MAX_DEVICES' && result['active_sessions'] != null) {
          // Don't count MAX_DEVICES as failed login attempt
          _failedLoginAttempts--;
          // Show device selection dialog
          if (mounted) {
            _showDeviceSelectionDialog(
              result['active_sessions'] as List,
              _mitgliedernummerController.text.trim(),
              _loginPasswordController.text,
            );
          }
        } else {
          setState(() {
            _loginErrorMessage = result['message'] ?? 'Anmeldung fehlgeschlagen';
            if (_failedLoginAttempts >= _maxFailedAttempts) {
              _loginErrorMessage = '${result['message'] ?? 'Anmeldung fehlgeschlagen'}\n\n⚠️ Account temporär gesperrt für 5 Minuten nach zu vielen Versuchen.';
            }
          });
        }
      }
    } catch (e) {
      _log.error('Login: Exception - $e', tag: 'AUTH');
      setState(() {
        _loginErrorMessage = 'Verbindungsfehler: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showDeviceSelectionDialog(List activeSessions, String mitgliedernummer, String password) async {
    final selectedSession = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.devices, color: Colors.orange),
            SizedBox(width: 8),
            Text('Zu viele Geräte'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sie sind bereits auf 3 Geräten angemeldet.\n'
                'Wählen Sie ein Gerät zum Abmelden:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...activeSessions.map((session) {
                final deviceInfo = session['device_info'] != null
                    ? jsonDecode(session['device_info'])
                    : null;
                final deviceName = deviceInfo?['device_name'] ?? 'Unbekanntes Gerät';
                final platform = deviceInfo?['platform'] ?? 'Unbekannt';
                final ipAddress = session['ip_address'] ?? 'Unbekannt';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.computer, color: Colors.blue),
                    title: Text(deviceName),
                    subtitle: Text('$platform • IP: $ipAddress'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () => Navigator.pop(ctx, session),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );

    if (selectedSession != null) {
      // User selected a device to logout
      setState(() {
        _isLoading = true;
        _loginErrorMessage = null;
      });

      try {
        final logoutResult = await _apiService.logoutDevice(
          mitgliedernummer,
          password,
          selectedSession['id'],
        );

        if (logoutResult['success'] == true) {
          // Device logged out, retry login automatically
          _log.info('Device logged out successfully, retrying login...', tag: 'AUTH');
          await _login(); // Retry login
        } else {
          setState(() {
            _loginErrorMessage = logoutResult['message'] ?? 'Fehler beim Abmelden';
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _loginErrorMessage = 'Fehler: $e';
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isInitializing || (_autoLogin && _isLoading)) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a2e),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.groups,
                size: 64,
                color: Color(0xFF4a90d9),
              ),
              const SizedBox(height: 24),
              const Text(
                'ICD360S e.V',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Automatische Anmeldung...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                color: Color(0xFF4a90d9),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo + Title
                const Icon(Icons.groups, size: 56, color: Color(0xFF4a90d9)),
                const SizedBox(height: 12),
                const Text('ICD360S e.V', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Vorsitzer Portal', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                const SizedBox(height: 32),
                // Login Card
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login, color: Color(0xFF4a90d9), size: 28),
                            SizedBox(width: 12),
                            Text('Anmelden', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4a90d9))),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 490,
                        child: LoginTab(
                          apiService: _apiService,
                          mitgliedernummerController: _mitgliedernummerController,
                          passwordController: _loginPasswordController,
                          rememberMe: _rememberMe,
                          autoLogin: _autoLogin,
                          startWithWindows: _startWithWindows,
                          isLoading: _isLoading,
                          errorMessage: _loginErrorMessage,
                          onRememberMeChanged: (value) {
                            setState(() {
                              _rememberMe = value;
                              if (!_rememberMe) _autoLogin = false;
                            });
                          },
                          onAutoLoginChanged: (value) => setState(() => _autoLogin = value),
                          onStartWithWindowsChanged: (value) => setState(() => _startWithWindows = value),
                          onLogin: _login,
                          onMaxDevices: _showDeviceSelectionDialog,
                          onPasswordlessLogin: _handlePasswordlessLogin,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Footer
                const LegalFooter(darkMode: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
