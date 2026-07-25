import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// One upload from a channel's public feed.
class YoutubeVideo {
  final String id;
  final String title;
  final DateTime? published;
  final String thumbnail;

  const YoutubeVideo({
    required this.id,
    required this.title,
    required this.published,
    required this.thumbnail,
  });

  factory YoutubeVideo.fromJson(Map<String, dynamic> j) => YoutubeVideo(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        published: DateTime.tryParse((j['published'] ?? '') as String)?.toLocal(),
        thumbnail: (j['thumbnail'] ?? '') as String,
      );

  String get watchUrl => 'https://www.youtube.com/watch?v=$id';
}

/// A saved YouTube channel. Everything except the badge/sort bookkeeping is
/// stored AES-256-GCM encrypted server-side; this is the decrypted view.
class YoutubeChannel {
  final int id;
  final String channelId;
  final String title;
  final String? latestVideoId;
  final String? latestTitle;
  final String? latestThumbnail;
  final DateTime? latestPublished;
  final List<YoutubeVideo> videos;
  final bool hasNew;

  const YoutubeChannel({
    required this.id,
    required this.channelId,
    required this.title,
    required this.latestVideoId,
    required this.latestTitle,
    required this.latestThumbnail,
    required this.latestPublished,
    required this.videos,
    required this.hasNew,
  });

  factory YoutubeChannel.fromJson(Map<String, dynamic> j) => YoutubeChannel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        channelId: (j['channel_id'] ?? '') as String,
        title: (j['title'] ?? 'Unbekannter Kanal') as String,
        latestVideoId: j['latest_video_id'] as String?,
        latestTitle: j['latest_title'] as String?,
        latestThumbnail: j['latest_thumbnail'] as String?,
        latestPublished:
            DateTime.tryParse((j['latest_published'] ?? '') as String)?.toLocal(),
        videos: ((j['videos'] as List?) ?? const [])
            .whereType<Map>()
            .map((v) => YoutubeVideo.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        hasNew: j['has_new'] == true,
      );

  YoutubeChannel copyWith({bool? hasNew}) => YoutubeChannel(
        id: id,
        channelId: channelId,
        title: title,
        latestVideoId: latestVideoId,
        latestTitle: latestTitle,
        latestThumbnail: latestThumbnail,
        latestPublished: latestPublished,
        videos: videos,
        hasNew: hasNew ?? this.hasNew,
      );

  String get channelUrl => 'https://www.youtube.com/channel/$channelId';

  /// Where the tile should take you: the newest upload if we know it,
  /// otherwise the channel page.
  String get targetUrl =>
      latestVideoId != null ? 'https://www.youtube.com/watch?v=$latestVideoId' : channelUrl;

  String get ageLabel {
    final p = latestPublished;
    if (p == null) return '';
    final d = DateTime.now().difference(p);
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
    if (d.inHours < 24) return 'vor ${d.inHours} Std.';
    if (d.inDays < 7) return 'vor ${d.inDays} Tag${d.inDays > 1 ? 'en' : ''}';
    return '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
  }
}

/// Saved YouTube channels + "is there a new video" state.
///
/// The server does the actual polling (cron, every 20 min, public Atom feed —
/// no API key, no quota) and pushes via ntfy. The app only reads the result,
/// so opening the TV screen costs one request, not one request per channel.
class YoutubeService {
  static final YoutubeService _instance = YoutubeService._internal();
  factory YoutubeService() => _instance;
  YoutubeService._internal();

  final ApiService _api = ApiService();

  List<YoutubeChannel> _channels = const [];
  List<YoutubeChannel> get channels => _channels;

  /// Number of channels with an unseen upload — drives the header badge.
  final ValueNotifier<int> newCount = ValueNotifier<int>(0);

  bool _loading = false;
  bool get isLoading => _loading;

  void _apply(Map<String, dynamic> resp) {
    final items = (resp['items'] as List?) ?? const [];
    _channels = items
        .whereType<Map>()
        .map((e) => YoutubeChannel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    newCount.value = (resp['new_count'] as num?)?.toInt() ??
        _channels.where((c) => c.hasNew).length;
  }

  /// Read the saved list. [refresh] additionally re-polls every feed on the
  /// server (pull-to-refresh); the unattended cron does the same on its own.
  Future<bool> load({bool refresh = false}) async {
    if (_loading) return false;
    _loading = true;
    try {
      final resp = await _api.youtubeAction(refresh ? 'refresh' : 'list');
      if (resp['success'] != true) {
        _log.warning('YouTube list failed: ${resp['message']}', tag: 'TV');
        return false;
      }
      _apply(resp);
      return true;
    } finally {
      _loading = false;
    }
  }

  /// Badge-only refresh for the dashboard header — no UI depends on the list
  /// itself here, so a failure stays silent.
  Future<void> refreshBadge() async {
    final resp = await _api.youtubeAction('list');
    if (resp['success'] == true) _apply(resp);
  }

  /// Save the channel the given YouTube URL belongs to. Works from a channel
  /// page, a @handle, or straight from a video — the server resolves the
  /// uploader. The message is server-supplied and names the channel, so the
  /// star can say "tagesschau gespeichert" instead of a generic confirmation.
  Future<({bool ok, String message})> addFromUrl(String url) async {
    final resp = await _api.youtubeAction('add', {'url': url});
    final ok = resp['success'] == true;
    final msg = (resp['message'] as String?)?.trim() ?? '';
    if (ok) await load();
    return (
      ok: ok,
      message: msg.isNotEmpty
          ? msg
          : (ok ? 'Kanal gespeichert' : 'Kanal konnte nicht gespeichert werden'),
    );
  }

  Future<void> markSeen(int id) async {
    // Optimistic: the badge should drop the moment the video is opened.
    _channels = _channels
        .map((c) => c.id == id ? c.copyWith(hasNew: false) : c)
        .toList();
    newCount.value = _channels.where((c) => c.hasNew).length;
    await _api.youtubeAction('seen', {'id': id});
  }

  Future<void> markAllSeen() async {
    await _api.youtubeAction('seen_all');
    await load();
  }

  Future<bool> remove(int id) async {
    final resp = await _api.youtubeAction('delete', {'id': id});
    if (resp['success'] != true) return false;
    await load();
    return true;
  }
}
