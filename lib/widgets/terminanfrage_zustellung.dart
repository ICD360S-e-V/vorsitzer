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
/// ⚠️ NUR für E-Mails. Ein Fax hat keine Message-ID; seinen Weg verfolgt der
/// sipgate-Sendebericht, und die Sitzungsnummer dafür steht in derselben
/// Notiz. Wo keine Message-ID liegt, zeigt dieses Widget nichts an, statt
/// einen leeren Status vorzutäuschen.
class TerminanfrageZustellung extends StatefulWidget {
  /// Die Notizen des Termins — dort steht die Message-ID.
  final String? notizen;

  /// Nur bei ausgehender E-Mail sinnvoll; sonst wird nichts gezeigt.
  final String art;
  final String richtung;

  final ApiService apiService;

  const TerminanfrageZustellung({
    super.key,
    required this.notizen,
    required this.art,
    required this.richtung,
    required this.apiService,
  });

  @override
  State<TerminanfrageZustellung> createState() =>
      _TerminanfrageZustellungState();
}

class _TerminanfrageZustellungState extends State<TerminanfrageZustellung> {
  MailDelivery? _stand;
  bool _laeuft = false;

  String get _id => terminZustellungMessageId(widget.notizen);

  bool get _zutreffend =>
      widget.art == 'email' && widget.richtung == 'ausgehend' && _id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_zutreffend) _holen();
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
    if (!_zutreffend || _stand == null) return const SizedBox.shrink();
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
}
