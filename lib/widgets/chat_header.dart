import 'package:flutter/material.dart';
import '../services/sms_service.dart';
import '../utils/anonymous_chat_helper.dart';

/// Die beiden Wege, auf denen eine Nachricht das Haus verlässt.
enum ChatChannel { app, sms }

/// Header for the selected conversation showing member info
class ConversationHeader extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final bool canCall;
  final bool isOpen;
  final bool isMuted;
  final VoidCallback onCall;
  final VoidCallback? onVideoCall;
  /// Start a Fernwartung (remote-support) session with this member.
  final VoidCallback? onRemoteControl;
  final VoidCallback onClose;
  final VoidCallback onMuteToggle;
  final VoidCallback? onScheduledSettings;
  final VoidCallback? onInfoTap;
  final VoidCallback? onAufgabenTap;
  final int aufgabenTotal;
  final int aufgabenOffen;
  final bool hasActiveScheduled;

  /// Open the member's permanent cloud (documents + 1 GB quota).
  final VoidCallback? onCloudTap;

  /// Number of files in the member's cloud (badge on the ☁ button).
  final int cloudFileCount;

  /// Aktuell gewählter Weg für die nächste Nachricht.
  final ChatChannel channel;

  /// Umschalten zwischen App und SMS. Null blendet die Auswahl aus.
  final ValueChanged<ChatChannel>? onChannelChanged;

  const ConversationHeader({
    super.key,
    required this.conversation,
    required this.canCall,
    required this.isOpen,
    required this.onCall,
    this.onVideoCall,
    this.onRemoteControl,
    required this.onClose,
    this.isMuted = false,
    required this.onMuteToggle,
    this.onScheduledSettings,
    this.onInfoTap,
    this.onAufgabenTap,
    this.aufgabenTotal = 0,
    this.aufgabenOffen = 0,
    this.hasActiveScheduled = false,
    this.onCloudTap,
    this.cloudFileCount = 0,
    this.channel = ChatChannel.app,
    this.onChannelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mitgliedernummer = conversation['mitgliedernummer']?.toString()
        ?? conversation['member_nr']?.toString()
        ?? '';
    final isAnonymous = AnonymousChatHelper.isAnonymousConversation(conversation);
    final anonMeta = isAnonymous ? AnonymousChatHelper.metadataFrom(conversation) : null;
    final displayName = isAnonymous
        ? AnonymousChatHelper.displayName(conversation)
        : (mitgliedernummer.isNotEmpty ? mitgliedernummer : 'Unbekannt');

    // Bis zu neun Icon-Buttons in einer Reihe: auf dem Tablet passt das, auf
    // einem Telefon (Pixel 8, 411 dp) sind es rund 430 dp Knöpfe in ~370 dp
    // Platz. Deshalb wird die Reihe unten nach gemessener Breite aufgeteilt,
    // statt an einem geratenen Schwellwert.
    final aktionen = <_Kopfaktion>[
      // Member info — disabled for anonymous (no profile to view)
      if (!isAnonymous)
        _Kopfaktion(
          icon: Icons.info_outline,
          farbe: Colors.lightBlueAccent,
          label: 'Mitglied-Informationen',
          onTap: onInfoTap,
          wichtig: true,
        ),
      // Permanent member cloud (documents + quota) — real members only
      if (!isAnonymous && onCloudTap != null)
        _Kopfaktion(
          icon: Icons.cloud,
          farbe: Colors.lightBlue.shade200,
          label: 'Cloud des Mitglieds (Dokumente)',
          onTap: onCloudTap,
          abzeichen: cloudFileCount > 0 ? '$cloudFileCount' : null,
          abzeichenFarbe: Colors.blue,
        ),
      // Aufgaben — only for real members (anonymous users have no record/Akte)
      if (!isAnonymous && onAufgabenTap != null)
        _Kopfaktion(
          icon: Icons.checklist,
          farbe: aufgabenOffen > 0 ? Colors.orange.shade300 : Colors.grey.shade400,
          label: 'Aufgaben',
          onTap: onAufgabenTap,
          abzeichen: aufgabenTotal > 0
              ? '${aufgabenTotal - aufgabenOffen}/$aufgabenTotal'
              : null,
          abzeichenFarbe: aufgabenOffen > 0 ? Colors.orange : Colors.green,
        ),
      // Scheduled messages — anonymous chat is reactive only, no auto-replies
      if (!isAnonymous && isOpen && onScheduledSettings != null)
        _Kopfaktion(
          icon: Icons.schedule_send,
          farbe: hasActiveScheduled ? Colors.greenAccent.shade400 : Colors.amber.shade300,
          label: hasActiveScheduled
              ? 'Automatische Nachrichten (aktiv)'
              : 'Automatische Nachrichten',
          onTap: onScheduledSettings,
        ),
      // Mute toggle (works for both)
      if (isOpen)
        _Kopfaktion(
          icon: isMuted ? Icons.notifications_off : Icons.notifications_active,
          farbe: isMuted ? Colors.orange : Colors.grey.shade400,
          label: isMuted ? 'Stummschaltung aufheben' : 'Stummschalten',
          onTap: onMuteToggle,
        ),
      // Voice/video call — text-only for anonymous visitors by design
      if (!isAnonymous && isOpen && canCall)
        _Kopfaktion(
          icon: Icons.call,
          farbe: Colors.green,
          label: 'Benutzer anrufen',
          onTap: onCall,
          wichtig: true,
        ),
      if (!isAnonymous && isOpen && canCall && onVideoCall != null)
        _Kopfaktion(
          icon: Icons.videocam,
          farbe: Colors.green,
          label: 'Videoanruf',
          onTap: onVideoCall,
        ),
      // Fernwartung (remote support) — see + control the member's screen
      // after they consent. Separate from the RDP office remote desktop.
      if (!isAnonymous && isOpen && onRemoteControl != null)
        _Kopfaktion(
          icon: Icons.screen_share,
          farbe: Colors.lightBlueAccent,
          label: 'Fernwartung (Bildschirm)',
          onTap: onRemoteControl,
        ),
      // Bewusst NICHT `wichtig`: das weiße × schließt die Konversation, nicht
      // den Dialog. Neben einem echten Schließen-Kreuz wäre das eine Falle.
      if (isOpen)
        _Kopfaktion(
          icon: Icons.close,
          farbe: Colors.white,
          label: 'Konversation schließen',
          onTap: onClose,
        ),
    ];

    final container = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAnonymous ? const Color(0xFFE65100) : const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, zwang) {
          // Avatar + Abstand + Mindestbreite für Name und Kanal-Chips.
          const platzFuerName = 36.0 + 12 + 150;
          final freiFuerKnoepfe = zwang.maxWidth - platzFuerName;
          var sichtbar = (freiFuerKnoepfe / _knopfBreite).floor();
          if (sichtbar < 0) sichtbar = 0;

          final List<_Kopfaktion> inDerReihe;
          final List<_Kopfaktion> imMenue;
          if (sichtbar >= aktionen.length) {
            inDerReihe = aktionen;
            imMenue = const [];
          } else {
            // Ein Platz geht an das ⋮ selbst.
            final plaetze = sichtbar - 1;
            final gewaehlt = aktionen
                .where((a) => a.wichtig)
                .take(plaetze < 0 ? 0 : plaetze)
                .toSet();
            inDerReihe = aktionen.where(gewaehlt.contains).toList();
            imMenue = aktionen.where((a) => !gewaehlt.contains(a)).toList();
          }

          return Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isAnonymous ? const Color(0xFFFFB74D) : Colors.blue,
                child: Icon(
                  isAnonymous ? Icons.help_outline : Icons.person,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (isAnonymous)
                      const Text(
                        'Vizitator anonim',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    // Anonyme Besucher haben keinen Datensatz und damit keine
                    // Rufnummer — für sie gibt es nur den App-Weg.
                    if (!isAnonymous && onChannelChanged != null)
                      _ChannelChips(
                        channel: channel,
                        onChanged: onChannelChanged!,
                        sms: _smsCheck(conversation),
                      ),
                  ],
                ),
              ),
              ...inDerReihe.map((a) => a.alsKnopf()),
              if (imMenue.isNotEmpty)
                PopupMenuButton<_Kopfaktion>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  tooltip: 'Weitere Aktionen',
                  onSelected: (a) => a.onTap?.call(),
                  itemBuilder: (_) => [
                    for (final a in imMenue)
                      PopupMenuItem<_Kopfaktion>(
                        value: a,
                        enabled: a.onTap != null,
                        child: Row(
                          children: [
                            Icon(a.icon, size: 20, color: _menueFarbe(a.farbe)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(a.label)),
                            if (a.abzeichen != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: a.abzeichenFarbe ?? Colors.blue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  a.abzeichen!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );

    if (!isAnonymous) return container;

    return _withMetadata(container, anonMeta);
  }

  /// Prüft die in Verifizierung Stufe 1 hinterlegte Rufnummer.
  ///
  /// `null` heißt: der Server liefert das Feld überhaupt nicht mit (ältere
  /// `api/chat/conversations.php`). Dann bleibt die Kanalauswahl ausgeblendet,
  /// statt „keine Nummer" zu behaupten — 23 der 42 Mitglieder haben eine, und
  /// die als nicht erreichbar anzuzeigen wäre schlicht falsch.
  static SmsNumberCheck? _smsCheck(Map<String, dynamic> conv) {
    if (!conv.containsKey('telefon_mobil')) return null;
    return SmsService.check(conv['telefon_mobil']?.toString());
  }

  Widget _withMetadata(Widget container, AnonymousMetadata? anonMeta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        container,
        const SizedBox(height: 6),
        _AnonymousMetadataPanel(metadata: anonMeta),
      ],
    );
  }

  /// Die Kopfleiste ist dunkel, das Popup-Menü hell. Weiß und die hellen
  /// Pastelltöne wären dort unlesbar, also dunkeln wir sie fürs Menü ab.
  static Color _menueFarbe(Color farbe) {
    return HSLColor.fromColor(farbe).lightness > 0.6
        ? HSLColor.fromColor(farbe).withLightness(0.35).toColor()
        : farbe;
  }
}

/// Breite eines IconButton in Material 3 (48 dp Tap-Ziel) — die Rechengröße,
/// mit der die Kopfleiste entscheidet, was noch in die Reihe passt.
const double _knopfBreite = 48.0;

/// Eine Aktion der Konversations-Kopfleiste, entweder als Knopf in der Reihe
/// oder als Zeile im ⋮-Menü. Beide Wege aus einer Beschreibung, damit auf dem
/// Telefon nichts verschwindet, was auf dem Tablet erreichbar ist.
class _Kopfaktion {
  final IconData icon;
  final Color farbe;
  final String label;
  final VoidCallback? onTap;
  final String? abzeichen;
  final Color? abzeichenFarbe;

  /// Bleibt sichtbar, solange überhaupt Platz für Knöpfe ist.
  final bool wichtig;

  const _Kopfaktion({
    required this.icon,
    required this.farbe,
    required this.label,
    required this.onTap,
    this.abzeichen,
    this.abzeichenFarbe,
    this.wichtig = false,
  });

  Widget alsKnopf() {
    final knopf = IconButton(
      icon: Icon(icon, color: farbe),
      onPressed: onTap,
      tooltip: label,
    );
    if (abzeichen == null) return knopf;
    return Stack(
      children: [
        knopf,
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: abzeichenFarbe ?? Colors.blue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              abzeichen!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// App | SMS — welchen Weg die nächste Nachricht nimmt.
///
/// Der gewählte Weg ist grün, der andere bleibt grau. Fehlt die Rufnummer,
/// wird der SMS-Knopf nicht einfach still weggelassen, sondern ausdrücklich
/// als nicht verfügbar angezeigt: das betrifft 19 der 42 Mitglieder, und ein
/// unsichtbarer Knopf sähe wie ein Fehler aus. Ein stilles Ausweichen auf die
/// App gibt es nicht — wer SMS wählt, bekommt SMS oder eine Erklärung.
class _ChannelChips extends StatelessWidget {
  final ChatChannel channel;
  final ValueChanged<ChatChannel> onChanged;
  final SmsNumberCheck? sms;

  const _ChannelChips({
    required this.channel,
    required this.onChanged,
    required this.sms,
  });

  @override
  Widget build(BuildContext context) {
    final check = sms;
    if (check == null) return const SizedBox.shrink();
    final smsMoeglich = check.canSend;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(
            label: 'App',
            icon: Icons.chat_bubble_outline,
            selected: channel == ChatChannel.app,
            enabled: true,
            tooltip: 'Nachricht im Live-Chat',
            onTap: () => onChanged(ChatChannel.app),
          ),
          const SizedBox(width: 6),
          _chip(
            label: smsMoeglich ? 'SMS' : 'SMS nicht verfügbar',
            icon: smsMoeglich ? Icons.sms_outlined : Icons.sms_failed_outlined,
            selected: smsMoeglich && channel == ChatChannel.sms,
            enabled: smsMoeglich,
            // Bei fehlender Nummer steht der Grund im Tooltip UND im Text —
            // der Vorsitzer soll sehen, dass die Nummer in Stufe 1 fehlt, und
            // nicht rätseln, warum der Knopf tot ist.
            tooltip: smsMoeglich
                ? 'SMS an ${check.label}'
                : 'Keine SMS möglich: ${check.label}',
            onTap: smsMoeglich ? () => onChanged(ChatChannel.sms) : null,
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final Color hintergrund;
    final Color vordergrund;
    final Color rand;
    if (selected) {
      hintergrund = Colors.green.shade600;
      vordergrund = Colors.white;
      rand = Colors.green.shade300;
    } else if (enabled) {
      hintergrund = Colors.white.withValues(alpha: 0.10);
      vordergrund = Colors.white70;
      rand = Colors.white24;
    } else {
      hintergrund = Colors.white.withValues(alpha: 0.04);
      vordergrund = Colors.white38;
      rand = Colors.white12;
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: hintergrund,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: rand, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: vordergrund),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: vordergrund,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnonymousMetadataPanel extends StatelessWidget {
  final AnonymousMetadata? metadata;
  const _AnonymousMetadataPanel({this.metadata});

  String _relative(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min';
    if (d.inHours < 24) return 'vor ${d.inHours} Std';
    if (d.inDays < 7) return 'vor ${d.inDays} Tag${d.inDays > 1 ? 'en' : ''}';
    return 'vor ${(d.inDays / 7).floor()} Wochen';
  }

  @override
  Widget build(BuildContext context) {
    final m = metadata;
    final rows = <Widget>[];

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
            ],
          ),
        );

    if (m?.language != null) rows.add(row(Icons.language, 'Gewählte Sprache', m!.languageLabel));
    if (m?.platform != null) {
      final v = m!.appVersion != null ? ' (v${m.appVersion})' : '';
      rows.add(row(Icons.devices, 'System', '${m.platform}$v'));
    }
    if (m?.lastActive != null) {
      rows.add(row(Icons.access_time, 'Aktiv', _relative(m!.lastActive!)));
    }
    if (m?.firstOpenAt != null) {
      rows.add(row(Icons.event, 'Erste Nutzung', _relative(m!.firstOpenAt!)));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          if (rows.isNotEmpty) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kein Mitglied — keine sensiblen Dokumente senden, keine persönlichen Daten erfragen.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A stat badge for showing counts (e.g., Open: 5, Total: 10)
class StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const StatBadge({
    super.key,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          // ⚠️ `mainAxisSize.min` macht die Reihe klein, wenn sie kann —
          // nicht, wenn sie muss. Die Kanal-Chips stehen in der 250 dp
          // breiten Konversationsspalte und liefen dort um 274 dp über.
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Connection status indicator
class ConnectionStatus extends StatelessWidget {
  final bool isConnected;

  const ConnectionStatus({
    super.key,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Typing indicator
class TypingIndicator extends StatelessWidget {
  final String userName;

  const TypingIndicator({
    super.key,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$userName schreibt...',
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
