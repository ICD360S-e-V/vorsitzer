import 'wort_vervollstaendigung.dart';

/// Setzt fehlende rumänische Häkchen dort, wo das Wörterbuch allein nicht
/// weiterhilft — nämlich wenn die Fassung OHNE Häkchen selbst ein Wort ist.
///
/// „multumesc" ist kein Wort, das erledigt die Vervollständigung. „sa", „ca",
/// „va", „pana", „tara" sind welche — und trotzdem meist falsch. Was richtig
/// ist, entscheidet erst der Nachbar:
///
///   `faptul ca`  -> faptul **că**      `va rog`   -> **vă** rog
///   `pana in`    -> **până** în        `va mai`   -> va mai   (Futur, bleibt)
///   `tara noastra` -> **țara** noastră `prima data` -> prima **dată**
///
/// ⚠️ WARUM DAS ÜBERHAUPT NÖTIG IST: nicht fürs Auge, sondern für die
/// Übersetzung. Gemessen am eigenen Server: `documentele care le-am trimis`
/// wird zu „die ich **ihnen** geschickt habe" — ein erfundenes Dativobjekt;
/// mit `pe care` verschwindet es. `va rog sa imi trimiteti hotararea` wird zu
/// „Bitte schicken Sie mir **Ihre** Entscheidung" — ebenfalls erfunden.
///
/// ⚠️ ALLE REGELN SIND GEMESSEN, KEINE IST EINGETRAGEN. Grundlage sind
/// 571.277 Sätze aus Nachrichtentexten, Wikipedia und Untertiteln, von denen
/// nur die zählen, in denen JEDES Wort im Wörterbuch steht — ein Satz mit
/// „fara" oder „facut" ist durchgehend ohne Häkchen getippt und taugt nicht
/// als Maßstab. Auf ungesehenen 10 % gemessen: **39,7 % der fehlenden Häkchen
/// gesetzt, 98,7 % davon richtig.**
///
/// ⚠️ Der Nachbar wird OHNE Häkchen nachgeschlagen. Wer sie weglässt, lässt
/// sie überall weg: neben „sa" steht dann „faca", nicht „facă". Eine Regel auf
/// „facă" griffe im echten Fall nie — dieser Fehler steckte in der ersten
/// Fassung und drückte die Trefferquote auf ein Zehntel.
class Diakritika {
  /// Kurze Formen, die gar keine Wörter sind — aus dem Wörterbuch allein
  /// ableitbar, ohne Kontext. `si` → `și`, `in` → `în`.
  ///
  /// Sie brauchen einen eigenen Weg, weil die Vorschlagsleiste erst ab drei
  /// Buchstaben anspringt und diese hier zwei haben — ausgerechnet die
  /// häufigsten Wörter der Sprache.
  final Map<String, String> kurz;

  /// nackte Form → Zielform → (rechte Nachbarn, linke Nachbarn).
  final Map<String, Map<String, Nachbarn>> kontext;

  const Diakritika._(this.kurz, this.kontext);

  static const Diakritika leer = Diakritika._({}, {});

  bool get bereit => kurz.isNotEmpty || kontext.isNotEmpty;

  factory Diakritika.ausJson(Map<String, dynamic> j) {
    final kurz = <String, String>{};
    (j['kurz'] as Map?)?.forEach((k, v) => kurz['$k'] = '$v');
    final kontext = <String, Map<String, Nachbarn>>{};
    (j['kontext'] as Map?)?.forEach((wort, formen) {
      final je = <String, Nachbarn>{};
      (formen as Map).forEach((form, regeln) {
        je['$form'] = Nachbarn(
          rechts: {for (final x in (regeln['r'] as List? ?? [])) '$x'},
          links: {for (final x in (regeln['l'] as List? ?? [])) '$x'},
        );
      });
      kontext['$wort'] = je;
    });
    return Diakritika._(kurz, kontext);
  }

  /// Die richtige Schreibung von [wort], oder `null` wenn nichts zu tun ist.
  ///
  /// [links] und [rechts] sind die Nachbarwörter; `null` heißt „gibt es
  /// nicht". Beide werden intern entdiakritisiert.
  String? korrektur(String wort, {String? links, String? rechts}) {
    final klein = wort.toLowerCase();
    final k = kurz[klein];
    if (k != null) return _schreibung(wort, k);

    final formen = kontext[klein];
    if (formen == null) return null;
    final l = links == null ? null : WortIndex.ohneDiakritika(links);
    final r = rechts == null ? null : WortIndex.ohneDiakritika(rechts);

    String? treffer;
    for (final e in formen.entries) {
      final passt = (r != null && e.value.rechts.contains(r)) ||
          (l != null && e.value.links.contains(l));
      if (!passt) continue;
      // ⚠️ Passen ZWEI Zielformen, weiß man es nicht — und Nichtstun ist dann
      // richtig. Ohne diese Regel wurde aus „in tara noastra" „țară noastră"
      // statt „țara noastră": global ist „țară" häufiger, hier aber falsch.
      if (treffer != null) return null;
      treffer = e.key;
    }
    if (treffer == null || treffer == wort) return null;
    return _schreibung(wort, treffer);
  }

  static String _schreibung(String eingabe, String ziel) =>
      WortIndex.schreibungUebernehmen(eingabe, ziel);
}

class Nachbarn {
  final Set<String> rechts;
  final Set<String> links;
  const Nachbarn({required this.rechts, required this.links});
}
