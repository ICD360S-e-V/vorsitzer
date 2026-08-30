import 'package:flutter/material.dart';

import '../models/mail_models.dart';
import '../services/api_service.dart';
import 'mail_delivery_indicator.dart';
import 'terminanfrage_versand_dialog.dart';
import '../utils/app_farben.dart';

/// Der Zustellstand der Anfrage-Mail, direkt an der Korrespondenzzeile.
///
/// WOFÜR
/// „Gesendet" heißt nur, dass unser Server die Nachricht übernommen hat. Ob
/// der ZIELSERVER sie angenommen hat, steht erst Sekunden bis Minuten später
/// im Postfix-Log — und eine Ablehnung (`554`, Adresse existiert nicht, voller
/// Briefkasten) kommt genau dort an, nirgends sonst. Wer sich auf „gesendet"
/// verlässt, wartet auf einen Termin, um den nie jemand gebeten wurde.
///
/// ⚠️ Der grüne Haken erscheint nur bei einer 2.x.x-Antwort des Zielservers,
/// nicht beim Absenden. Das ist die Zusage, die im Streitfall etwas wert ist.
///
/// ⚠️ Ein fehlgeschlagener Abruf ist KEIN Zustellfehler. Fällt die Abfrage aus,
/// bleibt der Stand „unbekannt" — niemals rot und niemals grün. Dieselbe Regel
/// wie im Mailschirm.
///
/// ⚠️ Wo weder Message-ID noch Faxzeile vorliegt, zeigt dieses Widget NICHTS
/// an, statt einen leeren Status vorzutäuschen.
///
/// FAX (seit 30.08.2026)
/// Vorher stand hier „NUR für E-Mails": ein Fax hat keine Message-ID. Es hat
/// aber eine Zeile in `sipgate_faxe`, und deren `id` liefert `sipgateFaxAction`
/// beim Senden mit. Damit ist der Weg nachfassbar — `action: 'stand'` fragt
/// bei sipgate nach und gibt `zugestellt` / `fehlgeschlagen` /
/// `in_zustellung` / `vorbereitet` / `storniert` zurück.
///
/// ⚠️ Bei einem Fax ist „besetzt" der Normalfall bei Behörden und Praxen, und
/// ein fehlgeschlagenes Fax sieht ohne diese Zeile genauso aus wie ein
/// zugestelltes: es steht in der Korrespondenz, und das war's.
///
/// ⚠️ Nachgefasst wird NUR, solange der Stand nicht endgültig ist. `stand`
/// ruft sipgate wirklich an; ein zugestelltes Fax noch einmal abzufragen
/// kostet einen Fremdaufruf und kann sein Ergebnis nicht mehr ändern.
class TerminanfrageZustellung extends StatefulWidget {
  /// Die Notizen des Termins — dort steht die Message-ID.
  ///
  /// ⚠️ Nur der Weg der ARZT-Tabs: deren Terminzeile hat feste Spalten und
  /// kein Feld für die Id, also reist sie in den Notizen mit. Wer die Id
  /// ohnehin einzeln vorliegen hat, gibt sie über [messageId] — dann muss
  /// niemand eine Notiz zusammenbauen, nur damit dieses Widget sie wieder
  /// auseinandernimmt.
  final String? notizen;

  /// Die Message-ID direkt. Hat Vorrang vor [notizen].
  final String? messageId;

  /// Unsere Zeile in `sipgate_faxe` — beim Senden als `id` zurückgegeben.
  ///
  /// ⚠️ NICHT die sipgate-Sitzungsnummer: mit der lässt sich der Stand nicht
  /// abfragen, sie steht nur im Sendebericht.
  final int? faxId;

  /// Der zuletzt bekannte Faxstand, falls er schon an der Zeile steht. Ist er
  /// endgültig, wird gar nicht erst nachgefasst.
  final String? faxStatus;

  /// Nur bei ausgehender Post sinnvoll; sonst wird nichts gezeigt.
  final String art;
  final String richtung;

  /// Als schmale Pastille statt als beschriftete Zeile — für die Zeile in der
  /// Korrespondenzliste, wo neben Datum und Betreff kein Platz für „Zustellung:
  /// …" ist.
  ///
  /// ⚠️ Auch kompakt wird nachgefasst. Das kostet je offener Zeile einen
  /// Aufruf; ein Termin trägt aber typischerweise ein bis drei Schreiben, und
  /// der Sinn der Anzeige ist gerade, dass man NICHT jede Zeile einzeln
  /// aufmachen muss, um zu sehen, ob etwas angekommen ist.
  final bool kompakt;

  final ApiService apiService;

  const TerminanfrageZustellung({
    super.key,
    this.notizen,
    this.messageId,
    this.faxId,
    this.faxStatus,
    this.kompakt = false,
    required this.art,
    required this.richtung,
    required this.apiService,
  });

  @override
  State<TerminanfrageZustellung> createState() =>
      _TerminanfrageZustellungState();
}

/// Ist dieser Faxstand endgültig? Nur dann hört das Nachfassen auf.
///
/// ⚠️ Wörtlich dieselbe Liste wie `sipgateFaxEndgueltig()` in
/// `api/sipgate/sipgate_fax_lib.php`. Wird sie dort erweitert, ohne dass es
/// hier ankommt, fragt die App einen fertigen Vorgang bis in alle Ewigkeit
/// nach.
const Set<String> kFaxEndgueltig = {
  'zugestellt',
  'fehlgeschlagen',
  'storniert',
};

/// Wie ein Faxstand am Menschen ankommt.
const Map<String, String> kFaxStandLabel = {
  'zugestellt': 'Zugestellt',
  'fehlgeschlagen': 'Fehlgeschlagen',
  'in_zustellung': 'Unterwegs',
  'vorbereitet': 'Vorbereitet',
  'storniert': 'Storniert',
  'verfallen': 'Verfallen',
};

class _TerminanfrageZustellungState extends State<TerminanfrageZustellung> {
  MailDelivery? _stand;
  bool _laeuft = false;

  /// Der Faxstand: erst der mitgegebene, dann der nachgefasste.
  String _faxStand = '';
  String _faxGrund = '';

  String get _id {
    final direkt = (widget.messageId ?? '').trim();
    return direkt.isEmpty ? terminZustellungMessageId(widget.notizen) : direkt;
  }

  bool get _mailZutreffend =>
      widget.art == 'email' && widget.richtung == 'ausgehend' && _id.isNotEmpty;

  bool get _faxZutreffend =>
      widget.art == 'fax' &&
      widget.richtung == 'ausgehend' &&
      (widget.faxId ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_mailZutreffend) _holen();
    if (_faxZutreffend) {
      _faxStand = (widget.faxStatus ?? '').trim();
      // ⚠️ Nur nachfassen, solange offen. `stand` ruft sipgate wirklich an;
      // ein zugestelltes Fax noch einmal zu fragen kostet einen Fremdaufruf
      // und kann sein Ergebnis nicht mehr ändern.
      if (!kFaxEndgueltig.contains(_faxStand)) _faxHolen();
    }
  }

  Future<void> _faxHolen() async {
    if (_laeuft) return;
    _laeuft = true;
    try {
      final res = await widget.apiService
          .sipgateFaxAction({'action': 'stand', 'id': widget.faxId});
      if (!mounted) return;
      if (res['success'] == true) {
        final st = (res['status'] ?? '').toString();
        if (st.isNotEmpty) {
          setState(() {
            _faxStand = res['verfallen'] == true && !kFaxEndgueltig.contains(st)
                ? 'verfallen'
                : st;
            _faxGrund = (res['fehler'] ?? '').toString();
          });
        }
      }
    } catch (_) {
      // Kein Zustellfehler — nur keine Auskunft. Der zuletzt bekannte Stand
      // bleibt stehen; niemals wird daraus „fehlgeschlagen". Siehe ⚠️ oben.
    } finally {
      _laeuft = false;
    }
  }

  Future<void> _holen() async {
    if (_laeuft) return;
    _laeuft = true;
    try {
      final res = await widget.apiService.getMailDelivery([_id]);
      if (!mounted) return;
      if (res['delivery'] is Map) {
        final roh = Map<String, dynamic>.from(res['delivery'] as Map);
        final d = roh[_id];
        if (d is Map) {
          setState(() =>
              _stand = MailDelivery.fromJson(Map<String, dynamic>.from(d)));
        }
      }
    } catch (_) {
      // Kein Zustellfehler — nur keine Auskunft. Siehe ⚠️ oben.
    } finally {
      _laeuft = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kompakt) return _pastille();
    if (_faxZutreffend) return _faxZeile();
    if (!_mailZutreffend || _stand == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 24,
          child: Icon(Icons.outbox, size: 16, color: F.h(Colors.grey, 600)),
        ),
        SizedBox(
          width: 110,
          child: Text('Zustellung',
              style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 700))),
        ),
        Expanded(
          child: MailDeliveryIndicator(delivery: _stand!, showLabel: true),
        ),
      ]),
    );
  }

  /// Die schmale Form für die Korrespondenzliste.
  ///
  /// ⚠️ Solange nichts bekannt ist, steht hier NICHTS — kein graues
  /// „unbekannt". Eine Pastille an jeder Zeile, die nur sagt „weiß ich nicht",
  /// macht die eine Zeile unauffindbar, an der wirklich etwas schiefging.
  Widget _pastille() {
    final (MaterialColor farbe, IconData symbol, String text) = () {
      if (_faxZutreffend && _faxStand.isNotEmpty) {
        return switch (_faxStand) {
          'zugestellt' => (Colors.green, Icons.check_circle, 'Zugestellt'),
          'fehlgeschlagen' => (Colors.red, Icons.error, 'Fehlgeschlagen'),
          'storniert' || 'verfallen' => (Colors.grey, Icons.cancel,
              kFaxStandLabel[_faxStand] ?? _faxStand),
          _ => (Colors.blue, Icons.schedule, 'Unterwegs'),
        };
      }
      if (_mailZutreffend && _stand != null) {
        // ⚠️ Grün NUR bei `sent`, also einer 2.x.x-Zusage des Zielservers.
        // „Von unserem Server übernommen" ist keine Zustellung — genau diese
        // Unterscheidung ist der Grund, warum es dieses Widget gibt.
        //
        // ⚠️ `deferred` ist NICHT rot: Postfix versucht es weiter, und ein
        // rotes „fehlgeschlagen" an einer Mail, die zwanzig Minuten später
        // ankommt, führt dazu, dass jemand ein zweites Mal schreibt.
        return switch (_stand!.state) {
          MailDeliveryState.sent =>
            (Colors.green, Icons.check_circle, 'Zugestellt'),
          MailDeliveryState.bounced => (Colors.red, Icons.error, 'Abgelehnt'),
          MailDeliveryState.queued ||
          MailDeliveryState.deferred =>
            (Colors.blue, Icons.schedule, 'Unterwegs'),
          _ => (Colors.grey, Icons.help_outline, ''),
        };
      }
      return (Colors.grey, Icons.help_outline, '');
    }();

    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: F.h(farbe, 100),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(farbe, 300)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(symbol, size: 11, color: F.h(farbe, 700)),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: F.h(farbe, 800))),
      ]),
    );
  }

  /// Derselbe Zeilenaufbau wie beim Mailstand, damit beide Wege an derselben
  /// Stelle stehen und gleich zu lesen sind.
  Widget _faxZeile() {
    if (_faxStand.isEmpty) return const SizedBox.shrink();
    final (farbe, symbol) = switch (_faxStand) {
      'zugestellt' => (Colors.green, Icons.check_circle),
      'fehlgeschlagen' => (Colors.red, Icons.error),
      'storniert' || 'verfallen' => (Colors.grey, Icons.cancel),
      _ => (Colors.blue, Icons.schedule),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 24,
          child: Icon(Icons.outbox, size: 16, color: F.h(Colors.grey, 600)),
        ),
        SizedBox(
          width: 110,
          child: Text('Zustellung',
              style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 700))),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(symbol, size: 15, color: F.h(farbe, 700)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(kFaxStandLabel[_faxStand] ?? _faxStand,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: F.h(farbe, 800))),
                ),
              ]),
              // ⚠️ Der Grund gehört DAZU. „Fehlgeschlagen" allein sagt nicht,
              // ob die Gegenstelle besetzt war (dann noch einmal senden) oder
              // die Nummer falsch ist (dann nützt kein zweiter Versuch).
              if (_faxGrund.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_faxGrund,
                      style: TextStyle(
                          fontSize: 11, color: F.h(Colors.grey, 700))),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
