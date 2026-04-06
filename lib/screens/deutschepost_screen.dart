import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'postcard.dart';
import 'sendungsverfolgung.dart';

class DeutschePostScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const DeutschePostScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<DeutschePostScreen> createState() => _DeutschePostScreenState();
}

class _DeutschePostScreenState extends State<DeutschePostScreen> {
  // Subview navigation: null = overview, 'sendung', 'filialfinder', 'postcard'
  String? _subview;

  // Counts from child widgets (for overview badges)
  int _shipmentCount = 0;
  int _postcardCount = 0;

  // API status from SendungsverfolgungView (for overview card)
  Color _apiStatusColor = Colors.orange;
  String _apiStatusText = 'Prüfe...';

  @override
  Widget build(BuildContext context) {
    // Subview routing
    if (_subview == 'sendung') {
      return _buildSubviewWrapper('Sendungsverfolgung', Icons.track_changes, Colors.blue.shade700,
        SendungsverfolgungView(
          apiService: widget.apiService,
          onCountChanged: (count) {
            if (_shipmentCount != count) setState(() => _shipmentCount = count);
          },
          onApiStatusChanged: (color, text) {
            if (_apiStatusColor != color || _apiStatusText != text) {
              setState(() {
                _apiStatusColor = color;
                _apiStatusText = text;
              });
            }
          },
        ),
      );
    } else if (_subview == 'postcard') {
      return _buildSubviewWrapper('POSTCARD Karten', Icons.credit_card, Colors.deepPurple.shade700,
        PostcardView(
          apiService: widget.apiService,
          onCountChanged: (count) {
            if (_postcardCount != count) setState(() => _postcardCount = count);
          },
        ),
      );
    }

    // Overview
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.local_shipping, size: 32, color: Colors.amber.shade700),
              const SizedBox(width: 12),
              const Text(
                'Deutsche Post',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('deutschepost.de'),
                onPressed: () => launchUrl(Uri.parse('https://www.deutschepost.de')),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Dienste & Preise
          _buildDiensteUebersicht(),
          const SizedBox(height: 24),

          // 3 clickable service cards
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildServiceCard(
                  icon: Icons.track_changes,
                  title: 'Sendungsverfolgung',
                  subtitle: 'DHL Pakete & Briefe verfolgen',
                  color: Colors.blue.shade700,
                  badge: _shipmentCount > 0 ? '$_shipmentCount' : null,
                  statusDot: _apiStatusColor,
                  statusText: _apiStatusText,
                  onTap: () => setState(() => _subview = 'sendung'),
                )),
                const SizedBox(width: 16),
                Expanded(child: _buildServiceCard(
                  icon: Icons.storefront,
                  title: 'Filialfinder',
                  subtitle: 'Filialen, Packstationen & Briefkästen',
                  color: Colors.red.shade700,
                  comingSoon: true,
                  onTap: null,
                )),
                const SizedBox(width: 16),
                Expanded(child: _buildServiceCard(
                  icon: Icons.credit_card,
                  title: 'POSTCARD',
                  subtitle: 'Geschäftskundenkarten verwalten',
                  color: Colors.deepPurple.shade700,
                  badge: _postcardCount > 0 ? '$_postcardCount' : null,
                  onTap: () => setState(() => _subview = 'postcard'),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubviewWrapper(String title, IconData icon, Color color, Widget content) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _subview = null),
                tooltip: 'Zurück zur Übersicht',
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 28, color: color),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('deutschepost.de'),
                onPressed: () => launchUrl(Uri.parse('https://www.deutschepost.de')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    String? badge,
    Color? statusDot,
    String? statusText,
    bool comingSoon = false,
    VoidCallback? onTap,
  }) {
    final effectiveColor = comingSoon ? Colors.grey : color;
    return Card(
      elevation: comingSoon ? 1 : 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: effectiveColor, size: 40),
              ),
              const SizedBox(height: 16),
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: comingSoon ? Colors.grey : null), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (comingSoon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Kommt bald', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                ),
              // Badge or status
              if (!comingSoon && badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(badge, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                ),
              if (!comingSoon && statusDot != null && statusText != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: statusDot),
                    ),
                    const SizedBox(width: 6),
                    Text(statusText, style: TextStyle(fontSize: 11, color: statusDot, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiensteUebersicht() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dienste & Preise (2026)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildDienstChip(Icons.email, 'Postkarte', '0,95 €', Colors.blue),
                _buildDienstChip(Icons.mail, 'Standardbrief', '0,95 €', Colors.blue),
                _buildDienstChip(Icons.mail_outline, 'Kompaktbrief', '1,10 €', Colors.blue),
                _buildDienstChip(Icons.markunread_mailbox, 'Großbrief', '1,80 €', Colors.orange),
                _buildDienstChip(Icons.inventory_2, 'Maxibrief', '2,90 €', Colors.orange),
                _buildDienstChip(Icons.local_shipping, 'DHL Paket', 'ab 4,99 €', Colors.amber.shade800),
                _buildDienstChip(Icons.flight, 'Int. Brief', 'ab 1,10 €', Colors.teal),
                _buildDienstChip(Icons.credit_card, 'POSTCARD', 'Geschäftskarte', Colors.deepPurple),
                _buildDienstChip(Icons.print, 'Online Frankierung', 'deutschepost.de', Colors.green),
                _buildDienstChip(Icons.storefront, 'Filialfinder', 'postfinder.de', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDienstChip(IconData icon, String label, String detail, Color color) {
    return InkWell(
      onTap: () {
        if (label == 'Online Frankierung') {
          launchUrl(Uri.parse('https://www.deutschepost.de/de/o/online-frankieren.html'));
        } else if (label == 'Filialfinder') {
          launchUrl(Uri.parse('https://www.deutschepost.de/de/s/standorte.html'));
        } else if (label == 'POSTCARD') {
          launchUrl(Uri.parse('https://www.deutschepost.de/de/p/postcard.html'));
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                Text(detail, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
