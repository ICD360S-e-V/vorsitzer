/// Helpers for anonymous-visitor chat. The Mitglieder client lets people
/// open a chat without signing up — server creates a ghost user with
/// role='anonymous' + is_anonymous=1 and the WebSocket flow is otherwise
/// identical to a real member's chat. From the Vorsitzer side we only
/// need to *recognise* those conversations so the operator sees a
/// distinct UI and avoids asking for personal data.
///
/// Everything here is defensive: until the Mitglieder stage-2 server
/// patch lands, the flags simply won't appear in the JSON and these
/// methods all return `false` / `null`. Nothing breaks.
library;

class AnonymousChatHelper {
  /// True when the conversation map carries an anonymous member.
  ///
  /// Accepted shapes (any one wins):
  ///   conversation['is_anonymous'] == 1 | true | "1"
  ///   conversation['member_role']  == 'anonymous'
  ///   conversation['mitgliedernummer'] starts with "ANON_"
  static bool isAnonymousConversation(Map<String, dynamic>? conv) {
    if (conv == null) return false;
    final flag = conv['is_anonymous'];
    if (flag == true || flag == 1 || flag == '1') return true;
    final role = (conv['member_role'] ?? conv['role'])?.toString();
    if (role == 'anonymous') return true;
    final mnr = (conv['mitgliedernummer'] ?? conv['member_nr'])?.toString() ?? '';
    if (mnr.startsWith('ANON_')) return true;
    return false;
  }

  /// True for an incoming new_message frame from an anonymous sender.
  static bool isAnonymousSenderRole(String? role) => role == 'anonymous';

  /// Short display tag for an anonymous member, e.g. "Anonim #A3F7".
  /// Falls back to whatever name the server already supplied.
  static String displayName(Map<String, dynamic> conv) {
    final fromServer = (conv['member_name'] ?? conv['name'])?.toString();
    if (fromServer != null && fromServer.trim().isNotEmpty) return fromServer;
    final mnr = (conv['mitgliedernummer'] ?? conv['member_nr'])?.toString() ?? '';
    if (mnr.startsWith('ANON_') && mnr.length >= 9) {
      return 'Anonim #${mnr.substring(5, 9).toUpperCase()}';
    }
    return mnr.isNotEmpty ? mnr : 'Anonym';
  }

  static AnonymousMetadata? metadataFrom(Map<String, dynamic> conv) {
    final raw = conv['anonymous_metadata'];
    if (raw is Map) {
      return AnonymousMetadata.fromJson(Map<String, dynamic>.from(raw));
    }
    // Some endpoints might flatten the fields next to the conversation
    // root (e.g. anon_list.php). Try that as a fallback so we don't lose
    // the nice metadata chip when the shape changes.
    final flat = AnonymousMetadata.fromJson(conv);
    if (flat.isEmpty) return null;
    return flat;
  }
}

class AnonymousMetadata {
  final String? anonymousId;
  final String? language;
  final String? platform;
  final String? appVersion;
  final DateTime? firstOpenAt;
  final DateTime? lastActive;

  const AnonymousMetadata({
    this.anonymousId,
    this.language,
    this.platform,
    this.appVersion,
    this.firstOpenAt,
    this.lastActive,
  });

  factory AnonymousMetadata.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return AnonymousMetadata(
      anonymousId: (json['anonymous_id'] ?? json['anonymousId'])?.toString(),
      language: json['language']?.toString(),
      platform: json['platform']?.toString(),
      appVersion: (json['app_version'] ?? json['appVersion'])?.toString(),
      firstOpenAt: parse(json['first_open_at'] ?? json['firstOpenAt']),
      lastActive: parse(json['last_active'] ?? json['lastActive']),
    );
  }

  bool get isEmpty =>
      anonymousId == null &&
      language == null &&
      platform == null &&
      appVersion == null &&
      firstOpenAt == null &&
      lastActive == null;

  String get languageLabel {
    switch (language) {
      case 'de':
        return 'Deutsch';
      case 'ro':
        return 'Română';
      case 'en':
        return 'English';
      case 'ru':
        return 'Русский';
      case 'uk':
        return 'Українська';
      case 'tr':
        return 'Türkçe';
      case 'ar':
        return 'العربية';
      default:
        return language ?? '—';
    }
  }
}
