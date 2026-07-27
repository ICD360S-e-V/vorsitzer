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

  /// GSM 03.38 Basis- und Erweiterungstabelle, soweit für uns relevant.
  /// Alles außerhalb zwingt die ganze SMS in UCS-2 (70 statt 160 Zeichen).
  static const _gsm7Alphabet =
      '@£\$¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
      '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
      '\n\r'
      '^{}[]~|\\€';

  /// Emoji, Steuerzeichen und typografischer Zierrat — fliegt in JEDER Sprache
  /// raus. Bei kyrillischen und arabischen Texten bleibt die Schrift selbst
  /// natürlich stehen, die Nachricht geht dann eben als UCS-2 raus.
  static String sanitize(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = _typografie[ch];
      if (mapped != null) {
        out.write(mapped);
        continue;
      }
      // Emoji und sonstige Symbole (So/Sk/Cn) tragen nichts bei und kosten in
      // UCS-2 zwei Einheiten pro Stück.
      if (RegExp(r'[\p{So}\p{Sk}\p{Cf}\p{Co}\p{Cs}]', unicode: true).hasMatch(ch)) {
        continue;
      }
      out.write(ch);
    }
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  /// Typografie, die in jeder Sprache durch ihr schlichtes Gegenstück ersetzt
  /// wird — Anführungszeichen, Gedankenstriche, geschützte Leerzeichen.
  static const _typografie = {
    '‘': "'", '’': "'", '‚': "'",
    '“': '"', '”': '"', '„': '"',
    '–': '-', '—': '-', '−': '-', '‑': '-',
    '…': '...',
    // Geschützte und schmale Leerzeichen — sehen aus wie ein Leerzeichen,
    '\u00A0': ' ', '\u202F': ' ', '\u2009': ' ', '\u2007': ' ',
    '•': '-', '·': '-', '™': '', '®': '', '©': '',
  };

  /// Bringt [input] ins GSM-7-Alphabet: Umlaute und ß sind darin enthalten und
  /// bleiben, Diakritika werden transliteriert (`Ședință` → `Sedinta`), alles
  /// andere fällt weg. Nur für lateinische Sprachen — bei ru/uk/ar würde diese
  /// Funktion den ganzen Text zerstören.
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

  /// Passt [text] vollständig ins GSM-7-Alphabet?
  ///
  /// Kyrillisch (ru/uk) und Arabisch tun das nicht — solche Nachrichten gehen
  /// zwangsläufig als UCS-2 raus und fassen nur 70 statt 160 Zeichen.
  static bool isGsm7(String text) {
    for (final rune in text.runes) {
      if (!_gsm7Alphabet.contains(String.fromCharCode(rune))) return false;
    }
    return true;
  }

  /// Segmente, die das Netz für [text] berechnet — jedes Segment kostet.
  static int segments(String text) {
    if (text.isEmpty) return 0;

    if (isGsm7(text)) {
      // Erweiterungszeichen (^{}[]~|\€) belegen zwei Stellen.
      const extended = r'^{}[]~|\€';
      var len = 0;
      for (final rune in text.runes) {
        len += extended.contains(String.fromCharCode(rune)) ? 2 : 1;
      }
      return len <= 160 ? 1 : (len / 153).ceil();
    }

    // UCS-2 rechnet in UTF-16-Einheiten; Zeichen außerhalb der BMP (Emoji)
    // belegen zwei davon — `text.length` zählt genau das richtig.
    final units = text.length;
    return units <= 70 ? 1 : (units / 67).ceil();
  }

  /// Wortschatz je Sprache. Bewusst feste Vorlagen statt NLLB: der Übersetzer
  /// halluziniert bei Zahlen, Datum und Uhrzeit — genau deshalb geht schon die
  /// Chat-Erinnerung mit `skipTranslation: true` raus. Eine falsche Uhrzeit in
  /// der Erinnerung wäre schlimmer als eine deutsche Erinnerung.
  static const _sprachen = <String, Map<String, String>>{
    'de': {
      'titel': 'Terminerinnerung', 'datum': 'Datum', 'uhrzeit': 'Uhrzeit',
      'dauer': 'Dauer', 'ort': 'Ort', 'betreff': 'Betreff', 'hinweis': 'Hinweis',
      'min': 'Min.', 'uhr': 'Uhr',
      'schluss': 'Bitte bestaetigen Sie Ihre Teilnahme oder sagen Sie rechtzeitig ab.',
      'tage': 'Mo,Di,Mi,Do,Fr,Sa,So',
    },
    'en': {
      'titel': 'Appointment reminder', 'datum': 'Date', 'uhrzeit': 'Time',
      'dauer': 'Duration', 'ort': 'Place', 'betreff': 'Subject', 'hinweis': 'Note',
      'min': 'min', 'uhr': '',
      'schluss': 'Please confirm your attendance or cancel in good time.',
      'tage': 'Mon,Tue,Wed,Thu,Fri,Sat,Sun',
    },
    'ro': {
      'titel': 'Reamintire programare', 'datum': 'Data', 'uhrzeit': 'Ora',
      'dauer': 'Durata', 'ort': 'Locul', 'betreff': 'Subiect', 'hinweis': 'Observatie',
      'min': 'min', 'uhr': '',
      'schluss': 'Va rugam sa confirmati participarea sau sa anulati din timp.',
      'tage': 'Lu,Ma,Mi,Jo,Vi,Sa,Du',
    },
    'tr': {
      'titel': 'Randevu hatirlatmasi', 'datum': 'Tarih', 'uhrzeit': 'Saat',
      'dauer': 'Sure', 'ort': 'Yer', 'betreff': 'Konu', 'hinweis': 'Not',
      'min': 'dk', 'uhr': '',
      'schluss': 'Lutfen katiliminizi onaylayin veya zamaninda iptal edin.',
      'tage': 'Pzt,Sal,Car,Per,Cum,Cmt,Paz',
    },
    'ru': {
      'titel': 'Напоминание о встрече', 'datum': 'Дата', 'uhrzeit': 'Время',
      'dauer': 'Продолжительность', 'ort': 'Место', 'betreff': 'Тема', 'hinweis': 'Примечание',
      'min': 'мин', 'uhr': '',
      'schluss': 'Пожалуйста, подтвердите участие или отмените заранее.',
      'tage': 'Пн,Вт,Ср,Чт,Пт,Сб,Вс',
    },
    'uk': {
      'titel': 'Нагадування про зустріч', 'datum': 'Дата', 'uhrzeit': 'Час',
      'dauer': 'Тривалість', 'ort': 'Місце', 'betreff': 'Тема', 'hinweis': 'Примітка',
      'min': 'хв', 'uhr': '',
      'schluss': 'Будь ласка, підтвердьте участь або скасуйте завчасно.',
      'tage': 'Пн,Вт,Ср,Чт,Пт,Сб,Нд',
    },
    'ar': {
      'titel': 'تذكير بالموعد', 'datum': 'التاريخ', 'uhrzeit': 'الوقت',
      'dauer': 'المدة', 'ort': 'المكان', 'betreff': 'الموضوع', 'hinweis': 'ملاحظة',
      'min': 'دقيقة', 'uhr': '',
      'schluss': 'يرجى تأكيد حضورك أو الإلغاء في الوقت المناسب.',
      'tage': 'الاثنين,الثلاثاء,الأربعاء,الخميس,الجمعة,السبت,الأحد',
    },
  };

  /// Sprachen in lateinischer Schrift — dort lohnt die Transliteration nach
  /// GSM-7 (160 statt 70 Zeichen je Segment). Bei ru/uk/ar würde sie den Text
  /// zerstören, da geht die SMS als UCS-2 raus.
  static const _lateinisch = {'de', 'en', 'ro', 'tr'};

  /// Ist für [language] eine Vorlage hinterlegt?
  ///
  /// Fragt bewusst NICHT über [_normalizeLanguage]: das fällt auf Deutsch
  /// zurück und würde für jede beliebige Eingabe true melden.
  static bool hasLanguage(String? language) =>
      _sprachen.containsKey(_codeOf(language));

  /// `de-DE`, `DE`, `ru_RU` → `de`/`de`/`ru`. Reine Formsache, ohne Wertung.
  static String _codeOf(String? raw) =>
      (raw ?? '').trim().toLowerCase().split(RegExp(r'[-_]')).first;

  /// Wie [_codeOf], aber Unbekanntes wird zu `de` (Vereinssprache).
  static String _normalizeLanguage(String? raw) {
    final code = _codeOf(raw);
    return _sprachen.containsKey(code) ? code : 'de';
  }

  /// Baut die Erinnerungs-SMS in der Sprache des Mitglieds
  /// (`users.preferred_language` — dieselbe, in die der Live-Chat übersetzt).
  ///
  /// Die Angaben aus dem Termin (Betreff, Ort, Notiz) bleiben unübersetzt: es
  /// sind Eigennamen, Adressen und Stichworte, und sie stehen im Chat und in
  /// der App genauso da.
  ///
  /// [maxSegments] deckelt die Kosten. Passt der Text nicht, werden zuerst die
  /// Notiz, dann der Ort gekürzt — Datum und Uhrzeit bleiben immer vollständig.
  /// Vier Segmente sind bewusst großzügig: in GSM-7 (de/en/ro/tr) reicht das
  /// für alles, in UCS-2 (ru/uk/ar) fasst ein Segment nur 67 Zeichen, ohne den
  /// Spielraum bliebe dort von der Notiz nichts übrig.
  static String buildTerminSms({
    required DateTime terminDate,
    required String title,
    required String location,
    String? description,
    int? durationMinutes,
    String? language,
    String? absender,
    int maxSegments = 4,
  }) {
    final sprache = _normalizeLanguage(language);
    final w = _sprachen[sprache]!;
    final latein = _lateinisch.contains(sprache);

    // Bewusst ohne DateFormat: im WorkManager-Isolat läuft keine MaterialApp,
    // die die Locale-Daten lädt — `DateFormat(..., 'de')` würfe dort
    // LocaleDataException und die automatische Erinnerung bliebe aus.
    String zwei(int v) => v.toString().padLeft(2, '0');
    final tage = w['tage']!.split(',');
    final datum = '${tage[terminDate.weekday - 1]} '
        '${zwei(terminDate.day)}.${zwei(terminDate.month)}.${terminDate.year}';

    final beginn = '${zwei(terminDate.hour)}:${zwei(terminDate.minute)}';
    String uhrzeit = beginn;
    if (durationMinutes != null && durationMinutes > 0) {
      final ende = terminDate.add(Duration(minutes: durationMinutes));
      uhrzeit = '$beginn-${zwei(ende.hour)}:${zwei(ende.minute)}';
    }
    if (w['uhr']!.isNotEmpty) uhrzeit = '$uhrzeit ${w['uhr']}';
    if (durationMinutes != null && durationMinutes > 0) {
      uhrzeit = '$uhrzeit ($durationMinutes ${w['min']})';
    }

    String feld(String? wert) {
      final s = sanitize(wert ?? '');
      return latein ? toGsm7(s) : s;
    }

    final kopf = '${absender ?? 'ICD360S e.V.'} - ${w['titel']}';
    final ort = feld(location);
    final betreff = feld(title);
    var notiz = feld(description);

    String zusammen(String ortText, String notizText) => [
          kopf,
          '${w['datum']}: $datum',
          '${w['uhrzeit']}: $uhrzeit',
          if (betreff.isNotEmpty) '${w['betreff']}: $betreff',
          if (ortText.isNotEmpty) '${w['ort']}: $ortText',
          if (notizText.isNotEmpty) '${w['hinweis']}: $notizText',
          '',
          w['schluss']!,
        ].join('\n');

    var text = zusammen(ort, notiz);
    if (segments(text) <= maxSegments) return text;

    // Zuerst die Notiz eindampfen — sie ist das Beiwerk.
    for (final grenze in [120, 80, 50, 0]) {
      notiz = grenze == 0 ? '' : _kuerzen(notiz, grenze);
      text = zusammen(ort, notiz);
      if (segments(text) <= maxSegments) return text;
    }
    // Dann den Ort. Datum, Uhrzeit und Betreff bleiben immer stehen.
    for (final grenze in [60, 40]) {
      text = zusammen(_kuerzen(ort, grenze), '');
      if (segments(text) <= maxSegments) return text;
    }
    return text;
  }

  /// Kürzt [text] auf [max] Zeichen und hängt „..." an, wenn etwas wegfällt.
  static String _kuerzen(String text, int max) {
    if (text.length <= max) return text;
    if (max < 8) return '';
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
