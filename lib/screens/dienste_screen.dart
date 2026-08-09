import 'package:flutter/material.dart';
import 'pdf_manager_screen.dart';
import 'db_mobilitat_unterstutzung_screen.dart';
import 'reiseplanung_screen.dart';
import 'jpg2pdf_screen.dart';
import '../widgets/eastern.dart';

class DiensteScreen extends StatefulWidget {
  const DiensteScreen({super.key});

  @override
  State<DiensteScreen> createState() => _DiensteScreenState();
}

class _DiensteScreenState extends State<DiensteScreen> {
  String? _subview;

  @override
  Widget build(BuildContext context) {
    if (_subview == 'pdf_manager') {
      return PdfManagerView(
        onBack: () => setState(() => _subview = null),
      );
    }
    if (_subview == 'db_mobilitat') {
      return DbMobilitaetUnterstuetzungScreen(
        onBack: () => setState(() => _subview = null),
      );
    }
    if (_subview == 'reiseplanung') {
      return ReiseplanungScreen(
        onBack: () => setState(() => _subview = null),
      );
    }
    if (_subview == 'jpg2pdf') {
      return Jpg2PdfScreen(
        onBack: () => setState(() => _subview = null),
      );
    }
    return _buildMainView();
  }

  Widget _buildMainView() {
    return SeasonalBackground(
      child: Padding(
      padding: const EdgeInsets.all(24),
      // ⚠️ KEIN SingleChildScrollView: diese Spalte hat ein Flex-Kind,
      // und ein Flex-Kind in unbegrenzter Höhe wirft. Der Überlauf bei
      // doppelter Schrift wird stattdessen vom `maxLines`/`Flexible`
      // im Inhalt aufgefangen.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.miscellaneous_services,
                  color: Colors.blue.shade700, size: 28),
              const SizedBox(width: 12),
              Text(
                'Dienste',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildServiceCard(
                icon: Icons.picture_as_pdf,
                title: 'PDF Manager',
                description:
                    'PDF bearbeiten, aufteilen, Text hinzufügen und unterschreiben',
                color: Colors.red.shade700,
                onTap: () => setState(() => _subview = 'pdf_manager'),
              ),
              _buildServiceCard(
                icon: Icons.train,
                title: 'DB Mobilitätsservice',
                description:
                    'Unterstützungsbedarf für Bahnreisen anmelden',
                color: Colors.blue.shade700,
                onTap: () => setState(() => _subview = 'db_mobilitat'),
              ),
              _buildServiceCard(
                icon: Icons.route,
                title: 'Reiseplanung',
                description:
                    'Verbindungen für Züge, Busse und Trams in ganz Deutschland',
                color: Colors.indigo.shade700,
                onTap: () => setState(() => _subview = 'reiseplanung'),
              ),
              _buildServiceCard(
                icon: Icons.image,
                title: 'Bilder zu PDF',
                description:
                    'JPG, PNG und andere Bilder in PDF konvertieren',
                color: Colors.orange.shade700,
                onTap: () => setState(() => _subview = 'jpg2pdf'),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 220,
      height: 160,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              // Bei doppelter Systemschrift braucht der Inhalt mehr Höhe, als die
              // Fläche hat. Scrollbar statt unten abgeschnitten.
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // ⚠️ Die Karte ist fest 160 dp hoch. Die Beschreibung lief
                // um 22 dp unten heraus — auf allen sechs Auflösungen, also
                // seit jeher und überall. `Flexible` mit `ellipsis` lässt
                // den Text kürzen, statt die Karte zu sprengen.
                // `maxLines: 2` stand schon da — es begrenzt aber nur den
                // Text, nicht die Zeile im Column. Erst `Flexible` gibt der
                // Karte die Erlaubnis, ihn zu stauchen.
                Flexible(
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
