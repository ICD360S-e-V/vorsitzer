import 'package:flutter/material.dart';

import '../utils/mail_echtheit.dart';

/// Zeigt, was der eigene Server über die Herkunft dieser Nachricht weiß.
///
/// ⚠️ Die Karte erscheint **nicht immer**. Ein grünes Häkchen an jeder Mail
/// wird nach drei Tagen zu Tapete, und dann fällt auch das rote nicht mehr auf.
/// Gezeigt wird nur, was eine Entscheidung ändern könnte:
///
/// * eine Prüfung ist durchgefallen,
/// * oder der angezeigte Name passt nicht zur Adresse,
/// * oder der Server hat gar nichts geprüft.
///
/// Ist alles in Ordnung, steht dort eine einzige unauffällige Zeile.
class MailEchtheitKarte extends StatelessWidget {
  /// Der rohe `From`-Kopf, mit Anzeigename.
  final String von;

  /// Der `Authentication-Results`-Kopf unseres Servers.
  final String? authResults;

  const MailEchtheitKarte({super.key, required this.von, this.authResults});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = mailEchtheitLesen(authResults);
    final verdacht = mailAbsenderVerdacht(von);

    final schlimm = e.istGescheitert || verdacht != MailVerdacht.keiner;
    if (!schlimm && e.istBestaetigt) return _zeile(cs, e);
    if (!schlimm && !e.hatBefund) return _ungeprueft(cs);
    if (!schlimm) return _zeile(cs, e);

    final farbe = e.istGescheitert ? const Color(0xFFB3261E) : const Color(0xFFE08A00);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.10),
        border: Border.all(color: farbe.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe_outlined, size: 20, color: farbe),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.istGescheitert
                      ? 'Herkunft konnte nicht bestätigt werden'
                      : 'Absender prüfen',
                  style: TextStyle(fontWeight: FontWeight.w700, color: farbe),
                ),
              ),
            ],
          ),
          if (verdacht != MailVerdacht.keiner) ...[
            const SizedBox(height: 6),
            Text(mailVerdachtText(verdacht),
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            _adressvergleich(cs),
          ],
          if (e.istGescheitert) ...[
            const SizedBox(height: 6),
            Text(
              'Der absendende Server hat sich nicht ausweisen können: '
              '${_befundText(e)}. Das heißt nicht zwingend Betrug — aber bei '
              'einer Aufforderung zu zahlen, ein Kennwort zu nennen oder etwas '
              'zu öffnen, gehört hier ein Anruf dazwischen.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  /// Name und wirkliche Adresse untereinander — die Gegenüberstellung ist das
  /// Argument, nicht der Satz darüber.
  Widget _adressvergleich(ColorScheme cs) {
    final t = mailAbsenderTeile(von);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paar(cs, 'angezeigt', t.name),
          const SizedBox(height: 2),
          _paar(cs, 'wirklich', t.adresse, fett: true),
        ],
      ),
    );
  }

  Widget _paar(ColorScheme cs, String k, String v, {bool fett = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(k,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(v,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: fett ? FontWeight.w700 : FontWeight.normal)),
          ),
        ],
      );

  /// Der ruhige Fall: eine Zeile, kein Kasten.
  Widget _zeile(ColorScheme cs, MailEchtheit e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, size: 15, color: Color(0xFF2E7D32)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.dkimDomain.isNotEmpty
                    ? 'Herkunft bestätigt (${e.dkimDomain})'
                    : 'Herkunft bestätigt',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  /// Kein Befund. Das ist kein Verdacht — aber es soll auch nicht wie ein
  /// bestandener Test aussehen.
  Widget _ungeprueft(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Herkunft nicht geprüft',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      );

  String _befundText(MailEchtheit e) {
    final teile = <String>[];
    if (e.dkim == MailPruefwert.gescheitert) teile.add('DKIM');
    if (e.spf == MailPruefwert.gescheitert) teile.add('SPF');
    if (e.dmarc == MailPruefwert.gescheitert) teile.add('DMARC');
    return teile.isEmpty ? 'die Prüfung schlug fehl' : '${teile.join(' und ')} fehlgeschlagen';
  }
}
