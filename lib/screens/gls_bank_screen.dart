import 'package:flutter/material.dart';

class GlsBankScreen extends StatelessWidget {
  final VoidCallback onBack;

  const GlsBankScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
                tooltip: 'Zurück zu Banken',
              ),
              const SizedBox(width: 8),
              Icon(Icons.eco, size: 32, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Text(
                'GLS Bank',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.eco, size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Nachhaltige Bank',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content - 2x2 grid + Nachhaltigkeit row
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Row 1: Kontoinformationen + Karten
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildKontoinformationenCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildKartenCard()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Row 2: Zahlungsverkehr + Konditionen
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildZahlungsverkehrCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildKonditionenCard()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Row 3: Nachhaltigkeit (full width)
                  _buildNachhaltigkeitCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CARD 1: KONTOINFORMATIONEN ====================

  Widget _buildKontoinformationenCard() {
    return _buildSectionCard(
      icon: Icons.account_balance_wallet,
      title: 'Kontoinformationen',
      color: Colors.green,
      child: Column(
        children: [
          _infoRow(Icons.business, 'Kontoinhaber', 'ICD360S e.V.'),
          _infoRow(Icons.tag, 'IBAN', 'DE12 4306 0967 1234 5678 00'),
          _infoRow(Icons.code, 'BIC / SWIFT', 'GENODEM1GLS'),
          _infoRow(Icons.numbers, 'Kontonummer', '1234567800'),
          _infoRow(Icons.pin, 'Bankleitzahl (BLZ)', '430 609 67'),
          const Divider(height: 24),
          _infoRow(Icons.category, 'Kontotyp', 'Konto für Gemeinnützige'),
          _infoRow(Icons.style, 'Kontomodell', 'GLS Vereinskonto'),
          _infoRow(Icons.location_on, 'Hauptsitz', 'GLS Bank, Bochum'),
          _infoRow(Icons.calendar_today, 'Eröffnet am', '—'),
          _infoRow(Icons.verified_user, 'Kontostand', '—'),
        ],
      ),
    );
  }

  // ==================== CARD 2: KARTEN ====================

  Widget _buildKartenCard() {
    return _buildSectionCard(
      icon: Icons.credit_card,
      title: 'Karten',
      color: Colors.teal,
      child: Column(
        children: [
          // GLS BankCard
          _buildCardItem(
            icon: Icons.credit_card,
            name: 'GLS BankCard (Girocard)',
            netzwerk: 'Debit Mastercard',
            color: Colors.green,
            material: 'Kartenkörper: 100% aus Holz',
            details: [
              _cardDetail('Karteninhaber', 'ICD360S e.V.'),
              _cardDetail('Kartennummer', '**** **** **** 9012'),
              _cardDetail('Gültig bis', '09/2028'),
              _cardDetail('Status', 'Aktiv'),
              _cardDetail('Kontaktlos', 'Ja (NFC)'),
            ],
            features: [
              'Kostenlos Bargeld an 15.000 Automaten (ServiceNetz)',
              'Kontaktlos bezahlen im Handel',
              'Weltweit einsetzbar (Debit Mastercard)',
            ],
          ),
          const SizedBox(height: 16),
          // GLS BusinessCard
          _buildCardItem(
            icon: Icons.credit_score,
            name: 'GLS BusinessCard',
            netzwerk: 'Kreditkarte (Mastercard)',
            color: Colors.teal,
            material: '75% bio-basierte Rohstoffe',
            details: [
              _cardDetail('Karteninhaber', 'ICD360S e.V.'),
              _cardDetail('Kartennummer', '**** **** **** 3456'),
              _cardDetail('Gültig bis', '03/2027'),
              _cardDetail('Status', 'Aktiv'),
              _cardDetail('Kreditrahmen', '5.000,00 EUR'),
            ],
            features: [
              'Online-Zahlungen weltweit',
              'Dienstreisen & Geschäftsausgaben',
              'Abrechnung über GLS Geschäftskonto',
            ],
          ),
        ],
      ),
    );
  }

  // ==================== CARD 3: ZAHLUNGSVERKEHR ====================

  Widget _buildZahlungsverkehrCard() {
    return _buildSectionCard(
      icon: Icons.swap_horiz,
      title: 'Zahlungsverkehr',
      color: Colors.blue,
      child: Column(
        children: [
          _buildFeatureItem(
            icon: Icons.send,
            title: 'Überweisungen',
            subtitle: 'SEPA-Einzelüberweisung, Sammelüberweisung',
            color: Colors.blue,
          ),
          _buildFeatureItem(
            icon: Icons.bolt,
            title: 'Echtzeitüberweisung',
            subtitle: 'Instant Payment — sofortige Gutschrift',
            color: Colors.amber.shade700,
          ),
          _buildFeatureItem(
            icon: Icons.repeat,
            title: 'Daueraufträge',
            subtitle: 'Regelmäßige Zahlungen automatisch ausführen',
            color: Colors.teal,
          ),
          _buildFeatureItem(
            icon: Icons.receipt_long,
            title: 'SEPA-Lastschriften',
            subtitle: 'Mitgliedsbeiträge automatisch einziehen',
            color: Colors.purple,
          ),
          _buildFeatureItem(
            icon: Icons.public,
            title: 'Internationale Überweisungen',
            subtitle: 'Zahlungen außerhalb des SEPA-Raums',
            color: Colors.indigo,
          ),
          _buildFeatureItem(
            icon: Icons.integration_instructions,
            title: 'DATEV-Anbindung',
            subtitle: 'Direkte Verbindung zum Steuerberater',
            color: Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  // ==================== CARD 4: KONDITIONEN ====================

  Widget _buildKonditionenCard() {
    return _buildSectionCard(
      icon: Icons.euro,
      title: 'Konditionen & Online-Banking',
      color: Colors.orange,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Kontogebühren',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          _konditionRow('GLS Beitrag (jährlich)', '60,00 EUR'),
          _konditionRow('GLS Mitgliedschaft', '5,00 EUR/Monat'),
          _konditionRow('Kontoführung/Monat', '8,80 EUR'),
          _konditionRow('GLS BankCard (erste)', 'Kostenlos'),
          _konditionRow('GLS BankCard (weitere)', '15,00 EUR/Jahr'),
          _konditionRow('GLS BusinessCard', '30,00 EUR/Jahr'),
          _konditionRow('Buchungsposten', '0,08 EUR'),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Online-Banking',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          _buildFeatureItem(
            icon: Icons.phone_android,
            title: 'GLS Banking App',
            subtitle: 'Kontoverwaltung mobil — Push-TAN, Umsätze',
            color: Colors.green,
          ),
          _buildFeatureItem(
            icon: Icons.computer,
            title: 'Online-Banking (Browser)',
            subtitle: 'Multi-Bank-fähig — alle Konten in einer Übersicht',
            color: Colors.blue,
          ),
          _buildFeatureItem(
            icon: Icons.security,
            title: 'TAN-Verfahren',
            subtitle: 'SecureGo plus, SmartTAN (chipTAN)',
            color: Colors.orange,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Einlagensicherung',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          _infoRow(Icons.shield, 'Gesetzlich', 'bis 100.000 EUR (EU)'),
          _infoRow(Icons.security, 'Genossenschaftlich', 'BVR Sicherungssystem (unbegrenzt)'),
        ],
      ),
    );
  }

  // ==================== CARD 5: NACHHALTIGKEIT ====================

  Widget _buildNachhaltigkeitCard() {
    return _buildSectionCard(
      icon: Icons.eco,
      title: 'Nachhaltigkeit — Wohin fließt Ihr Geld?',
      color: Colors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Die GLS Bank finanziert ausschließlich sozial-ökologische Unternehmen und Projekte. '
            'Als Kontoinhaber können Sie mitentscheiden, in welchem Bereich Ihr Geld wirkt:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _nachhaltigkeitItem(Icons.wind_power, 'Erneuerbare Energien', 'Windkraft, Solar, Biogas', Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _nachhaltigkeitItem(Icons.home, 'Wohnen', 'Soziales Wohnen, Baugruppen', Colors.brown)),
              const SizedBox(width: 12),
              Expanded(child: _nachhaltigkeitItem(Icons.health_and_safety, 'Soziales & Gesundheit', 'Pflege, Inklusion, Therapie', Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _nachhaltigkeitItem(Icons.store, 'Nachhaltige Wirtschaft', 'Bio, Naturkosmetik, Textilien', Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _nachhaltigkeitItem(Icons.school, 'Bildung & Kultur', 'Schulen, Kunst, Medien', Colors.purple)),
              const SizedBox(width: 12),
              Expanded(child: _nachhaltigkeitItem(Icons.restaurant, 'Ernährung', 'Bio-Landwirtschaft, Hofläden', Colors.orange)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.block, size: 18, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kein Geld fließt in: Kinderarbeit, Atomenergie, Rüstungsindustrie, Agrochemie',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nachhaltigkeitItem(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem({
    required IconData icon,
    required String name,
    required String netzwerk,
    required Color color,
    required String material,
    required List<Widget> details,
    required List<String> features,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(netzwerk, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Material badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco, size: 12, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(material, style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Card details
          ...details,
          if (features.isNotEmpty) ...[
            const Divider(height: 20),
            Text('Funktionen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _cardDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _konditionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
