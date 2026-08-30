import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logger_service.dart';
import 'platform_service.dart';

final _log = LoggerService();

/// Live-Untertitel dessen, was die Gegenstelle sagt.
///
/// WOFÜR
/// Der Vorsitzende hört schlecht. Am Telefon fehlt ihm damit genau das, was in
/// einem Behördengespräch zählt — Zahlen, Daten, Namen. Hier läuft mit, was der
/// andere sagt, während er spricht.
///
/// ⚠️ ES WIRD NICHTS AUFGEZEICHNET UND NICHTS GESPEICHERT — weder Ton noch
/// Text. Die Wörter stehen auf dem Schirm, solange das Gespräch läuft, und sind
/// danach weg. Festlegung des Users, und zugleich die Linie, die § 201 StGB
/// zieht: mitlesen, um zu verstehen, ist etwas anderes als eine Aufnahme des
/// gesprochenen Wortes.
///
/// ⚠️ ES VERLÄSST AUCH NICHTS DAS GERÄT, UND ES IST KEIN GOOGLE IM SPIEL.
/// Erkannt wird mit **Vosk** (Apache 2.0), das Modell liegt auf dem Gerät.
///
/// Der naheliegende Weg wäre Androids eigener Offline-Erkenner gewesen. Den
/// stellt aber Googles „Android System Intelligence" — ein Teil von Play. Ohne
/// Play gibt es ihn nicht: auf GrapheneOS meldet
/// `isOnDeviceRecognitionAvailable()` `false`, und im Fehlerverfolger des
/// Projekts steht so ein Dienst als OFFENE Bitte (os-issue-tracker#1593). Auf
/// dem künftigen Gerät — Pixel Fold mit GrapheneOS — wäre die Mitschrift also
/// nie angesprungen. Mit Vosk läuft dieselbe Fassung auf dem heutigen Samsung
/// A11 und auf dem Pixel.
///
/// ⚠️ Nebenbei fällt damit eine ganze Fehlerklasse weg: Androids Erkenner
/// öffnet laut seiner eigenen Doku **stillschweigend das Mikrofon**, wenn er
/// die mitgegebene Tonquelle nicht unterstützt — er schriebe dann den Raum mit
/// statt das Gespräch, und sähe dabei aus, als ginge alles. Im Weg über Vosk
/// kommt kein Mikrofon vor; der Fehler kann nicht auftreten.
class UntertitelService {
  UntertitelService._();
  static final UntertitelService _i = UntertitelService._();
  factory UntertitelService() => _i;

  static const MethodChannel _kanal =
      MethodChannel('de.icd360sev.vorsitzer/untertitel');
  static const EventChannel _strom =
      EventChannel('de.icd360sev.vorsitzer/untertitel_strom');

  /// Was gerade auf dem Schirm stehen soll. Leer = nichts.
  final ValueNotifier<String> text = ValueNotifier<String>('');

  /// Läuft die Erkennung?
  final ValueNotifier<bool> aktiv = ValueNotifier<bool>(false);

  /// Warum es nicht geht — für den Bildschirm, nicht fürs Protokoll.
  final ValueNotifier<String?> hindernis = ValueNotifier<String?>(null);

  StreamSubscription<dynamic>? _horcher;

  /// ⚠️ Die letzten Sätze, NUR im Speicher und nur solange das Gespräch läuft.
  /// [beenden] leert sie. Eine Datei oder eine Tabelle gibt es dafür nicht und
  /// soll es nicht geben.
  final List<String> _saetze = <String>[];
  static const int _hoechstens = 12;

  bool get plattformFaehig => PlatformService.isAndroid;

  /// Was das Gerät kann. `null` = nicht Android.
  Future<Map<String, dynamic>?> faehigkeiten() async {
    if (!plattformFaehig) return null;
    try {
      final m = await _kanal.invokeMapMethod<String, dynamic>('faehigkeiten');
      return m;
    } on MissingPluginException {
      return null;
    } catch (e) {
      _log.warning('Untertitel: Fähigkeiten nicht abfragbar ($e)', tag: 'UNTERTITEL');
      return null;
    }
  }

  /// Fehlt das Sprachmodell auf dem Gerät? Dann kann die Oberfläche es holen
  /// lassen, statt nur „geht nicht" zu sagen.
  final ValueNotifier<bool> modellFehlt = ValueNotifier<bool>(false);

  /// Startet die Untertitel für die Tonspur [spurId] der Gegenstelle.
  ///
  /// Gibt den Grund zurück, wenn es nicht geht — `null` heisst: läuft.
  Future<String?> starten(String spurId, {String sprache = 'de'}) async {
    if (!plattformFaehig) return 'Untertitel gibt es nur auf dem Tablet.';
    if (aktiv.value) return null;
    if (spurId.isEmpty) {
      return 'Die Tonspur der Gegenstelle steht noch nicht — bitte kurz warten.';
    }
    _lauschen();
    try {
      final a = await _kanal.invokeMapMethod<String, dynamic>(
          'starten', {'spurId': spurId, 'sprache': sprache});
      if (a?['ok'] == true) {
        aktiv.value = true;
        hindernis.value = null;
        return null;
      }
      modellFehlt.value = a?['modellFehlt'] == true;
      final grund = '${a?['grund'] ?? 'Untertitel konnten nicht starten.'}';
      hindernis.value = grund;
      return grund;
    } on MissingPluginException {
      return 'Diese App-Fassung kennt die Untertitel noch nicht.';
    } catch (e) {
      _log.warning('Untertitel: Start fehlgeschlagen ($e)', tag: 'UNTERTITEL');
      return '$e';
    }
  }

  Future<void> beenden() async {
    _horcher?.cancel();
    _horcher = null;
    aktiv.value = false;
    // ⚠️ Hier verschwindet der Text, und das ist der Zweck.
    _saetze.clear();
    text.value = '';
    if (!plattformFaehig) return;
    try {
      await _kanal.invokeMethod<void>('stoppen');
    } catch (_) {/* beim Aufräumen ist ein Fehler kein Grund zu werfen */}
  }

  void _lauschen() {
    _horcher ??= _strom.receiveBroadcastStream().listen((e) {
      if (e is! Map) return;
      switch ('${e['art']}') {
        case 'teil':
          // Zwischenstand: der angefangene Satz, hinter den fertigen.
          _zeigen(vorlaeufig: '${e['text'] ?? ''}');
          break;
        case 'satz':
          final s = '${e['text'] ?? ''}'.trim();
          if (s.isNotEmpty) {
            _saetze.add(s);
            while (_saetze.length > _hoechstens) {
              _saetze.removeAt(0);
            }
          }
          _zeigen();
          break;
        case 'fehler':
          _log.warning('Untertitel: Erkennerfehler ${e['code']}', tag: 'UNTERTITEL');
          break;
        case 'bereit':
          hindernis.value = null;
          break;
      }
    }, onError: (Object e) {
      _log.warning('Untertitel: Strom abgerissen ($e)', tag: 'UNTERTITEL');
    });
  }

  void _zeigen({String? vorlaeufig}) {
    final teile = <String>[..._saetze];
    final v = (vorlaeufig ?? '').trim();
    if (v.isNotEmpty) teile.add(v);
    text.value = teile.join(' ');
  }
}
