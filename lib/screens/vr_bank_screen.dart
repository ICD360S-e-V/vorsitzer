import 'package:flutter/material.dart';

class VrBankScreen extends StatelessWidget {
  final VoidCallback onBack;

  const VrBankScreen({super.key, required this.onBack});

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
              Icon(Icons.account_balance, size: 32, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              const Text(
                'VR Bank',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  'Vereinskonto',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content - 2x2 grid
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
      color: Colors.blue,
      child: Column(
        children: [
          _infoRow(Icons.business, 'Kontoinhaber', 'ICD360S e.V.'),
          _infoRow(Icons.tag, 'IBAN', 'DE89 3704 0044 0532 0130 00'),
          _infoRow(Icons.code, 'BIC / SWIFT', 'COBADEFFXXX'),
          _infoRow(Icons.numbers, 'Kontonummer', '0532013000'),
          _infoRow(Icons.pin, 'Bankleitzahl (BLZ)', '370 400 44'),
          const Divider(height: 24),
          _infoRow(Icons.category, 'Kontotyp', 'Vereinskonto (Geschäftsgirokonto)'),
          _infoRow(Icons.style, 'Kontomodell', 'VR-Giro Vereine'),
          _infoRow(Icons.location_on, 'Filiale', 'VR Bank Memmingen eG'),
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
      color: Colors.indigo,
      child: Column(
        children: [
          // Girocard
          _buildCardItem(
            icon: Icons.credit_card,
            name: 'Girocard (Debitkarte)',
            netzwerk: 'V PAY',
            color: Colors.blue,
            details: [
              _cardDetail('Karteninhaber', 'ICD360S e.V.'),
              _cardDetail('Kartennummer', '**** **** **** 1234'),
              _cardDetail('Gültig bis', '12/2028'),
              _cardDetail('Status', 'Aktiv'),
              _cardDetail('Kontaktlos', 'Ja (NFC)'),
              _cardDetail('Tageslimit', '1.000,00 EUR'),
            ],
            features: [
              'Bargeldabhebung an 14.700 Geldautomaten',
              'Bezahlung im Handel (kontaktlos / PIN)',
              'Kontoauszüge am Automaten drucken',
            ],
          ),
          const SizedBox(height: 16),
          // Mastercard Business
          _buildCardItem(
            icon: Icons.credit_score,
            name: 'Mastercard Business',
            netzwerk: 'Kreditkarte',
            color: Colors.orange,
            details: [
              _cardDetail('Karteninhaber', 'ICD360S e.V.'),
              _cardDetail('Kartennummer', '**** **** **** 5678'),
              _cardDetail('Gültig bis', '06/2027'),
              _cardDetail('Status', 'Aktiv'),
              _cardDetail('Kreditrahmen', '5.000,00 EUR'),
            ],
            features: [
              'Online-Zahlungen weltweit',
              'Auslandseinsatz (Reisekosten)',
              'Abrechnung über Geschäftskonto',
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
      color: Colors.teal,
      child: Column(
        children: [
          _buildFeatureItem(
            icon: Icons.send,
            title: 'Überweisungen',
            subtitle: 'SEPA-Einzelüberweisung, Sammelüberweisung',
            color: Colors.teal,
          ),
          _buildFeatureItem(
            icon: Icons.bolt,
            title: 'Echtzeitüberweisung',
            subtitle: 'Instant Payment — Geld in Sekunden beim Empfänger',
            color: Colors.amber.shade700,
          ),
          _buildFeatureItem(
            icon: Icons.repeat,
            title: 'Daueraufträge',
            subtitle: 'Regelmäßige Zahlungen (Miete, Versicherung, etc.)',
            color: Colors.blue,
          ),
          _buildFeatureItem(
            icon: Icons.receipt_long,
            title: 'SEPA-Lastschriften',
            subtitle: 'Mitgliedsbeiträge automatisch einziehen (Basis-Lastschrift)',
            color: Colors.purple,
          ),
          _buildFeatureItem(
            icon: Icons.upload_file,
            title: 'SEPA-Dateiverarbeitung',
            subtitle: 'Lohn-/Gehaltszahlungen per EBICS oder FinTS',
            color: Colors.indigo,
          ),
          _buildFeatureItem(
            icon: Icons.visibility,
            title: '4-Augen-Prinzip',
            subtitle: 'Auftragsfreigabe durch zweite Person (Firmenkunden)',
            color: Colors.red.shade400,
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
      color: Colors.green,
      child: Column(
        children: [
          // Konditionen
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
          _konditionRow('Kontoführung/Monat', '4,90 EUR'),
          _konditionRow('Girocard (erste)', 'Kostenlos'),
          _konditionRow('Girocard (weitere)', '6,00 EUR/Jahr'),
          _konditionRow('Mastercard Business', '30,00 EUR/Jahr'),
          _konditionRow('Buchungsposten', '0,10 - 0,20 EUR'),
          _konditionRow('Kontoauszug (Online)', 'Kostenlos'),
          _konditionRow('Kontoauszug (Papier)', '1,50 EUR/Stück'),
          const Divider(height: 24),
          // Online-Banking
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
            title: 'VR Banking App',
            subtitle: 'Kontoverwaltung mobil — Überweisungen, Umsätze, Push-TAN',
            color: Colors.blue,
          ),
          _buildFeatureItem(
            icon: Icons.computer,
            title: 'Online-Banking (Browser)',
            subtitle: 'Alle Funktionen im Webbrowser verfügbar',
            color: Colors.green,
          ),
          _buildFeatureItem(
            icon: Icons.security,
            title: 'TAN-Verfahren',
            subtitle: 'VR SecureGo plus (Push-TAN), SmartTAN',
            color: Colors.orange,
          ),
          _buildFeatureItem(
            icon: Icons.shield,
            title: 'Überweisungslimit',
            subtitle: 'Tägliches Online-Limit individuell einstellbar',
            color: Colors.red.shade400,
          ),
          const Divider(height: 24),
          // Service-Netz
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Service-Netz',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          _infoRow(Icons.atm, 'Geldautomaten', 'ca. 14.700 in Deutschland'),
          _infoRow(Icons.print, 'Kontoauszugsdrucker', 'ca. 14.000 bundesweit'),
          _infoRow(Icons.support_agent, 'Kundenservice', 'Telefon, Filiale, Online'),
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(netzwerk, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
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
