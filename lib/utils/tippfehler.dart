import 'wort_vervollstaendigung.dart';

/// Repariert VERTIPPTE Wörter — die, bei denen die Vervollständigung nichts
/// ausrichtet, weil sie kein Wortanfang sind.
///
/// `multu` ist der Anfang von `mulțumesc`, das erledigt [WortIndex]. `dovument`
/// ist der Anfang von gar nichts — dort hilft nur der Abstand zum richtigen
/// Wort: ein vertauschter, ausgelassener oder falsch getroffener Buchstabe.
///
/// ⚠️ WAS HIER NICHT PASSIERT, IST WICHTIGER ALS WAS PASSIERT.
/// Automatisch zu ersetzen ist der gefährlichste Teil der ganzen Funktion —
/// hier entstehen die Autokorrektur-Geschichten, die jeder kennt. Deshalb:
///
///   1. Erst ab [mindestLaenge] Zeichen. Bei zwei Buchstaben ist jedes andere
///      Wort einen Schritt entfernt.
///   2. Nur, wenn das Wort selbst KEINES ist.
///   3. Der Abstand wächst mit der Wortlänge, nicht pauschal:
///      3–5 Zeichen → 1, ab 6 → 2. Bei kurzen Wörtern sind zwei Schritte fast
///      das halbe Wort.
///   4. ⚠️ Der Treffer muss EINDEUTIG sein. Gibt es zwei Wörter im selben
///      Abstand, wird nichts geändert — raten wäre schlimmer als nichts tun.
///      `sare` und `mare` sind beide einen Schritt von `care` entfernt.
///   5. Großgeschriebenes mitten im Satz und Zurückgenommenes fasst der
///      Aufrufer ohnehin nicht an.
class Tippfehler {
  static const mindestLaenge = 3;

  /// Wörter nach Länge, innerhalb der Länge nach Häufigkeit.
  final Map<int, List<String>> _nachLaenge;

  /// Zu jedem Wort ein Bitmuster seiner Buchstaben — dieselbe Reihenfolge
  /// wie [_nachLaenge].
  ///
  /// ⚠️ Das ist der Unterschied zwischen 62 ms und wenigen Millisekunden.
  /// Der Abstand zweier Wörter wird sonst gegen jeden Kandidaten gerechnet;
  /// mit dem Bitmuster fallen die meisten in einem einzigen XOR heraus. Wer
  /// sich um höchstens d Schritte unterscheidet, kann sich in höchstens 2·d
  /// Buchstaben unterscheiden — eine Ersetzung nimmt einen weg und bringt
  /// einen mit.
  final Map<int, List<int>> _muster;
  final Set<String> _alle;

  const Tippfehler._(this._nachLaenge, this._muster, this._alle);

  static const Tippfehler leer = Tippfehler._({}, {}, {});

  bool get bereit => _alle.isNotEmpty;

  /// [woerter] muss nach Häufigkeit absteigend sortiert sein — die Reihenfolge
  /// entscheidet bei gleichem Abstand, welches Wort zuerst gefunden wird.
  factory Tippfehler.aufbauen(Iterable<String> woerter) {
    final nachLaenge = <int, List<String>>{};
    final muster = <int, List<int>>{};
    final alle = <String>{};
    for (final w in woerter) {
      if (w.length < mindestLaenge) continue;
      (nachLaenge[w.length] ??= <String>[]).add(w);
      (muster[w.length] ??= <int>[]).add(bitmuster(w));
      alle.add(w);
    }
    return Tippfehler._(nachLaenge, muster, alle);
  }

  /// Ein Bit je Buchstabe. Alles jenseits der 31 Klassen landet im letzten
  /// Bit — das macht den Filter nur unschärfer, nie falsch.
  static int bitmuster(String w) {
    var m = 0;
    for (var i = 0; i < w.length; i++) {
      final c = w.codeUnitAt(i);
      final k = c >= 0x61 && c <= 0x7A ? c - 0x61 : 25 + (c % 6);
      m |= 1 << k;
    }
    return m;
  }

  static int _bits(int x) {
    var n = 0;
    while (x != 0) {
      x &= x - 1;
      n++;
    }
    return n;
  }

  static int _erlaubterAbstand(int laenge) => laenge >= 6 ? 2 : 1;

  /// Das gemeinte Wort, oder `null` wenn es nicht eindeutig zu bestimmen ist.
  String? korrektur(String wort) {
    if (wort.length < mindestLaenge || !bereit) return null;
    final klein = wort.toLowerCase();
    if (_alle.contains(klein) || _alle.contains(wort)) return null;

    final grenze = _erlaubterAbstand(klein.length);
    String? bester;
    var besterAbstand = grenze + 1;
    var mehrdeutig = false;

    final eigenes = bitmuster(klein);
    for (var l = klein.length - grenze; l <= klein.length + grenze; l++) {
      final liste = _nachLaenge[l];
      if (liste == null) continue;
      final muster = _muster[l]!;
      for (var idx = 0; idx < liste.length; idx++) {
        if (_bits(eigenes ^ muster[idx]) > 2 * grenze) continue;
        final kandidat = liste[idx];
        // ⚠️ Mit `besterAbstand` als Schranke gälte ein zweiter Kandidat im
        // GLEICHEN Abstand als „zu weit" und fiele raus — die Prüfung auf
        // Mehrdeutigkeit unten liefe damit ins Leere. Gemessen: 27,6 % der
        // Korrekturen waren dadurch falsch (》axta《 wurde 》axa《 statt
        // 》asta《). Deshalb eins mehr zulassen und selbst vergleichen.
        final a = _abstand(klein, kandidat, besterAbstand + 1);
        if (a == null || a > besterAbstand) continue;
        if (a < besterAbstand) {
          besterAbstand = a;
          bester = kandidat;
          mehrdeutig = false;
        } else if (a == besterAbstand && kandidat != bester) {
          // ⚠️ Gleich weit weg heißt: man weiß es nicht. Die Häufigkeit
          // entscheiden zu lassen wäre bequem und falsch — „care" und „mare"
          // sind beide einen Schritt von „sare" entfernt, und welches gemeint
          // war, steht in keiner Häufigkeitsliste.
          mehrdeutig = true;
        }
      }
    }
    if (bester == null || mehrdeutig) return null;
    return WortIndex.schreibungUebernehmen(wort, bester);
  }

  /// Damerau-Levenshtein mit Abbruch, sobald [grenze] überschritten ist.
  ///
  /// Die Vertauschung gehört dazu: auf einer Tastatur ist „ducoment" für
  /// „document" ein Anschlag zu früh, kein zweiter Fehler.
  static int? _abstand(String a, String b, int grenze) {
    if ((a.length - b.length).abs() >= grenze) {
      if ((a.length - b.length).abs() > grenze) return null;
    }
    var vorvorige = <int>[];
    var vorige = List<int>.generate(b.length + 1, (i) => i);
    var jetzt = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      jetzt[0] = i;
      var kleinste = i;
      for (var j = 1; j <= b.length; j++) {
        final kosten = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var wert = [
          jetzt[j - 1] + 1,
          vorige[j] + 1,
          vorige[j - 1] + kosten,
        ].reduce((x, y) => x < y ? x : y);
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          final tausch = vorvorige[j - 2] + 1;
          if (tausch < wert) wert = tausch;
        }
        jetzt[j] = wert;
        if (wert < kleinste) kleinste = wert;
      }
      // Keine Zelle der Zeile liegt noch im Rahmen — es kann nichts mehr
      // werden. Das ist der Grund, warum der Durchlauf über zehntausend
      // Kandidaten überhaupt bezahlbar ist.
      if (kleinste >= grenze) return null;
      vorvorige = vorige;
      vorige = jetzt;
      jetzt = List<int>.filled(b.length + 1, 0);
    }
    final ergebnis = vorige[b.length];
    return ergebnis < grenze ? ergebnis : null;
  }
}
