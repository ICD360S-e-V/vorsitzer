import 'sprach_flaggen.dart';

/// Der Inhalt einer Visitenkarte, losgelöst vom Bildschirm.
///
/// ⚠️ Warum eine eigene Klasse und nicht einfach die Felder des Widgets: der
/// PDF-Bogen muss denselben Inhalt setzen wie die Karte auf dem Schirm, und er
/// darf dafür kein Widget bauen müssen. Ohne diese Naht wäre der Druck nur mit
/// laufender Oberfläche prüfbar — also gar nicht.
class VisitenkarteDaten {
  final String vereinsname;
  final String slogan;

  /// Vorname(n) und Nachname getrennt, weil die Karte den Nachnamen halbfett
  /// setzt — auf derselben Zeile, nicht darunter.
  final String vorname;
  final String nachname;

  final String funktion;
  final bool istGruender;
  final List<SprachAnzeige> sprachen;

  final String email;
  final String festnetz;
  final String mobil;
  final String web;
  final String mitgliedernummer;

  /// Anschrift ohne die c/o-Zeile, bereits einzeilig zusammengefasst.
  final String anschrift;

  /// „VR 201335 · Amtsgericht Memmingen, Bayern", schon zusammengesetzt.
  final String register;

  const VisitenkarteDaten({
    required this.vereinsname,
    required this.slogan,
    required this.vorname,
    required this.nachname,
    required this.funktion,
    required this.istGruender,
    required this.sprachen,
    required this.email,
    required this.festnetz,
    required this.mobil,
    required this.web,
    required this.mitgliedernummer,
    required this.anschrift,
    required this.register,
  });

  /// Die Sprachen als Kürzelzeile: `DE · RO · EN`.
  ///
  /// ⚠️ Im Druck gibt es keine Flaggen — die bundeleigene Schrift DejaVu Sans
  /// enthält die Regional-Indicator-Zeichen nicht, und keine der frei
  /// verfügbaren PDF-Schriften bildet farbige Emoji ab. Das ist kein Verlust:
  /// die Kürzel tragen die Information ohnehin allein, genau deshalb stehen sie
  /// auch auf dem Bildschirm neben der Flagge (siehe sprach_flaggen.dart).
  String get sprachZeile => sprachen.map((s) => s.kuerzel).join(' · ');
}
