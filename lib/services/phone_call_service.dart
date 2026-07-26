import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'logger_service.dart';
import '../utils/clipboard_helper.dart';

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

    // Aus Fließtext („Mo–Fr 8-16 Uhr, Tel 0711 123456") den Abschnitt mit den
    // meisten Ziffern nehmen — Öffnungszeiten und Hausnummern verlieren so
    // gegen die eigentliche Rufnummer.
    String? best;
    var bestDigits = 0;
    for (final m in _numberToken.allMatches(unbracketed)) {
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
