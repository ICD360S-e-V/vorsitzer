/// Die drei Rückfragen vor dem Senden.
///
/// Alle drei fangen Fehler ab, die man **nach** dem Senden nicht mehr
/// zurücknehmen kann. Sie sind bewusst als reine Funktionen geschrieben: eine
/// Prüfung, die man nicht in einem Test durchspielen kann, ist eine Prüfung,
/// der man nicht glauben darf.
library;

import 'mail_adressbuch.dart' show mailAdressenAufteilen;

/// Was vor dem Senden auffällt.
enum MailSendeWarnung {
  /// Der Text kündigt einen Anhang an, es hängt aber keiner dran.
  anhangVergessen,

  /// Viele sichtbare Empfänger — jeder sieht die Adressen aller anderen.
  offeneEmpfaengerliste,
}

/// Ein Befund mit fertigem Text für die Rückfrage.
class MailSendeBefund {
  final MailSendeWarnung art;
  final String titel;
  final String text;

  /// Beschriftung des Knopfes, der den Befund behebt — null, wenn es nichts
  /// automatisch zu beheben gibt.
  final String? behebenLabel;

  const MailSendeBefund({
    required this.art,
    required this.titel,
    required this.text,
    this.behebenLabel,
  });
}

// „anbei", „im Anhang", „beigefügt", „anhängend", „attached", „enclosed" …
//
// ⚠️ Wortgrenzen sind Pflicht. Ohne sie trifft „anbei" mitten in „Anbeißen" und
// „anlage" in „Anlagenbau" — und eine Rückfrage, die grundlos kommt, wird nach
// dem dritten Mal weggeklickt, ohne gelesen zu werden.
//
// ⚠️ Und `\b` reicht dafür NICHT: Dart zählt zu `\w` nur ASCII, also gilt
// zwischen „i" und „ß" eine Wortgrenze und `\banbei\b` trifft „Anbeißen"
// trotzdem. Genau daran ist die erste Fassung gescheitert. Deshalb eigene
// Grenzen, die die deutschen Buchstaben mitzählen.
const _wortRand = r'a-zA-Z0-9_äöüßÄÖÜ';
final _anhangWorte = RegExp(
    '(?<![$_wortRand])'
    r'(anbei|beigef(ü|ue)gt|beiliegend|im\s+anhang|als\s+anhang|'
    r'anh(ä|ae)ngend|in\s+der\s+anlage|als\s+anlage|'
    r'attached|enclosed|see\s+attachment)'
    '(?![$_wortRand])',
    caseSensitive: false);

/// Schneidet weg, was der Absender nicht selbst geschrieben hat.
///
/// ⚠️ Ohne das ist die Prüfung praktisch wertlos: bei jeder Antwort auf eine
/// Mail, in der „anbei“ stand, käme die Rückfrage — obwohl das Wort aus dem
/// Zitat stammt. Geschnitten wird an der ersten Zitatzeile (`> `) und an der
/// Signaturtrennlinie (`-- `), je nachdem, was zuerst kommt.
String mailEigenerText(String koerper) {
  final zeilen = koerper.split('\n');
  final eigen = <String>[];
  for (final z in zeilen) {
    final t = z.trimLeft();
    if (t.startsWith('>')) break;
    if (z.trimRight() == '--' || z.trimRight() == '-- ') break;
    // Die Kopfzeile, die unser eigener Zitat-Aufbau voranstellt.
    if (RegExp(r'^Am .+ schrieb .+:$').hasMatch(t)) break;
    eigen.add(z);
  }
  return eigen.join('\n');
}

/// Kündigt der selbst geschriebene Text einen Anhang an?
bool mailKuendigtAnhangAn(String koerper) =>
    _anhangWorte.hasMatch(mailEigenerText(koerper));

/// Ab so vielen sichtbaren Empfängern wird nach Bcc gefragt.
///
/// Vier ist der übliche Verteiler einer Antwort an alle und soll nicht stören;
/// ab fünf ist es eine Liste, und eine Liste im Cc gibt die Adressen aller
/// Beteiligten an alle weiter.
const int kMailOffeneListeAb = 5;

/// Die Prüfungen, die vor dem Senden laufen.
///
/// [anhangAnzahl] zählt hochgeladene **und** im Entwurf liegende Anhänge —
/// beide gehen mit hinaus, also darf keiner von beiden die Rückfrage auslösen.
List<MailSendeBefund> mailSendeBefunde({
  required String to,
  required String cc,
  required String bcc,
  required String koerper,
  required int anhangAnzahl,
}) {
  final befunde = <MailSendeBefund>[];

  if (anhangAnzahl == 0 && mailKuendigtAnhangAn(koerper)) {
    befunde.add(const MailSendeBefund(
      art: MailSendeWarnung.anhangVergessen,
      titel: 'Ohne Anhang senden?',
      text: 'Im Text steht, dass etwas beiliegt — es hängt aber keine Datei an '
          'dieser E-Mail.',
    ));
  }

  final sichtbar = <String>{
    ...mailAdressenAufteilen(to).map((a) => a.toLowerCase()),
    ...mailAdressenAufteilen(cc).map((a) => a.toLowerCase()),
  };
  if (sichtbar.length >= kMailOffeneListeAb) {
    befunde.add(MailSendeBefund(
      art: MailSendeWarnung.offeneEmpfaengerliste,
      titel: '${sichtbar.length} Empfänger sehen sich gegenseitig',
      text: 'An und Cc sind für alle lesbar — jeder dieser '
          '${sichtbar.length} Empfänger bekommt damit die Adressen aller '
          'anderen. Als Bcc bleibt jede Adresse für sich.',
      behebenLabel: 'Nach Bcc verschieben',
    ));
  }

  return befunde;
}

/// Verschiebt alles außer dem ersten Empfänger nach Bcc.
///
/// ⚠️ Einer muss im An bleiben: eine Mail ganz ohne sichtbaren Empfänger landet
/// bei mehreren großen Anbietern im Spam, und dann hat der Datenschutz gewonnen
/// und die Zustellung verloren. Der erste bleibt stehen, der Rest wandert.
({String to, String cc, String bcc}) mailNachBcc({
  required String to,
  required String cc,
  required String bcc,
}) {
  final sichtbar = <String>[];
  final gesehen = <String>{};
  for (final a in [...mailAdressenAufteilen(to), ...mailAdressenAufteilen(cc)]) {
    if (gesehen.add(a.toLowerCase())) sichtbar.add(a);
  }
  if (sichtbar.length <= 1) return (to: to, cc: cc, bcc: bcc);

  final blind = <String>[];
  for (final a in [...mailAdressenAufteilen(bcc), ...sichtbar.skip(1)]) {
    if (!blind.any((b) => b.toLowerCase() == a.toLowerCase())) blind.add(a);
  }
  return (to: sichtbar.first, cc: '', bcc: blind.join(', '));
}

/// Wie lange eine gesendete Mail noch zurückgeholt werden kann.
///
/// ⚠️ Der Wert ist ein Kompromiss, kein Zufall: kürzer als der Moment, in dem
/// man merkt, dass die Adresse falsch war, ist er wertlos — und länger als die
/// Geduld für „ist das jetzt raus?" ist er lästig. Gmail steht auf 5 s,
/// Outlook auf 10; hier zählt eine falsch adressierte Behördenakte mehr als
/// die Sekunde Wartezeit.
const Duration kMailSendeVerzoegerung = Duration(seconds: 15);
