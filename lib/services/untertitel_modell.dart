import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Entpackt das Archiv stückweise. Läuft in einem eigenen Isolat.
///
/// ⚠️ Muss auf Dateiebene stehen und darf nichts einfangen — sonst nimmt
/// `compute()` sie nicht an.
///
/// ⚠️ Gibt den Grund als Zeichenkette zurück, statt zu werfen: eine Ausnahme
/// aus einem Isolat kommt beim Aufrufer als `RemoteError` an, und in dem steht
/// nur wenig von dem, was schiefging.
@visibleForTesting
String? untertitelArchivEntpacken(List<String> pfade) {
  final zip = pfade[0];
  final ziel = pfade[1];
  InputFileStream? ein;
  try {
    ein = InputFileStream(zip);
    final archiv = ZipDecoder().decodeStream(ein);
    for (final e in archiv) {
      // ⚠️ Die Wurzel wegschneiden: im Archiv liegt alles unter
      // `vosk-model-small-de-0.15/`, die native Seite erwartet `am` direkt
      // im Ordner.
      final teile = e.name.split('/');
      if (teile.length < 2) continue;
      final rest = teile.sublist(1).join('/');
      if (rest.isEmpty) continue;
      // Kein Pfaddurchstieg aus einem Archiv, auch nicht aus unserem eigenen.
      if (rest.contains('..')) continue;
      if (e.isFile) {
        final datei = File('$ziel/$rest');
        datei.parent.createSync(recursive: true);
        final aus = OutputFileStream(datei.path);
        try {
          e.writeContent(aus);
        } finally {
          aus.closeSync();
        }
      } else {
        Directory('$ziel/$rest').createSync(recursive: true);
      }
    }
    // ⚠️ NACHSEHEN, OB WIRKLICH EIN MODELL DASTEHT.
    //
    // `decodeStream()` wirft bei Datenmüll NICHT — es liefert ein leeres
    // Archiv. Ohne diese Zeile meldete das Entpacken dann „gelungen", der
    // leere Ordner würde an seinen Platz geschoben, und die native Seite
    // sagte danach „kein Modell auf dem Gerät". Die Anwendung liefe in eine
    // Schleife: holen, entpacken, nichts da, wieder holen. Gefunden hat das
    // der Test, nicht das Nachdenken.
    if (!Directory('$ziel/am').existsSync()) {
      return 'Das Modell liess sich nicht entpacken: im Archiv fehlt der '
          'Ordner "am".';
    }
    return null;
  } catch (e) {
    return 'Das Modell liess sich nicht entpacken: $e';
  } finally {
    try {
      ein?.closeSync();
    } catch (_) {}
  }
}

/// Holt das Offline-Sprachmodell für die Live-Mitschrift auf das Gerät.
///
/// ⚠️ WARUM ES NICHT IM APK LIEGT: 46 MB gepackt, 91 MB entpackt. Im Paket
/// wäre es die halbe Anwendung, im Repo — das öffentlich ist — ein Binärklotz.
/// Es liegt deshalb auf unserem Server und wird beim ersten Einschalten geholt,
/// genau wie die Netzlogos.
class UntertitelModell {
  UntertitelModell._();
  static final UntertitelModell _i = UntertitelModell._();
  factory UntertitelModell() => _i;

  /// 0..1 während des Holens, `null` wenn gerade nichts läuft.
  final ValueNotifier<double?> fortschritt = ValueNotifier<double?>(null);

  bool _laeuft = false;

  /// Wohin es entpackt wird. Muss zu `Untertitel.modellOrdner()` auf der
  /// nativen Seite passen: dort steht `File(ctx.filesDir, "vosk-de")`, und
  /// `getApplicationSupportDirectory()` IST `filesDir` (nachgesehen in
  /// `path_provider_android`: `getApplicationSupportPath()` →
  /// `PathUtils.getFilesDir(context)`).
  Future<Directory> ordner() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/vosk-de');

  Future<bool> vorhanden() async {
    final o = await ordner();
    // Wie die native Seite: der Ordner allein genügt nicht, ein abgebrochener
    // Lauf hinterlässt auch einen. `am` ist der Teil, ohne den nichts lädt.
    return Directory('${o.path}/am').existsSync();
  }

  /// Holt und entpackt. Gibt den Grund zurück, wenn es nicht ging.
  Future<String?> holen({String sprache = 'de'}) async {
    if (_laeuft) return 'Wird bereits geholt.';
    _laeuft = true;
    fortschritt.value = 0;
    File? zip;
    try {
      final api = ApiService();
      final angaben = await api.sprachmodellAngaben(sprache);
      if (angaben['success'] != true) {
        return 'Das Modell ist auf dem Server nicht hinterlegt (${angaben['message'] ?? ''}).';
      }
      final erwartet = '${angaben['sha256'] ?? ''}';
      final gesamt = (angaben['groesse'] as num?)?.toInt() ?? 0;

      final tmp = await getTemporaryDirectory();
      zip = File('${tmp.path}/vosk-$sprache.zip');
      if (zip.existsSync()) await zip.delete();

      final antwort = await api.sprachmodellStrom(sprache);
      if (antwort.statusCode != 200) {
        return 'Herunterladen fehlgeschlagen (HTTP ${antwort.statusCode}).';
      }
      final senke = zip.openWrite();
      var geholt = 0;
      await for (final stueck in antwort.stream) {
        senke.add(stueck);
        geholt += stueck.length;
        if (gesamt > 0) fortschritt.value = (geholt / gesamt).clamp(0.0, 1.0);
      }
      await senke.close();

      // ⚠️ ERST PRÜFEN, DANN ENTPACKEN. Ein abgerissener Download ergäbe ein
      // halbes Modell, und Vosk lädt es entweder gar nicht oder — schlimmer —
      // mit fehlenden Teilen. Die Prüfsumme kostet ein paar Sekunden und
      // erspart einen Fehler, den niemand einordnen könnte.
      if (erwartet.isNotEmpty) {
        // ⚠️ IM STROM, nicht `readAsBytes()`. Die Datei ist 46 MB; sie dafür
        // ganz in den Speicher zu holen ist auf einem Tablet der Anfang genau
        // des Fehlers, den die Prüfsumme verhindern soll.
        final ist = (await sha256.bind(zip.openRead()).first).toString();
        if (ist != erwartet) {
          return 'Die geholte Datei ist unvollständig — bitte noch einmal versuchen.';
        }
      }

      final ziel = await ordner();
      // ⚠️ Erst daneben entpacken, dann umbenennen. Bricht das Entpacken ab,
      // steht sonst ein halbes Modell an der Stelle, an der die native Seite
      // ein ganzes erwartet.
      final neben = Directory('${ziel.path}.neu');
      if (neben.existsSync()) await neben.delete(recursive: true);
      await neben.create(recursive: true);

      // ⚠️ IN EINEM EIGENEN ISOLAT UND AUS DEM STROM — beides, und beides aus
      // gemessenen Gründen.
      //
      // Vorher stand hier `ZipDecoder().decodeBytes(await zip.readAsBytes())`
      // im Haupt-Isolat. Nachgemessen am echten Archiv: 46 MB gepackt, 91,2 MB
      // entpackt, und die GRÖSSTE Einzeldatei ist `graph/HCLr.fst` mit 40,0 MB.
      // Es lagen also mindestens 46 MB Archiv plus 40 MB Dateiinhalt
      // gleichzeitig im Speicher — auf dem Samsung-Tablet die Sorte Spitze, die
      // entweder den Speicher sprengt oder die Oberfläche so lange anhält, dass
      // Android sie für hängend hält.
      //
      // `InputFileStream`/`OutputFileStream` lesen und schreiben stückweise
      // über die Platte; im Speicher steht nie eine ganze Datei.
      final fehler = await compute(untertitelArchivEntpacken, [zip.path, neben.path]);
      if (fehler != null) return fehler;

      if (ziel.existsSync()) await ziel.delete(recursive: true);
      await neben.rename(ziel.path);
      _log.info('Sprachmodell $sprache entpackt nach ${ziel.path}', tag: 'UNTERTITEL');
      return null;
    } catch (e) {
      _log.error('Sprachmodell nicht geholt: $e', tag: 'UNTERTITEL');
      return '$e';
    } finally {
      // Die 46 MB im Zwischenspeicher wieder freigeben — sie werden nie wieder
      // gebraucht, das Modell liegt jetzt entpackt da.
      try {
        if (zip != null && zip.existsSync()) await zip.delete();
      } catch (_) {}
      fortschritt.value = null;
      _laeuft = false;
    }
  }
}
