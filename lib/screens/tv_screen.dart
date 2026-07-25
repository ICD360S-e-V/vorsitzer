import 'package:flutter/material.dart';

import '../services/youtube_service.dart';
import 'webview_screen.dart';

/// TV — gespeicherte YouTube-Kanäle mit Neue-Video-Erkennung.
///
/// Tippen auf einen Kanal öffnet direkt das neueste Video im eingebauten
/// Browser (unter Linux/Flatpak stattdessen im externen Chromium, siehe
/// [WebViewScreen]). Neue Kanäle kommen über den Stern in der Browser-Leiste
/// dazu — man muss die Kanal-ID nirgends abtippen.
class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  final _yt = YoutubeService();
  bool _busy = true;

  static const _accent = Color(0xFF4a90d9);
  static const _youtubeHome = 'https://www.youtube.com';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _busy = true);
    await _yt.load(refresh: refresh);
    if (mounted) setState(() => _busy = false);
  }

  /// The star handler shared by every browser we open from here.
  Future<({bool ok, String message})> _saveChannel(String url) =>
      _yt.addFromUrl(url);

  Future<void> _openBrowser(String url, {String title = 'YouTube'}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(
        title: title,
        url: url,
        onFavorite: _saveChannel,
        favoriteTooltip: 'Kanal speichern',
      ),
    ));
    // Coming back: a channel may have been starred inside the browser.
    if (mounted) await _load();
  }

  /// Tap on a channel: its Videos-tab list, newest first, so you can see which
  /// ones are new rather than being thrown straight into the newest video.
  Future<void> _openChannel(YoutubeChannel c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ChannelVideosScreen(channelId: c.id),
    ));
    if (mounted) await _load();
  }

  Future<void> _addByUrlDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kanal hinzufügen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YouTube-Adresse einfügen — Kanal, @Handle oder ein Video des Kanals.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'https://www.youtube.com/@…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final res = await _saveChannel(url);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.message),
      backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
  }

  Future<void> _confirmRemove(YoutubeChannel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kanal entfernen?'),
        content: Text('"${c.title}" wird aus der Liste gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _yt.remove(c.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final channels = _yt.channels;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TV — YouTube-Kanäle'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: 'YouTube öffnen',
            onPressed: () => _openBrowser(_youtubeHome),
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Kanal per Adresse hinzufügen',
            onPressed: _addByUrlDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Auf neue Videos prüfen',
            onPressed: _busy ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: channels.isEmpty
                ? _emptyState()
                : RefreshIndicator(
                    onRefresh: () => _load(refresh: true),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: channels.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _channelTile(channels[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBrowser(_youtubeHome),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.play_circle_outline),
        label: const Text('YouTube durchsuchen'),
      ),
    );
  }

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.live_tv, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Noch keine Kanäle gespeichert',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Text(
            'YouTube öffnen, auf einen Kanal oder ein Video gehen und oben auf '
            'den Stern ⭐ tippen — der Kanal wird gespeichert und ab dann auf '
            'neue Videos geprüft.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
          ),
        ],
      );

  Widget _channelTile(YoutubeChannel c) {
    final thumb = c.latestThumbnail;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: () => _openChannel(c),
      leading: SizedBox(
        width: 96,
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: thumb != null && thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbFallback(),
                    )
                  : _thumbFallback(),
            ),
            if (c.unseenCount > 0)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Text(
                    c.unseenCount > 1 ? '${c.unseenCount} NEU' : 'NEU',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        c.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: c.hasNew ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.latestTitle != null)
            Text(
              c.latestTitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          if (c.ageLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                c.ageLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'channel':
              _openBrowser(c.channelUrl, title: c.title);
              break;
            case 'seen':
              await _yt.markSeen(c.id);
              if (mounted) setState(() {});
              break;
            case 'delete':
              _confirmRemove(c);
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'channel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.subscriptions_outlined),
              title: Text('Kanalseite öffnen'),
            ),
          ),
          if (c.unseenCount > 0)
            const PopupMenuItem(
              value: 'seen',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.done_all),
                title: Text('Alle als gesehen markieren'),
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Entfernen'),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _thumbFallback() => Container(
      color: Colors.grey.shade300,
      child: Icon(Icons.play_arrow, color: Colors.grey.shade600),
    );

/// The Videos tab of one saved channel: newest first, NEU on everything that
/// was never opened from here. Reads its channel back out of [YoutubeService]
/// on every build so the marks stay in step with the list behind it.
class _ChannelVideosScreen extends StatefulWidget {
  final int channelId;

  const _ChannelVideosScreen({required this.channelId});

  @override
  State<_ChannelVideosScreen> createState() => _ChannelVideosScreenState();
}

class _ChannelVideosScreenState extends State<_ChannelVideosScreen> {
  final _yt = YoutubeService();

  YoutubeChannel? get _channel {
    for (final c in _yt.channels) {
      if (c.id == widget.channelId) return c;
    }
    return null;
  }

  Future<void> _openVideo(YoutubeChannel c, YoutubeVideo v) async {
    if (!v.seen) await _yt.markVideoSeen(c.id, v.id);
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(
        title: c.title,
        url: v.watchUrl,
        onFavorite: _yt.addFromUrl,
        favoriteTooltip: 'Kanal speichern',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = _channel;
    if (c == null) {
      // Channel removed while we were on it.
      return const Scaffold(body: Center(child: Text('Kanal nicht mehr vorhanden')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        backgroundColor: const Color(0xFF4a90d9),
        foregroundColor: Colors.white,
        actions: [
          if (c.unseenCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Alle als gesehen markieren',
              onPressed: () async {
                await _yt.markSeen(c.id);
                if (mounted) setState(() {});
              },
            ),
          IconButton(
            icon: const Icon(Icons.subscriptions_outlined),
            tooltip: 'Kanalseite öffnen',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WebViewScreen(
                title: c.title,
                url: c.channelUrl,
                onFavorite: _yt.addFromUrl,
                favoriteTooltip: 'Kanal speichern',
              ),
            )),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: c.videos.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final v = c.videos[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            onTap: () => _openVideo(c, v),
            leading: SizedBox(
              width: 110,
              height: 62,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: v.thumbnail.isNotEmpty
                    ? Image.network(
                        v.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
            ),
            title: Text(
              v.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: v.seen ? FontWeight.normal : FontWeight.bold,
                color: v.seen ? Colors.grey.shade700 : null,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (!v.seen)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'NEU',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.visibility_outlined,
                        size: 14, color: Colors.grey.shade500),
                  if (v.seen) const SizedBox(width: 6),
                  Text(
                    v.ageLabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
