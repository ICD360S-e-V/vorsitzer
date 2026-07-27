import 'dart:io';

import 'package:flutter/services.dart';

import 'logger_service.dart';
import 'phone_call_service.dart';

final _log = LoggerService();

/// Warum eine hinterlegte Nummer nicht per SMS erreichbar ist.
enum SmsNumberIssue {
  /// Nummer ist da und sieht nach Mobilfunk aus.
  none,

  /// In Verifizierung Stufe 1 wurde keine Telefonnummer erfasst.
  missing,

  /// Deutsche Festnetznummer. SMS ins Festnetz gibt es nicht mehr — Telekom
  /// und Vodafone haben den Dienst im März 2023 abgeschaltet, Anny Way im
  /// Dezember 2023. Eine SMS dorthin verschwindet kommentarlos.
  landline,

  /// Aus dem Feld ließ sich überhaupt keine Rufnummer lesen.
  invalid,
}

/// Prüfergebnis für die Telefonnummer eines Mitglieds.
class SmsNumberCheck {
  final String? e164;
  final SmsNumberIssue issue;

  /// Ausländische Nummer — Mobilfunk lässt sich hier nicht zuverlässig von
  /// Festnetz unterscheiden, die SMS geht trotzdem raus.
  final bool unverifiedForeign;

  const SmsNumberCheck._(this.e164, this.issue, {this.unverifiedForeign = false});

  bool get canSend => issue == SmsNumberIssue.none;

  String get label {
    switch (issue) {
      case SmsNumberIssue.none:
        return unverifiedForeign ? '$e164 (Ausland)' : e164 ?? '';
      case SmsNumberIssue.missing:
        return 'keine Nummer in Stufe 1';
      case SmsNumberIssue.landline:
        return 'Festnetz — keine SMS möglich';
      case SmsNumberIssue.invalid:
        return 'Nummer unlesbar';
    }
  }
}

/// Ergebnis eines Sendeversuchs.
enum SmsSendOutcome {
  sent,

  /// Abgeschickt, aber das Netz hat den Sendestatus nicht zurückgemeldet.
  /// Wird wie Erfolg behandelt, sonst würde die Warteschlange ewig wiederholen.
  sentUnconfirmed,

  permissionDenied,

  /// Der SMS-Schalter ist bei sideloaded APKs gesperrt, bis einmalig
  /// „Eingeschränkte Einstellungen zulassen" bestätigt wurde.
  permissionRestricted,

  /// Gerät ohne SIM/Mobilfunk (Desktop, WLAN-Tablet).
  notSupported,

  noService,
  radioOff,
  invalidNumber,
  failed,
}

extension SmsSendOutcomeX on SmsSendOutcome {
  bool get isSuccess =>
      this == SmsSendOutcome.sent || this == SmsSendOutcome.sentUnconfirmed;

  /// Lohnt ein späterer neuer Versuch? Bei fehlender Berechtigung oder
  /// kaputter Nummer nicht — das ändert sich nicht von allein.
  bool get isRetryable =>
      this == SmsSendOutcome.noService ||
      this == SmsSendOutcome.radioOff ||
      this == SmsSendOutcome.failed;

  String get message {
    switch (this) {
      case SmsSendOutcome.sent:
        return 'SMS versendet';
      case SmsSendOutcome.sentUnconfirmed:
        return 'SMS abgeschickt (Sendebericht ausgeblieben)';
      case SmsSendOutcome.permissionDenied:
        return 'SMS-Berechtigung fehlt';
      case SmsSendOutcome.permissionRestricted:
        return 'SMS gesperrt: App-Info → ⋮ → „Eingeschränkte Einstellungen zulassen"';
      case SmsSendOutcome.notSupported:
        return 'Gerät kann keine SMS senden';
      case SmsSendOutcome.noService:
        return 'Kein Mobilfunknetz';
      case SmsSendOutcome.radioOff:
        return 'Flugmodus aktiv';
      case SmsSendOutcome.invalidNumber:
        return 'Rufnummer ungültig';
      case SmsSendOutcome.failed:
        return 'SMS fehlgeschlagen';
    }
  }
}

/// Verschickt Termin-Erinnerungen als SMS über die SIM des Vereins-Tablets.
///
/// Nur Android: auf Desktop/Linux gibt es kein Mobilfunkmodem, dort bleibt es
/// bei der Chat-Erinnerung. Zielnummern sind ausschließlich Mobilfunknummern
/// (siehe [SmsNumberIssue.landline]).
class SmsService {
  static const _channel = MethodChannel('de.icd360sev.vorsitzer/sms');

  /// Deutsche Mobilfunk-Netzkennzahlen beginnen national mit 015/016/017.
  static final _deMobile = RegExp(r'^\+491[567]');

  static bool get isSupportedPlatform => Platform.isAndroid;

  /// Kann dieses Gerät gerade SMS verschicken? Fragt Modem **und**
  /// Berechtigung ab, ohne einen Permission-Dialog auszulösen.
  static Future<({bool messaging, bool permission})> capabilities() async {
    if (!isSupportedPlatform) return (messaging: false, permission: false);
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      return (
        messaging: raw?['messaging'] == true,
        permission: raw?['permission'] == true,
      );
    } on MissingPluginException {
      return (messaging: false, permission: false);
    } catch (e) {
      _log.debug('SMS-capabilities fehlgeschlagen: $e', tag: 'SMS');
      return (messaging: false, permission: false);
    }
  }

  // =========================================================================
  // RUFNUMMERN
  // =========================================================================

  /// Prüft die in Verifizierung Stufe 1 hinterlegte Nummer und bringt sie in
  /// E.164-Form (`+49176…`).
  ///
  ///   `0176 1234567`      → `+491761234567`
  ///   `0049 176 1234567`  → `+491761234567`
  ///   `+49 (0)176 1234567`→ `+491761234567`
  ///   `0711 123456`       → Festnetz, wird abgelehnt
  static SmsNumberCheck check(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const SmsNumberCheck._(null, SmsNumberIssue.missing);
    }

    // PhoneCallService kennt bereits die Schreibweisen aus den Datensätzen
    // (Klammern, Schrägstriche, „Tel." davor).
    final cleaned = PhoneCallService.normalize(raw);
    if (cleaned == null) {
      return const SmsNumberCheck._(null, SmsNumberIssue.invalid);
    }

    var digits = cleaned.replaceAll(RegExp(r'[^0-9+]'), '');
    String e164;
    if (digits.startsWith('+')) {
      e164 = digits;
    } else if (digits.startsWith('00')) {
      e164 = '+${digits.substring(2)}';
    } else if (digits.startsWith('0')) {
      // Nationale Schreibweise — Verein sitzt in Deutschland.
      e164 = '+49${digits.substring(1)}';
    } else {
      return const SmsNumberCheck._(null, SmsNumberIssue.invalid);
    }

    // `+49 (0)176` → die Verkehrsausscheidungsziffer fällt hinter der
    // Ländervorwahl weg.
    if (e164.startsWith('+490')) {
      e164 = '+49${e164.substring(4)}';
    }

    final bare = e164.substring(1);
    if (bare.length < 8 || bare.length > 15) {
      return const SmsNumberCheck._(null, SmsNumberIssue.invalid);
    }

    if (e164.startsWith('+49')) {
      if (!_deMobile.hasMatch(e164)) {
        return SmsNumberCheck._(e164, SmsNumberIssue.landline);
      }
      // 49 + Netzkennzahl (3) + mindestens 6 Teilnehmerziffern. Ohne diese
      // Untergrenze käme ein Tippfehler wie "0176 123" als gültige Nummer
      // durch und die SMS verschwände im Nichts.
      if (bare.length < 11) {
        return SmsNumberCheck._(e164, SmsNumberIssue.invalid);
      }
      return SmsNumberCheck._(e164, SmsNumberIssue.none);
    }

    // Ausland: Mobilfunk ist ohne Nummernplan-Datenbank nicht erkennbar.
    return SmsNumberCheck._(e164, SmsNumberIssue.none, unverifiedForeign: true);
  }

  // =========================================================================
  // TEXT
  // =========================================================================

  /// Zeichen außerhalb des GSM-7-Alphabets zwingen die ganze SMS in UCS-2 —
  /// dann passen statt 160 nur noch 70 Zeichen in ein Segment. Umlaute und ß
  /// sind in GSM-7 enthalten und bleiben, Emoji und typografische Sonder-
  /// zeichen werden ersetzt.
  static String toGsm7(String input) {
    const map = {
      '‘': "'", '’': "'", '‚': "'", '‹': "'", '›': "'",
      '“': '"', '”': '"', '„': '"', '«': '"', '»': '"',
      '–': '-', '—': '-', '−': '-', '‑': '-',
      '…': '...', ' ': ' ', ' ': ' ', ' ': ' ',
      '€': 'EUR', '•': '-', '·': '-', '°': ' Grad', '™': '', '®': '', '©': '',
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'û': 'u',
      'ș': 's', 'ş': 's', 'ț': 't', 'ţ': 't', 'ă': 'a',
      'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'ł': 'l', 'ń': 'n',
      'İ': 'I', 'ı': 'i', 'ğ': 'g', 'Ğ': 'G', 'Ş': 'S',
      // Großbuchstaben eigens: Namen und Orte stehen oft am Satzanfang, und
      // ohne diese Zeilen würde aus „Ședință" ein „?edinta".
      'Ș': 'S', 'Ț': 'T', 'Ţ': 'T', 'Ă': 'A', 'Â': 'A', 'Î': 'I',
      'Á': 'A', 'À': 'A', 'Ã': 'A', 'Å': 'A', 'Ê': 'E', 'Ë': 'E', 'È': 'E',
      'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Č': 'C', 'Ć': 'C', 'Š': 'S', 'Ž': 'Z',
      'Ł': 'L', 'Ń': 'N',
    };

    // GSM 03.38 Basis- und Erweiterungstabelle, soweit für uns relevant.
    const allowed =
        '@£\$¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
        '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
        '\n\r'
        '^{}[]~|\\€';

    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = map[ch];
      if (mapped != null) {
        out.write(mapped);
        continue;
      }
      if (allowed.contains(ch)) {
        out.write(ch);
        continue;
      }
      // Alles Übrige (Emoji, kyrillisch, arabisch …) würde UCS-2 erzwingen.
      // Buchstabenähnliches wird zu '?', reine Symbole fallen weg.
      if (RegExp(r'\p{L}|\p{N}', unicode: true).hasMatch(ch)) out.write('?');
    }
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  /// Segmente, die das Netz für [text] berechnet — jedes Segment kostet.
  static int segments(String text) {
    if (text.isEmpty) return 0;
    // Erweiterungszeichen (^{}[]~|\€) zählen doppelt.
    const extended = r'^{}[]~|\€';
    var len = 0;
    for (final rune in text.runes) {
      len += extended.contains(String.fromCharCode(rune)) ? 2 : 1;
    }
    if (len <= 160) return 1;
    return (len / 153).ceil();
  }

  /// Baut die Erinnerungs-SMS. Bewusst ohne Emoji und so knapp, dass sie in
  /// ein einziges Segment passt — der Chat-Text bleibt die ausführliche
  /// Fassung, die SMS ist nur der Anstupser.
  static String buildTerminSms({
    required DateTime terminDate,
    required String title,
    required String location,
    String? absender,
  }) {
    // Bewusst ohne DateFormat: im WorkManager-Isolat läuft keine MaterialApp,
    // die die deutschen Datums-Symbole lädt — `DateFormat(..., 'de')` würfe
    // dort LocaleDataException und die automatische Erinnerung bliebe aus.
    String zwei(int v) => v.toString().padLeft(2, '0');
    const wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final tag = '${wochentage[terminDate.weekday - 1]} '
        '${zwei(terminDate.day)}.${zwei(terminDate.month)}.${terminDate.year}';
    final uhr = '${zwei(terminDate.hour)}:${zwei(terminDate.minute)}';
    final head = '${absender ?? 'ICD360S e.V.'}: Terminerinnerung $tag, $uhr Uhr';
    const tail = 'Bitte Teilnahme bestaetigen.';

    // Was nach Kopf und Schluss noch in ein Segment passt, teilen sich Ort
    // und Betreff — der Ort zuerst, ohne ihn nützt die SMS am wenigsten.
    var budget = 160 - toGsm7('$head. $tail').length;
    final parts = <String>[];

    final ort = toGsm7(location.trim());
    if (ort.isNotEmpty && budget > 8) {
      final text = _fit('Ort: $ort', budget - 2);
      if (text != null) {
        parts.add(text);
        budget -= text.length + 2;
      }
    }

    final betreff = toGsm7(title.trim());
    if (betreff.isNotEmpty && budget > 12) {
      final text = _fit('Betreff: $betreff', budget - 2);
      if (text != null) parts.add(text);
    }

    return toGsm7([head, ...parts, tail].join('. '));
  }

  /// Kürzt [text] auf [max] Zeichen, aber nur wenn danach noch etwas
  /// Verständliches übrig bleibt.
  static String? _fit(String text, int max) {
    if (max < 12) return null;
    if (text.length <= max) return text;
    return '${text.substring(0, max - 3).trimRight()}...';
  }

  // =========================================================================
  // SENDEN
  // =========================================================================

  /// Verschickt [text] an [number] (E.164). Wartet auf den Sendebericht des
  /// Netzes, damit die Warteschlange nur echte Zustellungen abhakt.
  static Future<SmsSendOutcome> send({
    required String number,
    required String text,
  }) async {
    if (!isSupportedPlatform) return SmsSendOutcome.notSupported;
    if (number.trim().isEmpty || text.trim().isEmpty) {
      return SmsSendOutcome.invalidNumber;
    }

    String status;
    try {
      status = await _channel.invokeMethod<String>('send', {
            'number': number,
            'text': text,
          }) ??
          'failed';
    } on MissingPluginException {
      // Ältere Installation ohne den nativen Kanal.
      return SmsSendOutcome.notSupported;
    } catch (e) {
      _log.error('SMS-Versand fehlgeschlagen ($number): $e', tag: 'SMS');
      return SmsSendOutcome.failed;
    }

    final outcome = switch (status) {
      'sent' => SmsSendOutcome.sent,
      'sent_unconfirmed' => SmsSendOutcome.sentUnconfirmed,
      'permission_denied' => SmsSendOutcome.permissionDenied,
      'permission_denied_permanently' => SmsSendOutcome.permissionRestricted,
      'cancelled' => SmsSendOutcome.permissionDenied,
      'no_telephony' => SmsSendOutcome.notSupported,
      'no_service' => SmsSendOutcome.noService,
      'radio_off' => SmsSendOutcome.radioOff,
      'invalid_number' => SmsSendOutcome.invalidNumber,
      _ => SmsSendOutcome.failed,
    };

    if (outcome.isSuccess) {
      // Nummer bewusst nicht mitloggen — das Log wandert in Diagnosen.
      _log.info('SMS versendet (${segments(text)} Segment(e)), Status $status', tag: 'SMS');
    } else {
      _log.warning('SMS nicht versendet: $status', tag: 'SMS');
    }
    return outcome;
  }
}
