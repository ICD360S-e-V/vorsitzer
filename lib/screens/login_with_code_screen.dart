import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/device_key_service.dart';
import '../services/logger_service.dart';
import '../services/update_service.dart';
import 'dashboard_screen.dart';

/// Two-step activation login: Mitgliedernummer → 16-char one-time code
/// (4 boxes × 4 chars each). Used to enroll this device for the first time.
/// After success, device_key + JWT are persisted → app auto-logs in from then on.
class LoginWithCodeScreen extends StatefulWidget {
  const LoginWithCodeScreen({super.key});

  @override
  State<LoginWithCodeScreen> createState() => _LoginWithCodeScreenState();
}

class _LoginWithCodeScreenState extends State<LoginWithCodeScreen> {
  static final _log = LoggerService();
  static const _allowedChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final _apiService = ApiService();
  final _deviceKeyService = DeviceKeyService();

  final _mitgliedernummerC = TextEditingController();
  final List<TextEditingController> _blockC = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _blockFocus = List.generate(4, (_) => FocusNode());

  int _step = 0; // 0 = mitgliedernummer, 1 = code
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _mitgliedernummerC.dispose();
    for (final c in _blockC) {
      c.dispose();
    }
    for (final f in _blockFocus) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: _step == 0 ? _buildMitgliedStep() : _buildCodeStep(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // STEP 1: Mitgliedernummer
  // ═══════════════════════════════════════════════════════
  Widget _buildMitgliedStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.vpn_key, size: 64, color: Colors.indigo.shade400),
        const SizedBox(height: 16),
        Text(
          'Gerät aktivieren',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        const SizedBox(height: 6),
        Text(
          'Schritt 1 von 2 — Mitgliedernummer eingeben',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _mitgliedernummerC,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(20),
            TextInputFormatter.withFunction((_, n) => TextEditingValue(
                  text: n.text.toUpperCase(),
                  selection: n.selection,
                )),
          ],
          decoration: InputDecoration(
            labelText: 'Mitgliedernummer',
            hintText: 'z. B. V27655',
            prefixIcon: const Icon(Icons.badge),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: const TextStyle(fontSize: 16, letterSpacing: 2),
          onSubmitted: (_) => _goToCodeStep(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Weiter'),
            onPressed: _loading ? null : _goToCodeStep,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.indigo.shade700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Diese App ist ausschließlich für den Vorstand. Noch keinen Code? '
          'Bitte beim ersten Vorsitzer den Aktivierungscode anfordern.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _goToCodeStep() {
    final mg = _mitgliedernummerC.text.trim();
    if (mg.length < 4) {
      setState(() => _error = 'Bitte eine gültige Mitgliedernummer eingeben');
      return;
    }
    setState(() {
      _step = 1;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _blockFocus[0].requestFocus());
  }

  // ═══════════════════════════════════════════════════════
  // STEP 2: 4 × 4-char code boxes
  // ═══════════════════════════════════════════════════════
  Widget _buildCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pin, size: 64, color: Colors.indigo.shade400),
        const SizedBox(height: 16),
        Text(
          'Aktivierungscode',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        const SizedBox(height: 6),
        Text(
          'Schritt 2 von 2 — 16-stelligen Code eingeben',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Mitgliedernummer: ${_mitgliedernummerC.text.trim()}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 4; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('–', style: TextStyle(fontSize: 22, color: Colors.grey.shade400)),
                ),
              _codeBox(i),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Tipp: Sie können den vollständigen Code (mit oder ohne Bindestriche) in ein beliebiges Feld einfügen.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_error!),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle),
            label: Text(_loading ? 'Aktiviere…' : 'Gerät aktivieren'),
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.green.shade700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Mitgliedernummer ändern', style: TextStyle(fontSize: 12)),
          onPressed: _loading
              ? null
              : () {
                  for (final c in _blockC) {
                    c.clear();
                  }
                  setState(() {
                    _step = 0;
                    _error = null;
                  });
                },
        ),
      ],
    );
  }

  Widget _codeBox(int i) {
    return SizedBox(
      width: 78,
      height: 58,
      child: TextField(
        controller: _blockC[i],
        focusNode: _blockFocus[i],
        maxLength: 4,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3, fontFamily: 'monospace'),
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.indigo.shade700, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[$_allowedChars]', caseSensitive: false)),
          TextInputFormatter.withFunction((_, n) => TextEditingValue(
                text: n.text.toUpperCase(),
                selection: n.selection,
              )),
        ],
        onChanged: (v) {
          // Paste full code in any box → distribute across all 4
          if (v.length > 4) {
            _distributePaste(v);
            return;
          }
          if (v.length == 4 && i < 3) {
            _blockFocus[i + 1].requestFocus();
          }
          if (v.isEmpty && i > 0) {
            // backspace handling below via RawKeyboardListener omitted for brevity;
            // most users type forward.
          }
        },
        onSubmitted: (_) {
          if (i < 3) {
            _blockFocus[i + 1].requestFocus();
          } else {
            _submit();
          }
        },
      ),
    );
  }

  void _distributePaste(String raw) {
    // Strip non-allowed, uppercase, take first 16
    final clean = raw.toUpperCase().replaceAll(RegExp('[^$_allowedChars]'), '');
    if (clean.length < 4) return;
    final chunks = [
      clean.substring(0, clean.length >= 4 ? 4 : clean.length),
      clean.length >= 8 ? clean.substring(4, 8) : (clean.length > 4 ? clean.substring(4) : ''),
      clean.length >= 12 ? clean.substring(8, 12) : (clean.length > 8 ? clean.substring(8) : ''),
      clean.length >= 16 ? clean.substring(12, 16) : (clean.length > 12 ? clean.substring(12) : ''),
    ];
    for (int i = 0; i < 4; i++) {
      _blockC[i].text = chunks[i];
    }
    // Focus the last non-empty block or submit if complete
    if (clean.length >= 16) {
      _blockFocus[3].unfocus();
      _submit();
    } else {
      final lastIdx = ((clean.length) ~/ 4).clamp(0, 3);
      _blockFocus[lastIdx].requestFocus();
    }
  }

  // ═══════════════════════════════════════════════════════
  // SUBMIT
  // ═══════════════════════════════════════════════════════
  Future<void> _submit() async {
    final code = _blockC.map((c) => c.text.trim()).join('');
    if (code.length != 16) {
      setState(() => _error = 'Der Code muss genau 16 Zeichen enthalten');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Read existing device_id (if available) without triggering full device registration.
      // DeviceKeyService._readFromStorage handles macOS SharedPreferences fallback.
      String deviceId = _deviceKeyService.deviceId
          ?? '${_platformString().toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}';

      final deviceInfo = <String, dynamic>{
        'name': _deviceName(),
        'platform': _platformString(),
        'type': _deviceType(),
        'app_version': UpdateService.currentVersion,
      };

      final result = await _apiService.activateDeviceCode(
        mitgliedernummer: _mitgliedernummerC.text.trim(),
        code: code,
        deviceId: deviceId,
        deviceInfo: deviceInfo,
      );

      if (result['success'] != true) {
        final msg = (result['message'] ?? result['data']?['message'] ?? 'Aktivierung fehlgeschlagen').toString();
        setState(() {
          _error = msg;
          _loading = false;
        });
        return;
      }

      final data = (result['data'] as Map?) ?? {};
      final token = data['token']?.toString();
      final refreshToken = data['refresh_token']?.toString();
      final deviceKey = data['device_key']?.toString();
      final user = (data['user'] as Map?) ?? {};

      if (token == null || refreshToken == null || deviceKey == null) {
        setState(() {
          _error = 'Ungültige Server-Antwort (fehlende Tokens)';
          _loading = false;
        });
        return;
      }

      // Persist device_key via DeviceKeyService (uses SharedPreferences fallback on macOS)
      await _deviceKeyService.setActivatedCredentials(deviceKey, deviceId);

      // Save JWT tokens (ApiService handles fallback internally)
      await _apiService.saveTokens(token, refreshToken);

      // Save mitgliedernummer + auto-login prefs (SharedPreferences = always works)
      final mgnum = (user['mitgliedernummer'] ?? '').toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mitgliedernummer', mgnum);
      await prefs.setBool('remember_me', true);
      await prefs.setBool('auto_login', true);

      _log.info('Device activated successfully for $mgnum', tag: 'AUTH');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            userName: (user['name'] ?? '').toString(),
            currentMitgliedernummer: mgnum,
            currentEmail: (user['email'] ?? '').toString(),
            currentRole: (user['role'] ?? 'vorsitzer').toString(),
          ),
        ),
      );
    } catch (e) {
      _log.error('Activation error: $e', tag: 'AUTH');
      setState(() {
        _error = 'Netzwerkfehler: $e';
        _loading = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════
  Widget _errorBanner(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 12, color: Colors.red.shade900))),
      ]),
    );
  }

  String _platformString() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  String _deviceType() {
    if (Platform.isAndroid || Platform.isIOS) return 'phone';
    return 'desktop';
  }

  String _deviceName() {
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'PC';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Gerät';
  }
}
