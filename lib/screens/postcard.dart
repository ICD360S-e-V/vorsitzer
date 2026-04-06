import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'webview_screen.dart';

/// Self-contained POSTCARD card management widget.
/// Used by DeutschePostScreen for the "POSTCARD Karten" subview.
class PostcardView extends StatefulWidget {
  final ApiService apiService;
  /// Called whenever the card count changes (for parent badge updates).
  final ValueChanged<int>? onCountChanged;

  const PostcardView({
    super.key,
    required this.apiService,
    this.onCountChanged,
  });

  @override
  State<PostcardView> createState() => _PostcardViewState();
}

class _PostcardViewState extends State<PostcardView> {
  List<Map<String, dynamic>> _postcards = [];
  bool _isLoadingPostcards = true;

  @override
  void initState() {
    super.initState();
    _loadPostcards();
  }

  Future<void> _loadPostcards() async {
    setState(() => _isLoadingPostcards = true);
    final result = await widget.apiService.getPostcardKarten();
    if (mounted && result['success'] == true) {
      setState(() {
        _postcards = List<Map<String, dynamic>>.from(result['karten'] ?? []);
        _isLoadingPostcards = false;
      });
      widget.onCountChanged?.call(_postcards.length);
    } else if (mounted) {
      setState(() => _isLoadingPostcards = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Colors.deepPurple.shade700;
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
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.credit_card, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POSTCARD Karten',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Geschäftskundenkarten',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_postcards.length}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle_outline, color: color),
                  onPressed: _showAddPostcardDialog,
                  tooltip: 'Karte hinzufügen',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.settings, color: Colors.grey.shade600, size: 20),
                  onPressed: _showPostcardAccountDialog,
                  tooltip: 'Konto-Einstellungen',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
            const Divider(height: 24),
            // POSTCARD Service Info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bargeldlos bezahlen - sicher & kostenlos',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800),
                  ),
                  const SizedBox(height: 6),
                  _postcardInfoRow(Icons.check_circle, 'Kostenlos, ohne Mindestumsatz'),
                  _postcardInfoRow(Icons.check_circle, 'Fast alle Post-Produkte bargeldlos bezahlen'),
                  _postcardInfoRow(Icons.check_circle, 'Tägliches Kartenlimit (Sicherheit)'),
                  _postcardInfoRow(Icons.check_circle, 'Taggenau Abrechnung per Lastschrift'),
                  _postcardInfoRow(Icons.check_circle, 'Transaktionsübersicht im Shop'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => launchUrl(Uri.parse('https://www.deutschepost.de/de/p/postcard.html')),
                        child: Text(
                          'Mehr erfahren',
                          style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700, decoration: TextDecoration.underline),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => launchUrl(Uri.parse('https://shop.deutschepost.de')),
                        child: Text(
                          'Zum Shop',
                          style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Unsere Karten header
            Row(
              children: [
                Text('Unsere Karten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const Spacer(),
                Text('${_postcards.length} Karten', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: _isLoadingPostcards
                  ? const Center(child: CircularProgressIndicator())
                  : _postcards.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.credit_card, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Karten',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _postcards.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final card = _postcards[index];
                            final aktiv = card['aktiv'] == true;
                            final bezeichnung = card['bezeichnung'] as String? ?? '';
                            final kartennummer = card['kartennummer'] as String? ?? '';
                            final limit = card['tageslimit'] as num? ?? 10;

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.credit_card,
                                color: aktiv ? Colors.deepPurple : Colors.grey,
                                size: 20,
                              ),
                              title: Text(
                                bezeichnung.isNotEmpty ? bezeichnung : 'Karte ${index + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: aktiv ? null : Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    kartennummer.length > 8
                                        ? '${kartennummer.substring(0, 4)}...${kartennummer.substring(kartennummer.length - 4)}'
                                        : kartennummer,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${limit.toStringAsFixed(0)}€/Tag',
                                      style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (!aktiv) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Inaktiv',
                                        style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              onTap: () => _showPostcardDetailsDialog(card),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postcardInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.green.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  Future<void> _showAddPostcardDialog() async {
    final nummerCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final bezCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '10');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.credit_card, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            const Text('Karte hinzufügen', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bezCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bezeichnung',
                  hintText: 'z.B. Karte 1 - Vorsitzer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nummerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kartennummer *',
                  hintText: '17-stellige Postcard-Nummer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  hintText: '4-stellige PIN',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tageslimit (€)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nummerCtrl.text.trim().isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              final res = await widget.apiService.createPostcardKarte(
                kartennummer: nummerCtrl.text.trim(),
                pin: pinCtrl.text.trim().isNotEmpty ? pinCtrl.text.trim() : null,
                bezeichnung: bezCtrl.text.trim().isNotEmpty ? bezCtrl.text.trim() : null,
                tageslimit: double.tryParse(limitCtrl.text.trim()) ?? 10.0,
              );
              if (ctx.mounted) Navigator.pop(ctx, res['success'] == true);
              if (res['success'] != true) {
                messenger.showSnackBar(
                  SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade700),
            child: const Text('Speichern', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    nummerCtrl.dispose();
    pinCtrl.dispose();
    bezCtrl.dispose();
    limitCtrl.dispose();

    if (result == true && mounted) _loadPostcards();
  }

  Future<void> _showPostcardDetailsDialog(Map<String, dynamic> card) async {
    final nummerCtrl = TextEditingController(text: card['kartennummer'] ?? '');
    final pinCtrl = TextEditingController(text: card['pin'] ?? '');
    final bezCtrl = TextEditingController(text: card['bezeichnung'] ?? '');
    final limitCtrl = TextEditingController(text: (card['tageslimit'] as num? ?? 10).toStringAsFixed(0));
    bool obscurePin = true;
    bool isEditing = false;
    final aktiv = card['aktiv'] == true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final color = Colors.deepPurple.shade700;
          final bezeichnung = bezCtrl.text.isNotEmpty ? bezCtrl.text : 'POSTCARD';
          final pin = pinCtrl.text;

          // VIEW MODE
          if (!isEditing) {
            // Format card number with spaces for display (e.g. "5314 1598 34 2501 012")
            final rawNumber = nummerCtrl.text.replaceAll(' ', '');
            final formattedNumber = rawNumber.length >= 10
                ? '${rawNumber.substring(0, 4)} ${rawNumber.substring(4, 8)} ${rawNumber.substring(8, 10)} ${rawNumber.length > 10 ? rawNumber.substring(10) : ''}'.trim()
                : nummerCtrl.text;

            return AlertDialog(
              titlePadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== REALISTIC POSTCARD =====
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      height: 230,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFDAA520), Color(0xFFF5D060), Color(0xFFE8B830)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Subtle pattern overlay
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: CustomPaint(painter: _CardPatternPainter()),
                            ),
                          ),
                          // Card content
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: Deutsche Post logo + status
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Post horn icon + "Deutsche Post"
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Post horn icon
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFCC8800),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: const Center(
                                                child: Icon(Icons.local_post_office, size: 16, color: Colors.white),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Deutsche Post',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4A3000),
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        const Padding(
                                          padding: EdgeInsets.only(left: 36),
                                          child: Text(
                                            'POSTCARD',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF7A5500),
                                              letterSpacing: 3.0,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    // Status badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: aktiv
                                            ? Colors.green.shade700.withValues(alpha: 0.25)
                                            : Colors.red.shade700.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: aktiv ? Colors.green.shade800 : Colors.red.shade800,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        aktiv ? 'AKTIV' : 'INAKTIV',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: aktiv ? Colors.green.shade900 : Colors.red.shade900,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                // EMV Chip
                                Container(
                                  width: 45,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFD4A843), Color(0xFFF0D070), Color(0xFFD4A843)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    border: Border.all(color: const Color(0xFFB8922A), width: 1),
                                  ),
                                  child: CustomPaint(painter: _ChipPainter()),
                                ),
                                const Spacer(),
                                // Card number
                                Text(
                                  formattedNumber,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3A2500),
                                    letterSpacing: 2.0,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Bottom row: Bezeichnung + Limit
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        bezeichnung.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF5A3E00),
                                          letterSpacing: 1.0,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      'Limit: ${limitCtrl.text} EUR',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF6B4D00),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ===== DETAILS BELOW CARD =====
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // PIN row with eye toggle
                          _cardDetailRow(
                            'PIN',
                            obscurePin ? (pin.isNotEmpty ? '****' : '-') : (pin.isNotEmpty ? pin : '-'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pin.isNotEmpty)
                                  IconButton(
                                    icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.grey.shade600),
                                    onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                                    tooltip: obscurePin ? 'PIN anzeigen' : 'PIN verbergen',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                                const SizedBox(width: 4),
                                if (pin.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.copy, size: 16, color: Colors.grey.shade500),
                                    onPressed: () {
                                      ClipboardHelper.copy(context, pin, 'PIN');
                                    },
                                    tooltip: 'PIN kopieren',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 16),
                          // Kartennummer copyable
                          _cardDetailRow(
                            'Kartennummer',
                            nummerCtrl.text,
                            trailing: IconButton(
                              icon: Icon(Icons.copy, size: 16, color: Colors.grey.shade500),
                              onPressed: () {
                                ClipboardHelper.copy(context, nummerCtrl.text, 'Kartennummer');
                              },
                              tooltip: 'Kopieren',
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Löschen'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Schließen'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Bearbeiten', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: color),
                      onPressed: () => setDialogState(() => isEditing = true),
                    ),
                  ],
                ),
              ],
            );
          }

          // EDIT MODE
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit, color: color),
                const SizedBox(width: 8),
                const Text('Karte bearbeiten', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: bezCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nummerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kartennummer',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinCtrl,
                    obscureText: obscurePin,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tageslimit (EUR)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setDialogState(() => isEditing = false),
                child: const Text('Zurück'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: const Text('Speichern', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || action == null) {
      nummerCtrl.dispose();
      pinCtrl.dispose();
      bezCtrl.dispose();
      limitCtrl.dispose();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (action == 'save') {
      await widget.apiService.updatePostcardKarte(
        id: card['id'] as int,
        kartennummer: nummerCtrl.text.trim(),
        pin: pinCtrl.text.trim(),
        bezeichnung: bezCtrl.text.trim(),
        tageslimit: double.tryParse(limitCtrl.text.trim()) ?? 10.0,
      );
      if (mounted) _loadPostcards();
    } else if (action == 'delete') {
      final res = await widget.apiService.deletePostcardKarte(card['id'] as int);
      if (mounted) {
        if (res['success'] == true) {
          _loadPostcards();
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    }

    nummerCtrl.dispose();
    pinCtrl.dispose();
    bezCtrl.dispose();
    limitCtrl.dispose();
  }

  Widget _cardDetailRow(String label, String value, {Widget? trailing}) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Future<void> _showPostcardAccountDialog() async {
    final websiteCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = true;

    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Load account data on first build
          if (isLoading) {
            widget.apiService.getPostcardAccount().then((res) {
              if (ctx.mounted) {
                final account = res['account'];
                if (account != null) {
                  websiteCtrl.text = account['website'] ?? '';
                  usernameCtrl.text = account['username'] ?? '';
                  passwordCtrl.text = account['password'] ?? '';
                }
                setDialogState(() => isLoading = false);
              }
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.settings, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                const Text('Deutsche Post Konto', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zugangsdaten für das Deutsche Post Geschäftskundenportal',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: websiteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Website / Login-URL',
                            hintText: 'z.B. https://geschaeftskunden.deutschepost.de',
                            prefixIcon: Icon(Icons.language),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Benutzername / E-Mail',
                            hintText: 'Ihr Login-Name',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordCtrl,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Passwort',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Alle Daten werden mit AES-256 verschlüsselt gespeichert.',
                                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            actions: isLoading
                ? null
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Abbrechen'),
                    ),
                    if (websiteCtrl.text.isNotEmpty || usernameCtrl.text.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.language, size: 14),
                        label: const Text('Zum Login'),
                        onPressed: () {
                          final url = websiteCtrl.text.trim();
                          if (url.isNotEmpty) {
                            final user = usernameCtrl.text.trim();
                            final pass = passwordCtrl.text.trim();
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WebViewScreen(
                                  title: 'Deutsche Post Login',
                                  url: url.startsWith('http') ? url : 'https://$url',
                                  autoFillUsername: user.isNotEmpty ? user : null,
                                  autoFillPassword: pass.isNotEmpty ? pass : null,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Speichern', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade700),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final res = await widget.apiService.savePostcardAccount(
                          website: websiteCtrl.text.trim(),
                          username: usernameCtrl.text.trim(),
                          password: passwordCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, res['success'] == true);
                        if (res['success'] == true) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Kontodaten gespeichert'), backgroundColor: Colors.green),
                          );
                        } else {
                          messenger.showSnackBar(
                            SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red),
                          );
                        }
                      },
                    ),
                  ],
          );
        },
      ),
    );

    websiteCtrl.dispose();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
  }
}

/// Subtle diagonal line pattern for the card background
class _CardPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0A000000)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 20.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// EMV chip lines painter
class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x30000000)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Horizontal lines
    canvas.drawLine(Offset(0, size.height * 0.35), Offset(size.width, size.height * 0.35), paint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65), paint);

    // Vertical center line
    canvas.drawLine(Offset(size.width * 0.5, 0), Offset(size.width * 0.5, size.height), paint);

    // Small rectangles in chip pattern
    final rectPaint = Paint()
      ..color = const Color(0x15000000)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(size.width * 0.1, size.height * 0.1, size.width * 0.3, size.height * 0.2), rectPaint);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.6, size.height * 0.7, size.width * 0.3, size.height * 0.2), rectPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
