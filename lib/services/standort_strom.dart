import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'logger_service.dart';

final _log = LoggerService();

/// Ein einzelner Standort-Verbraucher. Wird von [StandortStrom.anmelden]
/// zurückgegeben und muss mit [abmelden] wieder freigegeben werden.
class StandortAbo {
  final String name;
  final int abstandMeter;
  final Duration intervall;
  final LocationAccuracy genauigkeit;
  final bool vordergrunddienst;
  final void Function(Position) onPosition;
  final void Function(Object)? onFehler;

  /// Letzte an **diesen** Verbraucher ausgelieferte Position — Grundlage für
  /// seine eigene Abstands-/Zeitschwelle.
  Position? letzte;
  DateTime? letzteZeit;
  bool _abgemeldet = false;

  StandortAbo._({
    required this.name,
    required this.abstandMeter,
    required this.intervall,
    required this.genauigkeit,
    required this.vordergrunddienst,
    required this.onPosition,
    this.onFehler,
  });

  bool get istAbgemeldet => _abgemeldet;

  void abmelden() {
    if (_abgemeldet) return;
    _abgemeldet = true;
    StandortStrom.instance._abmelden(this);
  }
}

/// Einziger Besitzer des Geolocator-Positionsstroms in dieser App.
///
/// ⚠️ **Warum es diesen Umweg gibt.** `Geolocator.getPositionStream` merkt sich
/// den einmal aufgebauten Strom und gibt ihn bei jedem weiteren Aufruf
/// unverändert zurück — die mitgegebenen `locationSettings` werden dann
/// **stillschweigend verworfen** (geolocator_android 5.0.3,
/// `geolocator_android.dart` Z. 166–212: `if (_positionStream != null) return
/// _positionStream!;`). Zurückgesetzt wird der Zwischenspeicher erst, wenn der
/// **letzte** Zuhörer abbestellt.
///
/// In dieser App hatte das eine handfeste Folge: Dashboard startet zuerst
/// `TransitService` (100 m / 15 s) und gleich danach `WeatherService`
/// (1 m / 15 min). Öffnet man später die Karte im ÖPNV-Dialog, fordert die
/// `distanceFilter: 10` an — bekommt aber den längst laufenden Strom mit den
/// Einstellungen des Erstanmelders. Der Wetterdienst bleibt dabei angemeldet,
/// also wird der Zwischenspeicher nie frei. Auf dem Telefon sah das so aus:
/// der blaue Punkt sprang im Bus erst nach etlichen Minuten weiter, obwohl im
/// Code 10 Meter standen. Kein Fehler des Verkehrsanbieters — die Anforderung
/// hat das Gerät nie erreicht.
///
/// **Regeln hier:**
/// - Es gibt genau **einen** nativen Strom. Er läuft immer mit der feinsten
///   Anforderung aller angemeldeten Verbraucher (kleinster Abstand, kürzestes
///   Intervall, höchste Genauigkeit, Vordergrunddienst sobald einer ihn will).
/// - Ändert sich diese Anforderung, wird der native Strom **abgebaut und neu
///   aufgebaut**. Nur so gibt geolocator seinen Zwischenspeicher frei; ein
///   zweiter Aufruf mit anderen Einstellungen bewirkt nichts.
/// - Jeder Verbraucher behält trotzdem seine eigene Schwelle: geliefert wird
///   erst, wenn seit der letzten Zustellung **an ihn** sowohl sein Intervall
///   verstrichen als auch sein Abstand zurückgelegt ist. Das ist dieselbe
///   UND-Verknüpfung, die Android für `setMinUpdateDistanceMeters` +
///   `setIntervalMillis` anwendet — der Wetterdienst wird also nicht dadurch
///   gesprächiger, dass die Karte offen ist.
class StandortStrom {
  StandortStrom._();
  static final StandortStrom instance = StandortStrom._();

  final List<StandortAbo> _abos = [];
  StreamSubscription<Position>? _sub;

  /// Einstellungen, mit denen der native Strom gerade läuft — für den
  /// Vergleich, ob ein Neuaufbau überhaupt nötig ist.
  _Anforderung? _aktiv;

  /// Serialisiert Auf-/Abbau. Ohne das können zwei schnell aufeinander
  /// folgende An-/Abmeldungen (Tabwechsel!) zwei native Ströme hinterlassen.
  Future<void> _kette = Future.value();

  /// Letzte bekannte Position — ein neuer Verbraucher bekommt sie sofort,
  /// statt bis zum ersten nativen Fix auf einen leeren Bildschirm zu sehen.
  Position? letztePosition;

  /// Für Tests/Diagnose: womit läuft der native Strom gerade?
  String get aktiveAnforderung => _aktiv == null
      ? 'aus'
      : '${_aktiv!.abstandMeter} m / ${_aktiv!.intervall.inMilliseconds} ms / '
          '${_aktiv!.genauigkeit.name}${_aktiv!.vordergrunddienst ? ' / Vordergrund' : ''}';

  int get anzahlVerbraucher => _abos.length;

  /// Meldet einen Verbraucher an. [abstandMeter] und [intervall] sind seine
  /// **eigene** Schwelle; der native Strom kann feiner laufen, wenn ein anderer
  /// Verbraucher mehr braucht.
  StandortAbo anmelden({
    required String name,
    required int abstandMeter,
    required Duration intervall,
    required void Function(Position) onPosition,
    LocationAccuracy genauigkeit = LocationAccuracy.high,
    bool vordergrunddienst = false,
    void Function(Object)? onFehler,
  }) {
    final abo = StandortAbo._(
      name: name,
      abstandMeter: abstandMeter,
      intervall: intervall,
      genauigkeit: genauigkeit,
      vordergrunddienst: vordergrunddienst,
      onPosition: onPosition,
      onFehler: onFehler,
    );
    _abos.add(abo);
    _log.debug('Standort: "$name" angemeldet (${abstandMeter}m / '
        '${intervall.inSeconds}s), jetzt ${_abos.length} Verbraucher',
        tag: 'STANDORT');
    _neuBewerten();
    // Sofort das Letztbekannte nachreichen — ohne Schwellenprüfung, sonst
    // startet eine frisch geöffnete Karte mit leerem Standort.
    final letzte = letztePosition;
    if (letzte != null) {
      scheduleMicrotask(() {
        if (abo._abgemeldet) return;
        abo.letzte = letzte;
        abo.letzteZeit = DateTime.now();
        try {
          abo.onPosition(letzte);
        } catch (_) {}
      });
    }
    return abo;
  }

  void _abmelden(StandortAbo abo) {
    _abos.remove(abo);
    _log.debug('Standort: "${abo.name}" abgemeldet, noch ${_abos.length}',
        tag: 'STANDORT');
    _neuBewerten();
  }

  /// Baut den nativen Strom neu auf, falls sich die feinste Anforderung
  /// geändert hat.
  void _neuBewerten() {
    final soll = _abos.isEmpty ? null : _Anforderung.ausAbos(_abos);
    if (soll == _aktiv) return;
    _kette = _kette.then((_) => _umschalten(soll)).catchError((Object e) {
      _log.error('Standort: Umschalten fehlgeschlagen: $e', tag: 'STANDORT');
    });
  }

  Future<void> _umschalten(_Anforderung? soll) async {
    // Erneut prüfen: zwischen Einreihen und Ausführen kann sich die Lage
    // geändert haben (Tab auf und gleich wieder zu).
    final jetzt = _abos.isEmpty ? null : _Anforderung.ausAbos(_abos);
    if (jetzt == _aktiv) return;

    // ⚠️ Erst abbestellen und **abwarten**. Der Zwischenspeicher in geolocator
    // wird im `onCancel` des Broadcast-Stroms geleert; ein neues Abonnement
    // davor bekäme wieder die alten Einstellungen.
    await _sub?.cancel();
    _sub = null;
    _aktiv = null;

    if (jetzt == null) {
      _log.debug('Standort: kein Verbraucher mehr, Strom aus', tag: 'STANDORT');
      return;
    }

    try {
      _sub = Geolocator.getPositionStream(locationSettings: jetzt.settings())
          .listen(_verteilen, onError: _fehler);
      _aktiv = jetzt;
      _log.info('Standort: Strom läuft mit $aktiveAnforderung '
          '(${_abos.length} Verbraucher: ${_abos.map((a) => a.name).join(", ")})',
          tag: 'STANDORT');
    } catch (e) {
      _log.error('Standort: Strom konnte nicht starten: $e', tag: 'STANDORT');
    }
  }

  void _verteilen(Position pos) {
    letztePosition = pos;
    final now = DateTime.now();
    for (final abo in List<StandortAbo>.from(_abos)) {
      if (abo._abgemeldet) continue;
      final vorher = abo.letzte;
      if (vorher != null) {
        final seit = abo.letzteZeit == null
            ? const Duration(days: 1)
            : now.difference(abo.letzteZeit!);
        if (seit < abo.intervall) continue;
        if (abo.abstandMeter > 0) {
          final meter = Geolocator.distanceBetween(
              vorher.latitude, vorher.longitude, pos.latitude, pos.longitude);
          if (meter < abo.abstandMeter) continue;
        }
      }
      abo.letzte = pos;
      abo.letzteZeit = now;
      try {
        abo.onPosition(pos);
      } catch (e) {
        _log.debug('Standort: "${abo.name}" warf beim Zustellen: $e',
            tag: 'STANDORT');
      }
    }
  }

  void _fehler(Object e) {
    _log.debug('Standort: Stromfehler: $e', tag: 'STANDORT');
    for (final abo in List<StandortAbo>.from(_abos)) {
      abo.onFehler?.call(e);
    }
  }

  /// Nur für Tests — hinterlässt den Broker im Ausgangszustand.
  Future<void> alleAbmeldenFuerTest() async {
    _abos.clear();
    await _sub?.cancel();
    _sub = null;
    _aktiv = null;
    letztePosition = null;
  }
}

/// Rang der Genauigkeit von grob nach fein.
///
/// ⚠️ **Nicht `LocationAccuracy.index` benutzen.** Die Aufzählung endet mit
/// `reduced` (Index 6), und das ist auf iOS die *ungenaueste* Stufe, nicht die
/// genaueste. Ein Vergleich über den Index würde also ausgerechnet die grobe
/// Stufe als „feinste Anforderung" gewinnen lassen.
int _rang(LocationAccuracy a) {
  switch (a) {
    case LocationAccuracy.reduced:
      return 0;
    case LocationAccuracy.lowest:
      return 1;
    case LocationAccuracy.low:
      return 2;
    case LocationAccuracy.medium:
      return 3;
    case LocationAccuracy.high:
      return 4;
    case LocationAccuracy.best:
      return 5;
    case LocationAccuracy.bestForNavigation:
      return 6;
  }
}

/// Die zusammengefasste Anforderung an das Gerät.
class _Anforderung {
  final int abstandMeter;
  final Duration intervall;
  final LocationAccuracy genauigkeit;
  final bool vordergrunddienst;

  const _Anforderung({
    required this.abstandMeter,
    required this.intervall,
    required this.genauigkeit,
    required this.vordergrunddienst,
  });

  factory _Anforderung.ausAbos(List<StandortAbo> abos) {
    var abstand = abos.first.abstandMeter;
    var intervall = abos.first.intervall;
    var genauigkeit = abos.first.genauigkeit;
    var vordergrund = false;
    for (final a in abos) {
      if (a.abstandMeter < abstand) abstand = a.abstandMeter;
      if (a.intervall < intervall) intervall = a.intervall;
      if (_rang(a.genauigkeit) > _rang(genauigkeit)) genauigkeit = a.genauigkeit;
      if (a.vordergrunddienst) vordergrund = true;
    }
    // Unter einer Sekunde fragt niemand sinnvoll ab; das nur zur Sicherheit,
    // damit ein Tippfehler nicht den Akku frisst.
    if (intervall < const Duration(seconds: 1)) {
      intervall = const Duration(seconds: 1);
    }
    return _Anforderung(
      abstandMeter: abstand < 0 ? 0 : abstand,
      intervall: intervall,
      genauigkeit: genauigkeit,
      vordergrunddienst: vordergrund,
    );
  }

  LocationSettings settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: genauigkeit,
        distanceFilter: abstandMeter,
        intervalDuration: intervall,
        forceLocationManager: false,
        foregroundNotificationConfig: vordergrunddienst
            ? const ForegroundNotificationConfig(
                notificationTitle: 'ÖPNV-Alarm aktiv',
                notificationText:
                    'Vibriert wenn du deine Ausstieg-Haltestelle erreichst.',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: genauigkeit,
        distanceFilter: abstandMeter,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: !vordergrunddienst,
      );
    }
    return LocationSettings(
      accuracy: genauigkeit,
      distanceFilter: abstandMeter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _Anforderung &&
      other.abstandMeter == abstandMeter &&
      other.intervall == intervall &&
      other.genauigkeit == genauigkeit &&
      other.vordergrunddienst == vordergrunddienst;

  @override
  int get hashCode =>
      Object.hash(abstandMeter, intervall, genauigkeit, vordergrunddienst);
}
