import '../models/dock_eintrag.dart';
import '../models/user.dart';
import '../services/termin_service.dart';

/// Baut die Zeilen, die die Schnellstart-Leiste anzeigt.
///
/// ⚠️ ABSICHTLICH REINE FUNKTIONEN in einer eigenen Datei, nicht im
/// Dashboard. Das Leisten-Fenster hat eine eigene Engine und sieht nur JSON;
/// was es zu sehen bekommt, entscheidet sich hier. Läge das im Dashboard,
/// wäre es nur zusammen mit einem angemeldeten Bildschirm und einem Server zu
/// prüfen — so hängt `test/dock_eintraege_test.dart` an nichts.
///
/// ⚠️ Die Leiste zeigt Namen von Mitgliedern und Betreffzeilen. Sie steht
/// über allen Fenstern und ist NICHT von der App-Sperre gedeckt: die greift
/// im Hauptfenster ([AppSperreHuelle]), nicht in einer fremden Engine.
/// Deshalb hier so wenig wie möglich — kein Geburtsdatum, keine Adresse,
/// keine Telefonnummer, und aus dem Chat nur ein kurzer Anriss.
class DockZeilen {
  DockZeilen._();

  /// Wie weit die Terminliste in die Zukunft schaut.
  static const Duration terminFenster = Duration(days: 14);

  /// Deckel je Liste. Mehr passt nicht auf ein Panel von 520 Pixeln Höhe,
  /// und alles darüber wäre ein Bildlauf durch die gesamte Mitgliederliste —
  /// dafür ist das Programm da, nicht die Leiste.
  static const int maxZeilen = 50;

  // ──────────────────────────────────────────────────────────────────
  // Mitglieder
  // ──────────────────────────────────────────────────────────────────

  /// ⚠️ Sortiert nach Namen, NICHT nach `id`. In der Leiste sucht man einen
  /// Menschen, nicht einen Datensatz; nach Anlagereihenfolge zu sortieren
  /// hiesse, dass dieselbe Person jede Woche woanders steht.
  static List<DockEintrag> mitglieder(List<User> users) {
    final sortiert = [...users]..sort((a, b) =>
        _anzeigename(a).toLowerCase().compareTo(_anzeigename(b).toLowerCase()));

    return sortiert.take(maxZeilen).map((u) {
      final ort = (u.ort ?? '').trim();
      return DockEintrag(
        id: u.id,
        titel: _anzeigename(u),
        unterzeile:
            ort.isEmpty ? u.mitgliedernummer : '${u.mitgliedernummer} · $ort',
        // ⚠️ Nur der abweichende Status. Bei 40 Mitgliedern „aktiv" hinter
        // jeden Namen zu schreiben, macht die Spalte zu Rauschen — und genau
        // dann fällt das eine „suspendiert" nicht mehr auf.
        zusatz: u.status == 'aktiv' ? '' : _statusText(u.status),
        betont: false,
      );
    }).toList();
  }

  static String _anzeigename(User u) {
    final v = (u.vorname ?? '').trim();
    final n = (u.nachname ?? '').trim();
    final zusammen = [v, n].where((t) => t.isNotEmpty).join(' ');
    if (zusammen.isNotEmpty) return zusammen;
    // ⚠️ Rückfall auf `name` und zuletzt auf die Nummer. Zwei Mitglieder
    // haben in `users` weder Vor- noch Nachnamen (Stand 08/2026); eine leere
    // Zeile wäre nicht anklickbar, weil man nicht wüsste, wen man anklickt.
    final name = u.name.trim();
    return name.isNotEmpty ? name : u.mitgliedernummer;
  }

  static String _statusText(String status) => switch (status) {
        'passiv' => 'passiv',
        'suspended' => 'gesperrt',
        'gekuendigt_selbst' => 'gekündigt',
        'nicht_verifiziert' => 'ungeprüft',
        _ => status,
      };

  // ──────────────────────────────────────────────────────────────────
  // Termine
  // ──────────────────────────────────────────────────────────────────

  /// Die nächsten Termine ab [jetzt], aufsteigend.
  ///
  /// ⚠️ `jetzt` wird HEREINGEREICHT und nicht selbst geholt. Sonst liesse
  /// sich „heute", „morgen" und die Wochentagsabkürzung nicht prüfen, ohne
  /// dass der Test am Tag der Ausführung hängt — und genau die Zeile ist es,
  /// die der Vorsitzende im Vorbeigehen liest.
  static List<DockEintrag> termine(List<Termin> alle, DateTime jetzt) {
    final bis = jetzt.add(terminFenster);
    final tagesbeginn = DateTime(jetzt.year, jetzt.month, jetzt.day);

    final kommend = alle
        .where((t) => t.status != 'cancelled')
        // ⚠️ Ab TAGESBEGINN, nicht ab der Uhrzeit. Ein Termin um 9 Uhr
        // verschwände sonst um 9:01 aus der Leiste — an genau dem Tag, an
        // dem man ihn braucht, weil man das Ergebnis noch nachtragen muss.
        .where((t) =>
            !t.terminDate.isBefore(tagesbeginn) && t.terminDate.isBefore(bis))
        .toList()
      ..sort((a, b) => a.terminDate.compareTo(b.terminDate));

    return kommend.take(maxZeilen).map((t) {
      final ort = t.location.trim();
      return DockEintrag(
        id: t.id,
        titel: t.title.trim().isEmpty ? 'Ohne Titel' : t.title.trim(),
        unterzeile: ort.isEmpty ? _kategorieText(t.category) : ort,
        zusatz: wannText(t.terminDate, jetzt),
        // Heute fällig oder Notfall — das sind die beiden Fälle, in denen
        // ein Blick auf die Leiste zu spät sein kann.
        betont: t.isNotfall || _gleicherTag(t.terminDate, jetzt),
      );
    }).toList();
  }

  static const List<String> _wochentage = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So',
  ];

  /// „Heute 14:30", „Morgen 09:00", „Do 09:00", „12.09. 09:00".
  ///
  /// ⚠️ Von Hand gebaut statt über `DateFormat('E', 'de')`. Die
  /// Gebietsschema-Daten von `intl` müssen initialisiert sein; in einem
  /// Isolat, das die Leiste bedient, ist das nicht garantiert, und der
  /// Fehlschlag wäre eine Ausnahme aus einem Future heraus — also eine
  /// wortlos leere Liste.
  static String wannText(DateTime wann, DateTime jetzt) {
    final uhr = '${_zwei(wann.hour)}:${_zwei(wann.minute)}';
    final tage = DateTime(wann.year, wann.month, wann.day)
        .difference(DateTime(jetzt.year, jetzt.month, jetzt.day))
        .inDays;
    if (tage == 0) return 'Heute $uhr';
    if (tage == 1) return 'Morgen $uhr';
    if (tage > 1 && tage < 7) return '${_wochentage[wann.weekday - 1]} $uhr';
    return '${_zwei(wann.day)}.${_zwei(wann.month)}. $uhr';
  }

  static String _zwei(int n) => n.toString().padLeft(2, '0');

  static bool _gleicherTag(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _kategorieText(String k) => switch (k) {
        'vorstandssitzung' => 'Vorstandssitzung',
        'mitgliederversammlung' => 'Mitgliederversammlung',
        'schulung' => 'Schulung',
        _ => 'Termin',
      };

  // ──────────────────────────────────────────────────────────────────
  // Live-Chat
  // ──────────────────────────────────────────────────────────────────

  /// Offene Unterhaltungen, ungelesene zuerst.
  ///
  /// Nimmt die Rohkarten aus `getChatConversations` entgegen — dieselbe Form,
  /// die das Dashboard schon für seine Abzeichen liest.
  static List<DockEintrag> chat(List<Map<String, dynamic>> unterhaltungen) {
    final offen = unterhaltungen
        .where((c) => '${c['status'] ?? 'open'}' == 'open')
        .toList();

    // Ungelesene nach oben, der Rest behält die Reihenfolge des Servers.
    //
    // ⚠️ ZERLEGT, NICHT SORTIERT — aus zwei Gründen, und beide sind gemessen.
    // Erstens ist `List.sort` in Dart NICHT stabil: schon ein Vergleich, der
    // für gleichwertige Zeilen 0 liefert, würfelt die Serverreihenfolge
    // durcheinander, und die Unterhaltungen stünden bei jedem Öffnen anders.
    // Zweitens gibt es hier bewusst KEINEN Zeitstempel als zweites Kriterium:
    // `getChatConversations` liefert `id`, `unread_count`, `member_name`,
    // `last_message`, `status` — ein erfundener Schlüssel wie
    // `last_message_at` käme als `null` zurück, alle Vergleiche wären 0, und
    // die Sortierung täte still gar nichts.
    final ungelesen = <Map<String, dynamic>>[];
    final gelesen = <Map<String, dynamic>>[];
    for (final c in offen) {
      ((_alsInt(c['unread_count']) ?? 0) > 0 ? ungelesen : gelesen).add(c);
    }

    return [...ungelesen, ...gelesen].take(maxZeilen).map((c) {
      final ungelesen = _alsInt(c['unread_count']) ?? 0;
      final name = '${c['member_name'] ?? ''}'.trim();
      return DockEintrag(
        id: _alsInt(c['id']),
        titel: name.isEmpty ? 'Unbekannt' : name,
        unterzeile: _anriss('${c['last_message'] ?? ''}'),
        abzeichen: ungelesen,
        betont: ungelesen > 0,
      );
    }).toList();
  }

  /// ⚠️ Kurz halten, und zwar aus einem anderen Grund als der Platz: die
  /// Leiste liegt über allen Fenstern und wird auch von jemandem gesehen, der
  /// nur zufällig auf den Bildschirm schaut. Zwei Zeilen Anriss sind eine
  /// Erinnerung, ein ganzer Absatz wäre ein Aushang.
  static String _anriss(String text) {
    final eine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (eine.length <= 60) return eine;
    return '${eine.substring(0, 60)}…';
  }

  static int? _alsInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}
