import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

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
        final ist = sha256.convert(await zip.readAsBytes()).toString();
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

      final archiv = ZipDecoder().decodeBytes(await zip.readAsBytes());
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
        final ausgabe = File('${neben.path}/$rest');
        if (e.isFile) {
          await ausgabe.parent.create(recursive: true);
          await ausgabe.writeAsBytes(e.content as List<int>);
        } else {
          await Directory('${neben.path}/$rest').create(recursive: true);
        }
      }

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
