/// Der Weg von einem Gespräch zu zweien — und dann zur Konferenz.
///
/// 🔴 WARUM DAS EIN EIGENER ABLAUF IST UND KEIN KNOPF
/// Vorher lagen die drei Schritte an drei Orten: die zweite Nummer stand in
/// einem Eingabefeld weit unten im Vollbild, „Hinzuwählen" daneben, und der
/// Konferenzknopf oben in einer Reihe, in der er nur unter einer Bedingung
/// auftauchte. Wer telefoniert, hat für so eine Suche keine Hand frei — und
/// gemeldet wurde es als „der Konferenzknopf ist weg".
///
/// Hier steht alles hintereinander: Nummer eingeben, die erste Person geht
/// dabei in die Warteschleife, und wenn die zweite abgehoben hat, schaltet ein
/// Knopf beide zusammen.
///
/// ⚠️ DIE ANLAGE MACHT DAS, NICHT WIR. Zwei entfernte Tonspuren ineinander zu
/// mischen kann `flutter_webrtc` nicht — jede Seite würde nur uns hören. Die
/// Tastenfolgen (`*3<nr>#`, `*5`, `*4`) sind die von sipgate dokumentierten;
/// die REST-Schnittstelle kennt gar keine Konferenz (nachgesehen: 144 Pfade,
/// unter `/calls` nur hold, muted, dtmf, announcements, recording, transfer).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/sipgate_service.dart';
import '../utils/app_farben.dart';

/// Öffnet den Ablauf. Gibt zurück, ob am Ende zusammengeschaltet wurde.
Future<bool> konferenzAblauf(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const KonferenzDialog(),
    ) ??
    false;

class KonferenzDialog extends StatefulWidget {
  const KonferenzDialog({super.key});

  @override
  State<KonferenzDialog> createState() => _KonferenzDialogState();
}

class _KonferenzDialogState extends State<KonferenzDialog> {
  final _dienst = SipgateService();
  final _nummer = TextEditingController();
  final _fokus = FocusNode();

  List<Map<String, dynamic>> _treffer = const [];
  Timer? _tippPause;
  bool _laeuft = false;
  String? _fehler;

  @override
  void dispose() {
    _tippPause?.cancel();
    _nummer.dispose();
    _fokus.dispose();
    super.dispose();
  }

  /// Sucht im Verzeichnis — aber erst, wenn das Tippen kurz aufhört.
  ///
  /// ⚠️ Ohne die Pause geht bei einer elfstelligen Nummer elfmal eine Anfrage
  /// hinaus, und zwar über die Leitung, auf der gerade telefoniert wird.
  void _suchen(String text) {
    _tippPause?.cancel();
    if (text.trim().length < 3) {
      setState(() => _treffer = const []);
      return;
    }
    _tippPause = Timer(const Duration(milliseconds: 400), () async {
      try {
        final a = await ApiService().sipgateAction({
          'action': 'kontakte',
          'suche': text.trim(),
          'limit': 8,
        });
        if (!mounted || a['success'] != true) return;
        setState(
          () => _treffer = SipgateService.kontakteAusAntwort(a).kontakte,
        );
      } catch (_) {
        // Eine Suche, die nicht durchkommt, ist kein Grund, den Ablauf zu
        // unterbrechen — die Nummer lässt sich tippen.
      }
    });
  }

  Future<void> _anwaehlen() async {
    final roh = _nummer.text.trim();
    if (roh.isEmpty) return;
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    final m = await _dienst.anrufen(roh);
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _fehler = m;
    });
  }

  Future<void> _zusammen() async {
    setState(() => _laeuft = true);
    final m = await _dienst.konferenzSchalten();
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _fehler = m;
    });
    if (m == null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SipgateZustand>(
      valueListenable: _dienst.zustand,
      builder: (ctx, z, _) {
        final erstes = z.gespraech;
        final zweites = z.zweites;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.groups),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  zweites == null ? 'Wen dazuholen?' : 'Beide zusammenschalten',
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            // ⚠️ Scrollbar, und nicht aus Vorsicht: bei 1,6-facher Schrift lief
            // der Inhalt über — gemessen um 0,4 px, also gerade so, und ein
            // AlertDialog scrollt von sich aus nicht. Wer die Schrift gross
            // stellt, bekäme sonst den gelb-schwarzen Balken quer über den
            // Hinweis, auf den es hier ankommt.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (erstes != null)
                    _teilnehmer(
                      nummer: 1,
                      text: erstes.anzeigeVerdeckt,
                      // ⚠️ „wartet" statt „gehalten": das Wort beschreibt, was
                      // die Person erlebt, nicht was die Anlage tut.
                      zusatz: zweites == null
                          ? 'im Gespräch'
                          : (erstes.gehalten ? 'wartet' : 'im Gespräch'),
                      farbe: erstes.gehalten ? Colors.orange : Colors.green,
                    ),
                  if (zweites == null) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Die zweite Nummer wird über die Telefonanlage gewählt. '
                      'Die erste Person hört dabei nichts mit — sie wartet.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nummer,
                      focusNode: _fokus,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      onChanged: _suchen,
                      onSubmitted: (_) => _anwaehlen(),
                      decoration: const InputDecoration(
                        labelText: 'Nummer oder Name',
                        prefixIcon: Icon(Icons.dialpad),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_treffer.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 190),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final k in _treffer)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline),
                                title: Text('${k['bezeichnung'] ?? ''}'),
                                subtitle: Text('${k['nummer'] ?? ''}'),
                                onTap: () {
                                  _nummer.text = '${k['nummer'] ?? ''}';
                                  setState(() => _treffer = const []);
                                },
                              ),
                          ],
                        ),
                      ),
                  ] else ...[
                    _teilnehmer(
                      nummer: 2,
                      text: zweites.anzeigeVerdeckt,
                      zusatz: 'wird angewählt',
                      farbe: Colors.blue,
                    ),
                    const SizedBox(height: 14),
                    // 🔴 DER WICHTIGSTE SATZ IN DIESEM DIALOG.
                    // Für den zweiten Teilnehmer gibt es KEIN Signal, wenn er
                    // abhebt — er kommt über die Anlage, nicht als eigener
                    // SIP-Dialog. Die App kann es nicht wissen; der Mensch am
                    // Hörer hört es. Ohne diesen Hinweis drückt man zu früh und
                    // schaltet ins Leere.
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: F.h(Colors.amber, 50),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: F.h(Colors.amber, 300)),
                      ),
                      // ⚠️ BRAUN, nicht `F.h(Colors.amber, 900)`. Nachgerechnet
                      // gegen den Kastengrund `F.h(Colors.amber, 50)`:
                      //
                      //     amber 900   #FF6F00   2,63:1   verlangt sind 4,5
                      //     orange 900  #E65100   3,57:1
                      //     brown 800   #4E342E  10,66:1
                      //
                      // Und im Dunkeln wird daraus `brown[200]` auf der dunklen
                      // Tönung: 5,33:1. Beide Seiten tragen also.
                      //
                      // ⚠️ Derselbe Griff (amber-50 mit amber-900) steht an
                      // mehreren anderen Stellen der App und hat dort dasselbe
                      // Problem — hier nicht mitrepariert, weil es andere
                      // Bildschirme sind.
                      child: Row(
                        children: [
                          Icon(
                            Icons.hearing,
                            size: 18,
                            color: F.h(Colors.brown, 800),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Erst zusammenschalten, wenn sich die zweite Person '
                              'gemeldet hat. Ob sie abgehoben hat, kann die App '
                              'nicht erkennen.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: F.h(Colors.brown, 800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_fehler != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _fehler!,
                      style: TextStyle(
                        color: F.h(Colors.red, 700),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: zweites == null
              ? [
                  TextButton(
                    onPressed: _laeuft
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton.icon(
                    onPressed: _laeuft ? null : _anwaehlen,
                    icon: _laeuft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call),
                    label: const Text('Anwählen'),
                  ),
                ]
              : [
                  TextButton.icon(
                    onPressed: _laeuft ? null : () => _dienst.makeln(),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Wechseln'),
                  ),
                  TextButton(
                    // ⚠️ „Später" und nicht „Abbrechen": die zweite Nummer ist
                    // gewählt, das lässt sich hier nicht zurücknehmen. Der
                    // Dialog geht zu, das Gespräch bleibt, wie es ist — und
                    // über das ⋯ auf der Karte kommt man zurück.
                    onPressed: _laeuft
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Später'),
                  ),
                  FilledButton.icon(
                    onPressed: _laeuft ? null : _zusammen,
                    icon: const Icon(Icons.groups),
                    label: const Text('Zusammenschalten'),
                  ),
                ],
        );
      },
    );
  }

  Widget _teilnehmer({
    required int nummer,
    required String text,
    required String zusatz,
    required MaterialColor farbe,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: F.h(farbe, 100),
          child: Text(
            '$nummer',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: F.h(farbe, 900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          zusatz,
          style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
        ),
      ],
    ),
  );
}
