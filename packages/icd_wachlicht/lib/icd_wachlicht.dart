import 'package:flutter/services.dart';

/// Hält den Prozessor wach — aber nur, solange es einen Grund gibt.
///
/// ⚠️ WAS DAS ERSETZT
/// `flutter_foreground_task` nimmt mit `allowWakeLock: true` einen
/// PARTIAL_WAKE_LOCK ohne Zeitgrenze und hält ihn, solange der Dienst lebt.
/// Auf dem Vereinsgerät waren das 24 Stunden am Tag; Googles Schwelle für
/// „excessive" liegt bei zwei Stunden binnen 24.
///
/// ⚠️ WARUM ES ÜBERHAUPT NOCH EINEN LOCK BRAUCHT
/// Der Takt des Wachdienstes ist eine Kotlin-Korutine mit `delay(interval)`
/// (ForegroundTask.kt:123), also ein Zeitgeber im Benutzerraum: er läuft
/// NICHT, solange der Prozessor schläft. Im Normalbetrieb macht das nichts —
/// der ntfy-Strom liefert alle 45 Sekunden ein Lebenszeichen, und ein
/// eintreffendes Netzpaket weckt das Gerät ohnehin (der Kernel nimmt dafür
/// selbst einen Lock). Reisst der Strom aber, fehlt genau diese Weckquelle,
/// und dann ist die Abfrage die einzige Absicherung, die noch greift.
///
/// Deshalb: kein Dauerlock, sondern einer, solange die Weckleitung steht.
class IcdWachlicht {
  IcdWachlicht._();

  static const _kanal = MethodChannel('de.icd360sev/wachlicht');

  /// Nimmt den Lock oder erneuert seine Zeitgrenze.
  ///
  /// ⚠️ [dauer] ist eine OBERGRENZE, kein Wunsch: läuft sie ab, gibt Android
  /// den Lock von selbst frei. Das ist Absicht — ein Absturz zwischen Nehmen
  /// und Freigeben darf das Gerät nicht für immer wach lassen. Wer länger
  /// braucht, ruft einfach erneut.
  ///
  /// Gibt zurück, ob der Lock danach gehalten wird. Auf allem ausser Android
  /// (und wenn der Kanal fehlt) `false` — ohne zu werfen, denn an einem
  /// Wachlicht darf kein Durchlauf scheitern.
  static Future<bool> nehmen({Duration dauer = const Duration(minutes: 1)}) async {
    try {
      return await _kanal.invokeMethod<bool>(
            'nehmen',
            {'timeoutMs': dauer.inMilliseconds},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Gibt den Lock frei. Mehrfach aufrufbar, auch wenn keiner gehalten wird.
  static Future<void> freigeben() async {
    try {
      await _kanal.invokeMethod<bool>('freigeben');
    } catch (_) {
      // Nichts zu tun: die Zeitgrenze räumt spätestens selbst auf.
    }
  }

  /// Nur zum Nachsehen (Diagnose, Test).
  static Future<bool> gehalten() async {
    try {
      return await _kanal.invokeMethod<bool>('gehalten') ?? false;
    } catch (_) {
      return false;
    }
  }
}
