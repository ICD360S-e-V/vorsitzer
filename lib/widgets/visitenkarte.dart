import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';

class Visitenkarte extends StatefulWidget {
  final String mitgliedernummer;
  final ApiService apiService;

  const Visitenkarte({
    super.key,
    required this.mitgliedernummer,
    required this.apiService,
  });

  @override
  State<Visitenkarte> createState() => _VisitenkarteState();
}

class _VisitenkarteState extends State<Visitenkarte> {
  bool _showFront = true;
  bool _isLoading = true;

  // Profile data from database
  String _userName = '';
  String _email = '';
  String _role = '';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final result = await widget.apiService.getProfile(widget.mitgliedernummer);
      if (result['success'] == true && mounted) {
        setState(() {
          _userName = result['name'] ?? '';
          _email = result['email'] ?? '';
          _role = result['role'] ?? '';
          _phone = result['telefon_mobil'] ?? '—';
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggerService().error('Visitenkarte: Error loading profile: $e', tag: 'Visitenkarte');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getVorname() {
    final parts = _userName.split(' ');
    return parts.isNotEmpty ? parts[0] : _userName;
  }

  String _getNachname() {
    final parts = _userName.split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : '';
  }

  String _getRoleText() {
    switch (_role) {
      case 'vorsitzer':
        return 'Vorsitzer';
      case 'schatzmeister':
        return 'Schatzmeister';
      case 'kassierer':
        return 'Kassierer';
      case 'mitgliedergrunder':
        return 'Gründungsmitglied';
      default:
        return _role;
    }
  }

  void _flipCard() {
    setState(() {
      _showFront = !_showFront;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Business Card
          GestureDetector(
            onTap: _flipCard,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _showFront ? _buildVorderseite() : _buildRuckseite(),
            ),
          ),
          const SizedBox(height: 16),
          // Flip instruction
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                _showFront ? 'Tippen für Rückseite' : 'Tippen für Vorderseite',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVorderseite() {
    return Container(
      key: const ValueKey('front'),
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF4a90d9),
            const Color(0xFF357abd),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header - Vereinsname
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ICD360S e.V.',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(204),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),

            // Person Info
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vorname Nachname
                  Text(
                    _getVorname(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _getNachname(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Funktion
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withAlpha(102),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _getRoleText(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Email
                  Row(
                    children: [
                      const Icon(Icons.email, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Telefon
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        _phone,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

            // Footer - Benutzernummer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.mitgliedernummer,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(178),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  Icons.badge,
                  size: 24,
                  color: Colors.white.withAlpha(128),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuckseite() {
    return Container(
      key: const ValueKey('back'),
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4a90d9), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'Rückseite kommt bald...',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

}
