import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Ungelesene im Eingang aus der Antwort von `mail/folders.php`.
///
/// `null`, wenn die Antwort den Eingang gar nicht nennt — das ist etwas
/// anderes als „null ungelesen" und darf ein bestehendes Abzeichen nicht
/// löschen. Andere Ordner werden bewusst ignoriert, auch `Junk`.
int? mailUngeleseneAusAntwort(Map<String, dynamic> antwort) {
  final ordner = antwort['folders'];
  // Die Ordnerliste kommt als JSON-Liste. Eine nach Ordnernamen geschlüsselte
  // Map wäre genauso lesbar — und die stille Verwechslung der beiden Formen
  // hat den Speedtest-Bildschirm schon einmal grau werden lassen.
  final eintraege = ordner is List
      ? ordner
      : ordner is Map
          ? ordner.values.toList()
          : const [];
  for (final f in eintraege) {
    if (f is Map && '${f['box'] ?? ''}' == 'INBOX') {
      final n = (f['unseen'] as num?)?.toInt() ?? 0;
      return n < 0 ? 0 : n;
    }
  }
  return null;
}

/// Ungelesene Mails im Eingang — die Zahl hinter dem Briefsymbol im Kopf.
///
/// Die Zahl gab es serverseitig längst: `mail/folders.php` liefert pro Ordner
/// `total`/`unseen`, und der Mail-Bildschirm zeigt daraus „N ungelesen" an.
/// Nur hat sie nie jemand ausserhalb des Mail-Bildschirms abgefragt, also
/// blieb das Briefsymbol im Kopf immer stumm — auch bei ungelesener Post.
///
/// ⚠️ Gezählt wird **allein INBOX**. Entwürfe und Spam sind technisch auch
/// „ungelesen", aber ein Abzeichen, das wegen dreier Werbemails im Spam
/// leuchtet, wird nach einer Woche ignoriert — und dann fällt die echte Mail
/// auch nicht mehr auf.
class MailBadgeService {
  static final MailBadgeService _instance = MailBadgeService._internal();
  factory MailBadgeService() => _instance;
  MailBadgeService._internal();

  final ApiService _api = ApiService();

  /// Ungelesene Nachrichten im Eingang. 0 heisst „nichts Ungelesenes", nicht
  /// „unbekannt" — bei einem Fehler bleibt der letzte bekannte Stand stehen.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  bool _laeuft = false;
  Timer? _takt;

  /// ⚠️ Bewusst gross. Die App hat sich schon einmal über Nacht am Dauertakt
  /// leergezogen (5.176 Anfragen/h im nginx-Log); fünf Minuten sind zwölf
  /// Anfragen in der Stunde, und `doveadm mailbox status` ist ein Zähler,
  /// keine Ordnerlistung. Wer schneller Bescheid wissen will, öffnet das
  /// Postfach — dann steht die Zahl ohnehin sofort.
  static const Duration taktweite = Duration(minutes: 5);

  /// Läuft, solange das Dashboard steht. Ohne das erschiene neue Post erst,
  /// wenn jemand die App weglegt und zurückholt — auf dem Schreibtisch also
  /// womöglich den ganzen Tag nicht.
  void start() {
    _takt ??= Timer.periodic(taktweite, (_) => refreshBadge());
  }

  void stop() {
    _takt?.cancel();
    _takt = null;
  }

  /// Eine Anfrage, absichtlich kein Dauer-Polling: das Telefon hat sich schon
  /// einmal an genau solchen Takten leergezogen. Aufgerufen wird beim Start,
  /// beim Aufwecken und nach dem Verlassen des Mail-Bildschirms — also immer
  /// dann, wenn sich der Stand überhaupt geändert haben kann.
  Future<void> refreshBadge() async {
    if (_laeuft) return;
    _laeuft = true;
    try {
      final res = await _api.getMailFolders();
      if (res['success'] != true) {
        _log.warning('Mail-Ordner nicht lesbar: ${res['message']}', tag: 'MAIL');
        return;
      }
      final n = mailUngeleseneAusAntwort(res);
      // null heisst „die Antwort nennt den Eingang nicht" — dann ist der letzte
      // bekannte Stand ehrlicher als eine erfundene 0.
      if (n != null) unreadCount.value = n;
    } catch (e) {
      _log.warning('Mail-Abzeichen fehlgeschlagen: $e', tag: 'MAIL');
    } finally {
      _laeuft = false;
    }
  }

  /// Übernimmt einen Stand, den der Mail-Bildschirm ohnehin gerade geladen
  /// hat. Spart die zweite Anfrage und hält das Abzeichen synchron, während
  /// jemand im Postfach Nachrichten öffnet oder als gelesen markiert.
  void setzeAusOrdnern(int inboxUnseen) {
    unreadCount.value = inboxUnseen < 0 ? 0 : inboxUnseen;
  }
}
