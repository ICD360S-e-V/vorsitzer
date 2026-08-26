import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// libmpv bricht mit `abort()` ab, wenn `LC_NUMERIC` nicht `C` ist:
///
/// ```
/// Non-C locale detected. This is not supported.
/// Call 'setlocale(LC_NUMERIC, "C");' in your code.
/// ```
///
/// Genau das passiert auf einem deutsch eingerichteten Linux-Desktop
/// (`LC_NUMERIC=de_DE.UTF-8`): GTK übernimmt beim Start die Locale aus der
/// Umgebung, und der erste `AudioPlayer` hinter `just_audio_media_kit` legt
/// dann einen mpv-Kontext an — der Prozess stirbt mit Core-Dump, ohne dass
/// eine Dart-Ausnahme entsteht. Aus der App heraus sah das aus wie „Radio-Knopf
/// = Absturz"; ein `try/catch` um `play()` kann daran nichts ändern, weil
/// `abort()` kein Fehler ist, den Dart sieht.
///
/// ⚠️ Muss VOR dem ersten `AudioPlayer` laufen, also vor
/// `JustAudioMediaKit.ensureInitialized()`.
///
/// ⚠️ Nur `LC_NUMERIC`, nie `LC_ALL`: Datum, Sortierung und Währung sollen
/// deutsch bleiben. Zahlenformatierung in der Oberfläche macht Dart/`intl`
/// selbst und ist von der C-Locale nicht betroffen.
///
/// Nur Linux. Auf Windows liefert media_kit sein eigenes libmpv mit, das
/// diese Prüfung nicht hat.
void mpvLocaleFix() {
  if (!Platform.isLinux) return;
  try {
    final setlocale = DynamicLibrary.process().lookupFunction<
        Pointer<Utf8> Function(Int32, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)>('setlocale');
    // glibc: LC_NUMERIC == 1 (bits/locale.h). Kein FFI-Konstantenimport
    // möglich, deshalb hier festgeschrieben — der Wert ist ABI und ändert
    // sich nicht.
    final c = 'C'.toNativeUtf8();
    try {
      setlocale(1, c);
    } finally {
      malloc.free(c);
    }
  } catch (_) {
    // Kein setlocale gefunden (fremde libc)? Dann bleibt es beim alten
    // Verhalten — schlimmstenfalls stummes Radio, nie ein Absturz hier.
  }
}
