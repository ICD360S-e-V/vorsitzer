/// Kanal-Definition für den nativen SMS-Versand.
///
/// Die Fachlogik (Rufnummernprüfung, GSM-7-Text, Warteschlange) liegt in
/// `lib/services/sms_service.dart` der App — dieses Paket existiert nur, damit
/// der Kanal über `GeneratedPluginRegistrant` in **jeder** Flutter-Engine
/// registriert wird, auch in der von WorkManager gestarteten Hintergrund-Engine.
library;

import 'package:flutter/services.dart';

/// Name des MethodChannels. Muss zu `IcdSmsPlugin.CHANNEL` passen.
const String icdSmsChannelName = 'de.icd360sev.vorsitzer/sms';

/// Fertig gebundener Kanal für Aufrufer, die nichts weiter brauchen.
const MethodChannel icdSmsChannel = MethodChannel(icdSmsChannelName);
