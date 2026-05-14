import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

final _log = LoggerService();

/// A single news article from Tagesschau RSS
class NewsArticle {
  final String title;
  final String description;
  final String link;
  final DateTime pubDate;
  final String? imageUrl;
  final String source; // "national" or region name

  NewsArticle({
    required this.title,
    required this.description,
    required this.link,
    required this.pubDate,
    this.imageUrl,
    required this.source,
  });

  /// How long ago the article was published
  String get timeAgo {
    final diff = DateTime.now().difference(pubDate);
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    return 'vor ${diff.inDays} Tag${diff.inDays > 1 ? 'en' : ''}';
  }
}

/// Mapping GPS coordinates → Bundesland → Tagesschau RSS region slug
class _RegionMapper {
  /// Map Bundesland name to Tagesschau RSS slug
  static const Map<String, String> _bundeslandSlugs = {
    'Baden-Württemberg': 'badenwuerttemberg',
    'Bayern': 'bayern',
    'Berlin': 'berlin',
    'Brandenburg': 'brandenburg',
    'Bremen': 'bremen',
    'Hamburg': 'hamburg',
    'Hessen': 'hessen',
    'Mecklenburg-Vorpommern': 'mecklenburgvorpommern',
    'Niedersachsen': 'niedersachsen',
    'Nordrhein-Westfalen': 'nordrheinwestfalen',
    'Rheinland-Pfalz': 'rheinlandpfalz',
    'Saarland': 'saarland',
    'Sachsen': 'sachsen',
    'Sachsen-Anhalt': 'sachsenanhalt',
    'Schleswig-Holstein': 'schleswigholstein',
    'Thüringen': 'thueringen',
  };

  /// Get Tagesschau RSS slug from Bundesland name
  static String? getSlug(String? bundesland) {
    if (bundesland == null) return null;
    return _bundeslandSlugs[bundesland];
  }
}

/// News service using Tagesschau RSS feeds (free, no API key)
/// Fetches national + regional news based on GPS location
class NewsService {
  Timer? _refreshTimer;
  String? _bundesland;
  String? _regionSlug;

  List<NewsArticle> nationalNews = [];
  List<NewsArticle> regionalNews = [];
  bool isLoading = false;

  // Callbacks
  void Function()? onNewsUpdate;

  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  /// Current region name for display
  String? get regionName => _bundesland;

  /// Start news monitoring — detects Bundesland from GPS via reverse geocoding
  Future<void> start({double? lat, double? lon}) async {
    // Determine region from GPS
    if (lat != null && lon != null) {
      await _detectRegion(lat, lon);
    }

    // Initial fetch
    await fetchNews();

    // Refresh every 15 minutes
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      fetchNews();
    });
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _log.info('News: Stopped', tag: 'NEWS');
  }

  /// Detect Bundesland from GPS coordinates using Nominatim
  Future<void> _detectRegion(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=de&zoom=5',
      );
      final response = await _client.get(uri, headers: {
        'User-Agent': 'ICD360S-eV-App/1.0',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];
        if (address != null) {
          final state = address['state']?.toString();
          if (state != null) {
            _bundesland = state;
            _regionSlug = _RegionMapper.getSlug(state);
            _log.info('News: Region detected → $_bundesland (slug: $_regionSlug)', tag: 'NEWS');
          }
        }
      }
    } catch (e) {
      _log.error('News: Region detection failed: $e', tag: 'NEWS');
    }
  }

  /// Fetch national + regional news
  Future<void> fetchNews() async {
    isLoading = true;

    await Future.wait([
      _fetchFeed(
        'https://www.tagesschau.de/index~rss2.xml',
        'Deutschland',
        (articles) => nationalNews = articles,
      ),
      if (_regionSlug != null)
        _fetchFeed(
          'https://www.tagesschau.de/inland/regional/$_regionSlug/index~rss2.xml',
          _bundesland ?? 'Regional',
          (articles) => regionalNews = articles,
        ),
    ]);

    isLoading = false;
    onNewsUpdate?.call();

    _log.debug(
      'News: ${nationalNews.length} national, ${regionalNews.length} regional ($_bundesland)',
      tag: 'NEWS',
    );
  }

  /// Parse a single RSS feed
  Future<void> _fetchFeed(
    String url,
    String source,
    void Function(List<NewsArticle>) onResult,
  ) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'ICD360S-eV-App/1.0',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final articles = _parseRss(response.body, source);
        onResult(articles);
      } else {
        _log.error('News: Feed $source returned ${response.statusCode}', tag: 'NEWS');
      }
    } catch (e) {
      _log.error('News: Feed $source failed: $e', tag: 'NEWS');
    }
  }

  /// Simple RSS XML parser (no external dependency needed)
  List<NewsArticle> _parseRss(String xml, String source) {
    final articles = <NewsArticle>[];

    // Split by <item> tags
    final items = xml.split('<item>');
    // Skip first element (header)
    for (int i = 1; i < items.length && i <= 20; i++) {
      final item = items[i];

      final title = _extractTag(item, 'title');
      final description = _extractTag(item, 'description');
      final link = _extractTag(item, 'link');
      final pubDateStr = _extractTag(item, 'pubDate');

      if (title == null || title.isEmpty) continue;

      // Extract image URL from content:encoded
      String? imageUrl;
      final contentEncoded = _extractCdata(item, 'content:encoded');
      if (contentEncoded != null) {
        final imgMatch = RegExp(r'<img\s+src="([^"]+)"').firstMatch(contentEncoded);
        if (imgMatch != null) {
          imageUrl = imgMatch.group(1);
        }
      }

      // Parse pubDate (RFC 2822)
      DateTime pubDate;
      if (pubDateStr != null) {
        pubDate = _parseRfc2822(pubDateStr) ?? DateTime.now();
      } else {
        pubDate = DateTime.now();
      }

      articles.add(NewsArticle(
        title: _decodeHtml(title),
        description: _decodeHtml(description ?? ''),
        link: link ?? '',
        pubDate: pubDate,
        imageUrl: imageUrl,
        source: source,
      ));
    }

    return articles;
  }

  /// Extract content between XML tags
  String? _extractTag(String xml, String tag) {
    final startTag = '<$tag>';
    final endTag = '</$tag>';
    final startIdx = xml.indexOf(startTag);
    if (startIdx == -1) return null;
    final contentStart = startIdx + startTag.length;
    final endIdx = xml.indexOf(endTag, contentStart);
    if (endIdx == -1) return null;
    var content = xml.substring(contentStart, endIdx).trim();
    // Remove CDATA wrapper if present
    if (content.startsWith('<![CDATA[')) {
      content = content.substring(9);
      if (content.endsWith(']]>')) {
        content = content.substring(0, content.length - 3);
      }
    }
    return content;
  }

  /// Extract CDATA content from namespaced tag
  String? _extractCdata(String xml, String tag) {
    final startTag = '<$tag>';
    final endTag = '</$tag>';
    final startIdx = xml.indexOf(startTag);
    if (startIdx == -1) return null;
    final contentStart = startIdx + startTag.length;
    final endIdx = xml.indexOf(endTag, contentStart);
    if (endIdx == -1) return null;
    var content = xml.substring(contentStart, endIdx).trim();
    if (content.startsWith('<![CDATA[')) {
      content = content.substring(9);
      if (content.endsWith(']]>')) {
        content = content.substring(0, content.length - 3);
      }
    }
    return content;
  }

  /// Parse RFC 2822 date (e.g. "Sun, 15 Feb 2026 16:37:43 +0100")
  DateTime? _parseRfc2822(String dateStr) {
    try {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };

      // Remove day name prefix if present
      final parts = dateStr.replaceAll(',', '').trim().split(RegExp(r'\s+'));
      // Expected: [DayName] Day Month Year Hour:Min:Sec Timezone
      int offset = 0;
      if (parts.length >= 6) offset = 1; // Has day name
      if (parts.length < 5) return null;

      final day = int.parse(parts[offset]);
      final month = months[parts[offset + 1]] ?? 1;
      final year = int.parse(parts[offset + 2]);
      final timeParts = parts[offset + 3].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      return null;
    }
  }

  /// Decode basic HTML entities
  String _decodeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Force refresh
  Future<void> refresh() async {
    await fetchNews();
  }
}
