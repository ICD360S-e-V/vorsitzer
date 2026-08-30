import '../services/wortliste_service.dart';
import 'wort_vervollstaendigung.dart';

/// Räumt den fertigen Text auf, bevor er rausgeht.
///
/// ⚠️ Diese Funktion gibt es, damit die Regel an ALLEN Schreibstellen
/// dieselbe ist. Der Blitz hat ein eigenes Feld mit eigenem Sendeweg; ohne
/// eine gemeinsame Stelle hätte er eine zweite, leicht andere Korrektur
/// bekommen — und beim nächsten Feld eine dritte.
///
/// Sie fasst nur das LETZTE Wort an. Alles davor ist beim Tippen schon durch
/// die Korrektur gelaufen (dort folgte ja ein Trennzeichen); dem letzten Wort
/// folgt keines mehr, und genau deshalb wäre es sonst das einzige, das
/// ungeprüft rausginge.
///
/// [inRuheLassen] sind Wörter, deren Korrektur der Mensch schon einmal mit
/// der Rücktaste zurückgenommen hat.
String autoKorrigiert(String text, {Set<String> inRuheLassen = const {}}) {
  if (text.isEmpty) return text;
  final letztes = AngefangenesWort.ausEingabe(text, text.length);
  if (letztes == null) return text;

  final davor =
      letztes.von > 0 ? AngefangenesWort.ausEingabe(text, letztes.von - 1) : null;
  final davorDavor = davor == null || davor.von == 0
      ? null
      : AngefangenesWort.ausEingabe(text, davor.von - 1);

  String? pruefen(AngefangenesWort w, {String? links, String? rechts}) {
    if (inRuheLassen.contains(w.text)) return null;
    // Ein großgeschriebener Eigenname mitten im Satz bleibt, wie er ist.
    if (AngefangenesWort.grossGeschrieben(w.text) &&
        !AngefangenesWort.istSatzanfang(text, w.von)) {
      return null;
    }
    final aus = WortlisteService.diakritika
            .korrektur(w.text, links: links, rechts: rechts) ??
        WortlisteService.tippfehler.korrektur(w.text);
    if (aus != null) return aus;

    // ⚠️ Auch die Vervollständigung, aber NUR wo sie gleich lang ist.
    // „marti" wird so noch zu „marți" — es fehlten ja bloß die Häkchen.
    // Ein längerer Vorschlag ist hier verboten: wer mitten im Wort auf
    // Senden drückt, hat „mult" geschrieben und nicht „mulțumesc" gemeint.
    if (WortlisteService.index.kennt(w.text)) return null;
    for (final v in WortlisteService.index.vorschlaege(w.text)) {
      if (v.length == w.text.length) {
        return WortIndex.schreibungUebernehmen(w.text, v);
      }
    }
    return null;
  }

  final neu = pruefen(letztes, links: davor?.text);
  final neuDavor = davor == null
      ? null
      : pruefen(davor, links: davorDavor?.text, rechts: letztes.text);
  if (neu == null && neuDavor == null) return text;

  // Von hinten nach vorn, damit die Stellen der vorderen Wörter gültig bleiben.
  var ergebnis = text;
  if (neu != null) {
    ergebnis = ergebnis.replaceRange(letztes.von, letztes.bis, neu);
  }
  if (neuDavor != null) {
    ergebnis = ergebnis.replaceRange(davor!.von, davor.bis, neuDavor);
  }
  return ergebnis;
}
