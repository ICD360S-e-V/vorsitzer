import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'dart:io' show Platform;
import '../services/notification_service.dart';
import '../services/transit_service.dart';
import '../services/transit_disruptions_service.dart';
import '../services/transit_favorites_service.dart';

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
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _EchtzeitTab(
                    transitService: widget.transitService,
                    initialDepartures: widget.initialDepartures,
                    city: widget.city,
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

  const _Header({required this.tabController, required this.onClose});

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

class _EchtzeitTab extends StatefulWidget {
  final TransitService transitService;
  final List<Departure> initialDepartures;
  final String city;

  const _EchtzeitTab({
    required this.transitService,
    required this.initialDepartures,
    required this.city,
  });

  @override
  State<_EchtzeitTab> createState() => _EchtzeitTabState();
}

class _EchtzeitTabState extends State<_EchtzeitTab> {
  late List<Departure> _departures;
  bool _isLoading = false;
  Timer? _refreshTimer;
  DateTime _lastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _departures = List.from(widget.initialDepartures);
    // Auto-refresh every 60s — also re-checks GPS via service.refresh()
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    if (_departures.isEmpty) _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await widget.transitService.refresh();
    if (!mounted) return;
    setState(() {
      _departures = List.from(widget.transitService.departures);
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
  Map<String, List<Departure>> get _byStop {
    final grouped = <String, List<Departure>>{};
    final now = DateTime.now();
    for (final d in _departures) {
      if (d.stopName.isEmpty) continue;
      if (d.minutesUntil < 0 || (d.realtimeTime ?? d.plannedTime).isBefore(now.subtract(const Duration(minutes: 1)))) continue;
      grouped.putIfAbsent(d.stopName, () => []).add(d);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byStop;
    final stops = widget.transitService.nearbyStops;
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
                  ? _EmptyState(loading: _isLoading, error: widget.transitService.locationError)
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final stop in stops.take(3))
                          _StopSection(
                            stop: stop,
                            departures: grouped[stop.name] ?? [],
                            transitService: widget.transitService,
                          ),
                      ],
                    ),
        ),
        _Footer(providerName: provider?.displayName ?? 'ÖPNV', lastUpdate: _lastUpdate),
      ],
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
  const _StopSection({required this.stop, required this.departures, required this.transitService});

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
            ...departures.take(6).map((d) => _DepartureRow(dep: d, transitService: transitService)),
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
  const _DepartureRow({required this.dep, required this.transitService});

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
    final isImminent = mins <= 2;
    final isSoon = mins <= 5;
    final isLive = dep.realtimeTime != null;

    final canOpenSequence = dep.stopID != null && dep.destID != null;
    final productLabel = switch (dep.productType) {
      'tram' => 'Straßenbahn',
      'subway' => 'U-Bahn',
      'suburban' => 'S-Bahn',
      'train' || 'regional' => 'Zug',
      'bus' => 'Bus',
      _ => 'Fahrzeug',
    };
    final delayLabel = dep.delay > 0 ? ', ${dep.delay} Minuten Verspätung' : '';
    final liveLabel = isLive ? 'Live-Daten' : 'Fahrplan';
    final minsLabel = mins == 0 ? 'jetzt' : 'in $mins Minuten';
    final sem = '$productLabel Linie ${dep.line} nach ${dep.direction}, '
        'Abfahrt $minsLabel um ${dep.timeString}$delayLabel. $liveLabel.'
        '${dep.platform != null ? " Gleis ${dep.platform}." : ""}';

    Color? bg;
    if (isImminent) bg = p.dark ? const Color(0xFF3D1F1F) : Colors.red.shade50;
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
                builder: (_) => _TripSequenceDialog(dep: dep, transitService: transitService),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: dep.delay >= 5 ? Colors.red.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '+${dep.delay}',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: dep.delay >= 5 ? Colors.red.shade800 : Colors.orange.shade800,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          // Platform
          if (dep.platform != null) ...[
            Text(dep.platform!, style: TextStyle(fontSize: 10, color: p.onSurfaceFaint)),
            const SizedBox(width: 6),
          ],
          // Live/Plan indicator
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isLive ? Colors.green.shade500 : p.iconMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isLive ? 'Live' : 'Plan',
            style: TextStyle(
              fontSize: 9,
              color: isLive ? Colors.green.shade500 : p.onSurfaceFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          // Time
          Text(
            dep.timeString,
            style: TextStyle(
              fontSize: 12, color: p.onSurfaceDim,
              decoration: dep.delay > 0 ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(width: 8),
          // Minutes
          SizedBox(
            width: 42,
            child: Text(
              mins == 0 ? 'jetzt' : '$mins′',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold,
                color: isImminent ? Colors.red.shade400 : (isSoon ? Colors.orange.shade400 : Colors.teal.shade400),
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

/// Modal that shows every stop this bus/tram/train visits on its way to its
/// terminus. The user's boarding stop is highlighted so they can see how far
/// along the route they are getting on. Cached 60s in the transit service.
class _TripSequenceDialog extends StatefulWidget {
  final Departure dep;
  final TransitService transitService;
  const _TripSequenceDialog({required this.dep, required this.transitService});

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final dep = widget.dep;
    final stops = _route?.stops ?? const <TripStop>[];
    final path = _route?.path ?? const <(double, double)>[];
    final currentIdx = stops.indexWhere((s) => s.isCurrent);
    final lineColor = _lineColor();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
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
                        Text('→ ${dep.direction}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          'Abfahrt ${dep.timeString}${dep.delay > 0 ? "  +${dep.delay} Min" : ""}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ), TabBar(
                controller: _tabController,
                labelColor: lineColor,
                unselectedLabelColor: Colors.grey.shade600,
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
                            ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: stops.length,
                              itemBuilder: (_, i) => _TripStopRow(
                                stop: stops[i],
                                isFirst: i == 0,
                                isLast: i == stops.length - 1,
                                beforeCurrent: currentIdx > 0 && i < currentIdx,
                                lineColor: lineColor,
                                isTarget: stops[i].stopID == _targetStopId,
                                onSetTarget: () => _setTarget(stops[i].stopID),
                              ),
                            ),
                            _TripMapView(
                              stops: stops, path: path, lineColor: lineColor,
                              targetStopId: _targetStopId,
                              onSetTarget: _setTarget,
                              transitService: widget.transitService,
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

class _TripStopRow extends StatelessWidget {
  final TripStop stop;
  final bool isFirst;
  final bool isLast;
  final bool beforeCurrent;
  final Color lineColor;
  final bool isTarget;
  final VoidCallback? onSetTarget;

  const _TripStopRow({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.beforeCurrent,
    required this.lineColor,
    this.isTarget = false,
    this.onSetTarget,
  });

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    final isCurrent = stop.isCurrent;
    final dotColor = isCurrent
        ? Colors.green.shade600
        : (isTarget ? Colors.red.shade600 : (beforeCurrent ? Colors.grey.shade400 : lineColor));
    final textColor = isCurrent
        ? (p.dark ? Colors.green.shade200 : Colors.green.shade900)
        : (isTarget
            ? (p.dark ? Colors.red.shade200 : Colors.red.shade900)
            : (beforeCurrent ? p.onSurfaceFaint : p.onSurface));
    final fontWeight = (isCurrent || isTarget) ? FontWeight.bold : FontWeight.w500;

    // Screen-reader description:
    // "Aktuelle Haltestelle: X, 08:32" / "Ziel-Haltestelle: X" / "Haltestelle X, 08:35"
    final semStatus = isCurrent
        ? 'Aktuelle Haltestelle'
        : (isTarget
            ? 'Ausstiegs-Ziel'
            : (beforeCurrent ? 'Bereits vorbei' : 'Haltestelle'));
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
                  width: (isCurrent || isTarget) ? 18 : (isFirst || isLast ? 14 : 10),
                  height: (isCurrent || isTarget) ? 18 : (isFirst || isLast ? 14 : 10),
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: (isCurrent || isTarget)
                        ? Border.all(color: Colors.white, width: 3)
                        : (isFirst || isLast
                            ? Border.all(color: Colors.white, width: 2)
                            : null),
                    boxShadow: isCurrent
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
                      if (isCurrent) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('HIER',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
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
                      if (isFirst && !isCurrent) ...[
                        Icon(Icons.play_arrow, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                      ],
                      if (isLast) ...[
                        Icon(Icons.flag, size: 12, color: lineColor),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          stop.name,
                          style: TextStyle(
                            fontSize: isCurrent ? 13.5 : 12.5,
                            fontWeight: fontWeight,
                            color: textColor,
                            decoration: beforeCurrent ? TextDecoration.lineThrough : null,
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
  TransitLocation? _from;
  TransitLocation? _to;
  DateTime _when = DateTime.now();
  bool _arriveBy = false;
  bool _searching = false;
  List<Journey>? _results;
  String? _error;
  List<TransitFavorite> _favorites = [];
  bool _onlyDTicket = false;

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
    setState(() => _onlyDTicket = sp.getBool(_kPrefsDTicketKey) ?? false);
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

  Future<void> _loadFavorites() async {
    final picks = await TransitFavoritesService.topPicks();
    if (!mounted) return;
    setState(() => _favorites = picks);
  }

  Future<void> _applyFavorite(TransitFavorite fav) async {
    setState(() {
      _from = fav.fromLocation;
      _to = fav.toLocation;
    });
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
      );
      if (!mounted) return;
      setState(() {
        _results = journeys;
        _searching = false;
        if (journeys.isEmpty) _error = 'Keine Verbindungen gefunden';
      });
      // Only record searches that actually returned results — random typos
      // or dead-end lookups shouldn't clutter the quick-pick row.
      if (journeys.isNotEmpty) {
        await TransitFavoritesService.record(_from!, _to!);
        await _loadFavorites();
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
                    onPressed: _searching ? null : _search,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // D-Ticket filter — critical for Jobcenter-user target audience:
              // strips ICE/IC/EC that need a separate ticket, so the shown routes
              // are 100% Deutschlandticket-covered (49 EUR flat).
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: _onlyDTicket
                        ? 'Nur Deutschlandticket-Verbindungen aktiv, Antippen zum Deaktivieren'
                        : 'Nur Deutschlandticket-Verbindungen anzeigen',
                    child: FilterChip(
                      label: const Text('Nur 49€-Ticket', style: TextStyle(fontSize: 11)),
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
                  const SizedBox(width: 6),
                  if (_onlyDTicket)
                    Expanded(
                      child: Text(
                        'ICE/IC/EC ausgeblendet',
                        style: TextStyle(fontSize: 10, color: p.onSurfaceDim),
                      ),
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
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _results!.length,
                  itemBuilder: (_, i) => _JourneyCard(
                    journey: _results![i],
                    onSend: (widget.currentMitgliedernummer != null && widget.users != null && widget.users!.isNotEmpty)
                        ? () => _sendRoute(_results![i])
                        : null,
                  ),
                ),
        ),
      ],
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

class _LocationField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Autocomplete<TransitLocation>(
      displayStringForOption: (loc) => loc.name,
      optionsBuilder: (textEditingValue) async {
        if (textEditingValue.text.trim().length < 2) return const [];
        return await service.searchLocations(textEditingValue.text);
      },
      onSelected: onChanged,
      initialValue: value != null ? TextEditingValue(text: value!.name) : null,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: Colors.teal.shade700),
            hintText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      controller.clear();
                      onChanged(null);
                    },
                  )
                : null,
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

class _JourneyCard extends StatelessWidget {
  final Journey journey;
  final VoidCallback? onSend;
  const _JourneyCard({required this.journey, this.onSend});

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
    final vehicleLegs = journey.legs.where((l) => !l.isWalk).length;
    final transfers = vehicleLegs > 0 ? vehicleLegs - 1 : 0;
    final durMin = journey.duration.inMinutes;
    final durStr = durMin >= 60 ? '${durMin ~/ 60}h ${durMin % 60}m' : '${durMin}m';
    final sem = 'Verbindung von ${journey.legs.first.fromName} nach '
        '${journey.legs.last.toName}. Abfahrt ${_hhmm(journey.depTime)}, '
        'Ankunft ${_hhmm(journey.arrTime)}. Dauer $durMin Minuten. '
        '${transfers == 0 ? "Direktverbindung" : "$transfers Umstiege"}.';

    return Semantics(
      label: sem,
      container: true,
      excludeSemantics: true,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
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
    ));
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

  const _TripMapView({
    required this.stops,
    required this.path,
    required this.lineColor,
    required this.transitService,
    this.targetStopId,
    this.onSetTarget,
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
  String? _lastAnnouncedStopId;
  bool _targetAlarmFired = false;

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
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
          Future.delayed(const Duration(milliseconds: 500), HapticFeedback.heavyImpact);
          if (_ttsEnabled) _tts.speak('Aussteigen: ${target.name}!');
          // Fire a heads-up local notification — critical for the background
          // case where the user has pocketed the phone. The GPS stream
          // continues via foreground service on Android, so this callback
          // still fires; the notification wakes the screen + plays sound.
          NotificationService().show(
            title: '🚨 Aussteigen: ${target.name}',
            body: 'Deine Ziel-Haltestelle ist erreicht — jetzt aussteigen!',
            payload: 'opnv:ausstieg:${target.stopID}',
            duration: const Duration(seconds: 10),
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
    widget.transitService.resumeCoarseTracking();
    _tts.stop();
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
