/// Ergebnis der Virenprüfung EINES Anhangs.
///
/// Der Scan läuft auf unserem eigenen Server (ClamAV), nicht bei einem
/// fremden Dienst — der Anhang verlässt das Haus nie.
///
/// ⚠️ Warum genau einmal geprüft wird: eine Mail wird von dovecot einmal
/// geschrieben und nie umgeschrieben. Die Bytes eines Anhangs stehen damit für
/// immer fest — ein Anhang kann sich nicht „neu infizieren". Der Server merkt
/// sich das Ergebnis unter dem sha256 des Inhalts, also auch dann, wenn
/// derselbe Anhang in fünf Mails liegt oder die Nachricht den Ordner wechselt.
///
/// ⚠️ Was sich sehr wohl ändert, ist der Signaturstand von ClamAV (mehrmals
/// täglich). „Sauber" ist deshalb keine Eigenschaft der Datei, sondern eine
/// Aussage darüber, was der Scanner in DIESEM Moment wusste. Genau deshalb
/// trägt die Plakette das Datum: „geprüft 28.08." ist wahr, „sicher" wäre es
/// nicht. Wer ein Jahr altes Dokument aus der Hand gibt, kann erneut prüfen.
library;

enum MailScanWert {
  /// Noch nie geprüft — bekommt bewusst KEIN Zeichen.
  unbekannt,

  /// Läuft gerade.
  laeuft,

  /// Von beiden Prüfern freigegeben, mit Datum und Signaturstand.
  sauber,

  /// ⚠️ Nur die ERWEITERTE Signaturquelle hat angeschlagen (Sanesecurity,
  /// URLhaus, rfxn, YARA), die amtliche ClamAV-Datenbank nicht.
  ///
  /// Wird angezeigt, aber NICHT gesperrt. Sanesecurity empfiehlt für diese
  /// Datenbanken selbst „score instead of block", und die Dateien hier sind
  /// Arztbriefe, Bescheide und Kontoauszüge — eine fälschlich gesperrte
  /// Behördenpost ist ein echter Schaden.
  verdaechtig,

  /// Die amtliche ClamAV-Datenbank hat angeschlagen — dieselbe, auf die hin
  /// clamav-milter eine Mail abweisen würde. Öffnen, Herunterladen,
  /// Weiterleiten und Sichern sind gesperrt.
  befallen,

  /// ⚠️ Fail-closed: Scanner nicht erreichbar, Datei zu groß, Abbruch.
  /// Ausdrücklich NICHT dasselbe wie „sauber" und niemals grün.
  fehler,
}

class MailScanBefund {
  final MailScanWert wert;

  /// Name der Signatur bei einem Treffer, sonst der Grund des Fehlers.
  final String? signatur;

  /// Wann geprüft wurde. Ohne dieses Datum ist „sauber" eine leere Behauptung.
  final DateTime? geprueftAm;

  /// Signaturstand von ClamAV, z. B. `28106`.
  final String? signaturen;

  /// Wie viele Prüfer angeschlagen haben und wie viele überhaupt geantwortet
  /// haben — das „X von N" der Anzeige.
  final int treffer;
  final int geprueft;

  const MailScanBefund({
    required this.wert,
    this.signatur,
    this.geprueftAm,
    this.signaturen,
    this.treffer = 0,
    this.geprueft = 0,
  });

  static const unbekannt = MailScanBefund(wert: MailScanWert.unbekannt);
  static const laeuft = MailScanBefund(wert: MailScanWert.laeuft);

  /// ⚠️ Gesperrt wird NUR bei [MailScanWert.befallen], also wenn die amtliche
  /// ClamAV-Datenbank angeschlagen hat. 'verdaechtig' sperrt ausdrücklich
  /// nicht: dort hat allein eine Drittanbieter-Signatur getroffen, und deren
  /// Fehlalarmrate rechtfertigt kein Blockieren von Behördenpost.
  bool get gesperrt => wert == MailScanWert.befallen;

  /// „2 von 2 Prüfern" — leer, solange nichts geprüft wurde.
  String get quote => geprueft <= 0 ? '' : '$treffer von $geprueft Prüfern';

  factory MailScanBefund.ausJson(Map<String, dynamic> j) {
    final roh = '${j['status'] ?? ''}';
    final wert = switch (roh) {
      'sauber' => MailScanWert.sauber,
      'verdaechtig' => MailScanWert.verdaechtig,
      'befallen' => MailScanWert.befallen,
      'fehler' => MailScanWert.fehler,
      // ⚠️ Alles Unbekannte ist NICHT sauber. Eine neuere Server-Fassung, die
      // einen weiteren Zustand einführt, darf hier nie als Freigabe landen.
      _ => MailScanWert.fehler,
    };
    return MailScanBefund(
      wert: wert,
      signatur: (j['signatur'] as String?)?.trim().isEmpty ?? true
          ? null
          : '${j['signatur']}'.trim(),
      geprueftAm: DateTime.tryParse('${j['geprueft_am'] ?? ''}'),
      signaturen: (j['signaturen'] as String?)?.trim().isEmpty ?? true
          ? null
          : '${j['signaturen']}'.trim(),
      treffer: (j['treffer'] as num?)?.toInt() ?? 0,
      geprueft: (j['geprueft'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Der schlechteste Befund einer Nachricht gewinnt.
///
/// ⚠️ Ein sauberer Anhang entschärft keinen befallenen — deshalb NICHT die
/// Mehrheit und nicht der erste Treffer, sondern das schlimmste Ergebnis.
MailScanWert mailScanGesamt(Iterable<MailScanBefund> befunde) {
  // Reihenfolge = Schwere. Der erste Fund gewinnt.
  const rang = [
    MailScanWert.befallen,
    MailScanWert.verdaechtig,
    MailScanWert.fehler,
    MailScanWert.laeuft,
    MailScanWert.sauber,
  ];
  final vorhanden = befunde.map((b) => b.wert).toSet();
  for (final w in rang) {
    if (vorhanden.contains(w)) return w;
  }
  return MailScanWert.unbekannt;
}

/// Den Sammelstand der Liste (`{"583":"sauber"}`) in einen Wert übersetzen.
MailScanWert mailScanWertAusText(Object? roh) => switch ('${roh ?? ''}') {
      'sauber' => MailScanWert.sauber,
      'verdaechtig' => MailScanWert.verdaechtig,
      'befallen' => MailScanWert.befallen,
      'fehler' => MailScanWert.fehler,
      // `leer` = geprüft, aber gar kein Anhang. Kein Zeichen, nichts zu sagen.
      _ => MailScanWert.unbekannt,
    };

/// `28.08.` — kurz, weil es neben den Dateinamen passen muss.
String mailScanDatumKurz(DateTime? d) {
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
}

/// Der ausführliche Satz für das lange Antippen — hier ist Platz für die
/// Einschränkung, die auf der Plakette nicht hinpasst.
String mailScanErklaerung(MailScanBefund b) {
  final d = b.geprueftAm;
  final wann = d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'
          ' um ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';
  final stand = b.signaturen == null ? '' : ' (Signaturen ${b.signaturen})';
  final quote = b.quote.isEmpty ? '' : ' (${b.quote})';
  switch (b.wert) {
    case MailScanWert.verdaechtig:
      return 'Auffällig$quote: nur die erweiterte Signaturquelle hat '
          'angeschlagen (${b.signatur ?? 'ohne Namen'}), die amtliche '
          'ClamAV-Datenbank nicht.\n\nGeprüft am $wann$stand. Die Datei ist '
          'deshalb NICHT gesperrt: die Zusatzsignaturen finden mehr, erzeugen '
          'aber auch mehr Fehlalarme, und ein fälschlich gesperrter '
          'Behördenbescheid wäre der größere Schaden. Wenn Sie die Datei nicht '
          'erwartet haben, öffnen Sie sie besser nicht.';
    case MailScanWert.sauber:
      return 'Von unserem eigenen Virenscanner geprüft am $wann$stand$quote — '
          'ohne Befund.\n\nDie Datei selbst kann sich nicht mehr ändern, '
          'deshalb wird sie nur einmal geprüft. Die Virensignaturen ändern '
          'sich aber täglich: geprüft wurde mit dem Stand von $wann, nicht mit '
          'dem von heute. Bei einer alten Datei lohnt sich vor dem Weitergeben '
          'eine erneute Prüfung.';
    case MailScanWert.befallen:
      return 'Schadsoftware erkannt: ${b.signatur ?? 'unbekannte Signatur'}'
          '$quote.\n\nGeprüft am $wann$stand. Öffnen, Herunterladen, '
          'Weiterleiten und das Sichern in der Cloud sind gesperrt.';
    case MailScanWert.fehler:
      return 'Die Prüfung ist nicht zustande gekommen'
          '${b.signatur == null ? '' : ': ${b.signatur}'}.\n\n'
          'Das heißt ausdrücklich NICHT, dass die Datei sauber ist — es heißt, '
          'dass nichts über sie bekannt ist.';
    case MailScanWert.laeuft:
      return 'Die Datei wird gerade von unserem Virenscanner geprüft.';
    case MailScanWert.unbekannt:
      return 'Dieser Anhang wurde noch nicht geprüft.';
  }
}
