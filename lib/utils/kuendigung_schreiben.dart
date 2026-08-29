/// Baut Betreff und Wortlaut einer schriftlichen Kündigung.
///
/// ⚠️ Reine Funktionen, kein Widget und kein Netz. Der Wortlaut einer
/// Kündigung ist der Teil, der vor Gericht zählt — er muss prüfbar sein,
/// ohne dass jemand einen Dialog öffnet und auf einen Knopf drückt.
///
/// Denselben Text bekommen PDF (Fax) und E-Mail. ⚠️ Nur EINE Stelle baut
/// ihn: zwei Fassungen laufen auseinander, und dann steht im Fax etwas
/// anderes als in der Mail — bei einem einseitigen Rechtsgeschäft ist das
/// kein Schönheitsfehler, sondern zwei verschiedene Erklärungen.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Wie gekündigt wird.
enum KuendigungsArt {
  /// Zum nächstmöglichen Termin — die sichere Wahl, solange das
  /// Ablaufdatum nicht feststeht. Kann keine Frist reissen.
  naechstmoeglich,

  /// Zu einem bestimmten Datum, das der Mensch eingetragen hat.
  zumDatum,

  /// Sonderkündigungsrecht (Beitragserhöhung, Schadenfall, Umzug …).
  ausserordentlich,
}

/// Wer unterschreibt.
///
/// ⚠️ Diese Wahl entscheidet nicht über die Höflichkeitsform, sondern über
/// die Wirksamkeit. Unterschreibt der Verein als Bevollmächtigter, kann der
/// Empfänger die Kündigung nach § 174 S. 1 BGB unverzüglich zurückweisen,
/// wenn keine Vollmachtsurkunde vorgelegt wird — und per Fax oder E-Mail
/// lässt sich eine Urkunde nicht vorlegen. Unterschreibt das Mitglied
/// selbst, stellt sich die Frage gar nicht.
enum KuendigungsUnterzeichner { mitglied, verein }

/// Alles, was in das Schreiben gehört.
class KuendigungsDaten {
  /// Name des Vertragspartners, z. B. „Generali Deutschland Versicherung AG".
  final String empfaengerName;
  final String empfaengerStrasse;
  final String empfaengerPlzOrt;

  /// Name des Versicherungsnehmers / Vertragsinhabers.
  final String absenderName;
  final String absenderStrasse;
  final String absenderPlzOrt;

  /// Was gekündigt wird — „Unfallversicherung", „Mobilfunkvertrag" …
  final String vertragsBezeichnung;

  /// Die Nummer, unter der der Vertrag geführt wird.
  final String vertragsNummer;

  /// Wie diese Nummer beim Empfänger heisst.
  final String nummerLabel;

  /// Kundennummer, falls vorhanden — manche Häuser finden den Vertrag nur
  /// darüber.
  final String kundenNummer;

  /// Rufnummer bei Telefonverträgen.
  final String rufNummer;

  final KuendigungsArt art;

  /// Nur bei [KuendigungsArt.zumDatum] — deutsches Datum, z. B. „17.06.2027".
  final String zumDatum;

  /// Nur bei [KuendigungsArt.ausserordentlich] — der Grund, im Klartext.
  final String grund;

  final KuendigungsUnterzeichner unterzeichner;

  /// Name des Vereins, wenn der Verein unterschreibt.
  final String vereinName;

  /// Wohin die Bestätigung gehen soll.
  final String bestaetigungAn;

  /// Ob das SEPA-Mandat mitwiderrufen wird.
  final bool sepaWiderrufen;

  /// Freie Zusatzsätze des Vorsitzenden.
  final String zusatz;

  /// Datum des Schreibens, deutsch.
  final String datum;

  const KuendigungsDaten({
    required this.empfaengerName,
    this.empfaengerStrasse = '',
    this.empfaengerPlzOrt = '',
    required this.absenderName,
    this.absenderStrasse = '',
    this.absenderPlzOrt = '',
    required this.vertragsBezeichnung,
    required this.vertragsNummer,
    this.nummerLabel = 'Vertragsnummer',
    this.kundenNummer = '',
    this.rufNummer = '',
    this.art = KuendigungsArt.naechstmoeglich,
    this.zumDatum = '',
    this.grund = '',
    this.unterzeichner = KuendigungsUnterzeichner.mitglied,
    this.vereinName = '',
    this.bestaetigungAn = '',
    this.sepaWiderrufen = true,
    this.zusatz = '',
    required this.datum,
  });
}

/// Wandelt `2027-06-17` in `17.06.2027`. Alles andere bleibt, wie es ist —
/// ein Mensch tippt das Datum oft schon deutsch ein.
String kuendigungDatumDeutsch(String roh) {
  final s = roh.trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return s;
  return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// Die Betreffzeile.
///
/// ⚠️ Die Nummer gehört in den Betreff, nicht erst in den Fliesstext. In
/// grossen Häusern sortiert die Poststelle nach dem Betreff; eine Kündigung
/// ohne Nummer landet im allgemeinen Eingang und ist Wochen später immer
/// noch nicht zugeordnet — die Frist läuft trotzdem.
String kuendigungBetreff(KuendigungsDaten d) {
  final teile = <String>['Kündigung'];
  if (d.vertragsBezeichnung.trim().isNotEmpty) {
    teile.add(d.vertragsBezeichnung.trim());
  }
  // ⚠️ Trenner ist der Mittelpunkt (U+00B7), NICHT der Gedankenstrich.
  // Gemessen am gerenderten PDF: die eingebaute Helvetica des pdf-Pakets
  // kann ausschliesslich Latin-1. Der ganze CP1252-Block 0x80–0x9F fehlt
  // ihr — alle 27 Zeichen, darunter — – „ " … und das EURO-ZEICHEN. Sie
  // erscheinen als schwarzes Kästchen, und zwar erst auf dem Blatt beim
  // Empfänger: am Bildschirm und in `flutter analyze` sieht alles richtig
  // aus. Ein Test hält den Zeichenvorrat fest.
  final b = StringBuffer(teile.join(' · '));
  if (d.vertragsNummer.trim().isNotEmpty) {
    b.write(' · ${d.nummerLabel}: ${d.vertragsNummer.trim()}');
  }
  return b.toString();
}

/// Der Wortlaut.
///
/// [alsBrief] steuert nur die Grussformel-Umgebung: im PDF steht der
/// Betreff darüber als eigene Zeile, in der E-Mail steht er im Kopf. Der
/// Kern ist beide Male derselbe.
String kuendigungBrieftext(KuendigungsDaten d, {bool alsBrief = true}) {
  final b = StringBuffer();
  b.writeln('Sehr geehrte Damen und Herren,');
  b.writeln();

  // ⚠️ Die Kennzeichnung des Vertrages wird im Text WIEDERHOLT, obwohl sie
  // im Betreff steht. Ein Sachbearbeiter, der den Betreff abschneidet oder
  // die Mail weiterleitet, muss den Vertrag am Fliesstext erkennen können.
  final kennung = <String>[];
  if (d.vertragsNummer.trim().isNotEmpty) {
    kennung.add('${d.nummerLabel} ${d.vertragsNummer.trim()}');
  }
  if (d.kundenNummer.trim().isNotEmpty) {
    kennung.add('Kundennummer ${d.kundenNummer.trim()}');
  }
  if (d.rufNummer.trim().isNotEmpty) {
    kennung.add('Rufnummer ${d.rufNummer.trim()}');
  }
  final bez = d.vertragsBezeichnung.trim().isEmpty
      ? 'den bei Ihnen geführten Vertrag'
      : 'den bei Ihnen geführten Vertrag ${d.vertragsBezeichnung.trim()}';
  final kennungText = kennung.isEmpty ? '' : ' (${kennung.join(', ')})';

  switch (d.art) {
    case KuendigungsArt.naechstmoeglich:
      b.writeln(
        'hiermit kündige ich $bez$kennungText ordentlich zum '
        'nächstmöglichen Zeitpunkt.',
      );
      break;
    case KuendigungsArt.zumDatum:
      final wann = d.zumDatum.trim().isEmpty
          ? 'zum nächstmöglichen Zeitpunkt'
          : 'zum ${kuendigungDatumDeutsch(d.zumDatum)}';
      b.writeln('hiermit kündige ich $bez$kennungText ordentlich $wann.');
      break;
    case KuendigungsArt.ausserordentlich:
      final grund = d.grund.trim().isEmpty ? '' : ' Grund: ${d.grund.trim()}.';
      b.writeln(
        'hiermit kündige ich $bez$kennungText außerordentlich zum '
        'nächstzulässigen Zeitpunkt.$grund',
      );
      break;
  }
  b.writeln(
    'Einer stillschweigenden Verlängerung des Vertrages widerspreche '
    'ich ausdrücklich.',
  );
  b.writeln();

  // ⚠️ Die Hilfskündigung ist kein Füllsatz. Ohne sie ist eine Kündigung
  // zum falsch berechneten Termin schlicht unwirksam und muss neu erklärt
  // werden — meist nach Ablauf der Frist. Mit ihr wirkt sie zum nächsten
  // zulässigen Termin weiter.
  b.writeln(
    'Sollte eine Kündigung zu dem genannten Zeitpunkt nicht möglich '
    'sein, kündige ich hilfsweise zum nächstzulässigen Termin und bitte um '
    'Mitteilung dieses Termins.',
  );
  b.writeln();
  final an = d.bestaetigungAn.trim().isEmpty
      ? ''
      : ' an ${d.bestaetigungAn.trim()}';
  b.writeln(
    'Bitte bestätigen Sie mir den Zugang dieser Kündigung sowie das '
    'genaue Vertragsende in Textform$an.',
  );

  if (d.sepaWiderrufen) {
    b.writeln();
    b.writeln(
      'Ferner widerrufe ich ein etwaig erteiltes '
      'SEPA-Lastschriftmandat mit Wirkung zum Vertragsende.',
    );
  }

  if (d.unterzeichner == KuendigungsUnterzeichner.verein) {
    b.writeln();
    // ⚠️ Der Hinweis ersetzt die Urkunde NICHT (§ 174 S. 1 BGB). Er nennt
    // sie nur, damit der Empfänger weiss, dass sie existiert und wo sie
    // ist — die Zurückweisung bleibt ihm möglich, solange sie nicht
    // vorliegt.
    b.writeln(
      'Die auf den Verein lautende Vollmacht des Vertragsinhabers '
      'ist beigefügt. Das Original wird auf Anforderung unverzüglich '
      'nachgereicht.',
    );
  }

  if (d.zusatz.trim().isNotEmpty) {
    b.writeln();
    b.writeln(d.zusatz.trim());
  }

  b.writeln();
  b.writeln('Mit freundlichen Grüßen');
  b.writeln();
  b.writeln();
  if (d.unterzeichner == KuendigungsUnterzeichner.verein) {
    if (d.vereinName.trim().isNotEmpty) b.writeln(d.vereinName.trim());
    b.writeln('i. V. für ${d.absenderName.trim()}');
  } else {
    b.writeln(d.absenderName.trim());
  }
  return b.toString().trimRight();
}

/// Was fehlt, bevor das Schreiben rausgehen darf.
///
/// ⚠️ Die Nummer ist die einzige Pflichtangabe, die niemand nachreichen
/// kann: ohne sie kann der Empfänger die Erklärung keinem Vertrag zuordnen,
/// und eine nicht zuordenbare Kündigung wirkt nicht. Alles andere lässt
/// sich hinterher klären.
List<String> kuendigungFehlendeAngaben(KuendigungsDaten d) {
  final fehlt = <String>[];
  if (d.vertragsNummer.trim().isEmpty) fehlt.add(d.nummerLabel);
  if (d.absenderName.trim().isEmpty) fehlt.add('Name des Vertragsinhabers');
  if (d.empfaengerName.trim().isEmpty) fehlt.add('Empfänger');
  if (d.art == KuendigungsArt.ausserordentlich && d.grund.trim().isEmpty) {
    fehlt.add('Grund der außerordentlichen Kündigung');
  }
  return fehlt;
}

/// Wie die Nummer beim jeweiligen Vertragstyp heisst.
///
/// ⚠️ Es ist DIESELBE Spalte (`mitglied_vertraege.vertragsnummer`), nur
/// anders beschriftet. Eine zweite Spalte „versicherungsscheinnummer"
/// daneben wäre die schlechtere Lösung: dann stünde die Nummer mal hier,
/// mal dort, und das Kündigungsschreiben müsste raten, welche der beiden
/// gemeint ist. Bei einem Schreiben, das einen Vertrag beenden soll, ist
/// Raten die teuerste Variante.
String kuendigungNummerLabel(String kategorie) => kategorie == 'versicherung'
    ? 'Versicherungsscheinnummer'
    : 'Vertragsnummer';

/// Das Schreiben als PDF — genau das, was per Fax rausgeht.
///
/// ⚠️ Helvetica ist die einzige Schrift, die ein PDF ohne eingebettete
/// Datei mitbringt, und sie kann nur WinAnsi (CP1252). Ein Zeichen
/// ausserhalb davon wird zu einem leeren Kästchen — sichtbar erst auf dem
/// gedruckten Blatt beim Empfänger. Ein Test hält Betreff und Brieftext
/// deshalb in WinAnsi fest.
///
/// [sendewegVermerk] steht über dem Anschriftenfeld („Per Telefax an …") —
/// der Empfänger soll dem Blatt ansehen, auf welchem Weg die Erklärung kam.
Future<Uint8List> kuendigungAlsPdf(
  KuendigungsDaten d, {
  String sendewegVermerk = '',
}) {
  final doc = pw.Document();
  final empf = <String>[
    d.empfaengerName,
    d.empfaengerStrasse,
    d.empfaengerPlzOrt,
  ].map((z) => z.trim()).where((z) => z.isNotEmpty).toList();
  final abs = <String>[
    d.absenderName,
    d.absenderStrasse,
    d.absenderPlzOrt,
  ].map((z) => z.trim()).where((z) => z.isNotEmpty).toList();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      // DIN 5008 Form B: 25 mm links, 20 mm rechts, 45 mm oben (Sichtfenster),
      // 25 mm unten.
      margin: const pw.EdgeInsets.fromLTRB(
        25 * PdfPageFormat.mm,
        45 * PdfPageFormat.mm,
        20 * PdfPageFormat.mm,
        25 * PdfPageFormat.mm,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Absenderzeile klein über dem Anschriftenfeld — so steht sie im
          // Fenstercouvert an der richtigen Stelle.
          if (abs.isNotEmpty)
            pw.Text(
              abs.join(' · '),
              style: const pw.TextStyle(fontSize: 8, lineSpacing: 1),
            ),
          pw.SizedBox(height: 12),
          for (final z in empf)
            pw.Text(z, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
          if (sendewegVermerk.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              sendewegVermerk.trim(),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(d.datum, style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            kuendigungBetreff(d),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            kuendigungBrieftext(d),
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
