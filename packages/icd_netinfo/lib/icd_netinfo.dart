/// Kanal-Definition für die Netz-Momentaufnahme.
///
/// Die Fachlogik liegt in `lib/services/speedtest_service.dart` der App —
/// dieses Paket existiert nur, damit der Kanal über `GeneratedPluginRegistrant`
/// in **jeder** Flutter-Engine registriert wird, auch in der von WorkManager
/// gestarteten Hintergrund-Engine. Genau dort laufen die automatischen
/// Messungen alle 30 Minuten.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// Name des MethodChannels. Muss zu `IcdNetinfoPlugin.CHANNEL` passen.
const String icdNetinfoChannelName = 'de.icd360sev.vorsitzer/netinfo';

const MethodChannel _kanal = MethodChannel(icdNetinfoChannelName);

/// Momentaufnahme des Netzes zum Zeitpunkt des Aufrufs.
///
/// Liefert `null` auf allen Plattformen außer Android — dort gibt es das
/// Plugin nicht, und der Speedtest läuft ohne Netzdaten weiter. Wirft nie:
/// eine fehlende Netzangabe darf niemals eine Messung verhindern.
Future<Map<String, dynamic>?> netzMomentaufnahme() async {
  if (!Platform.isAndroid) return null;
  try {
    final roh = await _kanal.invokeMapMethod<String, dynamic>('snapshot');
    return roh == null ? null : Map<String, dynamic>.from(roh);
  } catch (_) {
    return null;
  }
}

/// Bauform (`handy` / `tablet`) und Betriebssystem-Variante des Android-Geräts,
/// dazu die Roh-Build-Felder.
///
/// Liefert `null` außerhalb von Android — dort ermittelt
/// `speedtest_service.dart` die Bauform selbst.
///
/// ⚠️ `os_variante` ist ein INDIZ, kein Nachweis: sämtliche Build-Felder lassen
/// sich setzen. Findet sich kein Marker, steht dort `unbestimmt` und
/// ausdrücklich nicht `Stock-Android`.
Future<Map<String, dynamic>?> geraeteprofil() async {
  if (!Platform.isAndroid) return null;
  try {
    final roh = await _kanal.invokeMapMethod<String, dynamic>('deviceProfile');
    return roh == null ? null : Map<String, dynamic>.from(roh);
  } catch (_) {
    return null;
  }
}

/// Rohe Byte-Zähler des Geräts, zustandslos.
///
/// Zweimal lesen und die Differenz bilden. Belegt, dass während der Messung
/// nicht parallel etwas anderes die Leitung belegt hat — der billigste Einwand
/// der Gegenseite, sonst unwiderlegbar.
///
/// ⚠️ Einzelne Werte können `null` sein: `TrafficStats` liefert UNSUPPORTED,
/// wenn ein Zähler fehlt. Das muss `null` bleiben, denn die Differenz zweier
/// „−1" ergäbe sauber 0 und das Gerät spräche sich still selbst frei.
Future<Map<String, dynamic>?> verkehrszaehler() async {
  if (!Platform.isAndroid) return null;
  try {
    final roh = await _kanal.invokeMapMethod<String, dynamic>('trafficCounters');
    return roh == null ? null : Map<String, dynamic>.from(roh);
  } catch (_) {
    return null;
  }
}

/// Hat der Nutzer READ_PHONE_STATE erteilt?
///
/// Ohne die Berechtigung fehlen Mobilfunkgeneration, Betreiber und
/// Signalstärke — die Messung läuft trotzdem, sagt aber nichts mehr darüber
/// aus, WARUM die Leitung langsam war.
Future<bool> hatTelefonBerechtigung() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _kanal.invokeMethod<bool>('hasPhonePermission') ?? false;
  } catch (_) {
    return false;
  }
}

/// Fragt READ_PHONE_STATE an. Nur im Vordergrund sinnvoll — aus dem
/// WorkManager-Isolat gibt es keine Activity, dort kommt `false` zurück.
Future<bool> telefonBerechtigungAnfragen() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _kanal.invokeMethod<bool>('requestPhonePermission') ?? false;
  } catch (_) {
    return false;
  }
}
