import 'package:flutter/material.dart';

/// Helper function to get icon for document type
IconData getDokumentIcon(String typ) {
  switch (typ) {
    case 'urkunde': return Icons.verified;
    case 'vollmacht': return Icons.assignment_ind;
    case 'satzung': return Icons.article;
    case 'protokoll': return Icons.description;
    case 'antrag': return Icons.request_page;
    default: return Icons.insert_drive_file;
  }
}

/// Helper function to get label for document type
String getDokumentTypLabel(String typ) {
  switch (typ) {
    case 'urkunde': return 'Urkunde';
    case 'vollmacht': return 'Vollmacht';
    case 'satzung': return 'Satzung';
    case 'protokoll': return 'Protokoll';
    case 'antrag': return 'Antrag';
    default: return 'Sonstiges';
  }
}

/// Helper function to get icon for payment type
IconData getZahlungsartIcon(String art) {
  switch (art) {
    case 'ueberweisung': return Icons.account_balance;
    case 'bar': return Icons.payments;
    case 'lastschrift': return Icons.autorenew;
    case 'karte': return Icons.credit_card;
    default: return Icons.euro;
  }
}

/// Info row widget for notar data
class NotarInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtitle;

  const NotarInfoRow({
    super.key,
    required this.icon,
    required this.text,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card displaying notar contact information
class NotarDataCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final VoidCallback? onEdit;

  const NotarDataCard({
    super.key,
    required this.data,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.contact_page, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Notardaten',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: Colors.orange,
                  tooltip: 'Bearbeiten',
                  onPressed: data != null ? onEdit : null,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: data == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.contact_page, size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            'Keine Daten',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          Text(
                            data!['name'] ?? '',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          if (data!['name2'] != null && data!['name2'].toString().isNotEmpty)
                            Text(
                              data!['name2'],
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                            ),
                          const SizedBox(height: 12),
                          // Address
                          NotarInfoRow(
                            icon: Icons.location_on,
                            text: '${data!['strasse'] ?? ''} ${data!['hausnummer'] ?? ''}',
                            subtitle: '${data!['plz'] ?? ''} ${data!['ort'] ?? ''}',
                          ),
                          if (data!['telefon'] != null && data!['telefon'].toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            NotarInfoRow(icon: Icons.phone, text: data!['telefon']),
                          ],
                          if (data!['fax'] != null && data!['fax'].toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            NotarInfoRow(icon: Icons.fax, text: data!['fax']),
                          ],
                          if (data!['email'] != null && data!['email'].toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            NotarInfoRow(icon: Icons.email, text: data!['email']),
                          ],
                          if (data!['website'] != null && data!['website'].toString().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            NotarInfoRow(
                              icon: Icons.language,
                              text: data!['website'].toString().replaceAll('https://', '').replaceAll('http://', ''),
                            ),
                          ],
                          if (data!['notizen'] != null && data!['notizen'].toString().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              data!['notizen'],
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying notar invoices (Rechnungen)
class NotarRechnungenCard extends StatelessWidget {
  final List<Map<String, dynamic>> rechnungen;
  final bool isLoading;
  final VoidCallback onAdd;

  const NotarRechnungenCard({
    super.key,
    required this.rechnungen,
    required this.isLoading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate totals
    final totalBetrag = rechnungen.fold<double>(
      0, (sum, r) => sum + (r['betrag'] as num? ?? 0).toDouble());
    final unbezahltCount = rechnungen.where((r) => r['bezahlt'] != true).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rechnungen',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (rechnungen.isNotEmpty)
                        Text(
                          '${rechnungen.length} Rechnungen • ${totalBetrag.toStringAsFixed(2)} € • $unbezahltCount offen',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.blue,
                  tooltip: 'Rechnung hinzufügen',
                  onPressed: onAdd,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : rechnungen.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Rechnungen',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: rechnungen.length,
                          itemBuilder: (context, index) {
                            final r = rechnungen[index];
                            final bezahlt = r['bezahlt'] == true;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                bezahlt ? Icons.check_circle : Icons.pending,
                                color: bezahlt ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                              title: Text(
                                r['rechnungsnummer'] ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                r['datum'] ?? '',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: Text(
                                '${(r['betrag'] as num? ?? 0).toStringAsFixed(2)} €',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: bezahlt ? Colors.green : Colors.orange,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying notar visits (Besuche)
class NotarBesucheCard extends StatelessWidget {
  final List<Map<String, dynamic>> besuche;
  final bool isLoading;
  final VoidCallback onAdd;

  const NotarBesucheCard({
    super.key,
    required this.besuche,
    required this.isLoading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final geplant = besuche.where((b) => b['status'] == 'geplant').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_today, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Besuche',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (besuche.isNotEmpty)
                        Text(
                          '${besuche.length} Besuche${geplant > 0 ? ' • $geplant geplant' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.green,
                  tooltip: 'Besuch hinzufügen',
                  onPressed: onAdd,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : besuche.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Besuche',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: besuche.length,
                          itemBuilder: (context, index) {
                            final b = besuche[index];
                            final status = b['status'] ?? 'geplant';
                            final statusColor = status == 'abgeschlossen'
                                ? Colors.green
                                : status == 'abgesagt'
                                    ? Colors.red
                                    : Colors.blue;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                status == 'abgeschlossen'
                                    ? Icons.check_circle
                                    : status == 'abgesagt'
                                        ? Icons.cancel
                                        : Icons.schedule,
                                color: statusColor,
                                size: 20,
                              ),
                              title: Text(
                                b['zweck'] ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${b['datum'] ?? ''}${b['uhrzeit'] != null ? ' ${b['uhrzeit']}' : ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying notar documents (Dokumente)
class NotarDokumenteCard extends StatelessWidget {
  final List<Map<String, dynamic>> dokumente;
  final bool isLoading;
  final VoidCallback onAdd;

  const NotarDokumenteCard({
    super.key,
    required this.dokumente,
    required this.isLoading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_open, color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dokumente',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (dokumente.isNotEmpty)
                        Text(
                          '${dokumente.length} Dokumente',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.purple,
                  tooltip: 'Dokument hinzufügen',
                  onPressed: onAdd,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : dokumente.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Dokumente',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: dokumente.length,
                          itemBuilder: (context, index) {
                            final d = dokumente[index];
                            final typ = d['typ'] ?? 'sonstiges';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                getDokumentIcon(typ),
                                color: Colors.purple,
                                size: 20,
                              ),
                              title: Text(
                                d['titel'] ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${d['datum'] ?? ''} • ${getDokumentTypLabel(typ)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying notar tasks (Aufgaben)
class NotarAufgabenCard extends StatelessWidget {
  final List<Map<String, dynamic>> aufgaben;
  final bool isLoading;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic> aufgabe)? onTap;

  const NotarAufgabenCard({
    super.key,
    required this.aufgaben,
    required this.isLoading,
    required this.onAdd,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final offenCount = aufgaben.where((a) => a['status'] == 'offen').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.task_alt, color: Colors.deepOrange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aufgaben',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (aufgaben.isNotEmpty)
                        Text(
                          '${aufgaben.length} Aufgaben${offenCount > 0 ? ' • $offenCount offen' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.deepOrange,
                  tooltip: 'Aufgabe hinzufügen',
                  onPressed: onAdd,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : aufgaben.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.task_alt, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Aufgaben',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: aufgaben.length,
                          itemBuilder: (context, index) {
                            final a = aufgaben[index];
                            final status = a['status'] ?? 'offen';
                            final erledigt = status == 'erledigt';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onTap: onTap != null ? () => onTap!(a) : null,
                              leading: Icon(
                                erledigt ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: erledigt ? Colors.green : Colors.deepOrange,
                                size: 20,
                              ),
                              title: Text(
                                a['beschreibung'] ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  decoration: erledigt ? TextDecoration.lineThrough : null,
                                  color: erledigt ? Colors.grey : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${a['datum'] ?? ''}${a['uhrzeit'] != null ? ' ${a['uhrzeit']}' : ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying notar payments (Zahlungen)
class NotarZahlungenCard extends StatelessWidget {
  final List<Map<String, dynamic>> zahlungen;
  final bool isLoading;
  final VoidCallback onAdd;

  const NotarZahlungenCard({
    super.key,
    required this.zahlungen,
    required this.isLoading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final totalZahlungen = zahlungen.fold<double>(
      0, (sum, z) => sum + (z['betrag'] as num? ?? 0).toDouble());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.euro, color: Colors.teal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zahlungen',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (zahlungen.isNotEmpty)
                        Text(
                          '${zahlungen.length} Zahlungen • ${totalZahlungen.toStringAsFixed(2)} €',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.teal,
                  tooltip: 'Zahlung hinzufügen',
                  onPressed: onAdd,
                ),
              ],
            ),
            const Divider(height: 24),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : zahlungen.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.euro, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Zahlungen',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: zahlungen.length,
                          itemBuilder: (context, index) {
                            final z = zahlungen[index];
                            final zahlungsart = z['zahlungsart'] ?? 'ueberweisung';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                getZahlungsartIcon(zahlungsart),
                                color: Colors.teal,
                                size: 20,
                              ),
                              title: Text(
                                z['verwendungszweck'] ?? 'Zahlung',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                z['datum'] ?? '',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: Text(
                                '${(z['betrag'] as num? ?? 0).toStringAsFixed(2)} €',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
