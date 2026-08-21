import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/eastern.dart';
import '../widgets/pfandung_grenze.dart';
import '../widgets/grundfreibetrag_einstellung.dart';
import '../widgets/jobcenter_einstellung.dart';
import '../widgets/kindergeld_einstellung.dart';
import '../widgets/deutschlandticket_einstellung.dart';
import '../widgets/sms_gateway_einstellung.dart';
import '../widgets/theme_umschalter.dart';
import '../utils/app_farben.dart';
import 'server_screen.dart';
import 'client_screen.dart';

class EinstellungenScreen extends StatefulWidget {
  final ApiService apiService;

  const EinstellungenScreen({super.key, required this.apiService});

  @override
  State<EinstellungenScreen> createState() => _EinstellungenScreenState();
}

class _EinstellungenScreenState extends State<EinstellungenScreen> {
  String _selectedSection = 'pfandung_grenze';

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Row(
      children: [
        // Left navigation
        Container(
          width: 220,
          color: Colors.grey.shade100,
          child: SingleChildScrollView(
            // Bei doppelter Systemschrift braucht der Inhalt mehr Höhe, als die
            // Fläche hat. Scrollbar statt unten abgeschnitten.
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blueGrey.shade700,
                child: const Row(
                  children: [
                    Icon(Icons.settings, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Flexible(child: Text('Einstellungen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildNavItem(
                icon: Icons.shield,
                title: 'Pfändungsgrenze',
                section: 'pfandung_grenze',
                subtitle: 'P-Konto Freibeträge',
              ),
              _buildNavItem(
                icon: Icons.account_balance,
                title: 'Finanzamt',
                section: 'grundfreibetrag',
                subtitle: 'Grundfreibetrag verwalten',
              ),
              _buildNavItem(
                icon: Icons.account_balance_wallet,
                title: 'Jobcenter',
                section: 'jobcenter',
                subtitle: 'Bürgergeld / Grundsicherung',
              ),
              _buildNavItem(
                icon: Icons.child_friendly,
                title: 'Kindergeld',
                section: 'kindergeld',
                subtitle: 'Familienkasse',
              ),
              _buildNavItem(
                icon: Icons.train,
                title: 'Deutschlandticket',
                section: 'deutschlandticket',
                subtitle: 'ÖPNV-Abo / Preisverlauf',
              ),
              _buildNavItem(
                icon: Icons.savings,
                title: 'Banken-Datenbank',
                section: 'banken_db',
                subtitle: 'Banken verwalten',
              ),
              _buildNavItem(
                icon: Icons.sms,
                title: 'SMS-Erinnerung',
                section: 'sms_gateway',
                subtitle: 'Termin-SMS über das Tablet',
              ),
              const Divider(height: 1),
              const SizedBox(height: 4),
              _buildNavItem(
                icon: Icons.dns,
                title: 'Server',
                section: 'server',
                subtitle: 'Server-Verwaltung',
              ),
              _buildNavItem(
                icon: Icons.devices,
                title: 'Client',
                section: 'client',
                subtitle: 'Client-Verwaltung',
              ),
              _buildNavItem(
                icon: Icons.contrast,
                title: 'Erscheinungsbild',
                section: 'erscheinungsbild',
                subtitle: 'Hell, Dunkel oder System',
              ),
            ],
          ),
          ),
        ),
        // Divider
        Container(width: 1, color: Colors.grey.shade300),
        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    required String section,
    String? subtitle,
  }) {
    final isSelected = _selectedSection == section;
    return InkWell(
      onTap: () => setState(() => _selectedSection = section),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: isSelected ? Colors.blueGrey.shade50 : null,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              color: isSelected ? Colors.blueGrey.shade700 : Colors.transparent,
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: isSelected ? Colors.blueGrey.shade700 : Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.blueGrey.shade800 : Colors.grey.shade700)),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case 'pfandung_grenze':
        return PfandungGrenzeWidget(apiService: widget.apiService);
      case 'grundfreibetrag':
        return GrundfreibetragEinstellungWidget(apiService: widget.apiService);
      case 'jobcenter':
        return JobcenterEinstellungWidget(apiService: widget.apiService);
      case 'kindergeld':
        return KindergeldEinstellungWidget(apiService: widget.apiService);
      case 'deutschlandticket':
        return DeutschlandticketEinstellungWidget(apiService: widget.apiService);
      case 'banken_db':
        return _buildBankenPlaceholder();
      case 'sms_gateway':
        return const SmsGatewayEinstellungWidget();
      case 'server':
        return const ServerScreen();
      case 'client':
        return const ClientScreen();
      case 'erscheinungsbild':
        return _buildErscheinungsbild();
      default:
        return const Center(child: Text('Abschnitt wählen'));
    }
  }

  Widget _buildErscheinungsbild() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Erscheinungsbild',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Gilt für die ganze Anwendung und bleibt über Neustarts hinweg '
            'erhalten. „System" folgt der Einstellung des Geräts.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 18),
          const ThemeUmschalterZeile(),
          const SizedBox(height: 18),
          // Dieselbe Wahl steckt auch im Knopf oben rechts in der Kopfleiste;
          // dort schaltet sie reihum weiter.
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: F.textLeise),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Schneller geht es über den Knopf in der Kopfleiste — '
                  'auf dem Telefon über das ⋮-Menü.',
                  style: TextStyle(fontSize: 12, color: F.textSchwach),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankenPlaceholder() {
    return const Center(
      child: Text('Banken-Datenbank – kommt bald', style: TextStyle(fontSize: 14, color: Colors.grey)),
    );
  }
}
