import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import '../services/api_service.dart';
import '../services/app_sperre_service.dart';
import '../services/chat_service.dart';
import '../services/secure_store.dart';
import '../services/termin_service.dart';
import '../services/ticket_service.dart';
import '../utils/app_farben.dart';
import '../utils/role_helpers.dart';
import '../widgets/live_chat_dialog.dart';
import '../widgets/profile_dialog.dart';
import 'login_screen.dart';

/// Die App für ein Vorstandsmitglied mit eingeschränktem Zugriff.
///
/// Vier Dinge: mit wem man reden darf, die eigenen Termine, die eigenen
/// Tickets, das eigene Konto. Sonst nichts.
///
/// ⚠️ **Warum ein eigener Bildschirm und nicht ein ausgedünntes Dashboard.**
/// [DashboardScreen] hat 3.755 Zeilen und rund zwanzig Knöpfe in der
/// Kopfzeile. Jeden davon einzeln hinter eine Bedingung zu legen hiesse: die
/// Einschränkung gilt für das, woran heute jemand gedacht hat. Der nächste
/// Knopf, den irgendwer nächsten Monat hinzufügt, wäre wieder sichtbar — und
/// niemand würde es merken, weil nichts fehlschlägt. Hier ist es umgekehrt:
/// sichtbar ist nur, was hier ausdrücklich steht. Dasselbe Muster wie
/// [RdpOnlyScreen], und aus demselben Grund.
///
/// ⚠️ **Dieser Bildschirm ist KEINE Zugriffskontrolle.** Er ist die
/// Oberfläche, die zu den Rechten passt. Die Kontrolle sitzt auf dem Server:
/// `requireAdminRole()`, `requireRollen()`, `ticketZugriff()` und
/// `chatIstAdmin()` lesen `users.zugriff_eingeschraenkt`. Wer diesen
/// Bildschirm umgeht, bekommt dort 403 — nachgewiesen an den lebenden
/// Endpunkten, nicht angenommen.
class VorstandKompaktScreen extends StatefulWidget {
  final String userName;
  final String currentMitgliedernummer;
  final String currentEmail;
  final String currentRole;

  const VorstandKompaktScreen({
    super.key,
    required this.userName,
    required this.currentMitgliedernummer,
    required this.currentEmail,
    required this.currentRole,
  });

  @override
  State<VorstandKompaktScreen> createState() => _VorstandKompaktScreenState();
}

class _VorstandKompaktScreenState extends State<VorstandKompaktScreen> {
  final _api = ApiService();
  int _seite = 0;
  late String _email = widget.currentEmail;

  /// Wortgleich zum Dashboard und zum Kiosk — ein dritter, abweichender
  /// Abmeldeweg wäre eine Fehlerquelle, die man erst bemerkt, wenn ein Gerät
  /// verloren geht.
  Future<void> _abmelden() async {
    await _api.logout();
    await AppSperreService().zuruecksetzen();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_login', false);
    final store = SecureStore();
    await store.delete(key: 'mitgliedernummer');
    await store.delete(key: 'password');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _profilOeffnen() {
    showDialog(
      context: context,
      builder: (_) => ProfileDialog(
        userName: widget.userName,
        mitgliedernummer: widget.currentMitgliedernummer,
        email: _email,
        role: widget.currentRole,
        // ⚠️ Bewusst ohne userId: die käme im Dashboard aus der geladenen
        // Mitgliederliste, und genau die darf dieses Konto nicht abrufen.
        apiService: _api,
        onEmailChanged: (neu) => setState(() => _email = neu),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seiten = [
      _ChatBereich(
        mitgliedernummer: widget.currentMitgliedernummer,
        userName: widget.userName,
      ),
      const _TermineBereich(),
      _TicketBereich(mitgliedernummer: widget.currentMitgliedernummer),
      _KontoBereich(
        userName: widget.userName,
        mitgliedernummer: widget.currentMitgliedernummer,
        email: _email,
        role: widget.currentRole,
        onProfil: _profilOeffnen,
        onAbmelden: _abmelden,
      ),
    ];

    return Scaffold(
      backgroundColor: F.hintergrund,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.userName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${getRoleText(widget.currentRole)} · ${widget.currentMitgliedernummer}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mein Profil',
            onPressed: _profilOeffnen,
          ),
        ],
      ),
      body: IndexedStack(index: _seite, children: seiten),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _seite,
        onDestinationSelected: (i) => setState(() => _seite = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.event_outlined), label: 'Termine'),
          NavigationDestination(icon: Icon(Icons.confirmation_number_outlined), label: 'Tickets'),
          NavigationDestination(icon: Icon(Icons.account_circle_outlined), label: 'Konto'),
        ],
      ),
    );
  }
}

// ── Chat ────────────────────────────────────────────────────────────────────

/// Die Gespräche, die dieses Konto führen darf — nicht mehr.
///
/// ⚠️ Die Liste wird NICHT im Client gefiltert. `chat/conversations.php`
/// liefert einem eingeschränkten Konto von sich aus nur die eigenen Gespräche
/// (nachgemessen: 1 statt 29). Eine zweite Filterung hier sähe aus wie der
/// Schutz und wäre keiner — sie liesse sich mit jedem HTTP-Werkzeug umgehen.
class _ChatBereich extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;
  const _ChatBereich({required this.mitgliedernummer, required this.userName});

  @override
  State<_ChatBereich> createState() => _ChatBereichState();
}

class _ChatBereichState extends State<_ChatBereich> {
  final _api = ApiService();
  final _chat = ChatService();
  StreamSubscription? _lauscher;
  List<Map<String, dynamic>> _gespraeche = const [];
  bool _laden = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden0().then((_) => _imHintergrundBeitreten());
  }

  @override
  void dispose() {
    _lauscher?.cancel();
    super.dispose();
  }

  /// Beim WebSocket anmelden und ALLEN gelieferten Gesprächen beitreten.
  ///
  /// ⚠️ Ohne das sähe man eine neue Nachricht erst, wenn man den Chat gerade
  /// offen hat. Das Dashboard tut dasselbe (`_joinBackgroundConversations`);
  /// dieser Bildschirm ersetzt es, also muss er es mitbringen — sonst wäre
  /// die Einschränkung nebenbei eine Abschaltung der Benachrichtigungen.
  ///
  /// ⚠️ Beigetreten wird ALLEM, was der Server geliefert hat. Eine eigene
  /// Auswahl („nur wo ich member_id bin") wäre hier falsch: im Direktchat ist
  /// man mal die eine, mal die andere Seite.
  Future<void> _imHintergrundBeitreten() async {
    try {
      if (!_chat.isConnected) {
        await _chat.connect(widget.mitgliedernummer, userName: widget.userName);
      }
      for (final g in _gespraeche) {
        final id = g['id'];
        final n = id is int ? id : int.tryParse('$id');
        if (n != null) _chat.joinConversation(n);
      }
      _lauscher ??= _chat.messageStream.listen((_) {
        if (mounted) _laden0();
      });
    } catch (_) {
      // Ohne Echtzeit bleibt die Liste bedienbar: sie lädt beim Öffnen und
      // beim Herunterziehen. Ein Verbindungsfehler darf den Bildschirm nicht
      // unbrauchbar machen.
    }
  }

  Future<void> _laden0() async {
    setState(() {
      _laden = true;
      _fehler = null;
    });
    final r = await _api.getChatConversations(widget.mitgliedernummer);
    if (!mounted) return;
    setState(() {
      _laden = false;
      if (r['success'] == true) {
        _gespraeche = (r['conversations'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _fehler = r['message']?.toString() ?? 'Gespräche konnten nicht geladen werden';
      }
    });
  }

  void _oeffnen(Map<String, dynamic> g) {
    final id = g['id'];
    showDialog(
      context: context,
      builder: (_) => LiveChatDialog(
        mitgliedernummer: widget.mitgliedernummer,
        userName: widget.userName,
        conversationId: id is int ? id : int.tryParse('$id'),
        gegenueber: (g['gegenueber_name'] ?? g['member_name'])?.toString(),
      ),
    ).then((_) => _laden0());
  }

  @override
  Widget build(BuildContext context) {
    if (_laden) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return _Hinweis(text: _fehler!, onErneut: _laden0);
    if (_gespraeche.isEmpty) {
      return _Hinweis(
        text: 'Es ist noch kein Gespräch eingerichtet.\n'
            'Der Vorsitz legt es an.',
        onErneut: _laden0,
      );
    }
    return RefreshIndicator(
      onRefresh: _laden0,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _gespraeche.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final g = _gespraeche[i];
          final ungelesen = (g['unread_count'] as num?)?.toInt() ?? 0;
          final letzte = g['last_message']?.toString() ?? '';
          return Card(
            color: F.flaeche,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF4a90d9),
                child: Text(
                  ((g['gegenueber_name'] ?? g['member_name'])?.toString() ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                (g['gegenueber_name'] ?? g['member_name'])?.toString() ?? 'Gespräch ${g['id']}',
                style: TextStyle(fontWeight: FontWeight.w600, color: F.textStark),
              ),
              subtitle: Text(
                letzte.isEmpty ? 'Noch keine Nachricht' : letzte,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: F.textSchwach),
              ),
              trailing: ungelesen > 0
                  ? Badge(label: Text('$ungelesen'))
                  : const Icon(Icons.chevron_right),
              onTap: () => _oeffnen(g),
            ),
          );
        },
      ),
    );
  }
}

// ── Termine ─────────────────────────────────────────────────────────────────

class _TermineBereich extends StatefulWidget {
  const _TermineBereich();

  @override
  State<_TermineBereich> createState() => _TermineBereichState();
}

class _TermineBereichState extends State<_TermineBereich> {
  final _svc = TerminService();
  List<Map<String, dynamic>> _termine = const [];
  bool _laden = true;
  String? _fehler;
  String _filter = 'upcoming';

  @override
  void initState() {
    super.initState();
    _laden0();
  }

  Future<void> _laden0() async {
    setState(() {
      _laden = true;
      _fehler = null;
    });
    final r = await _svc.getMyTermine(filter: _filter);
    if (!mounted) return;
    setState(() {
      _laden = false;
      if (r['success'] == true) {
        _termine = (r['termine'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        _fehler = r['message']?.toString() ?? 'Termine konnten nicht geladen werden';
      }
    });
  }

  Future<void> _antworten(int id, String antwort) async {
    final r = await _svc.respondToTermin(terminId: id, response: antwort);
    if (!mounted) return;
    final ok = r['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Antwort gespeichert.'
          : (r['message']?.toString() ?? 'Antwort fehlgeschlagen')),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
    if (ok) _laden0();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upcoming', label: Text('Kommende')),
              ButtonSegment(value: 'past', label: Text('Vergangene')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) {
              setState(() => _filter = s.first);
              _laden0();
            },
          ),
        ),
        Expanded(child: _liste()),
      ],
    );
  }

  Widget _liste() {
    if (_laden) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return _Hinweis(text: _fehler!, onErneut: _laden0);
    if (_termine.isEmpty) {
      return _Hinweis(text: 'Keine Termine.', onErneut: _laden0);
    }
    return RefreshIndicator(
      onRefresh: _laden0,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _termine.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final t = _termine[i];
          final id = (t['id'] as num?)?.toInt() ?? 0;
          final antwort = t['response']?.toString() ?? 'pending';
          final offen = antwort == 'pending' && _filter == 'upcoming';
          return Card(
            color: F.flaeche,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['title']?.toString() ?? 'Termin',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: F.textStark)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.schedule, size: 15, color: F.textLeise),
                    const SizedBox(width: 4),
                    Text(_datum(t['termin_date']?.toString()),
                        style: TextStyle(color: F.textSchwach)),
                  ]),
                  if ((t['location']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.place_outlined, size: 15, color: F.textLeise),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(t['location'].toString(),
                            style: TextStyle(color: F.textSchwach)),
                      ),
                    ]),
                  ],
                  if ((t['description']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(t['description'].toString(),
                        style: TextStyle(color: F.textSchwach, fontSize: 13)),
                  ],
                  const SizedBox(height: 8),
                  if (offen)
                    Row(children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Zusagen'),
                        onPressed: () => _antworten(id, 'confirmed'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Absagen'),
                        onPressed: () => _antworten(id, 'declined'),
                      ),
                    ])
                  else
                    Chip(
                      label: Text(_antwortText(antwort)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _antwortText(String a) => switch (a) {
        'confirmed' => 'Zugesagt',
        'declined' => 'Abgesagt',
        'rescheduling' => 'Verlegung erbeten',
        _ => 'Offen',
      };

  static String _datum(String? roh) {
    if (roh == null || roh.isEmpty) return '—';
    final d = DateTime.tryParse(roh);
    if (d == null) return roh;
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(d.day)}.${z(d.month)}.${d.year}, ${z(d.hour)}:${z(d.minute)} Uhr';
  }
}

// ── Tickets ─────────────────────────────────────────────────────────────────

class _TicketBereich extends StatefulWidget {
  final String mitgliedernummer;
  const _TicketBereich({required this.mitgliedernummer});

  @override
  State<_TicketBereich> createState() => _TicketBereichState();
}

class _TicketBereichState extends State<_TicketBereich> {
  final _svc = TicketService();
  List<Ticket> _tickets = const [];
  bool _laden = true;

  @override
  void initState() {
    super.initState();
    _laden0();
  }

  Future<void> _laden0() async {
    setState(() => _laden = true);
    final t = await _svc.getTickets(widget.mitgliedernummer);
    if (!mounted) return;
    setState(() {
      _laden = false;
      _tickets = t;
    });
  }

  Future<void> _neu() async {
    final betreff = TextEditingController();
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neues Ticket'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: betreff,
            decoration: const InputDecoration(labelText: 'Betreff'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: text,
            decoration: const InputDecoration(labelText: 'Anliegen'),
            maxLines: 5,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Senden')),
        ],
      ),
    );
    if (ok != true) return;
    if (betreff.text.trim().isEmpty || text.text.trim().isEmpty) return;
    final r = await _svc.createTicket(
      mitgliedernummer: widget.mitgliedernummer,
      subject: betreff.text.trim(),
      message: text.text.trim(),
    );
    if (!mounted) return;
    final gut = r['ticket'] != null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(gut ? 'Ticket angelegt.' : (r['error']?.toString() ?? 'Fehlgeschlagen')),
      backgroundColor: gut ? Colors.green.shade700 : Colors.red.shade700,
    ));
    if (gut) _laden0();
  }

  void _oeffnen(Ticket t) {
    showDialog(
      context: context,
      builder: (_) => _TicketDialog(ticket: t, mitgliedernummer: widget.mitgliedernummer),
    ).then((_) => _laden0());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _neu,
        icon: const Icon(Icons.add),
        label: const Text('Neu'),
      ),
      body: _laden
          ? const Center(child: CircularProgressIndicator())
          : _tickets.isEmpty
              ? _Hinweis(text: 'Keine Tickets.', onErneut: _laden0)
              : RefreshIndicator(
                  onRefresh: _laden0,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: _tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = _tickets[i];
                      return Card(
                        color: F.flaeche,
                        child: ListTile(
                          title: Text(t.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: F.textStark)),
                          subtitle: Text(
                            '#${t.id} · ${_statusText(t.status)}',
                            style: TextStyle(color: F.textSchwach),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _oeffnen(t),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  static String _statusText(String s) => switch (s) {
        'open' => 'Offen',
        'in_progress' => 'In Bearbeitung',
        'closed' => 'Geschlossen',
        'resolved' => 'Erledigt',
        _ => s,
      };
}

class _TicketDialog extends StatefulWidget {
  final Ticket ticket;
  final String mitgliedernummer;
  const _TicketDialog({required this.ticket, required this.mitgliedernummer});

  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  final _svc = TicketService();
  final _eingabe = TextEditingController();
  List<TicketComment> _kommentare = const [];
  bool _laden = true;
  bool _sendet = false;

  @override
  void initState() {
    super.initState();
    _laden0();
  }

  @override
  void dispose() {
    _eingabe.dispose();
    super.dispose();
  }

  Future<void> _laden0() async {
    final r = await _svc.getComments(
        mitgliedernummer: widget.mitgliedernummer, ticketId: widget.ticket.id);
    if (!mounted) return;
    setState(() {
      _laden = false;
      // ⚠️ Interne Notizen des Vorstands gehören nicht in diese Ansicht.
      // Der Server liefert sie mit; ein `isInternal`-Kommentar ist eine
      // Bemerkung ÜBER den Vorgang, nicht an den Melder.
      _kommentare = (r?.comments ?? const []).where((c) => !c.isInternal).toList();
    });
  }

  Future<void> _senden() async {
    final txt = _eingabe.text.trim();
    if (txt.isEmpty || _sendet) return;
    setState(() => _sendet = true);
    final k = await _svc.addComment(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
      comment: txt,
    );
    if (!mounted) return;
    setState(() => _sendet = false);
    if (k != null) {
      _eingabe.clear();
      _laden0();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kommentar konnte nicht gesendet werden')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Text('#${widget.ticket.id} · ${widget.ticket.subject}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _laden
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        Text(widget.ticket.message,
                            style: TextStyle(color: F.textStark)),
                        const SizedBox(height: 14),
                        for (final k in _kommentare) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: F.flaecheGedaempft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k.userName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: F.textSchwach)),
                                const SizedBox(height: 2),
                                Text(k.comment,
                                    style: TextStyle(color: F.textStark)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _eingabe,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Antwort schreiben…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sendet ? null : _senden,
                  icon: const Icon(Icons.send),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Konto ───────────────────────────────────────────────────────────────────

class _KontoBereich extends StatelessWidget {
  final String userName;
  final String mitgliedernummer;
  final String email;
  final String role;
  final VoidCallback onProfil;
  final Future<void> Function() onAbmelden;

  const _KontoBereich({
    required this.userName,
    required this.mitgliedernummer,
    required this.email,
    required this.role,
    required this.onProfil,
    required this.onAbmelden,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: F.flaeche,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userName,
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: F.textStark)),
                const SizedBox(height: 6),
                _zeile(Icons.badge_outlined, mitgliedernummer),
                _zeile(Icons.workspace_premium_outlined, getRoleText(role)),
                _zeile(Icons.mail_outline, email.isEmpty ? '—' : email),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: F.flaeche,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Profil und Sicherheit'),
              subtitle: const Text('E-Mail, Passwort, Geräte'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onProfil,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red.shade700),
              title: Text('Abmelden',
                  style: TextStyle(color: Colors.red.shade700)),
              onTap: () async {
                final ja = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Abmelden?'),
                    content: const Text(
                        'Zum nächsten Anmelden wird wieder ein Aktivierungscode gebraucht.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Abbrechen')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Abmelden')),
                    ],
                  ),
                );
                if (ja == true) await onAbmelden();
              },
            ),
          ]),
        ),
      ],
    );
  }

  Widget _zeile(IconData ikone, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(ikone, size: 17, color: F.textLeise),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: F.textSchwach))),
        ]),
      );
}

// ── gemeinsam ───────────────────────────────────────────────────────────────

class _Hinweis extends StatelessWidget {
  final String text;
  final Future<void> Function() onErneut;
  const _Hinweis({required this.text, required this.onErneut});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: F.textLeise),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: F.textSchwach)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onErneut,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}
