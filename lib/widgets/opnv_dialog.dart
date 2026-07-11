import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'dart:io' show Platform;
import '../services/notification_service.dart';
import '../services/transit_service.dart';
import '../services/transit_disruptions_service.dart';
import '../services/transit_favorites_service.dart';
import '../services/transit_history_service.dart';
import '../services/transit_grippewelle_service.dart';
import '../services/transit_offline_cache.dart';
import '../services/transit_ongoing_ride_service.dart';
import '../services/transit_pattern_service.dart';
import '../services/transit_translations.dart';
import '../services/weather_service.dart';

/// ÖPNV dialog — two tabs:
///   1. Echtzeit — live departures grouped by nearest stops (GPS auto-refresh 60s)
///   2. Verbindung suchen — city→city journey planner
class OpnvDialog extends StatefulWidget {
  final TransitService transitService;
  final List<Departure> initialDepartures;
  final String city;
  /// Deep-link params — prefill "Verbindung suchen" tab and auto-jump to it.
  /// Used by termin card to launch the dialog with Verein → Behörde pre-filled.
  final TransitLocation? initialFrom;
  final TransitLocation? initialTo;
  final DateTime? initialArrivalTime;
  /// Own Mitgliedernummer — used as sender when Route-an-Mitglied posts to chat.
  final String? currentMitgliedernummer;
  /// Active member roster — used by the "Route senden" picker.
  final List<User>? users;
  /// Logged-in user's Muttersprache from Verifizierung Stufe 1. When set to
  /// a non-German language, the TripMap TTS speaks announcements in BOTH
  /// German and this language after a short delay ("Nächste Haltestelle: X"
  /// then "Următoarea stație: X").
  final String? userMuttersprache;

  const OpnvDialog({
    super.key,
    required this.transitService,
    required this.initialDepartures,
    required this.city,
    this.initialFrom,
    this.initialTo,
    this.initialArrivalTime,
    this.currentMitgliedernummer,
    this.users,
    this.userMuttersprache,
  });

  @override
  State<OpnvDialog> createState() => _OpnvDialogState();
}

class _OpnvDialogState extends State<OpnvDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Jump straight to "Verbindung suchen" tab when deep-linked with from/to.
    if (widget.initialFrom != null || widget.initialTo != null) {
      _tabController.index = 1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // On small screens (phone/tablet portrait), go near-fullscreen; on desktop, fixed size.
    final isCompact = size.width < 700;
    final dialogW = isCompact ? size.width - 16 : 560.0;
    final dialogH = isCompact ? size.height - 80 : 620.0;

    final p = _Palette.of(context);
    return Dialog(
      backgroundColor: p.bg,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 40,
        vertical: isCompact ? 40 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          children: [
            _Header(
              tabController: _tabController,
              onClose: () => Navigator.pop(context),
              onOpenHistory: () => showDialog(
                context: context,
                builder: (_) => const _HistoryDialog(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _EchtzeitTab(
                    transitService: widget.transitService,
                    initialDepartures: widget.initialDepartures,
                    city: widget.city,
                    userMuttersprache: widget.userMuttersprache,
                  ),
                  _VerbindungTab(
                    transitService: widget.transitService,
                    initialFrom: widget.initialFrom,
                    initialTo: widget.initialTo,
                    initialArrivalTime: widget.initialArrivalTime,
                    currentMitgliedernummer: widget.currentMitgliedernummer,
                    users: widget.users,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Palette — adaptive light/dark colors
// ══════════════════════════════════════════════════════════════
//
// The app forces Brightness.light globally, but this dialog opts out by
// reading the DEVICE brightness directly (MediaQuery.platformBrightnessOf).
// So a user with system dark mode on their Samsung tablet sees a dark
// ÖPNV dialog even though the rest of the app is light. Contrast ratios
// tuned to WCAG AA (≥4.5:1 for body text) for BFSG 2025 compliance.
class _Palette {
  final bool dark;
  const _Palette._(this.dark);
  factory _Palette.of(BuildContext ctx) =>
      _Palette._(MediaQuery.platformBrightnessOf(ctx) == Brightness.dark);

  Color get bg => dark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get surface => dark ? const Color(0xFF2A2A2A) : Colors.grey.shade50;
  Color get card => dark ? const Color(0xFF262626) : Colors.white;
  Color get border => dark ? const Color(0xFF3A3A3A) : Colors.grey.shade200;
  Color get divider => dark ? const Color(0xFF333333) : Colors.grey.shade100;
  Color get accentTint => dark ? const Color(0xFF0F3A3A) : Colors.teal.shade50;
  Color get onSurface => dark ? Colors.white70 : Colors.black87;
  Color get onSurfaceDim => dark ? Colors.white54 : Colors.grey.shade700;
  Color get onSurfaceFaint => dark ? Colors.white38 : Colors.grey.shade500;
  Color get iconMuted => dark ? Colors.white38 : Colors.grey.shade400;
}

// ══════════════════════════════════════════════════════════════
// Header — icon + title + close
// ══════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final TabController tabController;
  final VoidCallback onClose;
  final VoidCallback? onOpenHistory;

  const _Header({required this.tabController, required this.onClose, this.onOpenHistory});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      decoration: BoxDecoration(
        color: p.accentTint,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.directions_bus, color: Colors.teal.shade400, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ÖPNV',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800),
                ),
              ),
              if (onOpenHistory != null)
                IconButton(
                  icon: Icon(Icons.history, size: 20, color: p.onSurface),
                  tooltip: 'Historie deiner Fahrten',
                  onPressed: onOpenHistory,
                ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: p.onSurface),
                tooltip: 'Schließen',
                onPressed: onClose,
              ),
            ],
          ),
          TabBar(
            controller: tabController,
            labelColor: p.dark ? Colors.teal.shade100 : Colors.teal.shade800,
            unselectedLabelColor: p.onSurfaceDim,
            indicatorColor: Colors.teal.shade400,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.access_time_filled, size: 18), text: 'Echtzeit'),
              Tab(icon: Icon(Icons.route, size: 18), text: 'Verbindung suchen'),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Tab 1 — Echtzeit (grouped by nearest stops, GPS re-check 60s)
// ══════════════════════════════════════════════════════════════

/// Definește un sub-tab din Echtzeit filtrat per productType.
///
/// Câmpuri opționale pentru distincție Hbf vs Bhf:
/// - `hbfOnly = true` → stop-uri cu "Hbf"/"Hauptbahnhof" în nume
/// - `bhfOnly = true` → stop-uri cu "Bahnhof" (dar fără "Hbf"/"Hauptbahnhof")
/// - `useBahnDe = true` → forțează apel `fetchBhfNearby()` la deschiderea tab-ului
class _SubTabDef {
  final String label;
  final IconData icon;
  final Set<String>? types;
  final bool hbfOnly;
  final bool bhfOnly;
  final bool useBahnDe;
  const _SubTabDef({
    required this.label,
    required this.icon,
    required this.types,
    this.hbfOnly = false,
    this.bhfOnly = false,
    this.useBahnDe = false,
  });
}

class _EchtzeitTab extends StatefulWidget {
  final TransitService transitService;
  final List<Departure> initialDepartures;
  final String city;
  final String? userMuttersprache;

  const _EchtzeitTab({
    required this.transitService,
    required this.initialDepartures,
    required this.city,
    this.userMuttersprache,
  });

  @override
  State<_EchtzeitTab> createState() => _EchtzeitTabState();
}

class _EchtzeitTabState extends State<_EchtzeitTab>
    with SingleTickerProviderStateMixin {
  late List<Departure> _departures;
  bool _isLoading = false;
  Timer? _refreshTimer;
  DateTime _lastUpdate = DateTime.now();
  /// Non-null when the current UI is populated from the persisted offline
  /// snapshot rather than a live fetch. Shows a freshness banner.
  TransitOfflineSnapshot? _offline;

  /// Sub-tab controller: Bus / Tram / S-Bhf / U-Bhf / Bhf.
  /// Filtrează departures & stops per productType astfel încât userul
  /// vede rapid ce are lângă el fără să scaneze printre tipuri mixte.
  /// "Alle" eliminat 2026-07-11 (nu era relevant, user preferă tipuri).
  ///
  /// Sursă data per tab:
  /// - Bus / Tram / S-Bhf / U-Bhf → provider LOCAL activ (DING/MVV/HAFAS)
  /// - Hbf + Bhf → apel dedicat la bahn.de (v6.db.transport.rest/stops/nearby)
  ///   declanșat lazy când userul deschide tab-ul; distincție pe nume:
  ///   Hbf = doar Hauptbahnhof-uri (ICE/IC), Bhf = restul gărilor (RB/RE)
  late TabController _subTabController;
  bool _bhfLoading = false;
  static const _subTabs = <_SubTabDef>[
    _SubTabDef(label: 'Bus', icon: Icons.directions_bus, types: {'bus'}),
    _SubTabDef(label: 'Tram', icon: Icons.tram, types: {'tram'}),
    _SubTabDef(label: 'S-Bhf', icon: Icons.train_outlined, types: {'suburban'}),
    _SubTabDef(label: 'U-Bhf', icon: Icons.subway, types: {'subway'}),
    // Hauptbahnhof — doar Hbf-named (Ulm Hbf, München Hbf) — ICE/IC hub
    _SubTabDef(
      label: 'Hbf', icon: Icons.train,
      types: {'train', 'regional'},
      hbfOnly: true, useBahnDe: true,
    ),
    // Bahnhof local — Neu-Ulm Bahnhof, Senden Bahnhof — RB/RE only
    _SubTabDef(
      label: 'Bhf', icon: Icons.directions_railway,
      types: {'train', 'regional'},
      bhfOnly: true, useBahnDe: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _departures = List.from(widget.initialDepartures);
    _subTabController = TabController(length: _subTabs.length, vsync: this);
    _subTabController.addListener(_onSubTabChanged);
    // Auto-refresh every 60s — also re-checks GPS via service.refresh()
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    if (_departures.isEmpty) _refresh();
  }

  void _onSubTabChanged() {
    if (!mounted || _subTabController.indexIsChanging) return;
    setState(() {});
    // Lazy fetch bahn.de rail data DOAR când userul deschide tab Hbf sau Bhf.
    // Cache 60s intern serviciu → switching între Hbf/Bhf = no-op instant.
    final tab = _subTabs[_subTabController.index];
    if (tab.useBahnDe) _ensureBhfData();
  }

  Future<void> _ensureBhfData() async {
    if (!mounted) return;
    setState(() => _bhfLoading = true);
    try {
      await widget.transitService.fetchBhfNearby();
      if (!mounted) return;
      setState(() {
        _departures = List.from(widget.transitService.departures);
        _bhfLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _bhfLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _subTabController.removeListener(_onSubTabChanged);
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await widget.transitService.refresh();
    if (!mounted) return;
    var live = List<Departure>.from(widget.transitService.departures);
    TransitOfflineSnapshot? offlineSnap;
    // If refresh returned nothing (network down / provider unreachable),
    // fall back to the last persisted snapshot so the tab isn't empty.
    if (live.isEmpty && widget.transitService.nearbyStops.isEmpty) {
      offlineSnap = await widget.transitService.loadOfflineSnapshotIfEmpty();
      if (offlineSnap != null) live = List.from(widget.transitService.departures);
    }
    // Dacă suntem pe tab Hbf/Bhf → refresh și bahn.de data (force = refresh
    // explicit al user-ului, nu contează cache-ul).
    if (_subTabs[_subTabController.index].useBahnDe) {
      await widget.transitService.fetchBhfNearby(force: true);
      if (mounted) live = List.from(widget.transitService.departures);
    }
    if (!mounted) return;
    setState(() {
      _departures = live;
      _offline = offlineSnap;
      _lastUpdate = DateTime.now();
      _isLoading = false;
    });
  }

  /// Force a fresh raw GNSS chip fix — used from the "GPS erneuern" button
  /// when accuracy is >100m. Blocks up to 30s while the satellite radio locks.
  Future<void> _forceGnss() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await widget.transitService.forceGnssRefresh();
    if (!mounted) return;
    setState(() {
      _departures = List.from(widget.transitService.departures);
      _lastUpdate = DateTime.now();
      _isLoading = false;
    });
  }

  /// Group departures by stop name, keeping stop order by distance.
  /// Optional productType filter — pentru sub-tab-uri specializate.
  Map<String, List<Departure>> _byStop({Set<String>? productTypes}) {
    final grouped = <String, List<Departure>>{};
    final now = DateTime.now();
    for (final d in _departures) {
      if (d.stopName.isEmpty) continue;
      if (productTypes != null && !productTypes.contains(d.productType)) continue;
      if (d.minutesUntil < 0 ||
          (d.realtimeTime ?? d.plannedTime).isBefore(now.subtract(const Duration(minutes: 1)))) continue;
      grouped.putIfAbsent(d.stopName, () => []).add(d);
    }
    return grouped;
  }

  /// Returnează top 3 stații care au departures pentru tab-ul activ.
  /// Sortare după distanță crescătoare din TransitService.nearbyStops.
  /// Detectează dacă numele stației e Hauptbahnhof (Hbf).
  /// Match strict: token-boundary pe "Hbf" sau conține "Hauptbahnhof".
  static bool _isHbfName(String name) {
    final n = name.toLowerCase();
    if (n.contains('hauptbahnhof')) return true;
    // "Hbf" ca cuvânt separat: început/spațiu înainte + sfârșit/spațiu după
    final idx = n.indexOf('hbf');
    if (idx < 0) return false;
    final startOk = idx == 0 || !RegExp(r'[a-zäöüß]').hasMatch(n[idx - 1]);
    final endIdx = idx + 3;
    final endOk = endIdx >= n.length || !RegExp(r'[a-zäöüß]').hasMatch(n[endIdx]);
    return startOk && endOk;
  }

  /// Detectează dacă numele stației e Bahnhof (non-Hbf).
  /// Include "X Bahnhof", "Bahnhof X" — dar exclude Hbf/Hauptbahnhof.
  static bool _isBhfLocalName(String name) {
    if (_isHbfName(name)) return false; // Hbf are prioritate
    final n = name.toLowerCase();
    // Exclude străzi/piețe/adrese numerotate
    if (n.contains('bahnhofstr') || n.contains('bahnhofspl') ||
        n.contains('bahnhofsvor') || n.contains('bahnhofsvi')) return false;
    if (RegExp(r'bahnhof\s+\d').hasMatch(n)) return false;
    // Match "X Bahnhof" (final) sau "Bahnhof X" (început)
    return RegExp(r'(^|\s)bahnhof($|\s)').hasMatch(n);
  }

  List<TransitStop> _stopsForTab(_SubTabDef tab) {
    final allStops = widget.transitService.nearbyStops;
    final grouped = _byStop(productTypes: tab.types);
    Iterable<TransitStop> filtered = allStops.where(
      (s) => grouped.containsKey(s.name),
    );
    if (tab.hbfOnly) {
      filtered = filtered.where((s) => _isHbfName(s.name));
    } else if (tab.bhfOnly) {
      filtered = filtered.where((s) => _isBhfLocalName(s.name));
    }
    return filtered.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _subTabs[_subTabController.index];
    final grouped = _byStop(productTypes: currentTab.types);
    final stops = _stopsForTab(currentTab);
    final locLabel = widget.transitService.gpsCity ?? widget.city;
    final provider = widget.transitService.activeProvider;

    final accuracy = widget.transitService.lastAccuracy;
    final source = widget.transitService.lastSource;
    // Accuracy tiers (verified live vs. DING EFA):
    //   < 25m   → excellent — clear-sky GNSS lock, warm start
    //   < 50m   → very good — typical GNSS in open area
    //   < 100m  → good — urban / near buildings
    //   < 300m  → acceptable — still finds correct stops (EFA verified)
    //   ≥ 300m  → refused (shows _CoarseState with GPS refresh button)
    final isPrecise = accuracy != null && accuracy < 300;
    final accColor = accuracy == null
        ? Colors.grey
        : accuracy < 25
            ? Colors.green.shade700
            : accuracy < 50
                ? Colors.green.shade500
                : accuracy < 100
                    ? Colors.lime.shade700
                    : accuracy < 300
                        ? Colors.lime.shade800
                        : accuracy < 1000
                            ? Colors.orange.shade700
                            : Colors.red.shade600;
    final accLabel = accuracy == null
        ? '—'
        : accuracy < 25
            ? '±${accuracy.toStringAsFixed(0)}m ✓✓'
            : accuracy < 50
                ? '±${accuracy.toStringAsFixed(0)}m ✓'
                : accuracy < 100
                    ? '±${accuracy.toStringAsFixed(0)}m'
                    : accuracy < 300
                        ? '±${accuracy.toStringAsFixed(0)}m'
                        : accuracy < 1000
                            ? '±${accuracy.toStringAsFixed(0)}m ⚠'
                            : '±${(accuracy / 1000).toStringAsFixed(1)}km ⚠';
    final accQuality = accuracy == null
        ? ''
        : accuracy < 25
            ? 'Perfekt'
            : accuracy < 50
                ? 'Sehr gut'
                : accuracy < 100
                    ? 'Gut'
                    : accuracy < 300
                        ? 'Akzeptabel'
                        : '';
    final sourceLabel = switch (source) {
      LocationSource.gnss => 'GPS-Chip',
      LocationSource.fusedLocation => 'GPS+WiFi',
      LocationSource.cached => 'Cache',
      LocationSource.ipFallback => 'nur IP',
      LocationSource.cityGeocode => 'Stadt',
      LocationSource.none => '',
    };

    final p = _Palette.of(context);
    return Column(
      children: [
        // Ride-in-progress banner — supraviețuiește închiderii trip-map.
        // Se auto-hides când service.isRunning devine false.
        const _OngoingRideBanner(),
        // Grippewelle info — apare doar când RKI raportează activitate ridicată.
        const _GrippewelleBanner(),
        if (_offline != null) _OfflineBanner(snap: _offline!, onRetry: _refresh),
        // Location bar with accuracy indicator
        Semantics(
          label: 'Aktueller Standort: ${locLabel.isNotEmpty ? locLabel : 'wird ermittelt'}. '
              'GPS-Genauigkeit: $accLabel${accQuality.isNotEmpty ? ", $accQuality" : ""}.',
          container: true,
          child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
          color: p.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: accColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      locLabel.isNotEmpty ? locLabel : 'Standort wird ermittelt…',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (provider != null)
                    Text(provider.name, style: TextStyle(fontSize: 10, color: p.onSurfaceDim)),
                  const SizedBox(width: 6),
                  if (_isLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.refresh, size: 18, color: p.onSurface),
                      tooltip: 'Aktualisieren',
                      onPressed: _refresh,
                    ),
                ],
              ),
              // Accuracy row
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: accColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        accLabel,
                        style: TextStyle(fontSize: 10, color: accColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (accQuality.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(accQuality, style: TextStyle(fontSize: 10, color: accColor, fontWeight: FontWeight.w600)),
                    ],
                    if (sourceLabel.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('• $sourceLabel', style: TextStyle(fontSize: 10, color: p.onSurfaceDim)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        )),
        // Störungen-Banner: shows a compact strip if any HIM messages are
        // currently active. Tap to open full list dialog.
        _DisruptionsBanner(),
        // Sub-tab bar: Alle / Bus / Tram / S-Bhf / U-Bhf / Bhf.
        // Colorat pe tip, colorat activ pentru scanare rapidă.
        _SubTabBar(
          controller: _subTabController,
          tabs: _subTabs,
        ),
        // Body — if accuracy is too coarse, refuse to show stops
        Expanded(
          child: !isPrecise
              ? _CoarseState(
                  loading: _isLoading,
                  accuracy: accuracy,
                  source: source,
                  onForceGnss: _forceGnss,
                )
              : stops.isEmpty && grouped.isEmpty
                  ? _SubTabEmpty(
                      tab: currentTab,
                      loading: _isLoading || (currentTab.useBahnDe && _bhfLoading),
                      onShowAll: () => _subTabController.animateTo(0),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final stop in stops)
                          _StopSection(
                            stop: stop,
                            departures: grouped[stop.name] ?? [],
                            transitService: widget.transitService,
                            userMuttersprache: widget.userMuttersprache,
                          ),
                      ],
                    ),
        ),
        _Footer(providerName: provider?.displayName ?? 'ÖPNV', lastUpdate: _lastUpdate),
      ],
    );
  }
}

/// Banner cu warning Grippewelle — arată doar când RKI raportează
/// activitate ridicată (high / very-high). Nudge soft pentru mască în ÖPNV.
class _GrippewelleBanner extends StatefulWidget {
  const _GrippewelleBanner();

  @override
  State<_GrippewelleBanner> createState() => _GrippewelleBannerState();
}

class _GrippewelleBannerState extends State<_GrippewelleBanner> {
  final _svc = TransitGrippewelleService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    // Fire refresh la deschidere — respect cache 24h intern.
    _svc.refreshIfStale();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_svc.shouldWarn) return const SizedBox.shrink();
    final p = _Palette.of(context);
    final isVeryHigh = _svc.level == GrippewelleLevel.veryHigh;
    final color = isVeryHigh ? Colors.red.shade400 : Colors.orange.shade600;
    final kwLabel = _svc.kalenderwoche != null ? ' (KW ${_svc.kalenderwoche})' : '';
    return Semantics(
      label: '${_svc.germanLabel}$kwLabel. In öffentlichen Verkehrsmitteln '
          'FFP2-Maske empfohlen. Quelle RKI.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: p.dark ? 0.20 : 0.10),
          border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            const Text('🤧', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_svc.germanLabel}$kwLabel',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: color,
                    ),
                  ),
                  Text(
                    isVeryHigh
                        ? 'FFP2 im ÖPNV dringend empfohlen'
                        : 'Maske im ÖPNV empfohlen · Quelle RKI',
                    style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner care apare peste Echtzeit tab când există un ride activ
/// (Ausstieg-Alarm activ în background). Un tap deschide dialogul cu
/// trip-map-ul reluat. "Beenden" oprește ride-ul + notificarea persistentă.
class _OngoingRideBanner extends StatefulWidget {
  const _OngoingRideBanner();

  @override
  State<_OngoingRideBanner> createState() => _OngoingRideBannerState();
}

class _OngoingRideBannerState extends State<_OngoingRideBanner> {
  final _ride = TransitOngoingRideService();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-check every 15s ca să reflectăm eventuale stop-uri.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ride.isRunning) return const SizedBox.shrink();
    final t = _ride.target;
    final d = _ride.departure;
    if (t == null || d == null) return const SizedBox.shrink();
    final p = _Palette.of(context);
    return Semantics(
      label: 'Aktive Fahrt: Linie ${d.line} nach ${t.name}. Ausstieg-Alarm läuft im Hintergrund.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: p.dark ? 0.22 : 0.14),
          border: Border(bottom: BorderSide(color: Colors.orange.shade400)),
        ),
        child: Row(
          children: [
            Icon(Icons.directions_bus_filled, size: 16, color: Colors.orange.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Aktive Fahrt: Linie ${d.line} → ${t.name}',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Semantics(
              button: true,
              label: 'Ausstieg-Alarm beenden',
              child: InkWell(
                onTap: () async {
                  await _ride.stopRide();
                  if (mounted) setState(() {});
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.stop_circle, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 3),
                    Text('Beenden',
                        style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sub-tab bar din Echtzeit — Alle / Bus / Tram / S-Bhf / U-Bhf / Bhf.
/// Culoare-activ per tab pentru memoria musculară a userului.
class _SubTabBar extends StatelessWidget {
  final TabController controller;
  final List<_SubTabDef> tabs;
  const _SubTabBar({required this.controller, required this.tabs});

  Color _accentFor(_SubTabDef t) {
    if (t.types == null) return Colors.teal.shade600;
    if (t.types!.contains('bus')) return Colors.teal.shade700;
    if (t.types!.contains('tram')) return Colors.blue.shade700;
    if (t.types!.contains('suburban')) return Colors.green.shade700;
    if (t.types!.contains('subway')) return Colors.indigo.shade700;
    // Hbf vs Bhf: Hbf (Hauptbahnhof) = roșu vibrant, Bhf (local) = roșu mai
    // moderat pentru distincție vizuală.
    if (t.hbfOnly) return Colors.red.shade800;
    if (t.bhfOnly) return Colors.deepOrange.shade700;
    if (t.types!.contains('train') || t.types!.contains('regional')) return Colors.red.shade700;
    return Colors.grey.shade700;
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final currentAccent = _accentFor(tabs[controller.index]);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.divider)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: currentAccent,
        unselectedLabelColor: p.onSurfaceDim,
        indicatorColor: currentAccent,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        tabs: [
          for (final t in tabs)
            Tab(
              height: 36,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(t.icon, size: 14),
                const SizedBox(width: 4),
                Text(t.label),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Empty-state pentru sub-tab (nu găsim stații de tipul cerut).
/// User in mediu rural sau la marginea acoperirii → sugerăm "Alle".
class _SubTabEmpty extends StatelessWidget {
  final _SubTabDef tab;
  final bool loading;
  final VoidCallback onShowAll;
  const _SubTabEmpty({required this.tab, required this.loading, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final typeLabel = switch (tab.label) {
      'Bus' => 'Bushaltestelle',
      'Tram' => 'Straßenbahn-Haltestelle',
      'S-Bhf' => 'S-Bahnhof',
      'U-Bhf' => 'U-Bahnhof',
      'Hbf' => 'Hauptbahnhof',
      'Bhf' => 'Bahnhof',
      _ => 'Haltestelle',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 44, color: p.iconMuted),
            const SizedBox(height: 12),
            Text(
              'Keine $typeLabel in der Nähe',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Innerhalb 30 km wurde nichts gefunden.\n'
              'Aktueller Standort ist möglicherweise rural.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: p.onSurfaceDim),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onShowAll,
              icon: const Icon(Icons.public, size: 14),
              label: const Text('Zurück zu "Alle"', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal that lists the last 20 trips the user opened (planned, boarded,
/// arrived, missed) with an icon per status. Data source is
/// TransitHistoryService (SharedPreferences-backed, 20 entry cap).
class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog();

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<TransitHistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await TransitHistoryService.load();
    if (!mounted) return;
    setState(() => _entries = list);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Historie leeren?'),
        content: const Text('Alle 20 letzten Fahrten werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok != true) return;
    await TransitHistoryService.clear();
    await _load();
  }

  IconData _iconFor(TransitTripStatus s) {
    switch (s) {
      case TransitTripStatus.arrived:   return Icons.check_circle;
      case TransitTripStatus.boarded:   return Icons.directions_bus;
      case TransitTripStatus.missed:    return Icons.cancel;
      case TransitTripStatus.cancelled: return Icons.remove_circle_outline;
    }
  }
  Color _colorFor(TransitTripStatus s) {
    switch (s) {
      case TransitTripStatus.arrived:   return Colors.green.shade500;
      case TransitTripStatus.boarded:   return Colors.teal.shade400;
      case TransitTripStatus.missed:    return Colors.red.shade400;
      case TransitTripStatus.cancelled: return Colors.grey.shade400;
    }
  }
  String _labelFor(TransitTripStatus s) {
    switch (s) {
      case TransitTripStatus.arrived:   return 'Angekommen';
      case TransitTripStatus.boarded:   return 'Eingestiegen';
      case TransitTripStatus.missed:    return 'Verpasst';
      case TransitTripStatus.cancelled: return 'Abgebrochen';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final list = _entries;
    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 460, height: 560,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, size: 20, color: Colors.teal.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fahrten-Historie${list != null ? " (${list.length})" : ""}',
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800,
                      ),
                    ),
                  ),
                  if (list != null && list.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: p.onSurface),
                      tooltip: 'Alle löschen',
                      onPressed: _confirmClear,
                    ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: p.onSurface),
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_toggle_off, size: 40, color: p.iconMuted),
                              const SizedBox(height: 8),
                              Text(
                                'Noch keine Fahrten aufgezeichnet.\n'
                                'Öffne eine Abfahrt aus Echtzeit und wähle ein Ausstiegs-Ziel.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: p.onSurfaceFaint, fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                          itemBuilder: (_, i) {
                            final e = list[i];
                            final dep = e.plannedDep;
                            final dayLabel = _dayLabel(dep);
                            final hhmm = '${dep.hour.toString().padLeft(2, "0")}:${dep.minute.toString().padLeft(2, "0")}';
                            return Semantics(
                              label: '${_labelFor(e.status)}: Linie ${e.line} nach ${e.direction}, '
                                  '$dayLabel um $hhmm${e.toStop != null ? ", Ausstieg ${e.toStop}" : ""}',
                              container: true,
                              excludeSemantics: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Row(children: [
                                  Icon(_iconFor(e.status), size: 20, color: _colorFor(e.status)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: _colorFor(e.status).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(e.line, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _colorFor(e.status))),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '→ ${e.direction}',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.onSurface),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ]),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$dayLabel · $hhmm'
                                              '${e.fromStop != null ? " · von ${e.fromStop}" : ""}'
                                              '${e.toStop != null ? " · Ziel ${e.toStop}" : ""}',
                                          style: TextStyle(fontSize: 10.5, color: p.onSurfaceDim),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _labelFor(e.status),
                                    style: TextStyle(fontSize: 10, color: _colorFor(e.status), fontWeight: FontWeight.w600),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Relative day label: "heute", "gestern", "vor 3 Tagen", or DD.MM.
  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'heute';
    if (diff == 1) return 'gestern';
    if (diff < 7) return 'vor $diff Tagen';
    return '${t.day.toString().padLeft(2, "0")}.${t.month.toString().padLeft(2, "0")}.';
  }
}

/// Banner shown when the Echtzeit tab is populated from the persisted
/// SharedPreferences snapshot rather than a live fetch. Includes the
/// snapshot's captured-at time so the user can gauge how stale the data is.
class _OfflineBanner extends StatelessWidget {
  final TransitOfflineSnapshot snap;
  final VoidCallback onRetry;
  const _OfflineBanner({required this.snap, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final t = snap.capturedAt;
    final hhmm = '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
    final minutesAgo = snap.age.inMinutes;
    final ageLabel = minutesAgo < 60
        ? 'vor $minutesAgo Min'
        : 'vor ${(minutesAgo / 60).floor()}h ${minutesAgo % 60}m';
    // Color grades with age: <15m green-ish, up to 4h orange, older red.
    final Color bg;
    final Color fg;
    if (snap.isFresh) {
      bg = Colors.orange.shade100.withValues(alpha: p.dark ? 0.25 : 1.0);
      fg = Colors.orange.shade700;
    } else if (snap.isStale) {
      bg = Colors.red.shade100.withValues(alpha: p.dark ? 0.25 : 1.0);
      fg = Colors.red.shade600;
    } else {
      bg = Colors.orange.shade50.withValues(alpha: p.dark ? 0.25 : 1.0);
      fg = Colors.orange.shade600;
    }
    return Semantics(
      label: 'Offline-Modus, Daten von $hhmm, $ageLabel. Antippen um erneut zu versuchen.',
      child: InkWell(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: bg,
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: 14, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ohne Internet — Daten von $hhmm ($ageLabel)',
                  style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.refresh, size: 14, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when GPS accuracy is worse than 100m. Bus stops within 30-100m
/// walking range can't be identified from an IP or cell-tower fix, so we
/// refuse to display them and offer a "GPS erneuern" action instead.
class _CoarseState extends StatelessWidget {
  final bool loading;
  final double? accuracy;
  final LocationSource source;
  final VoidCallback onForceGnss;

  const _CoarseState({
    required this.loading,
    required this.accuracy,
    required this.source,
    required this.onForceGnss,
  });

  String get _diagnosis {
    if (source == LocationSource.ipFallback) {
      return 'Nur IP-Standort — GPS deaktiviert oder nicht verfügbar.\n'
             'App-Berechtigung: Standort → "Genau" erforderlich.';
    }
    if (source == LocationSource.cached) {
      return 'Alte gespeicherte Position. GPS-Chip antwortet noch nicht.';
    }
    if (accuracy != null && accuracy! >= 500) {
      return 'Nur Funkzellen-Standort (${accuracy!.toStringAsFixed(0)}m).\n'
             'GPS liefert kein Signal — draußen mit Blick auf den Himmel versuchen.';
    }
    return 'Standort noch zu ungenau (${accuracy?.toStringAsFixed(0) ?? "?"}m).\n'
           'Bushaltestellen liegen in 30–100m Umkreis — feinere Position nötig.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off, size: 56, color: Colors.orange.shade400),
            const SizedBox(height: 14),
            const Text(
              'Standort nicht präzise genug',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _diagnosis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              icon: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.gps_fixed, size: 18),
              label: Text(loading ? 'Suche GPS-Signal…' : 'GPS erneuern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: loading ? null : onForceGnss,
            ),
            const SizedBox(height: 8),
            Text(
              'Kann bis zu 30 Sekunden dauern beim ersten Fix',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool loading;
  final String? error;
  const _EmptyState({required this.loading, this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(loading ? Icons.schedule : Icons.location_off, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            loading
                ? 'Abfahrten werden geladen…'
                : (error ?? 'Keine Haltestellen in der Nähe gefunden'),
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StopSection extends StatelessWidget {
  final TransitStop stop;
  final List<Departure> departures;
  final TransitService transitService;
  final String? userMuttersprache;
  const _StopSection({
    required this.stop,
    required this.departures,
    required this.transitService,
    this.userMuttersprache,
  });

  String get _distStr {
    if (stop.distance >= 1000) return '${(stop.distance / 1000).toStringAsFixed(1)} km';
    return '${stop.distance} m';
  }

  /// True if this stop is a mainline station or has rail departures.
  /// Only mainline stations have DB Aufzüge data.
  ///
  /// Strict token match — "Klinikum am Bahnhof" / "Bahnhofstraße" are bus
  /// stops, not railway stations, so they don't get an Aufzüge button.
  static final RegExp _stationRe = RegExp(
    r'(^|\s)(hbf|hauptbahnhof)(\s|$)|^bahnhof\s+\S',
    caseSensitive: false,
  );
  bool get _isRailwayStation {
    final n = stop.name.toLowerCase();
    if (!n.contains('bahnhofstr') && !n.contains('bahnhofspl') && _stationRe.hasMatch(n)) {
      return true;
    }
    return departures.any((d) =>
        d.productType == 'train' ||
        d.productType == 'regional' ||
        d.productType == 'suburban' ||
        d.productType == 'subway');
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Semantics(
      label: 'Haltestelle ${stop.name}, ${stop.distance} Meter entfernt. ${departures.length} Abfahrten.',
      container: true,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: p.accentTint,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_bus, size: 16, color: Colors.teal.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stop.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(_distStr, style: TextStyle(fontSize: 11, color: p.onSurfaceDim)),
                if (_isRailwayStation) ...[
                  const SizedBox(width: 6),
                  Semantics(
                    button: true,
                    label: 'Aufzugsstatus anzeigen für ${stop.name}',
                    child: InkWell(
                      onTap: () => _openFacilitiesDialog(context),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🛗', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 3),
                            Text('Aufzüge', style: TextStyle(fontSize: 10, color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (departures.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Keine Abfahrten in Kürze', style: TextStyle(fontSize: 12, color: p.onSurfaceFaint)),
            )
          else
            ...departures.take(6).map((d) => _DepartureRow(
                dep: d, transitService: transitService,
                userMuttersprache: userMuttersprache,
            )),
        ],
      ),
    ));
  }

  void _openFacilitiesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _FacilitiesDialog(stationName: stop.name, transitService: transitService),
    );
  }
}

/// Modal that fetches + displays elevator/escalator status for one station.
class _FacilitiesDialog extends StatefulWidget {
  final String stationName;
  final TransitService transitService;
  const _FacilitiesDialog({required this.stationName, required this.transitService});

  @override
  State<_FacilitiesDialog> createState() => _FacilitiesDialogState();
}

class _FacilitiesDialogState extends State<_FacilitiesDialog> {
  List<StationFacility>? _facilities;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final f = await widget.transitService.fetchFacilities(widget.stationName);
    if (!mounted) return;
    setState(() {
      _facilities = f;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _facilities ?? [];
    final working = f.where((x) => x.isWorking).length;
    final broken = f.where((x) => x.isBroken).length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text('🛗', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aufzüge & Fahrtreppen',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                        ),
                        Text(
                          widget.stationName,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            // Summary
            if (!_loading && f.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade50,
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text('$working in Betrieb', style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 14),
                    if (broken > 0) ...[
                      Icon(Icons.cancel, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 4),
                      Text('$broken außer Betrieb', style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            // Body
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : f.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  'Keine Aufzugsdaten verfügbar.\nMöglicherweise keine DB-Bahnhof.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: f.length,
                          itemBuilder: (_, i) => _FacilityRow(facility: f[i]),
                        ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Text(
                'Daten: DB FaSta (via transport.rest)',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityRow extends StatelessWidget {
  final StationFacility facility;
  const _FacilityRow({required this.facility});

  @override
  Widget build(BuildContext context) {
    final color = facility.isWorking
        ? Colors.green.shade600
        : facility.isBroken
            ? Colors.red.shade600
            : Colors.orange.shade600;
    final label = facility.isWorking
        ? 'In Betrieb'
        : facility.isBroken
            ? 'Außer Betrieb'
            : 'Status unbekannt';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(facility.icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        facility.description,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                Text(
                  label + (facility.reason != null ? ' — ${facility.reason}' : ''),
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  final Departure dep;
  final TransitService transitService;
  final String? userMuttersprache;
  const _DepartureRow({
    required this.dep,
    required this.transitService,
    this.userMuttersprache,
  });

  Color _lineColor() {
    switch (dep.productType) {
      case 'tram': return Colors.blue.shade700;
      case 'subway': return Colors.indigo.shade700;
      case 'train':
      case 'regional': return Colors.red.shade700;
      case 'suburban': return Colors.green.shade700;
      default: return Colors.teal.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final mins = dep.minutesUntil;
    final isCancelled = dep.isCancelled;
    final isImminent = !isCancelled && mins <= 2;
    final isSoon = !isCancelled && mins <= 5;
    final isLive = dep.realtimeTime != null;

    // Trip sequence needs either:
    //   - stopID+destID (EFA XSLT_TRIP_REQUEST2), OR
    //   - tripID / jid (HAFAS JourneyDetails, most reliable).
    // Cancelled services skip both — the vehicle isn't running.
    final canOpenSequence = !isCancelled &&
        ((dep.stopID != null && dep.destID != null) ||
         (dep.tripID != null && dep.tripID!.isNotEmpty));
    final productLabel = switch (dep.productType) {
      'tram' => 'Straßenbahn',
      'subway' => 'U-Bahn',
      'suburban' => 'S-Bahn',
      'train' || 'regional' => 'Zug',
      'bus' => 'Bus',
      _ => 'Fahrzeug',
    };
    final delayLabel = dep.delay > 0 ? ', ${dep.delay} Minuten Verspätung' : '';
    final liveLabel = isCancelled ? 'Ausgefallen' : (isLive ? 'Live-Daten' : 'Fahrplan');
    final minsLabel = mins == 0 ? 'jetzt' : 'in $mins Minuten';
    final sem = '$productLabel Linie ${dep.line} nach ${dep.direction}, '
        'Abfahrt $minsLabel um ${dep.timeString}$delayLabel. $liveLabel.'
        '${dep.platform != null ? " Gleis ${dep.platform}." : ""}';

    Color? bg;
    if (isCancelled) bg = p.dark ? const Color(0xFF3D2A2A) : Colors.red.shade100.withValues(alpha: 0.4);
    else if (isImminent) bg = p.dark ? const Color(0xFF3D1F1F) : Colors.red.shade50;
    else if (isSoon) bg = p.dark ? const Color(0xFF3D2F1A) : Colors.orange.shade50;

    return Semantics(
      label: sem,
      button: canOpenSequence,
      hint: canOpenSequence ? 'Antippen für Haltestellenreihenfolge' : null,
      excludeSemantics: true,
      child: InkWell(
      onTap: canOpenSequence
          ? () => showDialog(
                context: context,
                builder: (_) => _TripSequenceDialog(
                  dep: dep,
                  transitService: transitService,
                  userMuttersprache: userMuttersprache,
                ),
              )
          : null,
      child: Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.divider)),
        color: bg,
      ),
      child: Row(
        children: [
          // Line badge
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: _lineColor(), borderRadius: BorderRadius.circular(4)),
            child: Text(
              dep.line,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Direction
          Expanded(
            child: Text(
              dep.direction,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Delay
          if (dep.delay > 0) ...[
            InkWell(
              onTap: dep.delay > 15
                  ? () {
                      // Look up any HIM disruption mentioning this line;
                      // afișează dialog cu explicație.
                      final hits = TransitDisruptionsService().disruptionsMentioning(dep.line);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Row(children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
                            const SizedBox(width: 8),
                            Text('Ungewöhnliche Verspätung: +${dep.delay} Min.'),
                          ]),
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Linie ${dep.line} nach ${dep.direction}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (hits.isEmpty)
                                const Text('Keine passende Störungsmeldung gefunden.\n'
                                    'Mögliche Ursachen: Bauarbeiten, Wetter, Signalstörung.')
                              else
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${hits.length} aktive Störungsmeldung${hits.length == 1 ? "" : "en"}:',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  ...hits.take(3).map((h) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('• ${h.headline}',
                                        style: const TextStyle(fontSize: 12)),
                                  )),
                                ]),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Schließen'),
                            ),
                          ],
                        ),
                      );
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: dep.delay >= 5 ? Colors.red.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    '+${dep.delay}',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold,
                      color: dep.delay >= 5 ? Colors.red.shade800 : Colors.orange.shade800,
                    ),
                  ),
                  // "?" badge când Verspätung e anormal de mare (>15min) —
                  // tap deschide dialog explicativ.
                  if (dep.delay > 15) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.help_outline, size: 10, color: Colors.red.shade800),
                  ],
                ]),
              ),
            ),
            const SizedBox(width: 6),
          ],
          // Platform — badge dedicat, culoare after tip peron.
          // "Gl 3a/b" (S-Bahn) e ambiguu → warning portocaliu.
          // "Gl 5" (simplu) = verde.
          if (dep.platform != null) ...[
            _PlatformBadge(platform: dep.platform!, productType: dep.productType),
            const SizedBox(width: 6),
          ],
          // Live/Plan/Cancelled indicator — Cancelled trumps everything.
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isCancelled
                  ? Colors.red.shade500
                  : (isLive ? Colors.green.shade500 : p.iconMuted),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isCancelled ? 'Ausf.' : (isLive ? 'Live' : 'Plan'),
            style: TextStyle(
              fontSize: 9,
              color: isCancelled
                  ? Colors.red.shade500
                  : (isLive ? Colors.green.shade500 : p.onSurfaceFaint),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          // Time — strikethrough on cancellation or delay
          Text(
            dep.timeString,
            style: TextStyle(
              fontSize: 12, color: p.onSurfaceDim,
              decoration: (isCancelled || dep.delay > 0) ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(width: 8),
          // Minutes
          SizedBox(
            width: 42,
            child: Text(
              isCancelled ? '—' : (mins == 0 ? 'jetzt' : '$mins′'),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold,
                color: isCancelled
                    ? Colors.red.shade500
                    : (isImminent ? Colors.red.shade400 : (isSoon ? Colors.orange.shade400 : Colors.teal.shade400)),
                decoration: isCancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}

/// Compact platform indicator. La stații mari (Hbf) platforma 3a/b poate
/// direcționa userul spre direcție opusă → semnalizează cu portocaliu.
class _PlatformBadge extends StatelessWidget {
  final String platform;
  final String productType;
  const _PlatformBadge({required this.platform, required this.productType});

  bool get _isSplitPlatform {
    // "3a" / "3b" — jumătatea sudică vs nordică. Ambiguu pentru user.
    final t = platform.trim().toLowerCase();
    return t.endsWith('a') || t.endsWith('b') || t.endsWith('c') || t.endsWith('d');
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final isTrainLike = productType == 'train' ||
        productType == 'regional' ||
        productType == 'suburban' ||
        productType == 'subway';
    final color = _isSplitPlatform
        ? Colors.orange.shade600
        : (isTrainLike ? Colors.blueGrey.shade500 : p.onSurfaceFaint);
    return Tooltip(
      message: _isSplitPlatform
          ? 'Bahnsteig-Abschnitt $platform — vor Einfahrt Beschilderung prüfen'
          : 'Gleis/Steig $platform',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color, width: 0.6),
        ),
        child: Text(
          isTrainLike ? 'Gl $platform' : 'St $platform',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }
}

/// Modal that shows every stop this bus/tram/train visits on its way to its
/// terminus. The user's boarding stop is highlighted so they can see how far
/// along the route they are getting on. Cached 60s in the transit service.
class _TripSequenceDialog extends StatefulWidget {
  final Departure dep;
  final TransitService transitService;
  final String? userMuttersprache;
  const _TripSequenceDialog({
    required this.dep,
    required this.transitService,
    this.userMuttersprache,
  });

  @override
  State<_TripSequenceDialog> createState() => _TripSequenceDialogState();
}

class _TripSequenceDialogState extends State<_TripSequenceDialog> with SingleTickerProviderStateMixin {
  TripRoute? _route;
  bool _loading = true;
  late TabController _tabController;
  /// stopID of the "Ausstieg" target — set by tapping a stop in either the
  /// list or the map. The map's GPS listener uses this to fire the
  /// Ausstieg-Alarm when the user is within ~150m of that stop.
  String? _targetStopId;
  /// True once the Ausstieg-Alarm fired for the current target. Read by
  /// dispose() to record an "arrived" (success) rather than "missed".
  bool _alarmFired = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recordHistoryOnClose();
    super.dispose();
  }

  /// Fire-and-forget history entry when the dialog closes. Status ladder:
  ///   - no target picked → cancelled
  ///   - target picked but alarm didn't fire → boarded (or missed if the
  ///     planned dep time is already >5 min old, meaning bus is gone)
  ///   - alarm fired → arrived (success)
  void _recordHistoryOnClose() {
    final dep = widget.dep;
    TransitTripStatus status;
    if (_alarmFired) {
      status = TransitTripStatus.arrived;
    } else if (_targetStopId != null) {
      final depAgo = DateTime.now().difference(dep.plannedTime).inMinutes;
      status = depAgo > 5 ? TransitTripStatus.missed : TransitTripStatus.boarded;
    } else {
      status = TransitTripStatus.cancelled;
    }
    String? toStop;
    if (_targetStopId != null && _route != null) {
      try {
        toStop = _route!.stops.firstWhere((s) => s.stopID == _targetStopId).name;
      } catch (_) {}
    }
    TransitHistoryService.record(TransitHistoryEntry(
      line: dep.line,
      direction: dep.direction,
      fromStop: dep.stopName,
      toStop: toStop,
      plannedDep: dep.plannedTime,
      recordedAt: DateTime.now(),
      status: status,
    ));
  }

  Future<void> _fetch() async {
    final r = await widget.transitService.fetchTripRoute(widget.dep);
    if (!mounted) return;
    setState(() {
      _route = r;
      _loading = false;
    });
  }

  void _setTarget(String? id) {
    setState(() {
      _targetStopId = (_targetStopId == id) ? null : id;
    });
    // Sync cu OngoingRideService — dacă utilizatorul a ales un target,
    // pornește ride-ul persistent. Dacă a debifat, oprește-l.
    final ride = TransitOngoingRideService();
    final stops = _route?.stops ?? const <TripStop>[];
    final tid = _targetStopId;
    if (tid == null) {
      // Un click nou pe același stop deselectă → nu oprim automat (poate
      // vrea doar să schimbe target-ul). Se oprește din banner sau la
      // "Alarm entfernen" în TripMapView.
      return;
    }
    TripStop? tgt;
    for (final s in stops) {
      if (s.stopID == tid) { tgt = s; break; }
    }
    if (tgt == null) return;
    if (ride.isRunning) {
      ride.updateTarget(tgt);
    } else {
      ride.startRide(dep: widget.dep, target: tgt, allStops: stops);
    }
  }

  Color _lineColor() {
    switch (widget.dep.productType) {
      case 'tram': return Colors.blue.shade700;
      case 'subway': return Colors.indigo.shade700;
      case 'train':
      case 'regional': return Colors.red.shade700;
      case 'suburban': return Colors.green.shade700;
      default: return Colors.teal.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final dep = widget.dep;
    final stops = _route?.stops ?? const <TripStop>[];
    final path = _route?.path ?? const <(double, double)>[];
    // Where the user is boarding — flagged by transit_service via isCurrent.
    final currentIdx = stops.indexWhere((s) => s.isCurrent);
    // Bus's estimated current position on the route: the last stop whose
    // planned/realtime time is already in the past. -1 = not yet started.
    final now = DateTime.now();
    int busCurrentIdx = -1;
    for (int i = 0; i < stops.length; i++) {
      final t = stops[i].realtimeTime ?? stops[i].plannedTime;
      if (!t.isAfter(now)) busCurrentIdx = i;
    }
    final lineColor = _lineColor();

    // Rich header context — three sub-lines: Start->Ziel, Bus-Status, User-ETA.
    final startStop = stops.isNotEmpty ? stops.first.name : null;
    final endStop = stops.isNotEmpty ? stops.last.name : dep.direction;
    final boardStop = currentIdx >= 0 ? stops[currentIdx].name : dep.stopName;
    String busStatus;
    if (stops.isEmpty) {
      busStatus = '';
    } else if (busCurrentIdx < 0) {
      busStatus = 'Bus startet bald bei ${stops.first.name}';
    } else if (busCurrentIdx >= stops.length - 1) {
      busStatus = 'Bus am Endhaltestelle';
    } else {
      busStatus = 'Bus zw. ${stops[busCurrentIdx].name} und ${stops[busCurrentIdx + 1].name}';
    }
    String? boardEta;
    if (currentIdx >= 0) {
      if (busCurrentIdx < currentIdx) {
        final t = stops[currentIdx].realtimeTime ?? stops[currentIdx].plannedTime;
        final mins = t.difference(now).inMinutes;
        boardEta = mins <= 0 ? 'gleich bei dir' : 'in $mins Min. bei dir';
      } else if (busCurrentIdx >= currentIdx) {
        boardEta = 'schon vorbei';
      }
    }

    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
              decoration: BoxDecoration(
                color: lineColor.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: lineColor.withValues(alpha: 0.3))),
              ),
              child: Column(children: [Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      dep.line,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line 1: Start-Haltestelle -> Ziel (Endhaltestelle)
                        Row(children: [
                          if (startStop != null) ...[
                            Icon(Icons.play_circle_filled, size: 13, color: Colors.green.shade600),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                startStop,
                                style: TextStyle(fontSize: 11.5, color: p.onSurfaceDim),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_right_alt, size: 14, color: p.onSurfaceFaint),
                            const SizedBox(width: 4),
                          ],
                          Icon(Icons.flag, size: 13, color: Colors.red.shade400),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              endStop,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: p.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        // Line 2: Bus-Status (wo ist das Fahrzeug jetzt)
                        if (busStatus.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            Icon(Icons.directions_bus, size: 12, color: Colors.orange.shade600),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                busStatus,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: p.onSurfaceDim),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                        ],
                        // Line 3: Deine Einstiegs-Haltestelle + ETA
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.person_pin_circle, size: 12, color: Colors.teal.shade400),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Du: $boardStop'
                                  '${boardEta != null ? " — $boardEta" : " · ${dep.timeString}"}'
                                  '${dep.delay > 0 ? "  +${dep.delay}′" : ""}',
                              style: TextStyle(fontSize: 10.5, color: p.onSurfaceDim),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: p.onSurface),
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ), TabBar(
                controller: _tabController,
                labelColor: lineColor,
                unselectedLabelColor: p.onSurfaceDim,
                indicatorColor: lineColor,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(icon: Icon(Icons.list_alt, size: 16), text: 'Liste', height: 40),
                  Tab(icon: Icon(Icons.map_outlined, size: 16), text: 'Karte', height: 40),
                ],
              )]),
            ),
            // Body — TabBarView Liste + Karte
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : stops.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.route, size: 44, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Streckenverlauf konnte nicht ermittelt werden.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            Column(children: [
                              // Compact legend so the badges are self-explanatory.
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.surface,
                                  border: Border(bottom: BorderSide(color: p.divider)),
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: [
                                    _LegendChip(color: Colors.green.shade700, label: 'Start'),
                                    _LegendChip(color: Colors.orange.shade600, label: 'Bus jetzt'),
                                    _LegendChip(color: Colors.teal.shade500, label: 'Du'),
                                    if (_targetStopId != null)
                                      _LegendChip(color: Colors.red.shade600, label: 'Ziel'),
                                    _LegendChip(color: Colors.red.shade700, label: 'Ende'),
                                  ],
                                ),
                              ),
                              Expanded(child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: stops.length,
                              itemBuilder: (_, i) => _TripStopRow(
                                stop: stops[i],
                                isFirst: i == 0,
                                isLast: i == stops.length - 1,
                                beforeCurrent: currentIdx > 0 && i < currentIdx,
                                isBusHere: i == busCurrentIdx,
                                lineColor: lineColor,
                                isTarget: stops[i].stopID == _targetStopId,
                                onSetTarget: () => _setTarget(stops[i].stopID),
                              ),
                            )),
                            ]),
                            _TripMapView(
                              stops: stops, path: path, lineColor: lineColor,
                              targetStopId: _targetStopId,
                              onSetTarget: _setTarget,
                              transitService: widget.transitService,
                              userMuttersprache: widget.userMuttersprache,
                              onAlarmFired: () => _alarmFired = true,
                            ),
                          ],
                        ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${stops.length} Haltestellen',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (currentIdx >= 0 && stops.isNotEmpty)
                    Text('${stops.length - currentIdx - 1} bis Endstation',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored dot + label used in the trip-sequence Liste legend row.
class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, color: p.onSurfaceDim, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _TripStopRow extends StatelessWidget {
  final TripStop stop;
  final bool isFirst;
  final bool isLast;
  final bool beforeCurrent;
  /// Bus's currently-estimated position on the route (last stop whose
  /// time is in the past). Independent of `stop.isCurrent`, which marks
  /// the user's own boarding stop.
  final bool isBusHere;
  final Color lineColor;
  final bool isTarget;
  final VoidCallback? onSetTarget;

  const _TripStopRow({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.beforeCurrent,
    required this.lineColor,
    this.isBusHere = false,
    this.isTarget = false,
    this.onSetTarget,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final isCurrent = stop.isCurrent;
    final dotColor = isBusHere
        ? Colors.orange.shade600
        : (isCurrent
            ? Colors.green.shade600
            : (isTarget ? Colors.red.shade600 : (beforeCurrent ? Colors.grey.shade400 : lineColor)));
    final textColor = isCurrent
        ? (p.dark ? Colors.green.shade200 : Colors.green.shade900)
        : (isTarget
            ? (p.dark ? Colors.red.shade200 : Colors.red.shade900)
            : (beforeCurrent ? p.onSurfaceFaint : p.onSurface));
    final fontWeight = (isCurrent || isTarget || isBusHere) ? FontWeight.bold : FontWeight.w500;

    // Screen-reader description merges up to 3 states:
    //   "Bus fährt hier gerade. Aktuelle Haltestelle: X, 08:32."
    final semStatus = [
      if (isBusHere) 'Bus hier',
      if (isFirst) 'Start-Haltestelle',
      if (isCurrent) 'Deine Einstiegs-Haltestelle',
      if (isTarget) 'Ausstiegs-Ziel',
      if (isLast) 'Endhaltestelle',
      if (beforeCurrent && !isBusHere) 'Bereits vorbei',
    ].join(', ');
    final delayNote = stop.delay > 0 ? ', ${stop.delay} Minuten Verspätung' : '';
    final sem = '$semStatus: ${stop.name}, ${stop.timeString}$delayNote';

    return Semantics(
      label: sem,
      button: !isCurrent && onSetTarget != null,
      hint: !isCurrent && onSetTarget != null ? 'Antippen um als Ausstiegs-Ziel zu wählen' : null,
      excludeSemantics: true,
      child: InkWell(
      onTap: (isCurrent || onSetTarget == null) ? null : onSetTarget,
      child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline column: vertical line + dot
          SizedBox(
            width: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vertical connecting line
                Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isFirst ? Colors.transparent : (beforeCurrent ? Colors.grey.shade300 : lineColor.withValues(alpha: 0.6)),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isLast ? Colors.transparent : (beforeCurrent || isCurrent ? lineColor.withValues(alpha: 0.6) : lineColor.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
                // Dot
                Container(
                  width: (isBusHere || isCurrent || isTarget) ? 18 : (isFirst || isLast ? 14 : 10),
                  height: (isBusHere || isCurrent || isTarget) ? 18 : (isFirst || isLast ? 14 : 10),
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: (isBusHere || isCurrent || isTarget)
                        ? Border.all(color: Colors.white, width: 3)
                        : (isFirst || isLast
                            ? Border.all(color: Colors.white, width: 2)
                            : null),
                    boxShadow: isBusHere
                        ? [BoxShadow(color: Colors.orange.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 3)]
                        : isCurrent
                            ? [BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 2)]
                            : isTarget
                                ? [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 2)]
                                : null,
                  ),
                ),
              ],
            ),
          ),
          // Stop content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // BUS-HERE badge: bus is currently at (or just left) this
                      // stop — appears in addition to any other status badge.
                      if (isBusHere) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.directions_bus, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text('BUS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isFirst) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('START',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isCurrent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade500,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_pin_circle, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text('DU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isTarget && !isCurrent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.notifications_active, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text('ZIEL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isLast) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.flag, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text('ENDE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          stop.name,
                          style: TextStyle(
                            fontSize: (isCurrent || isBusHere) ? 13.5 : 12.5,
                            fontWeight: fontWeight,
                            color: isBusHere ? Colors.orange.shade700 : textColor,
                            decoration: beforeCurrent && !isBusHere ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        stop.timeString,
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor,
                          fontWeight: fontWeight,
                          decoration: stop.delay > 0 ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (stop.delay > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: stop.delay >= 5 ? Colors.red.shade100 : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '+${stop.delay}',
                            style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold,
                              color: stop.delay >= 5 ? Colors.red.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (stop.platform != null)
                    Text('Gl. ${stop.platform}',
                        style: TextStyle(fontSize: 10, color: p.onSurfaceFaint)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String providerName;
  final DateTime lastUpdate;
  const _Footer({required this.providerName, required this.lastUpdate});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Daten: $providerName • GPS ⟳ 60s',
              style: TextStyle(fontSize: 9, color: p.onSurfaceFaint),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${lastUpdate.hour}:${lastUpdate.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 9, color: p.onSurfaceFaint),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Tab 2 — Verbindung suchen (Origin → Destination journey planner)
// ══════════════════════════════════════════════════════════════

class _VerbindungTab extends StatefulWidget {
  final TransitService transitService;
  final TransitLocation? initialFrom;
  final TransitLocation? initialTo;
  final DateTime? initialArrivalTime;
  final String? currentMitgliedernummer;
  final List<User>? users;
  const _VerbindungTab({
    required this.transitService,
    this.initialFrom,
    this.initialTo,
    this.initialArrivalTime,
    this.currentMitgliedernummer,
    this.users,
  });

  @override
  State<_VerbindungTab> createState() => _VerbindungTabState();
}

class _VerbindungTabState extends State<_VerbindungTab> {
  static const _kPrefsDTicketKey = 'opnv.filter.onlyDeutschlandTicket';
  static const _kPrefsBarrierFreiKey = 'opnv.filter.barrierFrei';
  static const _kPrefsFahrradKey = 'opnv.filter.fahrradmitnahme';
  TransitLocation? _from;
  TransitLocation? _to;
  DateTime _when = DateTime.now();
  bool _arriveBy = false;
  bool _searching = false;
  List<Journey>? _results;
  String? _error;
  List<TransitFavorite> _favorites = [];
  TransitRoutinePattern? _morningPattern;
  bool _onlyDTicket = false;
  bool _barrierFrei = false;
  bool _mitRad = false;
  /// Async accessibility check result per journey index. Populated by
  /// `_checkAccessibility()` after each search. When `_barrierFrei` toggle
  /// is on, journeys with brokenElevator status are hidden from the list.
  final Map<int, JourneyAccessibility> _accessibility = {};
  /// Line names the user asked to avoid via "Alternative suchen" — resets
  /// on every explicit search. Persists across re-search so the second
  /// alternative call keeps excluding all previously vetoed lines.
  final Set<String> _excludedLines = {};

  @override
  void initState() {
    super.initState();
    // Deep-link prefill (from termin card) — auto-search if all params given.
    if (widget.initialFrom != null) _from = widget.initialFrom;
    if (widget.initialTo != null) _to = widget.initialTo;
    if (widget.initialArrivalTime != null) {
      _when = widget.initialArrivalTime!;
      _arriveBy = true;
    }
    // Auto-search if deep-linked with full context
    if (_from != null && _to != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    } else {
      // Prefill "Von" with GPS city (as text) — user can pick a real stop from autocomplete
      final gpsCity = widget.transitService.gpsCity;
      if (gpsCity != null && gpsCity.isNotEmpty && _from == null) {
        _from = TransitLocation(id: gpsCity, name: gpsCity);
      }
    }
    _loadFavorites();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _onlyDTicket = sp.getBool(_kPrefsDTicketKey) ?? false;
      _barrierFrei = sp.getBool(_kPrefsBarrierFreiKey) ?? false;
      _mitRad = sp.getBool(_kPrefsFahrradKey) ?? false;
    });
  }

  Future<void> _toggleMitRad(bool v) async {
    setState(() => _mitRad = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefsFahrradKey, v);
    // Client-side only — filtrează pe legs.bikeAllowedHeuristic.
  }

  Future<void> _toggleDTicket(bool v) async {
    setState(() => _onlyDTicket = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefsDTicketKey, v);
    // Re-run the last search with the new filter so the user immediately sees the effect.
    if (_from != null && _to != null && _results != null) {
      await _search();
    }
  }

  Future<void> _toggleBarrierFrei(bool v) async {
    setState(() => _barrierFrei = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPrefsBarrierFreiKey, v);
    // Toggle is client-side only — no re-search needed, existing checks
    // are reused. UI just re-filters what to render.
  }

  /// Kick off DB FaSta elevator checks for each journey in parallel.
  /// Fire-and-forget: setState per result so cards light up as data arrives.
  void _checkAccessibility(List<Journey> journeys) {
    _accessibility.clear();
    for (int i = 0; i < journeys.length; i++) {
      final idx = i;
      final j = journeys[i];
      widget.transitService.checkJourneyAccessibility(j).then((acc) {
        if (!mounted) return;
        setState(() => _accessibility[idx] = acc);
      }).catchError((_) {
        // Silent — accessibility is best-effort; UI shows "unknown" fallback.
      });
    }
  }

  Future<void> _loadFavorites() async {
    final picks = await TransitFavoritesService.topPicks();
    final pattern = await TransitPatternService.detectMorningPattern();
    if (!mounted) return;
    setState(() {
      _favorites = picks;
      _morningPattern = pattern;
    });
  }

  Future<void> _applyFavorite(TransitFavorite fav) async {
    setState(() {
      _from = fav.fromLocation;
      _to = fav.toLocation;
      _excludedLines.clear();
    });
    await _search();
  }

  /// User tapped "Alternative suchen" on a card whose primary line has
  /// an active HIM disruption. Add all affected lines from that journey
  /// to the exclusion set and re-run the search.
  Future<void> _findAlternativeForJourney(Journey j) async {
    final svc = TransitDisruptionsService();
    // Collect every vehicle-leg line that is mentioned in an active disruption.
    final linesToAvoid = <String>{};
    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      if (svc.disruptionsMentioning(leg.line).isNotEmpty) {
        linesToAvoid.add(leg.line);
      }
    }
    if (linesToAvoid.isEmpty) return;
    setState(() => _excludedLines.addAll(linesToAvoid));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text('Alternative gesucht ohne: ${linesToAvoid.join(", ")}'),
    ));
    await _search();
  }

  Future<void> _search() async {
    if (_from == null || _to == null) {
      setState(() => _error = 'Bitte Von und Nach auswählen');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = null;
    });
    try {
      final journeys = await widget.transitService.searchJourneys(
        from: _from!, to: _to!,
        departureTime: _arriveBy ? null : _when,
        arrivalTime: _arriveBy ? _when : null,
        onlyDeutschlandTicket: _onlyDTicket,
        excludedLines: _excludedLines.isEmpty ? null : _excludedLines,
      );
      if (!mounted) return;
      setState(() {
        _results = journeys;
        _searching = false;
        _accessibility.clear();
        if (journeys.isEmpty) {
          // Explicativ pentru cross-provider: userul poate să nu știe că e
          // problemă de coverage regională sau network.
          _error = 'Keine Verbindungen gefunden.\n\n'
              'Mögliche Ursachen:\n'
              '• Streckenname anders in bahn.de (versuche "Hbf" statt "Hauptbahnhof")\n'
              '• Kein Nahverkehr — bei Fernverkehr D-Ticket-Filter deaktivieren\n'
              '• Netzwerkproblem — später erneut versuchen';
        }
      });
      // Only record searches that actually returned results — random typos
      // or dead-end lookups shouldn't clutter the quick-pick row.
      if (journeys.isNotEmpty) {
        await TransitFavoritesService.record(_from!, _to!);
        await _loadFavorites();
        // Kick off DB FaSta elevator checks in background — cards decorate
        // as data arrives, no blocking.
        _checkAccessibility(journeys);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Fehler: $e';
      });
    }
  }

  /// Formats one Journey as a plain-text chat message and posts it to the
  /// chosen member's DM conversation. Uses the same admin_start endpoint
  /// as admin_chat_dialog so a new conversation is created if needed.
  Future<void> _sendRoute(Journey journey) async {
    final me = widget.currentMitgliedernummer;
    final users = widget.users;
    if (me == null || users == null || users.isEmpty) return;

    final target = await showDialog<User>(
      context: context,
      builder: (ctx) => _MemberPickerDialog(users: users, currentMitgliedernummer: me),
    );
    if (target == null || !mounted) return;

    final text = _formatJourneyForChat(journey);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text('Sende Route an ${target.name}…'),
        ]),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final api = ApiService();
      final conv = await api.adminStartChat(me, target.mitgliedernummer);
      if (conv['success'] != true) {
        throw Exception(conv['message'] ?? 'Konversation konnte nicht gestartet werden');
      }
      final convId = conv['conversation_id'] as int?;
      if (convId == null) throw Exception('Keine conversation_id erhalten');

      final res = await api.sendChatMessage(convId, me, text, skipTranslation: true);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Route an ${target.name} gesendet'),
          backgroundColor: Colors.green.shade600,
        ));
      } else {
        throw Exception(res['message'] ?? 'send failed');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler: $e'),
        backgroundColor: Colors.red.shade600,
      ));
    }
  }

  static String _formatJourneyForChat(Journey j) {
    String hhmm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    final buf = StringBuffer();
    buf.writeln('🚌 ÖPNV-Verbindung');
    buf.writeln('${j.legs.first.fromName} → ${j.legs.last.toName}');
    buf.writeln('${hhmm(j.depTime)} → ${hhmm(j.arrTime)}  (${j.duration.inMinutes} Min.)');
    for (final leg in j.legs) {
      if (leg.isWalk) {
        buf.writeln('  🚶 ${leg.arrTime.difference(leg.depTime).inMinutes} Min. Fußweg');
      } else {
        buf.writeln('  ${leg.line}: ${leg.fromName} ${hhmm(leg.depTime)} → ${leg.toName} ${hhmm(leg.arrTime)}');
      }
    }
    return buf.toString();
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null || !mounted) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Column(
      children: [
        // Morgen-Route chip — apare cand user-ul a călătorit >=3× aceeași linie
        // dimineața între Lun-Vin. Tap = pre-fill Verbindung cu ora medie.
        if (_morningPattern != null)
          _MorgenRouteChip(
            pattern: _morningPattern!,
            onTap: () {
              final pat = _morningPattern!;
              // Setează _when pentru azi la ora medie.
              final now = DateTime.now();
              setState(() {
                _when = DateTime(now.year, now.month, now.day, pat.medianHour, pat.medianMinute);
                _arriveBy = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(pat.detailLabel),
                  duration: const Duration(seconds: 4),
                ),
              );
            },
          ),
        if (_favorites.isNotEmpty)
          _FavoritesChipRow(
            favorites: _favorites,
            onPick: _applyFavorite,
            onDelete: (fav) async {
              await TransitFavoritesService.remove(fav);
              await _loadFavorites();
            },
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _LocationField(
                label: 'Von',
                icon: Icons.my_location,
                value: _from,
                service: widget.transitService,
                onChanged: (loc) => setState(() => _from = loc),
              ),
              const SizedBox(height: 8),
              _LocationField(
                label: 'Nach',
                icon: Icons.place,
                value: _to,
                service: widget.transitService,
                onChanged: (loc) => setState(() => _to = loc),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        '${_when.day}.${_when.month}.  ${_when.hour}:${_when.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _pickTime,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: _searching
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search, size: 16),
                    label: const Text('Suchen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade400,
                      foregroundColor: Colors.white,
                    ),
                    // Manual search resets any previous "Alternative suchen"
                    // exclusions — user starts fresh.
                    onPressed: _searching ? null : () {
                      _excludedLines.clear();
                      _search();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Filter chips row — D-Ticket + Barrierefrei. Wrap so both
              // fit on portrait tablets without overflow.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // D-Ticket filter — critical for Jobcenter-user target audience:
                  // strips ICE/IC/EC that need a separate ticket, so the shown routes
                  // are 100% Deutschlandticket-covered (49 EUR flat).
                  Semantics(
                    button: true,
                    label: _onlyDTicket
                        ? 'Nur Deutschlandticket-Verbindungen aktiv, Antippen zum Deaktivieren'
                        : 'Nur Deutschlandticket-Verbindungen anzeigen',
                    child: FilterChip(
                      label: const Text('Nur D-Ticket 63€', style: TextStyle(fontSize: 11)),
                      selected: _onlyDTicket,
                      onSelected: _toggleDTicket,
                      avatar: Icon(
                        _onlyDTicket ? Icons.check_circle : Icons.euro_symbol,
                        size: 14,
                        color: _onlyDTicket ? Colors.white : Colors.teal.shade400,
                      ),
                      selectedColor: Colors.teal.shade400,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: _onlyDTicket ? Colors.white : p.onSurface,
                      ),
                      backgroundColor: p.card,
                      side: BorderSide(color: p.border),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // Barrierefrei filter — checks DB FaSta elevator status at every
                  // transfer stop of each journey. Hides routes with broken elevator.
                  // Unknown-facilities stops don't count as failure (fail-open).
                  Semantics(
                    button: true,
                    label: _barrierFrei
                        ? 'Barrierefrei aktiv — Routen mit defekten Aufzügen werden ausgeblendet'
                        : 'Nur barrierefreie Routen anzeigen',
                    child: FilterChip(
                      label: const Text('Barrierefrei', style: TextStyle(fontSize: 11)),
                      selected: _barrierFrei,
                      onSelected: _toggleBarrierFrei,
                      avatar: Icon(
                        _barrierFrei ? Icons.check_circle : Icons.accessible,
                        size: 14,
                        color: _barrierFrei ? Colors.white : Colors.teal.shade400,
                      ),
                      selectedColor: Colors.teal.shade400,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: _barrierFrei ? Colors.white : p.onSurface,
                      ),
                      backgroundColor: p.card,
                      side: BorderSide(color: p.border),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // Fahrradmitnahme — filter care ascunde rute cu leg-uri
                  // fără bicicletă permisă (ICE/IC/EC, unele buse). Heuristic
                  // per productType + line prefix. RE/RB/S-Bahn/Tram = OK.
                  Semantics(
                    button: true,
                    label: _mitRad
                        ? 'Nur Fahrradmitnahme-Routen aktiv'
                        : 'Nur Routen mit Fahrradmitnahme anzeigen',
                    child: FilterChip(
                      label: const Text('mit Rad', style: TextStyle(fontSize: 11)),
                      selected: _mitRad,
                      onSelected: _toggleMitRad,
                      avatar: Icon(
                        _mitRad ? Icons.check_circle : Icons.directions_bike,
                        size: 14,
                        color: _mitRad ? Colors.white : Colors.teal.shade400,
                      ),
                      selectedColor: Colors.teal.shade400,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: _mitRad ? Colors.white : p.onSurface,
                      ),
                      backgroundColor: p.card,
                      side: BorderSide(color: p.border),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (_onlyDTicket)
                    Text(
                      'Nur Nahverkehr (RE/RB/S/U/Bus/Tram)',
                      style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                    ),
                  if (_mitRad)
                    Text(
                      'Nur Bahnen mit Rad',
                      style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                    ),
                  if (_barrierFrei)
                    Text(
                      'Defekte Aufzüge ausgeblendet',
                      style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                    ),
                  if (_excludedLines.isNotEmpty)
                    InputChip(
                      label: Text('ohne ${_excludedLines.join(", ")}',
                          style: const TextStyle(fontSize: 10)),
                      avatar: Icon(Icons.autorenew, size: 12, color: Colors.orange.shade700),
                      backgroundColor: Colors.orange.shade50,
                      side: BorderSide(color: Colors.orange.shade200),
                      onDeleted: () {
                        setState(() => _excludedLines.clear());
                        _search();
                      },
                      deleteButtonTooltipMessage: 'Alternative-Filter aufheben',
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: TextStyle(color: Colors.orange.shade400, fontSize: 12)),
          ),
        Expanded(
          child: _results == null
              ? Center(
                  child: Text(
                    _searching ? 'Suche läuft…' : 'Von–Nach eingeben und suchen',
                    style: TextStyle(color: p.onSurfaceFaint, fontSize: 13),
                  ),
                )
              : Builder(builder: (_) {
                  // Build filtered index list preserving original indexes so
                  // that _accessibility lookups (keyed by original position)
                  // still line up after the Barrierefrei toggle hides some.
                  final visible = <int>[];
                  for (int i = 0; i < _results!.length; i++) {
                    final acc = _accessibility[i];
                    if (_barrierFrei &&
                        acc != null &&
                        acc.status == JourneyAccessibilityStatus.brokenElevator) {
                      continue;
                    }
                    if (_mitRad) {
                      // Ascunde ruta dacă orice leg (excluzând walks) nu
                      // permite bicicletă conform heuristic.
                      final j = _results![i];
                      final blocked = j.legs.any((l) => !l.isWalk && !l.bikeAllowedHeuristic);
                      if (blocked) continue;
                    }
                    visible.add(i);
                  }
                  if (visible.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _barrierFrei
                              ? 'Keine barrierefreien Verbindungen gefunden.\n'
                                  'Deaktiviere den Barrierefrei-Filter für Alternativen.'
                              : 'Keine Verbindungen',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.onSurfaceFaint, fontSize: 13),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: visible.length,
                    itemBuilder: (_, listIdx) {
                      final i = visible[listIdx];
                      return _JourneyCard(
                        journey: _results![i],
                        accessibility: _accessibility[i],
                        onSend: (widget.currentMitgliedernummer != null && widget.users != null && widget.users!.isNotEmpty)
                            ? () => _sendRoute(_results![i])
                            : null,
                        onFindAlternative: _findAlternativeForJourney,
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }
}

/// Detected recurring morning-commute chip. Apare doar când algoritmul din
/// TransitPatternService a găsit >=3 călătorii identice în intervalul 5-11h.
class _MorgenRouteChip extends StatelessWidget {
  final TransitRoutinePattern pattern;
  final VoidCallback onTap;
  const _MorgenRouteChip({required this.pattern, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: p.dark
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.amber.shade50,
        border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
      ),
      child: Semantics(
        button: true,
        label: pattern.detailLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.wb_twilight, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Muster erkannt: ${pattern.chipLabel}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.dark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade600,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('${pattern.occurrences}×',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal quick-pick chip row of ranked favorite routes.
/// Shown above the Von/Nach fields — one tap fills both and auto-searches.
class _FavoritesChipRow extends StatelessWidget {
  final List<TransitFavorite> favorites;
  final ValueChanged<TransitFavorite> onPick;
  final ValueChanged<TransitFavorite> onDelete;
  const _FavoritesChipRow({
    required this.favorites,
    required this.onPick,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, size: 12, color: Colors.amber.shade600),
              const SizedBox(width: 4),
              Text(
                'Häufig gesucht',
                style: TextStyle(fontSize: 10, color: p.onSurfaceDim, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final fav = favorites[i];
                return Semantics(
                  button: true,
                  label: 'Route von ${fav.fromName} nach ${fav.toName}. '
                      '${fav.hits} mal gesucht. Antippen um erneut zu suchen.',
                  child: InputChip(
                    label: Text(fav.chipLabel, style: const TextStyle(fontSize: 11)),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: p.card,
                    side: BorderSide(color: p.border),
                    avatar: Icon(Icons.replay, size: 14, color: Colors.teal.shade400),
                    onDeleted: () => onDelete(fav),
                    deleteIconColor: p.onSurfaceFaint,
                    deleteButtonTooltipMessage: 'Aus Favoriten entfernen',
                    onPressed: () => onPick(fav),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationField extends StatefulWidget {
  final String label;
  final IconData icon;
  final TransitLocation? value;
  final TransitService service;
  final ValueChanged<TransitLocation?> onChanged;

  const _LocationField({
    required this.label,
    required this.icon,
    required this.value,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<_LocationField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _voiceReady = false;
  bool _listening = false;

  /// Doar mobil (Android/iOS) — desktop nu are runtime STT prin plugin.
  bool get _voiceSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> _toggleListen(TextEditingController controller) async {
    if (!_voiceSupported) return;
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_voiceReady) {
      _voiceReady = await _speech.initialize(
        onError: (_) {},
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
    }
    if (!_voiceReady || !mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'de_DE',
      onResult: (r) async {
        controller.text = r.recognizedWords;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
        if (r.finalResult && r.recognizedWords.trim().length >= 2) {
          final list = await widget.service.searchLocations(r.recognizedWords);
          if (list.isNotEmpty) widget.onChanged(list.first);
        }
      },
    );
  }

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<TransitLocation>(
      displayStringForOption: (loc) => loc.name,
      optionsBuilder: (textEditingValue) async {
        if (textEditingValue.text.trim().length < 2) return const [];
        return await widget.service.searchLocations(textEditingValue.text);
      },
      onSelected: widget.onChanged,
      initialValue: widget.value != null ? TextEditingValue(text: widget.value!.name) : null,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            prefixIcon: Icon(widget.icon, size: 18, color: Colors.teal.shade700),
            hintText: widget.label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_voiceSupported)
                  IconButton(
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      size: 18,
                      color: _listening ? Colors.red.shade600 : Colors.teal.shade700,
                    ),
                    tooltip: _listening ? 'Höre zu…' : 'Ziel per Sprache eingeben',
                    onPressed: () => _toggleListen(controller),
                  ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      controller.clear();
                      widget.onChanged(null);
                    },
                  ),
              ],
            ),
          ),
          style: const TextStyle(fontSize: 13),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 500),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final o = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            o.type == 'stop' ? Icons.directions_bus : Icons.location_city,
                            size: 14, color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(o.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact strip that surfaces active nationwide disruptions inside the
/// Echtzeit tab. Listens to TransitDisruptionsService for reactive count.
class _DisruptionsBanner extends StatefulWidget {
  @override
  State<_DisruptionsBanner> createState() => _DisruptionsBannerState();
}

class _DisruptionsBannerState extends State<_DisruptionsBanner> {
  final _svc = TransitDisruptionsService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _svc.start();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_svc.count == 0) return const SizedBox.shrink();
    final p = _Palette.of(context);
    final high = _svc.highPriorityCount > 0;
    return Semantics(
      button: true,
      label: '${_svc.count} aktive Störungen. Antippen für Details.',
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => const _DisruptionsListDialog(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (high ? Colors.red : Colors.orange).withValues(alpha: p.dark ? 0.2 : 0.1),
            border: Border(bottom: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: high ? Colors.red.shade400 : Colors.orange.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _svc.bypassRegionFilter
                      ? '${_svc.count} Störung${_svc.count == 1 ? "" : "en"} bundesweit'
                      : '${_svc.count} Störung${_svc.count == 1 ? "" : "en"} in deiner Region',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: high ? Colors.red.shade400 : Colors.orange.shade600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: p.onSurfaceDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisruptionsListDialog extends StatefulWidget {
  const _DisruptionsListDialog();

  @override
  State<_DisruptionsListDialog> createState() => _DisruptionsListDialogState();
}

class _DisruptionsListDialogState extends State<_DisruptionsListDialog> {
  final _svc = TransitDisruptionsService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_rebuild);
  }

  @override
  void dispose() {
    _svc.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final bypass = _svc.bypassRegionFilter;
    final filteredCount = _svc.count;
    final allCount = _svc.allCount;
    final regionalHidden = !bypass && allCount > filteredCount;

    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 480, height: 560,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bypass
                              ? 'Störungen bundesweit ($allCount)'
                              : 'Störungen in deiner Region ($filteredCount)',
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold,
                            color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800,
                          ),
                        ),
                        if (regionalHidden)
                          Text(
                            '${allCount - filteredCount} weitere bundesweit',
                            style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, size: 18, color: p.onSurface),
                    tooltip: 'Neu laden',
                    onPressed: () => _svc.fetch(force: true),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: p.onSurface),
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Region filter toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(bottom: BorderSide(color: p.divider)),
              ),
              child: Row(
                children: [
                  Icon(
                    bypass ? Icons.public : Icons.location_on,
                    size: 14,
                    color: p.onSurfaceDim,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      bypass
                          ? 'Zeige alle bundesweiten Störungen'
                          : 'Nur regional relevante Störungen',
                      style: TextStyle(fontSize: 11, color: p.onSurfaceDim),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: bypass
                        ? 'Zurück zum Regionalfilter'
                        : 'Auch bundesweite Störungen anzeigen',
                    child: Switch(
                      value: bypass,
                      onChanged: (v) => _svc.bypassRegionFilter = v,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _svc.disruptions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 40, color: Colors.green.shade400),
                          const SizedBox(height: 8),
                          Text(
                            bypass ? 'Keine aktiven Störungen' : 'Keine Störungen in deiner Region',
                            style: TextStyle(color: p.onSurfaceFaint, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _svc.disruptions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                      itemBuilder: (_, i) => _DisruptionRow(d: _svc.disruptions[i]),
                    ),
            ),
            if (_svc.lastFetch != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Text(
                  'Aktualisiert ${_svc.lastFetch!.hour}:${_svc.lastFetch!.minute.toString().padLeft(2, '0')} • bahn.de HIM',
                  style: TextStyle(fontSize: 9, color: p.onSurfaceFaint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DisruptionRow extends StatelessWidget {
  final TransitDisruption d;
  const _DisruptionRow({required this.d});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    return Semantics(
      label: '${d.isHigh ? "Wichtige " : ""}Störung: ${d.headline}. '
          '${d.affected != null ? "Betroffen: ${d.affected}. " : ""}'
          '${d.text ?? ""}',
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4, height: 40,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                color: d.isHigh ? Colors.red.shade400 : Colors.orange.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.headline,
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold, color: p.onSurface,
                    ),
                  ),
                  if (d.affected != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      d.affected!,
                      style: TextStyle(fontSize: 11, color: Colors.teal.shade400, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (d.text != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      d.text!,
                      style: TextStyle(fontSize: 11, color: p.onSurfaceDim, height: 1.3),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (d.validUntil != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Gültig bis: ${d.validUntil!.day}.${d.validUntil!.month}. ${d.validUntil!.hour}:${d.validUntil!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 9, color: p.onSurfaceFaint),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal that lists all active members with a search box; returns the picked
/// User to the caller. Used by "Route an Mitglied schicken".
class _MemberPickerDialog extends StatefulWidget {
  final List<User> users;
  final String currentMitgliedernummer;
  const _MemberPickerDialog({required this.users, required this.currentMitgliedernummer});

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final query = _q.trim().toLowerCase();
    // Never send to yourself; hide deactivated accounts.
    final filtered = widget.users
        .where((u) => u.mitgliedernummer != widget.currentMitgliedernummer)
        .where((u) => u.status.toLowerCase() != 'deaktiviert' && u.status.toLowerCase() != 'inaktiv')
        .where((u) => query.isEmpty ||
            u.name.toLowerCase().contains(query) ||
            u.mitgliedernummer.toLowerCase().contains(query))
        .toList();
    filtered.sort((a, b) => a.name.compareTo(b.name));

    return Dialog(
      backgroundColor: p.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.send, size: 20, color: Colors.teal.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Route an Mitglied senden',
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: p.onSurface),
                    tooltip: 'Abbrechen',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18, color: p.onSurfaceDim),
                  hintText: 'Name oder V-Nummer suchen',
                  hintStyle: TextStyle(color: p.onSurfaceFaint, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                style: TextStyle(color: p.onSurface, fontSize: 13),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Keine Mitglieder gefunden',
                        style: TextStyle(color: p.onSurfaceFaint, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: p.divider),
                      itemBuilder: (_, i) {
                        final u = filtered[i];
                        return Semantics(
                          button: true,
                          label: 'An ${u.name}, ${u.mitgliedernummer} senden',
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.teal.shade400,
                              child: Text(
                                u.name.isNotEmpty ? u.name.substring(0, 1).toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(u.name, style: TextStyle(color: p.onSurface, fontSize: 13)),
                            subtitle: Text(u.mitgliedernummer, style: TextStyle(color: p.onSurfaceDim, fontSize: 11)),
                            trailing: Icon(Icons.chevron_right, size: 18, color: p.onSurfaceFaint),
                            onTap: () => Navigator.of(context).pop(u),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fare estimation helper — computes if journey is covered by D-Ticket
/// (63€/lună Deutschlandticket 2026) or dacă include Fernverkehr.
/// Target audience ICD-Jobcenter: important să știe dacă rută costă +25-70€.
class _FareInfo {
  /// True dacă toate leg-urile sunt Nahverkehr (S/RB/RE/IRE/MEX/Bus/Tram/U) →
  /// acoperit de D-Ticket 63€.
  final bool coveredByDTicket;
  /// Estimare cost adăugător pentru leg-urile Fernverkehr (best-effort, se
  /// bazează pe distanță aproximativă). null când e integral D-Ticket-abgedeckt.
  final int? extraEuroEstimate;
  final List<String> fernverkehrLines;

  const _FareInfo({
    required this.coveredByDTicket,
    this.extraEuroEstimate,
    this.fernverkehrLines = const [],
  });

  /// IC-Linien speciale acceptate ca Nahverkehr (D-Ticket-freigabe conform
  /// bahn.de/service/nahverkehrsfreigabe). Actualizat 2026.
  static const _dTicketIcNumbers = <String>{
    // Dortmund ↔ Iserlohn-Letmathe ↔ Dillenburg
    '2222', '2223', '2224', '2225', '2226',
    '2320', '2323', '2324', '2325', '2326', '2327',
    // Sylt ↔ Niebüll (nur Mo-Fr!)
    '2075',
  };
  /// Prefixes stricte Fernverkehr (case-insensitive, extras uppercase).
  /// Ordonate descrescător pentru match corect ("ICE" înainte de "IC").
  static const _fvPrefixes = <String>[
    'ICE', 'ECE', 'ECX', 'THALYS', 'FLIXT',
    'IC', 'EC', 'IR', 'TGV', 'RJ', 'NJ', 'EN', 'FLX', 'CNL', 'EIC', 'TER',
  ];

  /// True dacă line-ul e Fernverkehr conform prefix + numărul IC. Handle-uiește
  /// și "ICE100" (fără spațiu) și "IC 61" (Erfurt-Chemnitz = OK D-Ticket).
  static bool _isFernverkehr(JourneyLeg leg) {
    final line = leg.line.trim().toUpperCase();
    if (line.isEmpty) return false;
    for (final prefix in _fvPrefixes) {
      if (line == prefix) return true;
      if (line.length > prefix.length && line.startsWith(prefix)) {
        final nextChar = line[prefix.length];
        // Prefix urmat de spațiu, cifră sau `-` (ICE100, ICE 100, ICE-T).
        final isSep = nextChar == ' ' || nextChar == '-' || nextChar == '.' ||
            (nextChar.codeUnitAt(0) >= 0x30 && nextChar.codeUnitAt(0) <= 0x39);
        if (!isSep) continue;
        // Exception pentru IC: unele linii sunt D-Ticket eligible.
        if (prefix == 'IC') {
          final m = RegExp(r'^IC\s?(\d+)').firstMatch(line);
          if (m != null && _dTicketIcNumbers.contains(m.group(1))) {
            return false; // IC 2222 etc. → D-Ticket OK
          }
        }
        return true;
      }
    }
    return false;
  }

  static _FareInfo forJourney(Journey j) {
    final fv = <String>[];
    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      if (_isFernverkehr(leg)) fv.add(leg.line);
    }
    if (fv.isEmpty) {
      return const _FareInfo(coveredByDTicket: true);
    }
    // Estimare: distanță drum aproximativ per Fernverkehr = 25-70€.
    // Fără polyline reală, aproximăm după durata legelor FV.
    int fvMinutes = 0;
    for (final leg in j.legs) {
      if (leg.isWalk) continue;
      if (_isFernverkehr(leg)) {
        fvMinutes += leg.arrTime.difference(leg.depTime).inMinutes;
      }
    }
    // Tarif ICE mediu ~0.35€/km, viteza ~150 km/h → ~0.87€/min. Adăugăm 10€ base.
    final estimate = (10 + fvMinutes * 0.87).clamp(15, 200).round();
    return _FareInfo(
      coveredByDTicket: false,
      extraEuroEstimate: estimate,
      fernverkehrLines: fv,
    );
  }
}

/// One transfer/depart/arrive moment with an "adverse" weather forecast.
/// Attached to the Journey card as a warning line. "Adverse" = rain, snow,
/// thunderstorm or dense fog per WMO code. Sunny/cloudy = no warning.
class _WeatherAlert {
  final String stopName;
  final DateTime time;
  final String emoji;
  final String label;
  const _WeatherAlert(this.stopName, this.time, this.emoji, this.label);

  static bool _isAdverse(String emoji) {
    // Match against the icons emitted by WeatherCode.icon().
    return emoji == '🌧️' || emoji == '🌨️' || emoji == '⛈️' || emoji == '🌫️';
  }

  static List<_WeatherAlert> forJourney(Journey j) {
    final ws = WeatherService.instance;
    final alerts = <_WeatherAlert>[];
    void tryAdd(String name, DateTime time) {
      final hint = ws.weatherHintAt(time);
      if (hint == null) return;
      if (!_isAdverse(hint.emoji)) return;
      // Skip if already have alert for the same time — one weather line per moment.
      if (alerts.any((a) => a.time == time)) return;
      alerts.add(_WeatherAlert(name, time, hint.emoji, hint.label));
    }
    // Warn for departure, every Umstieg, and arrival.
    if (j.legs.isNotEmpty) {
      tryAdd('Abfahrt ${j.legs.first.fromName}', j.depTime);
      for (int i = 0; i < j.legs.length - 1; i++) {
        final at = j.legs[i].arrTime;
        tryAdd('Umstieg ${j.legs[i].toName}', at);
      }
      tryAdd('Ankunft ${j.legs.last.toName}', j.arrTime);

      // Walk-leg specific: dacă un fußweg >= 3 min traversează vreme
      // adversă → warning separat cu 🚶 prefix. Deja detectăm start/arr
      // deasupra, deci filtrăm doar walks intermediare cu durata utilă.
      for (int i = 0; i < j.legs.length; i++) {
        final leg = j.legs[i];
        if (!leg.isWalk) continue;
        final walkMin = leg.arrTime.difference(leg.depTime).inMinutes;
        if (walkMin < 3) continue;
        // Alertă la mijlocul walk-ului (compromis între dep și arr).
        final mid = leg.depTime.add(Duration(minutes: walkMin ~/ 2));
        final hint = ws.weatherHintAt(mid);
        if (hint == null || !_isAdverse(hint.emoji)) continue;
        if (alerts.any((a) => a.time == mid)) continue;
        alerts.add(_WeatherAlert(
          '🚶 $walkMin Min. Fußweg (${leg.fromName})',
          mid, hint.emoji, hint.label,
        ));
      }
    }
    return alerts;
  }
}

/// Small icon + tooltip that surfaces the DB FaSta elevator status for a
/// journey. Null status renders nothing (result not in yet).
///
/// - green ♿ = all elevators active where FaSta has data
/// - red   🚫 = at least one elevator broken (details in tooltip)
/// - grey  ? = no facility data (all bus stops, or DB unreachable)
class _AccessibilityBadge extends StatelessWidget {
  final JourneyAccessibility? status;
  const _AccessibilityBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    IconData icon;
    Color color;
    switch (s.status) {
      case JourneyAccessibilityStatus.barrierFree:
        icon = Icons.accessible;
        color = Colors.green.shade500;
        break;
      case JourneyAccessibilityStatus.brokenElevator:
        icon = Icons.not_accessible;
        color = Colors.red.shade400;
        break;
      case JourneyAccessibilityStatus.unknown:
        return const SizedBox.shrink();
    }
    return Tooltip(
      message: s.germanLabel,
      child: Semantics(
        label: s.germanLabel,
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}

/// Compact badge care afișează dacă traseul e acoperit de D-Ticket 63€
/// sau cere plată suplimentară pentru Fernverkehr (ICE/IC/EC).
class _FareBadge extends StatelessWidget {
  final _FareInfo info;
  const _FareBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    if (info.coveredByDTicket) {
      return Tooltip(
        message: 'Alle Fahrten mit dem Deutschlandticket (63€, 2. Klasse) enthalten',
        child: Semantics(
          label: 'Deutschlandticket-kompatibel',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.green.shade400),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 10, color: Colors.green.shade800),
              const SizedBox(width: 2),
              Text('D-Ticket',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            ]),
          ),
        ),
      );
    }
    final extra = info.extraEuroEstimate ?? 0;
    return Tooltip(
      message: 'Enthält ${info.fernverkehrLines.join(", ")} — kostet ca. $extra€ '
          'zusätzlich zum Deutschlandticket.',
      child: Semantics(
        label: 'Zusatzkosten ca. $extra Euro für Fernverkehr',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.orange.shade400),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.euro_symbol, size: 10, color: Colors.orange.shade800),
            const SizedBox(width: 2),
            Text('~$extra€',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          ]),
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final Journey journey;
  final VoidCallback? onSend;
  /// Async elevator-status check for transfer stops. Null while still
  /// loading (shown as a subtle "prüft…" hint). Populated in
  /// _VerbindungTabState._checkAccessibility.
  final JourneyAccessibility? accessibility;
  /// When set, "Alternative suchen" button appears if any of this journey's
  /// lines has an active HIM disruption. Tapping asks parent to re-search
  /// excluding the affected lines.
  final ValueChanged<Journey>? onFindAlternative;
  const _JourneyCard({
    required this.journey,
    this.onSend,
    this.accessibility,
    this.onFindAlternative,
  });

  /// Construiește URL public bahn.de care preîncarcă interogarea completă
  /// atunci când e deschis pe orice device. Fructos pentru WhatsApp / SMS.
  static String _buildBahnDeUrl(Journey j) {
    final from = Uri.encodeComponent(j.legs.first.fromName);
    final to = Uri.encodeComponent(j.legs.last.toName);
    final d = j.depTime;
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
        'T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';
    return 'https://www.bahn.de/buchung/fahrplan/suche#!connection?'
        'sts=true&so=$from&zo=$to&kl=2&r=13:16:KLASSENLOS:1:0&hd=$iso';
  }

  static Future<void> _shareLink(BuildContext ctx, Journey j) async {
    final url = _buildBahnDeUrl(j);
    await Clipboard.setData(ClipboardData(text: url));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Row(children: [
        const Icon(Icons.link, color: Colors.white, size: 16),
        const SizedBox(width: 6),
        const Expanded(child: Text('Link kopiert — im Chat einfügen')),
        TextButton(
          onPressed: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('Öffnen', style: TextStyle(color: Colors.white)),
        ),
      ]),
    ));
  }

  String _hhmm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  Color _colorFor(String product) {
    switch (product) {
      case 'tram': return Colors.blue.shade700;
      case 'train':
      case 'regional': return Colors.red.shade700;
      case 'suburban': return Colors.green.shade700;
      case 'walk': return Colors.grey.shade500;
      default: return Colors.teal.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final transfers = journey.transfers;
    final durMin = journey.duration.inMinutes;
    final durStr = durMin >= 60 ? '${durMin ~/ 60}h ${durMin % 60}m' : '${durMin}m';
    final accSuffix = (accessibility != null &&
            accessibility!.status != JourneyAccessibilityStatus.unknown)
        ? ' ${accessibility!.germanLabel}.'
        : '';
    final sem = 'Verbindung von ${journey.legs.first.fromName} nach '
        '${journey.legs.last.toName}. Abfahrt ${_hhmm(journey.depTime)}, '
        'Ankunft ${_hhmm(journey.arrTime)}. Dauer $durMin Minuten. '
        '${transfers == 0 ? "Direktverbindung" : "$transfers Umstiege"}.'
        '$accSuffix';

    return Semantics(
      label: sem,
      button: true,
      hint: 'Antippen für Details mit allen Umstiegen',
      excludeSemantics: true,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _JourneyDetailsDialog(journey: journey),
        ),
        child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${_hhmm(journey.depTime)} → ${_hhmm(journey.arrTime)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: p.onSurface),
                ),
                const SizedBox(width: 6),
                _AccessibilityBadge(status: accessibility),
                const SizedBox(width: 4),
                _FareBadge(info: _FareInfo.forJourney(journey)),
                const Spacer(),
                Text(durStr, style: TextStyle(fontSize: 12, color: p.onSurfaceDim, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    transfers == 0 ? 'direkt' : '$transfers ×',
                    style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                  ),
                ),
              ],
            ),
            // "Aufzug defekt: X" warning line — only when accessibility
            // check found a broken elevator on this journey's route.
            if (accessibility?.status == JourneyAccessibilityStatus.brokenElevator &&
                accessibility!.brokenAt.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red.shade400),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    'Aufzug defekt: ${accessibility!.brokenAt.take(2).join(", ")}'
                        '${accessibility!.brokenAt.length > 2 ? " +${accessibility!.brokenAt.length - 2}" : ""}',
                    style: TextStyle(fontSize: 10.5, color: Colors.red.shade400, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
            // Störung-Warning + "Alternative suchen" button — surfaces when
            // any vehicle-leg line matches an active HIM disruption. Cheap
            // client-side check against TransitDisruptionsService cache.
            if (onFindAlternative != null) ...[
              Builder(builder: (_) {
                final svc = TransitDisruptionsService();
                final hitLines = <String>[];
                for (final leg in journey.legs) {
                  if (leg.isWalk) continue;
                  if (svc.disruptionsMentioning(leg.line).isNotEmpty) {
                    if (!hitLines.contains(leg.line)) hitLines.add(leg.line);
                  }
                }
                if (hitLines.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange.shade600),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          'Störung auf ${hitLines.join(", ")}',
                          style: TextStyle(fontSize: 10.5, color: Colors.orange.shade600, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Alternative Route ohne ${hitLines.join(", ")} suchen',
                        child: InkWell(
                          onTap: () => onFindAlternative!(journey),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.autorenew, size: 12, color: Colors.orange.shade700),
                              const SizedBox(width: 3),
                              Text('Alternative',
                                  style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            // Weather warning lines — one per adverse-weather moment on the
            // route (depart/umstieg/arrive). Uses the existing dashboard
            // WeatherService.hourlyForecast — zero extra network calls.
            for (final w in _WeatherAlert.forJourney(journey)) ...[
              const SizedBox(height: 3),
              Row(children: [
                Text(w.emoji, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${w.label} bei ${w.stopName} (${w.time.hour.toString().padLeft(2, "0")}:${w.time.minute.toString().padLeft(2, "0")})',
                    style: TextStyle(fontSize: 10.5, color: Colors.blue.shade400, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 4, runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (int i = 0; i < journey.legs.length; i++) ...[
                  if (i > 0) Icon(Icons.chevron_right, size: 14, color: p.iconMuted),
                  _LegChip(leg: journey.legs[i], color: _colorFor(journey.legs[i].productType)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${journey.legs.first.fromName} → ${journey.legs.last.toName}',
                    style: TextStyle(fontSize: 11, color: p.onSurfaceDim),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Share link button — copiază URL bahn.de în clipboard pentru
                // WhatsApp/SMS/orice altă aplicație de comunicare externă.
                Semantics(
                  button: true,
                  label: 'Link zu bahn.de kopieren',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _shareLink(context, journey),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.link, size: 12, color: Colors.blue.shade600),
                        const SizedBox(width: 3),
                        Text('Teilen',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: p.dark ? Colors.blue.shade200 : Colors.blue.shade700,
                            )),
                      ]),
                    ),
                  ),
                ),
                if (onSend != null)
                  Semantics(
                    button: true,
                    label: 'Diese Verbindung an ein Mitglied senden',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: onSend,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send, size: 12, color: Colors.teal.shade400),
                            const SizedBox(width: 3),
                            Text(
                              'Senden',
                              style: TextStyle(
                                fontSize: 10,
                                color: p.dark ? Colors.teal.shade100 : Colors.teal.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    ));
  }
}

/// Full-journey drill-down modal — opens when the user taps a JourneyCard
/// in the Verbindung tab. Renders every leg vertically with a coloured
/// per-vehicle strip, separated by Umstieg-Banner boxes that show the
/// transfer window ("6 Min. Umstieg" — green >=5, orange 2-4, red <2).
///
/// Walking legs get their own compact "🚶 350m Fußweg" card between
/// vehicle legs (real bahn.de journeys often include short walks between
/// platforms; suppressing them would misrepresent the trip).
class _JourneyDetailsDialog extends StatelessWidget {
  final Journey journey;
  const _JourneyDetailsDialog({required this.journey});

  String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';

  Color _colorFor(String product) {
    switch (product) {
      case 'tram': return Colors.blue.shade700;
      case 'subway': return Colors.indigo.shade700;
      case 'train':
      case 'regional': return Colors.red.shade700;
      case 'suburban': return Colors.green.shade700;
      case 'walk': return Colors.grey.shade500;
      default: return Colors.teal.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final size = MediaQuery.of(context).size;
    final compact = size.width < 700;
    final dialogW = compact ? size.width - 16 : 520.0;
    final dialogH = compact ? size.height - 80 : 650.0;
    final durMin = journey.duration.inMinutes;
    final durStr = durMin >= 60 ? '${durMin ~/ 60}h ${durMin % 60}m' : '${durMin}m';
    final vehicleLegs = journey.legs.where((l) => !l.isWalk).length;
    return Dialog(
      backgroundColor: p.bg,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 40,
        vertical: compact ? 40 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          children: [
            // Header — full journey summary
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.route, size: 20, color: Colors.teal.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verbindungsdetails',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold,
                          color: p.dark ? Colors.teal.shade100 : Colors.teal.shade800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: p.onSurface),
                      tooltip: 'Schließen',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.play_circle_filled, size: 14, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Flexible(child: Text(
                      journey.legs.first.fromName,
                      style: TextStyle(fontSize: 12, color: p.onSurfaceDim),
                      overflow: TextOverflow.ellipsis,
                    )),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_right_alt, size: 14, color: p.onSurfaceFaint),
                    const SizedBox(width: 6),
                    Icon(Icons.flag, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Flexible(child: Text(
                      journey.legs.last.toName,
                      style: TextStyle(fontSize: 13, color: p.onSurface, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${_hhmm(journey.depTime)} → ${_hhmm(journey.arrTime)} · $durStr · '
                        '${vehicleLegs == 0 ? "nur Fußweg" : vehicleLegs == 1 ? "direkt" : "${vehicleLegs - 1} Umstiege"}',
                    style: TextStyle(fontSize: 11, color: p.onSurfaceDim),
                  ),
                ],
              ),
            ),
            // Body — leg cards + umstieg banners
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: journey.legs.length * 2 - 1,
                itemBuilder: (_, idx) {
                  // Alternate: leg (even idx) — umstieg banner (odd idx)
                  if (idx.isEven) {
                    final legIdx = idx ~/ 2;
                    return _JourneyLegCard(
                      leg: journey.legs[legIdx],
                      color: _colorFor(journey.legs[legIdx].productType),
                    );
                  } else {
                    final legIdx = idx ~/ 2;
                    final arriveLeg = journey.legs[legIdx];
                    final nextLeg = journey.legs[legIdx + 1];
                    // Skip "umstieg" between walk-and-vehicle — it's not really
                    // a transfer, just walking to the next stop. Also skip
                    // when times touch (transfer window ~0 minutes).
                    if (arriveLeg.isWalk || nextLeg.isWalk) {
                      return const SizedBox(height: 4);
                    }
                    final windowMin = nextLeg.depTime.difference(arriveLeg.arrTime).inMinutes;
                    return _UmstiegBanner(
                      stopName: arriveLeg.toName,
                      windowMinutes: windowMin,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical stack card for one leg: header (line + direction + times) +
/// from → to. Walking legs use a compact one-liner.
class _JourneyLegCard extends StatelessWidget {
  final JourneyLeg leg;
  final Color color;
  const _JourneyLegCard({required this.leg, required this.color});

  String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    if (leg.isWalk) {
      final mins = leg.arrTime.difference(leg.depTime).inMinutes;
      // Estimare distanță: mers pe jos mediu 4.5 km/h → ~75 m/min.
      final approxMeters = mins * 75;
      final distLabel = approxMeters >= 1000
          ? '${(approxMeters / 1000).toStringAsFixed(1)} km'
          : '~$approxMeters m';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Row(children: [
          Icon(Icons.directions_walk, size: 16, color: p.onSurfaceDim),
          const SizedBox(width: 6),
          Text(
            '$distLabel · $mins Min. Fußweg',
            style: TextStyle(fontSize: 11.5, color: p.onSurfaceDim, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 6),
          // OSM highway=steps check e prea scump în timp real (Overpass).
          // Marker soft: dacă walk-ul e < 5min = probabil accesibil (nu trece
          // prin Bhf-Etage); > 5min = poate include Treppen la conexiuni.
          if (mins < 5)
            Tooltip(
              message: 'Kurzer Fußweg — meist ebenerdig / barrierefrei',
              child: Icon(Icons.accessible, size: 12, color: Colors.green.shade600),
            )
          else
            Tooltip(
              message: 'Längerer Fußweg — evtl. Treppen unterwegs (nicht geprüft)',
              child: Icon(Icons.info_outline, size: 12, color: Colors.orange.shade600),
            ),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                child: Text(leg.line,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '→ ${leg.direction}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.play_circle_filled, size: 12, color: Colors.green.shade600),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  leg.fromName,
                  style: TextStyle(fontSize: 11.5, color: p.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(_hhmm(leg.depTime),
                  style: TextStyle(fontSize: 11, color: p.onSurfaceDim, fontWeight: FontWeight.w600)),
              if (leg.depDelay > 0) ...[
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(2)),
                  child: Text('+${leg.depDelay}',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.flag, size: 12, color: Colors.red.shade400),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  leg.toName,
                  style: TextStyle(fontSize: 11.5, color: p.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(_hhmm(leg.arrTime),
                  style: TextStyle(fontSize: 11, color: p.onSurfaceDim, fontWeight: FontWeight.w600)),
              if (leg.arrDelay > 0) ...[
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(2)),
                  child: Text('+${leg.arrDelay}',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ),
              ],
            ]),
            if (leg.fromPlatform != null || leg.toPlatform != null) ...[
              const SizedBox(height: 3),
              Text(
                'Gleis${leg.fromPlatform != null ? " ${leg.fromPlatform} ab" : ""}'
                    '${leg.toPlatform != null ? " · ${leg.toPlatform} an" : ""}',
                style: TextStyle(fontSize: 10, color: p.onSurfaceFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Umstieg-Banner shown between two vehicle legs. Colour encodes the
/// tightness of the transfer window: green ≥5 Min (comfortable),
/// orange 2-4 Min (viable but risky), red <2 Min (likely to miss).
class _UmstiegBanner extends StatelessWidget {
  final String stopName;
  final int windowMinutes;
  const _UmstiegBanner({required this.stopName, required this.windowMinutes});

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final Color color;
    final String label;
    if (windowMinutes >= 5) {
      color = Colors.green.shade500;
      label = 'Bequem';
    } else if (windowMinutes >= 2) {
      color = Colors.orange.shade500;
      label = 'Knapp';
    } else {
      color = Colors.red.shade500;
      label = 'Sehr knapp';
    }
    return Semantics(
      label: 'Umstieg bei $stopName, ${windowMinutes < 0 ? 0 : windowMinutes} Minuten Zeit. $label.',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: p.dark ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.swap_calls, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Umstieg bei $stopName',
              style: TextStyle(fontSize: 11, color: p.onSurface, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${windowMinutes < 0 ? 0 : windowMinutes} Min. — $label',
            style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

class _LegChip extends StatelessWidget {
  final JourneyLeg leg;
  final Color color;
  const _LegChip({required this.leg, required this.color});

  @override
  Widget build(BuildContext context) {
    if (leg.isWalk) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 14, color: Colors.grey.shade600),
          Text(
            '${leg.arrTime.difference(leg.depTime).inMinutes}m',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: Text(
        leg.line,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

/// Live map for the trip-sequence dialog. Since the user is INSIDE the
/// vehicle, their GPS position doubles as the vehicle's live position —
/// no separate real-time vehicle feed needed.
///
/// Uses `flutter_map` + free OSM tiles.
class _TripMapView extends StatefulWidget {
  final List<TripStop> stops;
  final List<(double, double)> path;
  final Color lineColor;
  final String? targetStopId;
  final ValueChanged<String?>? onSetTarget;
  final TransitService transitService;
  /// User's Muttersprache from Verifizierung Stufe 1 — when set to a
  /// non-German language TTS speaks bilingual announcements.
  final String? userMuttersprache;
  /// Notified once, when the target-stop alarm fires for the first time.
  /// Used by parent [_TripSequenceDialog] to mark the history entry as
  /// "arrived" instead of "boarded" on dispose.
  final VoidCallback? onAlarmFired;

  const _TripMapView({
    required this.stops,
    required this.path,
    required this.lineColor,
    required this.transitService,
    this.targetStopId,
    this.onSetTarget,
    this.userMuttersprache,
    this.onAlarmFired,
  });

  @override
  State<_TripMapView> createState() => _TripMapViewState();
}

class _TripMapViewState extends State<_TripMapView> {
  StreamSubscription<Position>? _positionSub;
  LatLng? _userPosition;
  final _mapController = MapController();
  bool _followUser = true;
  bool _ttsEnabled = false;
  final FlutterTts _tts = FlutterTts();
  /// Timer care re-calc poziția interpolată a vehiculului la 15s.
  Timer? _vehicleInterpolateTimer;
  /// Ultima poziție calculată a vehiculului (segment.lat/lon).
  LatLng? _vehiclePosition;
  /// Second TTS instance in the user's Muttersprache (RO/UK/TR/EN/…).
  /// Only allocated if the language is supported and non-German. The
  /// German TTS speaks first; this one follows after a short delay.
  FlutterTts? _ttsMuttersprache;
  /// Normalized language code (e.g. 'ro' from 'Rumänisch').
  String? _muttersprache;
  String? _lastAnnouncedStopId;
  bool _targetAlarmFired = false;

  /// Speak the given text in the user's Muttersprache TTS after a short
  /// delay so the German announcement isn't cut off. No-op if the second
  /// TTS wasn't allocated (user language is German or unsupported).
  void _speakMuttersprache(String text) {
    final tts = _ttsMuttersprache;
    if (tts == null) return;
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      tts.speak(text);
    });
  }

  /// Haversine distance in metres between two points.
  double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('de-DE');
    _tts.setSpeechRate(0.55);
    // Muttersprache TTS — only if user Verifizierung Stufe 1 has a supported
    // non-German language recorded. Announcements will be bilingual.
    final lang = TransitTranslations.normalize(widget.userMuttersprache);
    if (lang != null && lang != 'de') {
      _muttersprache = lang;
      final tts = FlutterTts();
      tts.setLanguage(TransitTranslations.bcpForLangCode(lang));
      tts.setSpeechRate(0.55);
      _ttsMuttersprache = tts;
    }
    // Pause the coarse (100m) dashboard stream while we run a fine (5m) one.
    // Running both = ~2× battery drain and duplicate FusedLocation callbacks.
    widget.transitService.pauseCoarseTracking();

    // On Android, promote the GPS stream to a foreground service so it keeps
    // firing when the user pockets the phone / switches to WhatsApp / locks
    // the screen — otherwise the Ausstieg-Alarm dies the moment the user
    // stops looking at the map. iOS handles this via the "when in use"
    // permission but doesn't need the extra config.
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'ÖPNV-Alarm aktiv',
              notificationText: 'Vibriert wenn du deine Ausstieg-Haltestelle erreichst.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        if (!mounted) return;
        final userLl = LatLng(pos.latitude, pos.longitude);
        setState(() => _userPosition = userLl);
        if (_followUser) {
          _mapController.move(userLl, _mapController.camera.zoom);
        }
        _handleProximity(userLl);
      },
      onError: (_) {},
    );
    // Rulează interpolarea imediat + la fiecare 15s.
    _updateVehiclePosition();
    _vehicleInterpolateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _updateVehiclePosition();
    });
  }

  /// Extrapolează poziția vehiculului pe polyline între stațiile a căror
  /// timpuri planificate/realtime încadrează `now`. Când 2 stații consecutive
  /// au `t1 ≤ now ≤ t2` → poziție = lerp(t1.coord, t2.coord, ratio).
  ///
  /// Când polyline detaliat nu e disponibil, cade back la stops (drept-liniar).
  void _updateVehiclePosition() {
    final stops = widget.stops;
    if (stops.length < 2) return;
    final now = DateTime.now();
    // Găsim segmentul curent.
    int segIdx = -1;
    for (int i = 0; i < stops.length - 1; i++) {
      final t1 = stops[i].realtimeTime ?? stops[i].plannedTime;
      final t2 = stops[i + 1].realtimeTime ?? stops[i + 1].plannedTime;
      if (!t1.isAfter(now) && t2.isAfter(now)) {
        segIdx = i;
        break;
      }
    }
    if (segIdx < 0) {
      setState(() => _vehiclePosition = null);
      return;
    }
    final a = stops[segIdx];
    final b = stops[segIdx + 1];
    if (a.lat == null || a.lon == null || b.lat == null || b.lon == null) {
      setState(() => _vehiclePosition = null);
      return;
    }
    final t1 = (a.realtimeTime ?? a.plannedTime).millisecondsSinceEpoch;
    final t2 = (b.realtimeTime ?? b.plannedTime).millisecondsSinceEpoch;
    if (t2 <= t1) {
      setState(() => _vehiclePosition = LatLng(a.lat!, a.lon!));
      return;
    }
    final ratio = ((now.millisecondsSinceEpoch - t1) / (t2 - t1)).clamp(0.0, 1.0);
    final lat = a.lat! + (b.lat! - a.lat!) * ratio;
    final lon = a.lon! + (b.lon! - a.lon!) * ratio;
    setState(() => _vehiclePosition = LatLng(lat, lon));
  }

  /// GPS-driven side effects: Ausstieg-Alarm + TTS "Nächste Haltestelle".
  ///
  /// - **Target alarm** (hysteresis): fires when user first enters <150 m of
  ///   the Ausstieg-Ziel. Won't repeat until they exit >400 m — so a bus
  ///   idling next to the stop doesn't spam alarms, but a round-trip that
  ///   passes the target twice DOES trigger both times.
  /// - **TTS "Nächste Haltestelle"** at <200 m for non-current stops.
  ///   Same hysteresis: once announced, the stop must be >400 m away to
  ///   re-arm — supports loop lines that visit the same stop twice.
  void _handleProximity(LatLng user) {
    final targetId = widget.targetStopId;
    if (targetId != null) {
      final target = widget.stops.firstWhere(
        (s) => s.stopID == targetId,
        orElse: () => TripStop(name: '', stopID: '', plannedTime: DateTime.now()),
      );
      if (target.lat != null && target.lon != null) {
        final d = _distMeters(user, LatLng(target.lat!, target.lon!));
        // Re-arm once we've clearly moved past the target.
        if (_targetAlarmFired && d > 400) _targetAlarmFired = false;
        if (!_targetAlarmFired && d < 150) {
          _targetAlarmFired = true;
          widget.onAlarmFired?.call();
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
          Future.delayed(const Duration(milliseconds: 500), HapticFeedback.heavyImpact);
          if (_ttsEnabled) {
            _tts.speak('Aussteigen: ${target.name}!');
            _speakMuttersprache(TransitTranslations.getOff(_muttersprache ?? '', target.name));
          }
          // Fire a heads-up local notification — critical for the background
          // case where the user has pocketed the phone. The GPS stream
          // continues via foreground service on Android, so this callback
          // still fires; the notification wakes the screen + plays sound.
          NotificationService().show(
            title: '🚨 Aussteigen: ${target.name}',
            body: 'Deine Ziel-Haltestelle ist erreicht — jetzt aussteigen!',
            payload: 'opnv:ausstieg:${target.stopID}',
            duration: const Duration(seconds: 10),
            androidChannelId: NotificationService.channelIdOpnvAlarm,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 6),
              content: Row(children: [
                const Icon(Icons.notifications_active, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aussteigen: ${target.name}!',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ));
          }
        }
      }
    }

    if (_ttsEnabled) {
      for (final s in widget.stops) {
        if (s.isCurrent) continue;
        if (s.lat == null || s.lon == null) continue;
        final d = _distMeters(user, LatLng(s.lat!, s.lon!));
        // Re-arm TTS for this stop if user has left the area — supports
        // round-trip / loop lines.
        if (_lastAnnouncedStopId == s.stopID && d > 400) {
          _lastAnnouncedStopId = null;
        }
        if (_lastAnnouncedStopId == s.stopID) continue;
        if (d < 200) {
          _lastAnnouncedStopId = s.stopID;
          _tts.speak('Nächste Haltestelle: ${s.name}');
          _speakMuttersprache(TransitTranslations.nextStop(_muttersprache ?? '', s.name));
          break;
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant _TripMapView old) {
    super.didUpdateWidget(old);
    if (old.targetStopId != widget.targetStopId) {
      // New target chosen (or cleared) → reset both alarm-fired and TTS
      // cursor so the next stop announcements/alarms fire cleanly.
      _targetAlarmFired = false;
      _lastAnnouncedStopId = null;
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _vehicleInterpolateTimer?.cancel();
    widget.transitService.resumeCoarseTracking();
    _tts.stop();
    _ttsMuttersprache?.stop();
    super.dispose();
  }

  /// Deep-link to Google/Apple Maps walking navigation from user's current
  /// position to the Ausstiegs-Ziel. Used after the alarm fires so the last
  /// 300-800 m are covered by pedestrian nav.
  ///
  /// Fallback chain:
  ///   1) Native Maps app if installed (geo: / maps: URI).
  ///   2) Browser to google.com/maps if no app.
  ///   3) SnackBar if all fail.
  Future<void> _openWalkingNav() async {
    final targetId = widget.targetStopId;
    if (targetId == null) return;
    final target = widget.stops.firstWhere(
      (s) => s.stopID == targetId,
      orElse: () => TripStop(name: '', stopID: '', plannedTime: DateTime.now()),
    );
    if (target.lat == null || target.lon == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Koordinaten für das Ziel bekannt')),
        );
      }
      return;
    }
    final lat = target.lat!;
    final lon = target.lon!;

    // Try platform-native URI first (opens Maps app directly).
    // - Android: google.navigation with mode=w for walking
    // - iOS: maps.apple.com with dirflg=w
    // - Web fallback: universal https URL that works everywhere.
    final candidates = [
      Uri.parse('google.navigation:q=$lat,$lon&mode=w'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=walking'),
      Uri.parse('https://maps.apple.com/?daddr=$lat,$lon&dirflg=w'),
    ];
    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte keine Karten-App öffnen')),
      );
    }
  }

  LatLngBounds? _computeBounds() {
    final all = <LatLng>[];
    for (final p in widget.path) {
      all.add(LatLng(p.$1, p.$2));
    }
    for (final s in widget.stops) {
      if (s.lat != null && s.lon != null) all.add(LatLng(s.lat!, s.lon!));
    }
    if (all.isEmpty) return null;
    return LatLngBounds.fromPoints(all);
  }

  @override
  Widget build(BuildContext context) {
    final polylinePoints = widget.path.map((p) => LatLng(p.$1, p.$2)).toList();
    if (polylinePoints.isEmpty) {
      // Fallback: straight lines between stops
      for (final s in widget.stops) {
        if (s.lat != null && s.lon != null) {
          polylinePoints.add(LatLng(s.lat!, s.lon!));
        }
      }
    }
    final bounds = _computeBounds();
    final center = bounds != null
        ? LatLng((bounds.north + bounds.south) / 2, (bounds.east + bounds.west) / 2)
        : const LatLng(48.4, 10.0);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: bounds != null
                ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(30))
                : null,
            initialCenter: center,
            initialZoom: 13,
            minZoom: 8,
            maxZoom: 18,
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture && _followUser) {
                setState(() => _followUser = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'de.icd360s.vorsitzer',
              maxZoom: 19,
            ),
            if (polylinePoints.length >= 2)
              PolylineLayer(polylines: [
                Polyline(points: polylinePoints, strokeWidth: 7, color: Colors.white),
                Polyline(points: polylinePoints, strokeWidth: 4, color: widget.lineColor),
              ]),
            MarkerLayer(markers: [
              for (final s in widget.stops)
                if (s.lat != null && s.lon != null)
                  Marker(
                    point: LatLng(s.lat!, s.lon!),
                    width: (s.isCurrent || s.stopID == widget.targetStopId) ? 32 : 22,
                    height: (s.isCurrent || s.stopID == widget.targetStopId) ? 32 : 22,
                    child: GestureDetector(
                      onTap: s.isCurrent || widget.onSetTarget == null
                          ? null
                          : () => widget.onSetTarget?.call(s.stopID),
                      child: s.isCurrent
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 8)],
                              ),
                            )
                          : s.stopID == widget.targetStopId
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 8)],
                                  ),
                                  child: const Icon(Icons.notifications_active, size: 16, color: Colors.white),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: widget.lineColor, width: 2.5),
                                  ),
                                ),
                    ),
                  ),
            ]),
            // Vehicul interpolat pe polyline (portocaliu, cu pulse animat).
            if (_vehiclePosition != null)
              MarkerLayer(markers: [
                Marker(
                  point: _vehiclePosition!,
                  width: 36, height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(color: Colors.orange.withValues(alpha: 0.7),
                            blurRadius: 12, spreadRadius: 3),
                      ],
                    ),
                    child: const Icon(Icons.directions_bus_filled, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            if (_userPosition != null)
              MarkerLayer(markers: [
                Marker(
                  point: _userPosition!,
                  width: 40, height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 2)],
                    ),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                  ),
                ),
              ]),
          ],
        ),
        Positioned(
          right: 8, bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_userPosition != null && !_followUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: FloatingActionButton.small(
                    heroTag: 'centerUser',
                    onPressed: () {
                      setState(() => _followUser = true);
                      _mapController.move(_userPosition!, 16);
                    },
                    backgroundColor: Colors.blue.shade600,
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ),
              FloatingActionButton.small(
                heroTag: 'fitRoute',
                onPressed: () {
                  final b = _computeBounds();
                  if (b != null) {
                    _mapController.fitCamera(CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(30)));
                    setState(() => _followUser = false);
                  }
                },
                backgroundColor: Colors.white,
                foregroundColor: widget.lineColor,
                child: const Icon(Icons.zoom_out_map),
              ),
            ],
          ),
        ),
        Positioned(
          left: 8, top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.navigation, size: 10, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                const Text('Ich', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                if (_vehiclePosition != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.directions_bus_filled, size: 10, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  const Text('Bus', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(width: 8),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.green.shade600, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('Einstieg', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                if (widget.targetStopId != null) ...[
                  const SizedBox(width: 8),
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.red.shade600, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  const Text('Ziel', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
        // Top-right — TTS toggle
        Positioned(
          right: 8, top: 8,
          child: Material(
            color: _ttsEnabled ? Colors.teal.shade600 : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(6),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                setState(() {
                  _ttsEnabled = !_ttsEnabled;
                  if (!_ttsEnabled) _tts.stop();
                });
                if (_ttsEnabled) {
                  await _tts.speak('Sprachansagen aktiviert');
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                      size: 14,
                      color: _ttsEnabled ? Colors.white : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ansagen',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: _ttsEnabled ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Center-bottom — target status banner + walking-nav button
        if (widget.targetStopId != null)
          Positioned(
            left: 0, right: 0, bottom: 60,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade700.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_active, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            () {
                              final s = widget.stops.firstWhere(
                                (x) => x.stopID == widget.targetStopId,
                                orElse: () => TripStop(name: '?', stopID: '', plannedTime: DateTime.now()),
                              );
                              return 'Alarm bei: ${s.name}';
                            }(),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (Platform.isAndroid)
                            const Text(
                              'auch im Hintergrund aktiv',
                              style: TextStyle(color: Colors.white70, fontSize: 8),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Walking-nav deep-link → Google/Apple Maps for the last few
                    // hundred meters after Ausstieg.
                    Semantics(
                      button: true,
                      label: 'Zu Fuß mit Google Maps zum Ziel navigieren',
                      child: InkWell(
                        onTap: _openWalkingNav,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          child: Icon(Icons.directions_walk, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: 'Ausstiegs-Ziel entfernen',
                      child: InkWell(
                        onTap: () => widget.onSetTarget?.call(null),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
