import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/anredeform.dart';
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

/// Wie es um das Lesen des SMS-Verlaufs auf diesem Gerät steht.
enum SmsReadLage {
  /// Kein Android, oder eine App-Version ohne den Lesekanal.
  nichtUnterstuetzt,

  /// Berechtigung noch nicht erteilt — ein Dialog kann das lösen.
  fragenMoeglich,

  /// Der Knackpunkt: die Berechtigung gilt formal als erteilt, der App-Op
  /// steht aber auf `ignored`. Die Abfrage liefert dann null Zeilen, ohne zu
  /// scheitern. Das passiert, wenn die hard-restricted Permission beim
  /// INSTALLIEREN nicht auf der Allowlist des Installers stand — und dagegen
  /// hilft kein Antippen in den Einstellungen, nur ein anderer Installationsweg.
  vomInstallerBlockiert,

  /// Gefragt wurde, aber es erschien kein Dialog.
  ///
  /// ⚠️ Ab **Android 15** hat das zwei mögliche Ursachen, und nur eine davon
  /// ist aussichtslos:
  ///
  /// 1. **Enhanced Confirmation Mode** (neu in Android 15, API 35). Android
  ///    prüft eine Allowlist aus dem Werksabbild
  ///    (`/system/etc/sysconfig`); wer nicht darauf steht — und ein eigenes
  ///    F-Droid-Repo steht nie darauf —, bekommt SMS-Berechtigungen erst nach
  ///    einer ausdrücklichen Freigabe in der App-Info. **Das behebt der
  ///    Nutzer selbst, mit einem Tipp.**
  /// 2. Die fehlende Installer-Allowlist von oben.
  ///
  /// Beide sehen von hier aus gleich aus: `requestPermissions` antwortet
  /// „denied", `shouldShowRequestPermissionRationale` sagt false, ein Dialog
  /// war nie zu sehen. Deshalb wird hier **nicht** behauptet, es sei
  /// aussichtslos — es wird der Weg genannt, der in Fall 1 hilft, und erst
  /// wenn der nichts ändert, bleibt Fall 2 übrig.
  dialogBleibtAus,

  /// Erteilt, aber die Abfrage scheitert trotzdem.
  lesefehler,

  /// Alles offen, es lässt sich lesen.
  bereit,
}

/// Ausgang eines Leseversuchs für eine bestimmte Rufnummer.
///
/// Absichtlich getrennt von [SmsReadLage]: die Diagnose beantwortet einmalig
/// beim Einrichten „kann dieses Gerät überhaupt lesen?", das hier beantwortet
/// bei jedem Durchgang „was kam für dieses eine Mitglied an?". Ein gemeinsamer
/// Typ hätte in beiden Fällen Zustände, die dort nicht vorkommen können.
enum SmsLeseLage {
  /// Kein Android, oder eine App-Version ohne den Lesekanal.
  nichtUnterstuetzt,

  /// READ_SMS ist nicht erteilt.
  keineBerechtigung,

  /// Erteilt, aber der App-Op steht auf `ignored`/`errored` — die Abfrage
  /// gäbe stumm null Zeilen zurück. Das MUSS von „nichts Neues" unterscheidbar
  /// bleiben, sonst wartet man ewig auf Nachrichten, die nie kommen können.
  vomInstallerBlockiert,

  /// Das Mitglied hat keine Mobilnummer hinterlegt.
  keineNummer,

  /// Die Abfrage selbst ist gescheitert.
  fehler,

  /// Gelesen — [SmsVerlauf.nachrichten] kann trotzdem leer sein.
  bereit,
}

/// Eine eingegangene SMS eines Mitglieds.
class SmsEingang {
  /// `_id` aus dem Android-Posteingang. Einziger stabiler Schlüssel gegen
  /// Doppelimporte — zwei SMS derselben Sekunde mit gleichem Text sind sonst
  /// nicht auseinanderzuhalten.
  final int geraetId;

  /// Die Rufnummer aus der übergebenen Liste, die gepasst hat — nicht die
  /// Adresse, wie sie im Posteingang steht. Der Server ordnet danach dem
  /// Mitglied zu, ohne die Schreibweise des Netzes noch einmal normalisieren
  /// zu müssen.
  final String nummer;
  final String text;
  final DateTime empfangen;

  const SmsEingang({
    required this.geraetId,
    required this.nummer,
    required this.text,
    required this.empfangen,
  });
}

/// Ergebnis von [SmsService.readConversation].
class SmsVerlauf {
  final SmsLeseLage lage;
  final List<SmsEingang> nachrichten;

  /// Wie viele eingegangene Zeilen im Fenster überhaupt angesehen wurden.
  ///
  /// ⚠️ Ohne diese Zahl sind zwei völlig verschiedene Lagen ununterscheidbar:
  /// „es kam nichts an" und „es kam etwas an, gehörte aber zu keiner bekannten
  /// Rufnummer". Beide meldeten sonst schlicht nichts — und die Zuordnung
  /// hätte niemand in Verdacht.
  final int geprueft;

  /// Es lagen mehr als [SmsService.readConversations]s `limit` bereit. Der Rest
  /// kommt beim nächsten Durchgang — verschwiegen würde er nie ankommen.
  final bool abgeschnitten;
  final String? fehler;

  const SmsVerlauf({
    required this.lage,
    this.nachrichten = const [],
    this.geprueft = 0,
    this.abgeschnitten = false,
    this.fehler,
  });

  /// Baut das Ergebnis aus der Antwort des Plattformkanals.
  ///
  /// Bewusst als eigene Fabrik und nicht inline in
  /// [SmsService.readConversation]: dort steht ein `Platform.isAndroid` davor,
  /// hinter dem im Test nichts mehr passiert. Die Übersetzung von roher Map zu
  /// Objekt ist aber genau die Stelle, an der sich ein Tippfehler im
  /// Schlüsselnamen als „keine neuen Nachrichten" tarnt.
  factory SmsVerlauf.ausRoh(Map<String, dynamic> roh) {
    final lage = switch (roh['lage']?.toString()) {
      'bereit' => SmsLeseLage.bereit,
      'keine_berechtigung' => SmsLeseLage.keineBerechtigung,
      'vom_installer_blockiert' => SmsLeseLage.vomInstallerBlockiert,
      'keine_nummer' => SmsLeseLage.keineNummer,
      // Auch ein unbekannter Zustand ist ein Fehler, kein leerer Posteingang.
      _ => SmsLeseLage.fehler,
    };

    final liste = (roh['nachrichten'] as List?) ?? const [];
    return SmsVerlauf(
      lage: lage,
      nachrichten: liste
          .whereType<Map>()
          .map((m) => SmsEingang(
                geraetId: (m['geraet_id'] as num?)?.toInt() ?? 0,
                nummer: m['nummer']?.toString() ?? '',
                text: m['text']?.toString() ?? '',
                empfangen: DateTime.fromMillisecondsSinceEpoch(
                  (m['empfangen_ms'] as num?)?.toInt() ?? 0,
                ),
              ))
          // Ohne Geräte-ID gibt es keinen Schutz gegen Doppelimport, ohne
          // Nummer keine Zuordnung zum Mitglied. Lieber eine SMS nicht
          // importieren als sie bei jedem Durchgang erneut in den Chat zu
          // schreiben oder sie dem Falschen zuzuordnen.
          .where((e) => e.geraetId > 0 && e.nummer.isNotEmpty)
          .toList(),
      geprueft: (roh['geprueft'] as num?)?.toInt() ?? 0,
      abgeschnitten: roh['abgeschnitten'] == true,
      fehler: roh['fehler']?.toString(),
    );
  }

  bool get gelesen => lage == SmsLeseLage.bereit;
}

/// Ergebnis der Lese-Vorprüfung. Sie zählt nur Zeilen — es wandert kein
/// einziges SMS-Wort und keine Rufnummer über den Kanal.
class SmsReadDiagnose {
  final bool permission;
  final String appOp;
  final bool cursorOk;
  final int rowCount;
  final bool hasActivity;
  final int sdkInt;
  final String? fehler;
  final String? hinweis;

  /// Es wurde gefragt und es kam kein Dialog.
  ///
  /// Steht bewusst NICHT in der nativen Diagnose: die zählt nur den Ist-Zustand
  /// und kann nicht wissen, ob je jemand gefragt hat. Erst die Antwort
  /// `denied_permanently` auf eine echte Anfrage macht aus „noch nicht erteilt"
  /// die Aussage „lässt sich so nicht erteilen".
  final bool dialogBliebAus;

  const SmsReadDiagnose({
    required this.permission,
    required this.appOp,
    required this.cursorOk,
    required this.rowCount,
    required this.hasActivity,
    required this.sdkInt,
    this.fehler,
    this.hinweis,
    this.dialogBliebAus = false,
  });

  SmsReadDiagnose copyWith({bool? dialogBliebAus}) => SmsReadDiagnose(
        permission: permission,
        appOp: appOp,
        cursorOk: cursorOk,
        rowCount: rowCount,
        hasActivity: hasActivity,
        sdkInt: sdkInt,
        fehler: fehler,
        hinweis: hinweis,
        dialogBliebAus: dialogBliebAus ?? this.dialogBliebAus,
      );

  /// Ab Android 15 greift Enhanced Confirmation Mode. Darunter gibt es nur die
  /// Installer-Allowlist, also auch nur eine Erklärung.
  bool get ecmMoeglich => sdkInt >= 35;

  const SmsReadDiagnose.nichtUnterstuetzt({this.hinweis})
      : permission = false,
        appOp = 'n/a',
        cursorOk = false,
        rowCount = -1,
        hasActivity = false,
        sdkInt = 0,
        fehler = null,
        dialogBliebAus = false;

  SmsReadLage get lage {
    if (sdkInt == 0) return SmsReadLage.nichtUnterstuetzt;
    // Reihenfolge: erst der belegte Fehlschlag, dann die Vermutung. Wer schon
    // gefragt hat und keinen Dialog sah, dem hilft ein zweites „Anfragen"
    // nicht — der Knopf würde bei jedem Tipp dasselbe Nichts tun.
    if (!permission && dialogBliebAus) return SmsReadLage.dialogBleibtAus;
    if (!permission) return SmsReadLage.fragenMoeglich;
    // Erteilt UND App-Op offen UND Abfrage lief -> es geht wirklich.
    if (cursorOk && appOp != 'ignored' && appOp != 'errored') {
      return SmsReadLage.bereit;
    }
    if (appOp == 'ignored' || appOp == 'errored') {
      return SmsReadLage.vomInstallerBlockiert;
    }
    return SmsReadLage.lesefehler;
  }

  /// Klartext für die Diagnose-Anzeige.
  String get urteil {
    switch (lage) {
      case SmsReadLage.nichtUnterstuetzt:
        return hinweis ?? 'Nur auf dem Vereins-Tablet (Android) möglich';
      case SmsReadLage.fragenMoeglich:
        return 'Berechtigung noch nicht erteilt — antippen zum Anfragen';
      case SmsReadLage.dialogBleibtAus:
        return ecmMoeglich
            ? 'Gefragt, aber Android zeigt keinen Dialog. Ab Android 15 ist '
                'das meist die Freigabe in der App-Info („Eingeschränkte '
                'Einstellungen zulassen") — danach hier erneut anfragen.'
            : 'Gefragt, aber Android zeigt keinen Dialog. Diese Installation '
                'darf READ_SMS nicht erhalten.';
      case SmsReadLage.vomInstallerBlockiert:
        return 'Vom Installationsweg gesperrt (App-Op „$appOp"). '
            'Die Berechtigung lässt sich hier NICHT freischalten — die App '
            'muss über einen Weg installiert werden, der READ_SMS erlaubt.';
      case SmsReadLage.lesefehler:
        return 'Erteilt, aber die Abfrage scheitert: ${fehler ?? 'unbekannt'}';
      case SmsReadLage.bereit:
        return 'Lesen möglich — $rowCount SMS auf dem Gerät gefunden';
    }
  }

  /// Nur wenn das hier true ist, lohnt es sich, den Verlauf zu bauen.
  bool get funktioniert => lage == SmsReadLage.bereit;
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
  // SMS-VERLAUF: VORPRÜFUNG
  // =========================================================================

  /// Ergebnis der Lese-Vorprüfung auf dem Vereins-Tablet.
  ///
  /// [appOp] ist der entscheidende Wert. `checkSelfPermission` meldet auch dann
  /// GRANTED, wenn der App-Op auf `ignored` steht — die Abfrage liefert dann
  /// null Zeilen, ohne zu scheitern. Ohne diesen Wert wäre „darf nicht lesen"
  /// von „hat keine SMS" nicht zu unterscheiden.
  static Future<SmsReadDiagnose> readDiagnose() async {
    if (!isSupportedPlatform) return const SmsReadDiagnose.nichtUnterstuetzt();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('readDiagnose');
      if (raw == null) return const SmsReadDiagnose.nichtUnterstuetzt();
      return SmsReadDiagnose(
        permission: raw['permission'] == true,
        appOp: raw['appOp']?.toString() ?? 'unbekannt',
        cursorOk: raw['cursorOk'] == true,
        rowCount: (raw['rowCount'] as num?)?.toInt() ?? -1,
        hasActivity: raw['hasActivity'] == true,
        sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
        fehler: raw['fehler']?.toString(),
      );
    } on MissingPluginException {
      // Installation ohne den erweiterten Kanal — die App ist älter als das
      // Feature, nicht das Gerät zu alt.
      return const SmsReadDiagnose.nichtUnterstuetzt(
        hinweis: 'App-Version kennt die Lesefunktion noch nicht',
      );
    } catch (e) {
      _log.warning('SMS-Lesediagnose fehlgeschlagen: $e', tag: 'SMS');
      return SmsReadDiagnose.nichtUnterstuetzt(hinweis: '$e');
    }
  }

  /// Fragt READ_SMS an. Liefert `granted`, `denied`, `denied_permanently`,
  /// `no_activity`, `cancelled` oder `not_supported`.
  static Future<String> requestReadPermission() async {
    if (!isSupportedPlatform) return 'not_supported';
    try {
      return await _channel.invokeMethod<String>('requestReadPermission') ?? 'denied';
    } on MissingPluginException {
      return 'not_supported';
    } catch (e) {
      _log.warning('READ_SMS-Anfrage fehlgeschlagen: $e', tag: 'SMS');
      return 'denied';
    }
  }

  /// Liest die eingegangenen SMS **der übergebenen Rufnummern** — und nur
  /// dieser.
  ///
  /// Gelesen wird der Text ausschließlich für Nachrichten, die einer der
  /// Nummern zugeordnet werden konnten; das steckt im nativen Code. Auf der
  /// Vereins-SIM liegen auch Bank-TANs und 2FA-Codes, und deren Text betritt
  /// diesen Prozess nie.
  ///
  /// [seit] grenzt auf Neues ein. Beim allerersten Lauf ist das der Punkt, ab
  /// dem importiert wird — ohne ihn zöge der erste Durchgang Jahre alter SMS
  /// in den Chat, die dort nie standen und die niemand mehr beantworten will.
  static Future<SmsVerlauf> readConversations(
    List<String> nummern, {
    DateTime? seit,
    int limit = 50,
  }) async {
    if (!isSupportedPlatform) {
      return const SmsVerlauf(lage: SmsLeseLage.nichtUnterstuetzt);
    }
    if (nummern.isEmpty) {
      return const SmsVerlauf(lage: SmsLeseLage.keineNummer);
    }
    try {
      final roh = await _channel.invokeMapMethod<String, dynamic>(
        'readConversations',
        {
          'numbers': nummern,
          'sinceMs': seit?.millisecondsSinceEpoch ?? 0,
          'limit': limit,
        },
      );
      if (roh == null) return const SmsVerlauf(lage: SmsLeseLage.nichtUnterstuetzt);
      return SmsVerlauf.ausRoh(roh);
    } on MissingPluginException {
      // Installation ohne den erweiterten Kanal — die App ist älter als das
      // Feature, nicht das Gerät zu alt.
      return const SmsVerlauf(lage: SmsLeseLage.nichtUnterstuetzt);
    } catch (e) {
      _log.warning('SMS-Verlauf lesen fehlgeschlagen: $e', tag: 'SMS');
      return SmsVerlauf(lage: SmsLeseLage.fehler, fehler: '$e');
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

      // 2026-08-04, mit den 21 neuen Sprachvorlagen dazugekommen. Nicht nur
      // wegen der Vorlagen selbst: Namen, Orte und Notizen laufen durch
      // dieselbe Funktion, deshalb steht hier das ganze Alphabet der jeweiligen
      // Sprache und nicht bloß, was in den Vorlagen vorkommt. Fehlt ein
      // Zeichen, wird daraus ein '?' — „Id?pont" statt „Időpont".
      // Kleines ç ist NICHT Teil der GSM-7-Tabelle (nur das große Ç), muss also
      // ersetzt werden — betrifft Portugiesisch, Französisch und Türkisch.
      'ç': 'c',
      // Tschechisch / Slowakisch
      'ď': 'd', 'ě': 'e', 'ň': 'n', 'ř': 'r', 'ť': 't', 'ů': 'u', 'ý': 'y',
      'ĺ': 'l', 'ľ': 'l', 'ŕ': 'r',
      'Ď': 'D', 'Ě': 'E', 'Ň': 'N', 'Ř': 'R', 'Ť': 'T', 'Ů': 'U', 'Ý': 'Y',
      'Ĺ': 'L', 'Ľ': 'L', 'Ŕ': 'R',
      // Polnisch
      'ą': 'a', 'ę': 'e', 'ś': 's', 'ź': 'z', 'ż': 'z',
      'Ą': 'A', 'Ę': 'E', 'Ś': 'S', 'Ź': 'Z', 'Ż': 'Z',
      // Ungarisch (ö/ü stehen schon in GSM-7, ő/ű nicht)
      'ő': 'o', 'ű': 'u', 'Ő': 'O', 'Ű': 'U',
      // Kroatisch / Slowenisch
      'đ': 'd', 'Đ': 'D',
      // Lettisch
      'ā': 'a', 'ē': 'e', 'ģ': 'g', 'ī': 'i', 'ķ': 'k', 'ļ': 'l', 'ņ': 'n',
      'ū': 'u', 'ŗ': 'r',
      'Ā': 'A', 'Ē': 'E', 'Ģ': 'G', 'Ī': 'I', 'Ķ': 'K', 'Ļ': 'L', 'Ņ': 'N',
      'Ū': 'U', 'Ŗ': 'R',
      // Litauisch (ū teilt es sich mit dem Lettischen, steht schon oben)
      'ė': 'e', 'į': 'i', 'ų': 'u', 'Ė': 'E', 'Į': 'I', 'Ų': 'U',
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
    'de': { 'datum': 'Datum', 'uhrzeit': 'Uhrzeit',
      'dauer': 'Dauer', 'ort': 'Ort', 'betreff': 'Betreff', 'hinweis': 'Hinweis',
      'min': 'Min.', 'uhr': 'Uhr',
      // Umlaute und ß sind Teil von GSM-7 — „bestätigen" und „Grüßen" dürfen
      // hier also richtig geschrieben stehen, das kostet kein Segment.
      'morgens': 'am Morgen', 'mittags': 'am Mittag', 'abends': 'am Abend', 'nachts': 'in der Nacht',
      'med_satz': 'bitte denken Sie an Ihre Medikamente',
      'wetter_titel': 'Wetterwarnung für Ihren Wohnort',
      'wetter_hinweis': 'Bitte bleiben Sie nach Möglichkeit zu Hause und melden Sie sich, wenn Sie Hilfe brauchen.',
      'anrede_frau': 'Sehr geehrte Frau', 'anrede_herr': 'Sehr geehrter Herr',
      'anrede_neutral': 'Guten Tag', 'gruss': 'Mit freundlichen Grüßen',
      'schluss': 'Bitte bestätigen Sie Ihre Teilnahme oder sagen Sie rechtzeitig ab.',
      'tage': 'Mo,Di,Mi,Do,Fr,Sa,So',
    },
    'en': { 'datum': 'Date', 'uhrzeit': 'Time',
      'dauer': 'Duration', 'ort': 'Place', 'betreff': 'Subject', 'hinweis': 'Note',
      'min': 'min', 'uhr': '',
      'morgens': 'in the morning', 'mittags': 'at midday', 'abends': 'in the evening', 'nachts': 'at night',
      'med_satz': 'please remember to take your medication',
      'wetter_titel': 'Weather warning for your area',
      'wetter_hinweis': 'Please stay indoors if you can, and get in touch if you need help.',
      'anrede_frau': 'Dear Ms', 'anrede_herr': 'Dear Mr',
      'anrede_neutral': 'Dear', 'gruss': 'Kind regards',
      'schluss': 'Please confirm your attendance or cancel in good time.',
      'tage': 'Mon,Tue,Wed,Thu,Fri,Sat,Sun',
    },
    'ro': { 'datum': 'Data', 'uhrzeit': 'Ora',
      'dauer': 'Durata', 'ort': 'Locul', 'betreff': 'Subiect', 'hinweis': 'Observatie',
      'min': 'min', 'uhr': '',
      'morgens': 'dimineata', 'mittags': 'la pranz', 'abends': 'seara', 'nachts': 'noaptea',
      'med_satz': 'va rugam sa nu uitati medicamentele',
      'wetter_titel': 'Avertizare meteo pentru localitatea dumneavoastra',
      'wetter_hinweis': 'Va rugam sa ramaneti in casa daca este posibil si sa ne anuntati daca aveti nevoie de ajutor.',
      'anrede_frau': 'Stimată doamnă', 'anrede_herr': 'Stimate domnule',
      'anrede_neutral': 'Bună ziua', 'gruss': 'Cu stimă',
      'schluss': 'Va rugam sa confirmati participarea sau sa anulati din timp.',
      'tage': 'Lu,Ma,Mi,Jo,Vi,Sa,Du',
    },
    'tr': { 'datum': 'Tarih', 'uhrzeit': 'Saat',
      'dauer': 'Sure', 'ort': 'Yer', 'betreff': 'Konu', 'hinweis': 'Not',
      'min': 'dk', 'uhr': '',
      // Türkisch stellt den Titel hinter den Namen („Sayın Ayşe Hanım"). Das
      // schlichte „Sayın <Name>" ist üblich, korrekt und geschlechtsneutral —
      // also für alle drei Fälle dasselbe, statt es falsch zu beugen.
      'morgens': 'sabah', 'mittags': 'ogle', 'abends': 'aksam', 'nachts': 'gece',
      'med_satz': 'lutfen {zeit} ilaclarinizi almayi unutmayin',
      'wetter_titel': 'Bulundugunuz yer icin hava uyarisi',
      'wetter_hinweis': 'Mumkunse evde kalin ve yardima ihtiyaciniz olursa bize haber verin.',
      'anrede_frau': 'Sayın', 'anrede_herr': 'Sayın',
      'anrede_neutral': 'Sayın', 'gruss': 'Saygılarımızla',
      'schluss': 'Lutfen katiliminizi onaylayin veya zamaninda iptal edin.',
      'tage': 'Pzt,Sal,Car,Per,Cum,Cmt,Paz',
    },
    'ru': { 'datum': 'Дата', 'uhrzeit': 'Время',
      'dauer': 'Продолжительность', 'ort': 'Место', 'betreff': 'Тема', 'hinweis': 'Примечание',
      'min': 'мин', 'uhr': '',
      'morgens': 'утром', 'mittags': 'днём', 'abends': 'вечером', 'nachts': 'ночью',
      'med_satz': 'пожалуйста, не забудьте принять лекарства',
      'wetter_titel': 'Штормовое предупреждение для вашего района',
      'wetter_hinweis': 'По возможности оставайтесь дома и сообщите нам, если нужна помощь.',
      'anrede_frau': 'Уважаемая г-жа', 'anrede_herr': 'Уважаемый г-н',
      'anrede_neutral': 'Здравствуйте,', 'gruss': 'С уважением',
      'schluss': 'Пожалуйста, подтвердите участие или отмените заранее.',
      'tage': 'Пн,Вт,Ср,Чт,Пт,Сб,Вс',
    },
    'uk': { 'datum': 'Дата', 'uhrzeit': 'Час',
      'dauer': 'Тривалість', 'ort': 'Місце', 'betreff': 'Тема', 'hinweis': 'Примітка',
      'min': 'хв', 'uhr': '',
      'morgens': 'вранці', 'mittags': 'вдень', 'abends': 'ввечері', 'nachts': 'вночі',
      'med_satz': 'будь ласка, не забудьте прийняти ліки',
      'wetter_titel': 'Попередження про погоду для вашого району',
      'wetter_hinweis': 'За можливості залишайтеся вдома і повідомте нас, якщо потрібна допомога.',
      'anrede_frau': 'Шановна пані', 'anrede_herr': 'Шановний пане',
      'anrede_neutral': 'Доброго дня,', 'gruss': 'З повагою',
      'schluss': 'Будь ласка, підтвердьте участь або скасуйте завчасно.',
      'tage': 'Пн,Вт,Ср,Чт,Пт,Сб,Нд',
    },
    'ar': { 'datum': 'التاريخ', 'uhrzeit': 'الوقت',
      'dauer': 'المدة', 'ort': 'المكان', 'betreff': 'الموضوع', 'hinweis': 'ملاحظة',
      'min': 'دقيقة', 'uhr': '',
      'komma': '،',
      'morgens': 'صباحاً', 'mittags': 'ظهراً', 'abends': 'مساءً', 'nachts': 'ليلاً',
      'med_satz': 'يرجى تذكر تناول أدويتك',
      'wetter_titel': 'تحذير من الطقس في منطقتك',
      'wetter_hinweis': 'يرجى البقاء في المنزل إن أمكن وإبلاغنا إذا كنت بحاجة إلى مساعدة.',
      'anrede_frau': 'السيدة المحترمة', 'anrede_herr': 'السيد المحترم',
      'anrede_neutral': 'تحية طيبة،', 'gruss': 'مع أطيب التحيات',
      'schluss': 'يرجى تأكيد حضورك أو الإلغاء في الوقت المناسب.',
      'tage': 'الاثنين,الثلاثاء,الأربعاء,الخميس,الجمعة,السبت,الأحد',
    },

    // ── 2026-08-04: die übrigen 21 Werte des ENUM `preferred_language` ──────
    //
    // Bis hierher hatten nur sieben Sprachen eine Vorlage, alle anderen fielen
    // über `_normalizeLanguage` auf Deutsch zurück — ein Mitglied mit polnisch
    // eingestellter App bekam die Terminerinnerung auf Deutsch.
    //
    // Weiterhin bewusst KEIN NLLB: nicht wegen der Sprachen (der Dienst kann
    // seit dem 2026-08-04 alle 28), sondern wegen der Stelle. Übersetzt würde
    // die fertige SMS — mitsamt Datum, Uhrzeit und Adresse. Feste Vorlagen
    // lassen genau diese Werte unberührt.
    //
    // Die Wochentagskürzel stammen aus CLDR (`DateFormat.E(locale)`), nicht aus
    // dem Kopf: ein falscher Wochentag verschiebt einen Termin.
    'bg': { 'datum': 'Дата', 'uhrzeit': 'Час',
      'dauer': 'Продължителност', 'ort': 'Място', 'betreff': 'Тема', 'hinweis': 'Бележка',
      'min': 'мин', 'uhr': '',
      'morgens': 'сутринта', 'mittags': 'по обед', 'abends': 'вечерта', 'nachts': 'през нощта',
      'med_satz': 'моля, не забравяйте лекарствата си',
      'wetter_titel': 'Предупреждение за времето за вашия район',
      'wetter_hinweis': 'Моля, останете вкъщи, ако е възможно, и ни се обадете, ако имате нужда от помощ.',
      // „господине" ist die Anrede ohne Namen; steht einer dahinter, heißt es
      // „господин". Der Code hängt immer den Namen an.
      'anrede_frau': 'Уважаема госпожо', 'anrede_herr': 'Уважаеми господин',
      'anrede_neutral': 'Добър ден', 'gruss': 'С уважение',
      'schluss': 'Моля, потвърдете участието си или се откажете навреме.',
      'tage': 'пн,вт,ср,чт,пт,сб,нд',
    },
    'cs': { 'datum': 'Datum', 'uhrzeit': 'Čas',
      'dauer': 'Doba trvání', 'ort': 'Místo', 'betreff': 'Předmět', 'hinweis': 'Poznámka',
      'min': 'min', 'uhr': '',
      'morgens': 'ráno', 'mittags': 'v poledne', 'abends': 'večer', 'nachts': 'v noci',
      'med_satz': 'nezapomeňte prosím na své léky',
      'wetter_titel': 'Výstraha před počasím pro vaše bydliště',
      'wetter_hinweis': 'Zůstaňte prosím pokud možno doma a ozvěte se nám, pokud budete potřebovat pomoc.',
      'anrede_frau': 'Vážená paní', 'anrede_herr': 'Vážený pane',
      'anrede_neutral': 'Dobrý den', 'gruss': 'S pozdravem',
      'schluss': 'Potvrďte prosím svou účast nebo se včas omluvte.',
      'tage': 'po,út,st,čt,pá,so,ne',
    },
    // Dänisch, Norwegisch und Schwedisch siezen nicht mehr — das höfliche „De"
    // ist dort seit den Siebzigern ungebräuchlich und klänge steif.
    'da': { 'datum': 'Dato', 'uhrzeit': 'Tidspunkt',
      'dauer': 'Varighed', 'ort': 'Sted', 'betreff': 'Emne', 'hinweis': 'Bemærkning',
      'min': 'min', 'uhr': '',
      'morgens': 'om morgenen', 'mittags': 'midt på dagen', 'abends': 'om aftenen', 'nachts': 'om natten',
      'med_satz': 'husk venligst din medicin',
      'wetter_titel': 'Vejrvarsel for dit område',
      'wetter_hinweis': 'Bliv venligst hjemme, hvis det er muligt, og kontakt os, hvis du har brug for hjælp.',
      'anrede_frau': 'Kære fru', 'anrede_herr': 'Kære hr.',
      'anrede_neutral': 'Goddag', 'gruss': 'Med venlig hilsen',
      'schluss': 'Bekræft venligst din deltagelse, eller meld afbud i god tid.',
      'tage': 'man.,tirs.,ons.,tors.,fre.,lør.,søn.',
    },
    'el': { 'datum': 'Ημερομηνία', 'uhrzeit': 'Ώρα',
      'dauer': 'Διάρκεια', 'ort': 'Τόπος', 'betreff': 'Θέμα', 'hinweis': 'Σημείωση',
      'min': 'λεπτά', 'uhr': '',
      'morgens': 'το πρωί', 'mittags': 'το μεσημέρι', 'abends': 'το βράδυ', 'nachts': 'τη νύχτα',
      'med_satz': 'μην ξεχάσετε τα φάρμακά σας',
      'wetter_titel': 'Προειδοποίηση καιρού για την περιοχή σας',
      'wetter_hinweis': 'Παρακαλούμε μείνετε στο σπίτι αν είναι δυνατόν και επικοινωνήστε μαζί μας αν χρειάζεστε βοήθεια.',
      'anrede_frau': 'Αξιότιμη κυρία', 'anrede_herr': 'Αξιότιμε κύριε',
      'anrede_neutral': 'Γεια σας', 'gruss': 'Με εκτίμηση',
      'schluss': 'Παρακαλούμε επιβεβαιώστε τη συμμετοχή σας ή ακυρώστε εγκαίρως.',
      'tage': 'Δευ,Τρί,Τετ,Πέμ,Παρ,Σάβ,Κυρ',
    },
    'es': { 'datum': 'Fecha', 'uhrzeit': 'Hora',
      'dauer': 'Duración', 'ort': 'Lugar', 'betreff': 'Asunto', 'hinweis': 'Nota',
      'min': 'min', 'uhr': '',
      'morgens': 'por la mañana', 'mittags': 'al mediodía', 'abends': 'por la tarde', 'nachts': 'por la noche',
      'med_satz': 'no olvide sus medicamentos {zeit}, por favor',
      'wetter_titel': 'Aviso meteorológico para su localidad',
      'wetter_hinweis': 'Por favor, quédese en casa si le es posible y avísenos si necesita ayuda.',
      'anrede_frau': 'Estimada señora', 'anrede_herr': 'Estimado señor',
      'anrede_neutral': 'Buenos días', 'gruss': 'Atentamente',
      'schluss': 'Por favor, confirme su asistencia o cancele con antelación.',
      'tage': 'lun,mar,mié,jue,vie,sáb,dom',
    },
    'et': { 'datum': 'Kuupäev', 'uhrzeit': 'Kellaaeg',
      'dauer': 'Kestus', 'ort': 'Koht', 'betreff': 'Teema', 'hinweis': 'Märkus',
      'min': 'min', 'uhr': '',
      'morgens': 'hommikul', 'mittags': 'keskpäeval', 'abends': 'õhtul', 'nachts': 'öösel',
      'med_satz': 'palun ärge unustage oma ravimeid',
      'wetter_titel': 'Ilmahoiatus teie piirkonnas',
      'wetter_hinweis': 'Palun jääge võimaluse korral koju ja andke meile teada, kui vajate abi.',
      'anrede_frau': 'Lugupeetud proua', 'anrede_herr': 'Lugupeetud härra',
      'anrede_neutral': 'Tere päevast', 'gruss': 'Lugupidamisega',
      'schluss': 'Palun kinnitage oma osalemine või tühistage see õigeaegselt.',
      // Estnisch kürzt die Wochentage auf einen Buchstaben — das ist die
      // CLDR-Form, kein Verlust beim Kopieren.
      'tage': 'E,T,K,N,R,L,P',
    },
    'fi': { 'datum': 'Päivämäärä', 'uhrzeit': 'Kellonaika',
      'dauer': 'Kesto', 'ort': 'Paikka', 'betreff': 'Aihe', 'hinweis': 'Huomautus',
      'min': 'min', 'uhr': '',
      'morgens': 'aamulla', 'mittags': 'keskipäivällä', 'abends': 'illalla', 'nachts': 'yöllä',
      'med_satz': 'muistattehan lääkkeenne',
      'wetter_titel': 'Säävaroitus asuinalueellenne',
      'wetter_hinweis': 'Pysykää mahdollisuuksien mukaan kotona ja ottakaa yhteyttä, jos tarvitsette apua.',
      'anrede_frau': 'Hyvä rouva', 'anrede_herr': 'Hyvä herra',
      'anrede_neutral': 'Hyvää päivää', 'gruss': 'Ystävällisin terveisin',
      'schluss': 'Vahvistakaa osallistumisenne tai perukaa ajoissa.',
      'tage': 'ma,ti,ke,to,pe,la,su',
    },
    'fr': { 'datum': 'Date', 'uhrzeit': 'Heure',
      'dauer': 'Durée', 'ort': 'Lieu', 'betreff': 'Objet', 'hinweis': 'Remarque',
      'min': 'min', 'uhr': '',
      'morgens': 'le matin', 'mittags': 'à midi', 'abends': 'le soir', 'nachts': 'la nuit',
      'med_satz': 'pensez à prendre vos médicaments',
      'wetter_titel': 'Alerte météo pour votre commune',
      'wetter_hinweis': "Restez chez vous si possible et faites-nous signe si vous avez besoin d'aide.",
      'anrede_frau': 'Chère Madame', 'anrede_herr': 'Cher Monsieur',
      'anrede_neutral': 'Bonjour', 'gruss': 'Cordialement',
      'schluss': "Merci de confirmer votre présence ou d'annuler à temps.",
      'tage': 'lun.,mar.,mer.,jeu.,ven.,sam.,dim.',
    },
    'hr': { 'datum': 'Datum', 'uhrzeit': 'Vrijeme',
      'dauer': 'Trajanje', 'ort': 'Mjesto', 'betreff': 'Predmet', 'hinweis': 'Napomena',
      'min': 'min', 'uhr': '',
      'morgens': 'ujutro', 'mittags': 'u podne', 'abends': 'navečer', 'nachts': 'noću',
      'med_satz': 'molimo ne zaboravite svoje lijekove',
      'wetter_titel': 'Upozorenje na vremenske prilike za vaše mjesto',
      'wetter_hinweis': 'Molimo ostanite kod kuće ako je moguće i javite nam se ako trebate pomoć.',
      'anrede_frau': 'Poštovana gospođo', 'anrede_herr': 'Poštovani gospodine',
      'anrede_neutral': 'Dobar dan', 'gruss': 'S poštovanjem',
      'schluss': 'Molimo potvrdite svoje sudjelovanje ili se pravovremeno odjavite.',
      'tage': 'pon,uto,sri,čet,pet,sub,ned',
    },
    'hu': { 'datum': 'Dátum', 'uhrzeit': 'Időpont',
      'dauer': 'Időtartam', 'ort': 'Helyszín', 'betreff': 'Tárgy', 'hinweis': 'Megjegyzés',
      'min': 'perc', 'uhr': '',
      'morgens': 'reggel', 'mittags': 'délben', 'abends': 'este', 'nachts': 'éjszaka',
      'med_satz': 'kérjük, {zeit} ne feledkezzen meg a gyógyszereiről',
      'wetter_titel': 'Időjárási figyelmeztetés az Ön lakóhelyére',
      'wetter_hinweis': 'Kérjük, lehetőség szerint maradjon otthon, és jelezze, ha segítségre van szüksége.',
      // „Tisztelt Asszonyom/Uram" heißt „Sehr geehrte Dame / sehr geehrter
      // Herr" und steht für sich allein — mit Namen dahinter wäre es doppelt
      // gemoppelt („Tisztelt Uram Padurean"). Vor einem Namen bleibt nur
      // „Tisztelt", wie im Türkischen „Sayın".
      'anrede_frau': 'Tisztelt', 'anrede_herr': 'Tisztelt',
      'anrede_neutral': 'Jó napot kívánok', 'gruss': 'Üdvözlettel',
      'schluss': 'Kérjük, erősítse meg a részvételét, vagy mondja le időben.',
      'tage': 'H,K,Sze,Cs,P,Szo,V',
    },
    'it': { 'datum': 'Data', 'uhrzeit': 'Ora',
      'dauer': 'Durata', 'ort': 'Luogo', 'betreff': 'Oggetto', 'hinweis': 'Nota',
      'min': 'min', 'uhr': '',
      'morgens': 'al mattino', 'mittags': 'a mezzogiorno', 'abends': 'di sera', 'nachts': 'di notte',
      'med_satz': 'si ricordi dei suoi farmaci',
      'wetter_titel': 'Allerta meteo per la sua zona',
      'wetter_hinweis': 'Resti a casa se possibile e ci contatti se ha bisogno di aiuto.',
      'anrede_frau': 'Gentile signora', 'anrede_herr': 'Gentile signor',
      'anrede_neutral': 'Buongiorno', 'gruss': 'Cordiali saluti',
      'schluss': 'La preghiamo di confermare la sua partecipazione o di disdire per tempo.',
      'tage': 'lun,mar,mer,gio,ven,sab,dom',
    },
    'lt': { 'datum': 'Data', 'uhrzeit': 'Laikas',
      'dauer': 'Trukmė', 'ort': 'Vieta', 'betreff': 'Tema', 'hinweis': 'Pastaba',
      'min': 'min', 'uhr': '',
      'morgens': 'ryte', 'mittags': 'vidurdienį', 'abends': 'vakare', 'nachts': 'naktį',
      'med_satz': 'nepamirškite savo vaistų',
      'wetter_titel': 'Įspėjimas apie orus jūsų vietovėje',
      'wetter_hinweis': 'Jei įmanoma, likite namuose ir praneškite mums, jei reikia pagalbos.',
      'anrede_frau': 'Gerbiamoji ponia', 'anrede_herr': 'Gerbiamasis pone',
      'anrede_neutral': 'Laba diena', 'gruss': 'Pagarbiai',
      'schluss': 'Prašome patvirtinti dalyvavimą arba laiku atšaukti.',
      'tage': 'pr,an,tr,kt,pn,št,sk',
    },
    'lv': { 'datum': 'Datums', 'uhrzeit': 'Laiks',
      'dauer': 'Ilgums', 'ort': 'Vieta', 'betreff': 'Temats', 'hinweis': 'Piezīme',
      'min': 'min', 'uhr': '',
      'morgens': 'no rīta', 'mittags': 'pusdienlaikā', 'abends': 'vakarā', 'nachts': 'naktī',
      'med_satz': 'lūdzu, neaizmirstiet savas zāles',
      'wetter_titel': 'Laikapstākļu brīdinājums jūsu dzīvesvietai',
      'wetter_hinweis': 'Lūdzu, palieciet mājās, ja iespējams, un sazinieties ar mums, ja nepieciešama palīdzība.',
      // Lettisch stellt „kungs"/„kundze" HINTER den Namen („Cienījamais
      // Padurean kungs"). Der Code kann den Titel nur davorstellen, also
      // bleibt er weg — „Cienījamais Padurean" ist korrekt und höflich.
      'anrede_frau': 'Cienījamā', 'anrede_herr': 'Cienījamais',
      'anrede_neutral': 'Labdien', 'gruss': 'Ar cieņu',
      'schluss': 'Lūdzu, apstipriniet savu dalību vai atsauciet to laikus.',
      'tage': 'Pirmd.,Otrd.,Trešd.,Ceturtd.,Piektd.,Sestd.,Svētd.',
    },
    'nb': { 'datum': 'Dato', 'uhrzeit': 'Tidspunkt',
      'dauer': 'Varighet', 'ort': 'Sted', 'betreff': 'Emne', 'hinweis': 'Merknad',
      'min': 'min', 'uhr': '',
      'morgens': 'om morgenen', 'mittags': 'midt på dagen', 'abends': 'om kvelden', 'nachts': 'om natten',
      'med_satz': 'husk medisinene dine',
      'wetter_titel': 'Værvarsel for området ditt',
      'wetter_hinweis': 'Bli hjemme hvis du kan, og ta kontakt hvis du trenger hjelp.',
      'anrede_frau': 'Kjære fru', 'anrede_herr': 'Kjære herr',
      'anrede_neutral': 'God dag', 'gruss': 'Med vennlig hilsen',
      'schluss': 'Vennligst bekreft at du kommer, eller meld fra i god tid.',
      'tage': 'man.,tir.,ons.,tor.,fre.,lør.,søn.',
    },
    'nl': { 'datum': 'Datum', 'uhrzeit': 'Tijd',
      'dauer': 'Duur', 'ort': 'Plaats', 'betreff': 'Onderwerp', 'hinweis': 'Opmerking',
      'min': 'min', 'uhr': '',
      'morgens': "'s ochtends", 'mittags': "'s middags", 'abends': "'s avonds", 'nachts': "'s nachts",
      'med_satz': 'denkt u aan uw medicijnen',
      'wetter_titel': 'Weerwaarschuwing voor uw woonplaats',
      'wetter_hinweis': 'Blijf zo mogelijk thuis en laat het ons weten als u hulp nodig heeft.',
      'anrede_frau': 'Geachte mevrouw', 'anrede_herr': 'Geachte heer',
      'anrede_neutral': 'Goedendag', 'gruss': 'Met vriendelijke groet',
      'schluss': 'Bevestig uw deelname of zeg tijdig af.',
      'tage': 'ma,di,wo,do,vr,za,zo',
    },
    'pl': { 'datum': 'Data', 'uhrzeit': 'Godzina',
      'dauer': 'Czas trwania', 'ort': 'Miejsce', 'betreff': 'Temat', 'hinweis': 'Uwaga',
      'min': 'min', 'uhr': '',
      'morgens': 'rano', 'mittags': 'w południe', 'abends': 'wieczorem', 'nachts': 'w nocy',
      'med_satz': 'prosimy pamiętać o lekach',
      'wetter_titel': 'Ostrzeżenie pogodowe dla Państwa miejscowości',
      'wetter_hinweis': 'Prosimy w miarę możliwości pozostać w domu i dać nam znać, jeśli potrzebują Państwo pomocy.',
      'anrede_frau': 'Szanowna Pani', 'anrede_herr': 'Szanowny Panie',
      'anrede_neutral': 'Dzień dobry', 'gruss': 'Z poważaniem',
      'schluss': 'Prosimy o potwierdzenie obecności lub odwołanie w odpowiednim czasie.',
      'tage': 'pon.,wt.,śr.,czw.,pt.,sob.,niedz.',
    },
    'pt': { 'datum': 'Data', 'uhrzeit': 'Hora',
      'dauer': 'Duração', 'ort': 'Local', 'betreff': 'Assunto', 'hinweis': 'Observação',
      'min': 'min', 'uhr': '',
      'morgens': 'de manhã', 'mittags': 'ao meio-dia', 'abends': 'à noite', 'nachts': 'durante a noite',
      'med_satz': 'não se esqueça dos seus medicamentos',
      'wetter_titel': 'Aviso meteorológico para a sua localidade',
      'wetter_hinweis': 'Se possível, fique em casa e avise-nos se precisar de ajuda.',
      'anrede_frau': 'Exma. Senhora', 'anrede_herr': 'Exmo. Senhor',
      'anrede_neutral': 'Bom dia', 'gruss': 'Com os melhores cumprimentos',
      'schluss': 'Confirme a sua presença ou cancele atempadamente.',
      'tage': 'seg.,ter.,qua.,qui.,sex.,sáb.,dom.',
    },
    'sk': { 'datum': 'Dátum', 'uhrzeit': 'Čas',
      'dauer': 'Trvanie', 'ort': 'Miesto', 'betreff': 'Predmet', 'hinweis': 'Poznámka',
      'min': 'min', 'uhr': '',
      'morgens': 'ráno', 'mittags': 'napoludnie', 'abends': 'večer', 'nachts': 'v noci',
      'med_satz': 'nezabudnite prosím na svoje lieky',
      'wetter_titel': 'Výstraha pred počasím pre vaše bydlisko',
      'wetter_hinweis': 'Zostaňte prosím podľa možnosti doma a ozvite sa nám, ak budete potrebovať pomoc.',
      'anrede_frau': 'Vážená pani', 'anrede_herr': 'Vážený pán',
      'anrede_neutral': 'Dobrý deň', 'gruss': 'S pozdravom',
      'schluss': 'Potvrďte prosím svoju účasť alebo sa včas ospravedlňte.',
      'tage': 'po,ut,st,št,pi,so,ne',
    },
    'sl': { 'datum': 'Datum', 'uhrzeit': 'Ura',
      'dauer': 'Trajanje', 'ort': 'Kraj', 'betreff': 'Zadeva', 'hinweis': 'Opomba',
      'min': 'min', 'uhr': '',
      'morgens': 'zjutraj', 'mittags': 'opoldne', 'abends': 'zvečer', 'nachts': 'ponoči',
      'med_satz': 'ne pozabite na svoja zdravila',
      'wetter_titel': 'Vremensko opozorilo za vaš kraj',
      'wetter_hinweis': 'Če je mogoče, ostanite doma in nam sporočite, če potrebujete pomoč.',
      'anrede_frau': 'Spoštovana gospa', 'anrede_herr': 'Spoštovani gospod',
      'anrede_neutral': 'Dober dan', 'gruss': 'S spoštovanjem',
      'schluss': 'Prosimo, potrdite udeležbo ali pravočasno odpovejte.',
      'tage': 'pon.,tor.,sre.,čet.,pet.,sob.,ned.',
    },
    // Serbisch durchgehend kyrillisch — so steht es auch in `app_sr.arb` der
    // Mitglieder-App und so gibt es NLLB zurück (srp_Cyrl, eine lateinische
    // Variante hat das Modell nicht). Zwei Schriften nebeneinander wären
    // verwirrender als eine.
    'sr': { 'datum': 'Датум', 'uhrzeit': 'Време',
      'dauer': 'Трајање', 'ort': 'Место', 'betreff': 'Предмет', 'hinweis': 'Напомена',
      'min': 'мин', 'uhr': '',
      'morgens': 'ујутро', 'mittags': 'у подне', 'abends': 'увече', 'nachts': 'ноћу',
      'med_satz': 'молимо не заборавите своје лекове',
      'wetter_titel': 'Упозорење на временске прилике за ваше место',
      'wetter_hinweis': 'Молимо останите код куће ако је могуће и јавите нам се ако вам треба помоћ.',
      'anrede_frau': 'Поштована госпођо', 'anrede_herr': 'Поштовани господине',
      'anrede_neutral': 'Добар дан', 'gruss': 'С поштовањем',
      'schluss': 'Молимо потврдите своје учешће или се благовремено одјавите.',
      'tage': 'пон,уто,сре,чет,пет,суб,нед',
    },
    'sv': { 'datum': 'Datum', 'uhrzeit': 'Tid',
      'dauer': 'Längd', 'ort': 'Plats', 'betreff': 'Ämne', 'hinweis': 'Anmärkning',
      'min': 'min', 'uhr': '',
      'morgens': 'på morgonen', 'mittags': 'mitt på dagen', 'abends': 'på kvällen', 'nachts': 'på natten',
      'med_satz': 'glöm inte dina mediciner',
      'wetter_titel': 'Vädervarning för din ort',
      'wetter_hinweis': 'Stanna hemma om du kan och hör av dig om du behöver hjälp.',
      'anrede_frau': 'Bästa fru', 'anrede_herr': 'Bäste herr',
      'anrede_neutral': 'God dag', 'gruss': 'Med vänliga hälsningar',
      'schluss': 'Bekräfta ditt deltagande eller lämna återbud i god tid.',
      'tage': 'mån,tis,ons,tors,fre,lör,sön',
    },
  };

  /// Sprachen in lateinischer Schrift — dort lohnt die Transliteration nach
  /// GSM-7 (160 statt 70 Zeichen je Segment). Bei ru/uk/ar würde sie den Text
  /// zerstören, da geht die SMS als UCS-2 raus.
  static const _lateinisch = {
    'de', 'en', 'ro', 'tr',
    // 2026-08-04: alle übrigen Vorlagen in lateinischer Schrift. Draußen
    // bleiben nur die vier anderen Schriften — bg, sr (kyrillisch), el
    // (griechisch), ru, uk, ar.
    'cs', 'da', 'es', 'et', 'fi', 'fr', 'hr', 'hu', 'it', 'lt', 'lv', 'nb',
    'nl', 'pl', 'pt', 'sk', 'sl', 'sv',
  };

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
  /// [maxSegments] ist die Notbremse gegen ausufernde Nachrichten, kein
  /// Sparzwang — der Verein hat eine SMS-Flat. Sechs Segmente sind bewusst
  /// großzügig gewählt: in UCS-2 (ru/uk/ar) fasst ein Segment nur 67 Zeichen,
  /// bei vier wäre dort regelmäßig die Notiz weggefallen, während dieselbe
  /// Nachricht auf Deutsch vollständig ankam. Muss doch gekürzt werden, trifft
  /// es zuerst die Notiz, dann den Ort; Datum und Uhrzeit bleiben immer stehen.
  static String buildTerminSms({
    required DateTime terminDate,
    required String title,
    required String location,
    String? description,
    int? durationMinutes,
    String? language,
    String? vorname,
    String? nachname,
    String? geschlecht,
    String? absender,
    int maxSegments = 6,
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

    final kopf = _anrede(w, sprache, latein,
        vorname: vorname, nachname: nachname, geschlecht: geschlecht);
    final ort = feld(location);
    final betreff = feld(title);
    var notiz = feld(description);

    // Aufbau wie ein kurzer Brief: Anrede, Angaben, Bitte um Rückmeldung,
    // Grußformel, Absender.
    final komma = w['komma'] ?? ',';

    String zusammen(String ortText, String notizText) {
      final roh = [
          '$kopf$komma',
          '',
          '${w['datum']}: $datum',
          '${w['uhrzeit']}: $uhrzeit',
          if (betreff.isNotEmpty) '${w['betreff']}: $betreff',
          if (ortText.isNotEmpty) '${w['ort']}: $ortText',
          if (notizText.isNotEmpty) '${w['hinweis']}: $notizText',
          '',
          w['schluss']!,
          '',
          w['gruss']!,
          absender ?? 'ICD360S e.V.',
      ].join('\n');
      // Erst am fertigen Text: die Vorlagenwörter selbst tragen Diakritika
      // („Cu stimă", „Saygılarımızla"), die nicht ins GSM-7-Alphabet passen.
      // Ohne diesen Durchgang kippte die ganze rumänische und türkische SMS in
      // UCS-2 und kostete statt drei plötzlich fünf Segmente.
      return latein ? toGsm7(roh) : sanitize(roh);
    }

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

  /// Baut die Anrede: „Sehr geehrte Frau Weber" bzw. „Sehr geehrter Herr
  /// Weber". Ist in Stufe 1 kein Geschlecht hinterlegt — das ist bei 18 von 50
  /// Mitgliedern der Fall — wird mit „Guten Tag Anna Weber" ohne Frau/Herr
  /// angeredet, statt zu raten oder ein hölzernes „Sehr geehrte(r)"
  /// hinzuschreiben.
  static String _anrede(
    Map<String, String> w,
    String sprache,
    bool latein, {
    String? vorname,
    String? nachname,
    String? geschlecht,
  }) {
    String sauber(String? v) {
      final s = sanitize(v ?? '');
      return latein ? toGsm7(s) : s;
    }

    final vn = sauber(vorname);
    final nn = sauber(nachname);
    final form = anredeform(geschlecht);

    // Ohne Namen bleibt nur der Gruß selbst — besser als „Sehr geehrte Frau ,".
    if (vn.isEmpty && nn.isEmpty) return w['anrede_neutral']!;

    // Förmlich wird nur der Nachname genannt; fehlt er, tut es der Vorname.
    final nachnameOderVorname = nn.isNotEmpty ? nn : vn;
    final vollerName = [vn, nn].where((t) => t.isNotEmpty).join(' ');

    // Türkisch stellt den Titel hinter den Namen, deshalb dort immer der volle
    // Name hinter „Sayın" — die anderen Sprachen bleiben beim Nachnamen.
    if (sprache == 'tr') return '${w['anrede_neutral']} $vollerName';

    switch (form) {
      case Anredeform.frau:
        return '${w['anrede_frau']} $nachnameOderVorname';
      case Anredeform.herr:
        return '${w['anrede_herr']} $nachnameOderVorname';
      case Anredeform.neutral:
        return '${w['anrede_neutral']} $vollerName';
    }
  }

  /// Baut die Medikamenten-Erinnerung in der Sprache des Mitglieds.
  ///
  /// Die Namen der Medikamente stehen bewusst drin — so entschieden, weil eine
  /// Erinnerung ohne Namen bei mehreren Präparaten zu unterschiedlichen Zeiten
  /// nicht weiterhilft. Genau deshalb verlangt der Versand eine ausdrückliche
  /// Einwilligung (Art. 9 DSGVO): der Name verrät die Diagnose.
  ///
  /// [slot] ist eine der vier Tageszeiten (`morgens`/`mittags`/`abends`/
  /// `nachts`), [medikamente] die vom Server zusammengestellte Liste.
  static String buildMedikamentSms({
    required String slot,
    required String medikamente,
    String? language,
    String? vorname,
    String? nachname,
    String? geschlecht,
    String? absender,
    int maxSegments = 6,
  }) {
    final sprache = _normalizeLanguage(language);
    final w = _sprachen[sprache]!;
    final latein = _lateinisch.contains(sprache);
    final komma = w['komma'] ?? ',';

    final anrede = _anrede(w, sprache, latein,
        vorname: vorname, nachname: nachname, geschlecht: geschlecht);
    final zeit = w[slot] ?? w['morgens']!;

    // Die Tageszeit gehört an die Stelle, an der die jeweilige Sprache sie
    // verlangt — nicht pauschal hinten dran. In 25 der 28 Vorlagen ist das
    // dasselbe, in dreien nicht:
    //   tr  „lutfen ilaclarinizi almayi unutmayin sabah"      → verbfinal
    //   hu  „… ne feledkezzen meg a gyógyszereiről reggel"    → dito
    //   es  „no olvide sus medicamentos, por favor por la mañana" → doppelt
    // Diese drei tragen deshalb einen Platzhalter `{zeit}` mitten im Satz.
    // Der Platzhalter wird hier ersetzt, also lange bevor toGsm7() läuft —
    // `{` und `}` kämen sonst als Erweiterungszeichen in die Segmentzählung.
    final muster = w['med_satz']!;
    final medSatz = muster.contains('{zeit}')
        ? muster.replaceFirst('{zeit}', zeit)
        : '$muster $zeit';

    String bauen(String liste) {
      final roh = [
        '$anrede$komma',
        '',
        '$medSatz:',
        liste,
        '',
        w['gruss']!,
        absender ?? 'ICD360S e.V.',
      ].join('\n');
      return latein ? toGsm7(roh) : sanitize(roh);
    }

    var liste = latein ? toGsm7(sanitize(medikamente)) : sanitize(medikamente);
    var text = bauen(liste);
    if (segments(text) <= maxSegments) return text;

    // Zu viele Präparate für eine Nachricht: lieber die Liste kürzen als die
    // Erinnerung ganz ausfallen zu lassen — der Anstoß ist das Wichtige.
    for (final grenze in [300, 200, 120, 60]) {
      liste = _kuerzen(liste, grenze);
      text = bauen(liste);
      if (segments(text) <= maxSegments) return text;
    }
    return text;
  }

  /// Baut die Wetterwarnung in der Sprache des Mitglieds.
  ///
  /// Nur für Warnungen ab Stufe „schwer" gedacht — die Schwelle setzt der
  /// Server. Eine mäßige Windwarnung um 23 Uhr rechtfertigt keine SMS, und wer
  /// zu oft geweckt wird, liest die Nachricht nicht mehr, wenn es zählt.
  ///
  /// [event] und [headline] kommen unübersetzt vom DWD — es sind amtliche
  /// Formulierungen, und eine maschinelle Übersetzung davon wäre schlechter
  /// als das Original.
  static String buildWetterSms({
    required String event,
    required String headline,
    required String severity,
    String? language,
    String? vorname,
    String? nachname,
    String? geschlecht,
    String? absender,
    int maxSegments = 6,
  }) {
    final sprache = _normalizeLanguage(language);
    final w = _sprachen[sprache]!;
    final latein = _lateinisch.contains(sprache);
    final komma = w['komma'] ?? ',';

    final anrede = _anrede(w, sprache, latein,
        vorname: vorname, nachname: nachname, geschlecht: geschlecht);
    final stufe = switch (severity) {
      'extreme' => 'AKUT',
      'severe' => 'Schwer',
      _ => '',
    };

    String bauen(String kopfzeile) {
      final roh = [
        '$anrede$komma',
        '',
        '${w['wetter_titel']}:',
        kopfzeile,
        '',
        w['wetter_hinweis']!,
        '',
        w['gruss']!,
        absender ?? 'ICD360S e.V.',
      ].join('\n');
      return latein ? toGsm7(roh) : sanitize(roh);
    }

    final ereignis = [
      if (event.trim().isNotEmpty) event.trim(),
      if (stufe.isNotEmpty) '($stufe)',
    ].join(' ');
    var kopf = [ereignis, headline.trim()].where((t) => t.isNotEmpty).join(' - ');
    kopf = latein ? toGsm7(sanitize(kopf)) : sanitize(kopf);

    var text = bauen(kopf);
    if (segments(text) <= maxSegments) return text;

    // DWD-Wortlaute können sehr lang werden; lieber kürzen als gar nicht warnen.
    for (final grenze in [200, 140, 90]) {
      text = bauen(_kuerzen(kopf, grenze));
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
