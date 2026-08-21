import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'anruf_gateway_service.dart';
import 'logger_service.dart';
import '../utils/clipboard_helper.dart';
import '../utils/app_farben.dart';

final _log = LoggerService();

/// Ergebnis eines Wählversuchs. Wird von [PhoneCallService.call] gemeldet,
/// damit Aufrufer bei Bedarf eigenes UI zeigen können — der Standardpfad
/// zeigt die Rückmeldung bereits selbst als SnackBar.
enum PhoneCallOutcome {
  /// Anruf läuft (ACTION_CALL abgesetzt).
  called,

  /// Telefon-App wurde nur geöffnet, der Anruf muss bestätigt werden.
  dialerOpened,

  /// Berechtigung fehlt bzw. wurde verweigert.
  permissionDenied,

  /// Gerät hat keine App, die tel: verarbeitet.
  noDialer,

  /// Aus dem Text ließ sich keine Rufnummer lesen.
  invalidNumber,

  /// Wählversuch fehlgeschlagen.
  failed,

  /// Der Auftrag ging an das Telefon des Vereins und dort läuft der Anruf.
  fernGewaehlt,

  /// Der Auftrag ist beim Telefon, gewählt wurde dort aber noch nicht — es
  /// liegt eine Benachrichtigung, die angetippt werden muss.
  fernLiegtBereit,
}

/// Wählt Telefonnummern aus Behörden-, Arzt- und Mitglieder-Karten direkt.
///
/// Auf Android geht der Anruf über einen nativen `ACTION_CALL`-Intent, d. h.
/// ein Tipp auf die Nummer ruft sofort an — ohne Zwischenschritt im Dialer.
/// Fehlt die `CALL_PHONE`-Berechtigung, fällt die native Seite automatisch
/// auf `ACTION_DIAL` zurück, damit die Nummer nie ins Leere führt.
///
/// Alle anderen Plattformen benutzen `tel:` über url_launcher. Dort ist ein
/// Direktanruf ohne Bestätigung technisch nicht vorgesehen (iOS zeigt immer
/// einen Systemdialog, Desktop reicht an den registrierten Handler weiter).
class PhoneCallService {
  static const _channel = MethodChannel('de.icd360sev.vorsitzer/dialer');

  /// Zeichen, die in einer wählbaren Nummer stehen dürfen.
  static final _dialableChars = RegExp(r'[^0-9+*#]');

  /// Ein zusammenhängender nummernartiger Abschnitt inkl. der üblichen
  /// deutschen Trenner (`0711 / 123 456-78`).
  static final _numberToken = RegExp(r'\+?[0-9][0-9\s\-./]*[0-9]|[0-9]{3,}');

  static final _digits = RegExp(r'[0-9]');

  /// Liest aus einem Anzeigetext die wählbare Rufnummer heraus.
  ///
  /// Verkraftet die Schreibweisen, die in den Behörden-/Arzt-Datensätzen
  /// tatsächlich vorkommen:
  ///
  ///   `0711 / 123 456-78`          → `071112345678`
  ///   `+49 (0)711 123456`          → `+49711123456`   ((0) ist Verkehrsausscheidungsziffer)
  ///   `(0711) 123456`              → `0711123456`     (Klammern = Vorwahl)
  ///   `01806 999 555 10 (20 Ct/Anruf)` → `0180699955510` (Preishinweis fällt weg)
  ///   `Tel. 0711 123456`           → `0711123456`
  ///
  /// Gibt `null` zurück, wenn nichts Wählbares übrig bleibt.
  /// Ersetzt einen trennenden Schrägstrich durch `;`, damit der Tokenizer dort
  /// abbricht — aber nur, wenn davor schon eine vollständige Nummer steht.
  ///
  /// ⚠️ Muss NACH der Klammerauflösung laufen. Andersherum zerlegt der
  /// Schrägstrich in „(20 Ct/Anruf)" den Preishinweis, und übrig bleibt eine
  /// Nummer, die es nie gab. Auf der Serverseite ist genau daran die erste
  /// Fassung von `sipgateNummernAusFeld()` gescheitert.
  static String _mehrfachnummernTrennen(String text) {
    final b = StringBuffer();
    var ziffernSeitGrenze = 0;
    for (final z in text.split('')) {
      if (z == ',' || z == ';' || z == '\n' || z == '\r') {
        b.write(z);
        ziffernSeitGrenze = 0;
        continue;
      }
      if (z == '/') {
        b.write(ziffernSeitGrenze >= 6 ? ';' : ' ');
        if (ziffernSeitGrenze >= 6) ziffernSeitGrenze = 0;
        continue;
      }
      if (_digits.hasMatch(z)) ziffernSeitGrenze++;
      b.write(z);
    }
    return b.toString();
  }

  static String? normalize(String raw) {
    if (raw.trim().isEmpty) return null;

    // Klammerinhalte auflösen: `(0)` ist die wegfallende Null vor der Vorwahl,
    // eine reine Ziffernfolge ist die Vorwahl selbst, alles andere (etwa
    // `(20 Ct/Anruf)`) ist Beiwerk und fliegt raus.
    final unbracketed = raw.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
      final inner = m.group(1)!.trim();
      if (inner == '0') return '';
      if (inner.isNotEmpty && !inner.contains(_dialableChars)) return inner;
      return ' ';
    });

    // ⚠️ Ein Feld kann ZWEI Anschlüsse tragen: „0800 4555500 (AN) / 0731
    // 160900" steht so bei der Agentur für Arbeit Ulm in der Datenbank. Der
    // Schrägstrich ist im `_numberToken` erlaubt (er trennt üblicherweise
    // Vorwahl und Rufnummer), also verschmolzen beide zu einer 21-stelligen
    // Ziffernfolge — und ein Tipp auf die Nummer wählte sie auch.
    //
    // Unterschieden wird nach dem, was DAVOR steht: eine deutsche Vorwahl hat
    // drei bis fünf Stellen, alles ab sechs ist bereits ein vollständiger
    // Anschluss. Steht davor also schon eine Nummer, beginnt hinter dem
    // Schrägstrich eine neue. Der Rest erledigt sich von selbst, weil `;`
    // nicht im `_numberToken` steht und den Abschnitt beendet.
    final getrennt = _mehrfachnummernTrennen(unbracketed);

    // Aus Fließtext („Mo–Fr 8-16 Uhr, Tel 0711 123456") den Abschnitt mit den
    // meisten Ziffern nehmen — Öffnungszeiten und Hausnummern verlieren so
    // gegen die eigentliche Rufnummer.
    String? best;
    var bestDigits = 0;
    for (final m in _numberToken.allMatches(getrennt)) {
      final token = m.group(0)!;
      final count = _digits.allMatches(token).length;
      if (count > bestDigits) {
        bestDigits = count;
        best = token;
      }
    }
    if (best == null) return null;

    // Führendes `+` erhalten, im Rest zählen nur noch Ziffern und die vom
    // Dialer akzeptierten Sonderzeichen.
    final hasPlus = best.trimLeft().startsWith('+');
    final cleaned = best.replaceAll(_dialableChars, '');
    if (cleaned.isEmpty) return null;

    final withoutPlus = cleaned.replaceAll('+', '');
    final digitCount = _digits.allMatches(withoutPlus).length;

    // Kurznummern (110, 112, 116117) sind gültig, aber nur als
    // zusammenhängende Ziffernfolge. Sonst würde „8-16 Uhr" aus einer
    // Öffnungszeit zur Rufnummer 816 zusammenschmelzen und im Ernstfall
    // wirklich gewählt werden.
    final contiguous = !best.contains(RegExp(r'[\s\-./]'));
    if (digitCount < 3) return null;
    if (digitCount < 5 && !contiguous) return null;

    return hasPlus ? '+$withoutPlus' : withoutPlus;
  }

  /// `true`, wenn [raw] überhaupt eine wählbare Nummer enthält.
  static bool isDialable(String? raw) =>
      raw != null && normalize(raw) != null;

  /// Wählt die in [raw] enthaltene Nummer und meldet das Ergebnis per SnackBar.
  ///
  /// [label] erscheint in den Rückmeldungen (z. B. „Jobcenter Stuttgart"),
  /// damit bei einem versehentlichen Tipp sofort sichtbar ist, wen die App
  /// gerade anruft.
  static Future<PhoneCallOutcome> call(
    BuildContext context,
    String raw, {
    String? label,
  }) async {
    final number = normalize(raw);
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (number == null) {
      _log.warning('Nicht wählbar: "$raw"', tag: 'PHONE');
      _show(messenger, 'Keine gültige Rufnummer: $raw', isError: true);
      return PhoneCallOutcome.invalidNumber;
    }

    // Geräte ohne SIM lassen das Vereinstelefon wählen, statt ein `tel:` an
    // irgendeinen Handler zu reichen, den es auf dem Linux-Rechner meistens
    // gar nicht gibt. Notrufe niemals: die löst man nicht in einem Raum aus,
    // in dem niemand steht.
    if (!Platform.isAndroid && !_istNotruf(number) && await AnrufFernwahl.istAktiv()) {
      // Zwischen dem Tipp und dieser Zeile liegt ein await; ist der Bildschirm
      // inzwischen weg, gibt es auch niemanden mehr, dem man den Auflegen-
      // Knopf zeigen könnte.
      if (!context.mounted) {
        return _launchTelUri(messenger, number);
      }
      return _fernwahl(context, messenger, number, label);
    }

    // Sofortige Rückmeldung, noch bevor die Telefon-App den Bildschirm
    // übernimmt — bei Direktwahl ist das die einzige Chance zu sehen, welche
    // Nummer gerade gewählt wurde.
    _show(
      messenger,
      label == null ? 'Ruft an: $number' : 'Ruft an: $label ($number)',
      duration: const Duration(seconds: 3),
    );

    if (!Platform.isAndroid) {
      return _launchTelUri(messenger, number);
    }

    String status;
    try {
      status = await _channel.invokeMethod<String>('call', {'number': number}) ?? 'failed';
    } on MissingPluginException {
      // Ältere Installation ohne den nativen Kanal — tel: tut es auch.
      return _launchTelUri(messenger, number);
    } catch (e) {
      _log.error('Direktwahl fehlgeschlagen ($number): $e', tag: 'PHONE');
      return _launchTelUri(messenger, number);
    }

    switch (status) {
      case 'called':
        _log.info('Anruf gestartet: $number', tag: 'PHONE');
        return PhoneCallOutcome.called;

      case 'dialer_opened':
        _show(messenger, 'Telefon-App geöffnet — Anruf bitte bestätigen.');
        return PhoneCallOutcome.dialerOpened;

      case 'emergency_dialer':
        // Notrufe darf keine App ohne CALL_PRIVILEGED selbst absetzen; die
        // letzte Bestätigung muss im Dialer passieren.
        _show(
          messenger,
          'Notruf $number — bitte in der Telefon-App auf Anrufen tippen.',
          duration: const Duration(seconds: 6),
        );
        return PhoneCallOutcome.dialerOpened;

      case 'permission_denied':
        _show(
          messenger,
          'Ohne Anrufberechtigung muss der Anruf in der Telefon-App bestätigt werden.',
          isError: true,
        );
        return PhoneCallOutcome.permissionDenied;

      case 'permission_denied_permanently':
        _show(
          messenger,
          'Anrufberechtigung dauerhaft abgelehnt. Zum Direktwählen in den '
          'App-Einstellungen unter „Berechtigungen → Telefon" erlauben.',
          isError: true,
          duration: const Duration(seconds: 6),
        );
        return PhoneCallOutcome.permissionDenied;

      case 'no_dialer':
        // Nichts kann wählen — dann wenigstens die Nummer in die Zwischenablage,
        // damit sie von Hand ins Festnetztelefon übernommen werden kann.
        if (context.mounted) {
          ClipboardHelper.copy(context, number, 'Rufnummer');
        } else {
          _show(messenger, 'Keine Telefon-App gefunden. Nummer: $number', isError: true);
        }
        return PhoneCallOutcome.noDialer;

      case 'cancelled':
        return PhoneCallOutcome.failed;

      case 'invalid_number':
        _show(messenger, 'Keine gültige Rufnummer: $raw', isError: true);
        return PhoneCallOutcome.invalidNumber;

      default:
        _show(messenger, 'Anruf konnte nicht gestartet werden.', isError: true);
        return PhoneCallOutcome.failed;
    }
  }

  /// Notrufe. Dieselbe Liste wie in `MainActivity.isEmergencyNumber`,
  /// `IcdAnrufPlugin` und `anruf/queue.php` — bewusst ohne 115 und 116117,
  /// die keine Notrufe sind.
  static const _notrufe = {'110', '112', '911', '999'};

  static bool _istNotruf(String number) =>
      _notrufe.contains(number.replaceAll(RegExp(r'\D'), ''));

  /// Lässt das Vereinstelefon wählen und begleitet den Auftrag bis zur
  /// Rückmeldung.
  ///
  /// Die Zwischenstände sind kein Zierrat: zwischen Klick und Klingeln liegen
  /// der Takt des Telefons und ein Netzweg. Ohne sichtbaren Fortschritt hält
  /// der Vorsitzer den Klick für verloren und klickt noch dreimal.
  static Future<PhoneCallOutcome> _fernwahl(
    BuildContext context,
    ScaffoldMessengerState? messenger,
    String number,
    String? label,
  ) async {
    final wen = label == null ? number : '$label ($number)';
    _show(messenger, 'Auftrag ans Vereinstelefon: $wen',
        duration: const Duration(seconds: 20));

    final ergebnis = await AnrufFernwahl.waehlenLassen(
      number,
      bezeichnung: label,
      melde: (text) => _show(messenger, '$text ($wen)',
          duration: const Duration(seconds: 20)),
    );

    switch (ergebnis.stand) {
      case AnrufFernStand.gewaehlt:
        _log.info('Fernwahl läuft: $number', tag: 'PHONE');
        // Kein SnackBar: der kommt nach vier Sekunden weg, ein Gespräch dauert
        // Minuten. Solange es läuft, soll der Auflegen-Knopf erreichbar sein,
        // ohne dass jemand zum Telefon greifen muss.
        if (context.mounted) {
          unawaited(_zeigeGespraechDialog(context, wen));
        } else {
          _show(messenger, 'Das Vereinstelefon ruft an: $wen');
        }
        return PhoneCallOutcome.fernGewaehlt;

      case AnrufFernStand.liegtAmTelefon:
        _log.warning('Fernwahl liegt am Telefon: ${ergebnis.meldung}', tag: 'PHONE');
        _show(messenger, ergebnis.meldung, duration: const Duration(seconds: 8));
        return PhoneCallOutcome.fernLiegtBereit;

      case AnrufFernStand.schlaeft:
        // Kein Fehlschlag: das Telefon läuft nachweislich und wählt, sobald es
        // aufwacht. Deshalb auch KEIN tel:-Rückfall — der würde hier zu einem
        // zweiten Anruf führen, sobald das Telefon dran ist.
        _log.info('Fernwahl wartet auf Aufwachen: ${ergebnis.meldung}', tag: 'PHONE');
        _show(messenger, ergebnis.meldung, duration: const Duration(seconds: 10));
        return PhoneCallOutcome.fernLiegtBereit;

      case AnrufFernStand.keinGeraet:
      case AnrufFernStand.fehler:
      case AnrufFernStand.nichtGesendet:
        _log.error('Fernwahl gescheitert: ${ergebnis.meldung}', tag: 'PHONE');
        _show(messenger, ergebnis.meldung, isError: true,
            duration: const Duration(seconds: 8));
        // Der lokale Weg bleibt als Rückfalltür offen: gibt es auf diesem
        // Rechner doch einen tel:-Handler (Softphone), soll der Klick nicht
        // vollends folgenlos bleiben.
        return _launchTelUri(messenger, number);
    }
  }

  /// Begleitet das laufende Gespräch und bietet das Auflegen an.
  ///
  /// Bewusst ein Dialog und kein SnackBar: der verschwindet nach Sekunden, ein
  /// Gespräch dauert Minuten. Wer vom Rechner aus anrufen kann, soll von dort
  /// auch beenden können, ohne zum Telefon zu greifen.
  static Future<void> _zeigeGespraechDialog(BuildContext context, String wen) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        var legtAuf = false;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            icon: Icon(Icons.phone_in_talk, color: F.h(Colors.green, 700), size: 32),
            title: const Text('Das Vereinstelefon ruft an'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(wen, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(
                  // Nicht verschweigen: gesprochen wird am Telefon. Wer das
                  // hier zum ersten Mal benutzt, sucht sonst am Rechner nach
                  // einem Mikrofon, das es nie geben wird.
                  'Gesprochen wird am Telefon — der Rechner kann den Ton eines '
                  'Mobilfunkgesprächs nicht übernehmen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700), height: 1.4),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: legtAuf ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Schließen'),
              ),
              FilledButton.icon(
                onPressed: legtAuf
                    ? null
                    : () async {
                        setState(() => legtAuf = true);
                        final e = await AnrufFernwahl.auflegenLassen();
                        if (!ctx.mounted) return;
                        Navigator.of(dialogContext).pop();
                        _show(
                          ScaffoldMessenger.maybeOf(context),
                          e.meldung,
                          isError: !e.erfolgreich,
                          duration: const Duration(seconds: 6),
                        );
                      },
                icon: legtAuf
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.call_end, size: 18),
                label: Text(legtAuf ? 'Legt auf…' : 'Auflegen'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<PhoneCallOutcome> _launchTelUri(
    ScaffoldMessengerState? messenger,
    String number,
  ) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      if (await launchUrl(uri)) {
        _log.info('tel: gestartet: $number', tag: 'PHONE');
        return PhoneCallOutcome.dialerOpened;
      }
    } catch (e) {
      _log.error('tel: fehlgeschlagen ($number): $e', tag: 'PHONE');
    }
    _show(
      messenger,
      'Auf diesem Gerät ist keine Telefon-App eingerichtet. Nummer: $number',
      isError: true,
      duration: const Duration(seconds: 5),
    );
    return PhoneCallOutcome.noDialer;
  }

  static void _show(
    ScaffoldMessengerState? messenger,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }
}
