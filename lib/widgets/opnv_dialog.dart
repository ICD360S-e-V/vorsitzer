import 'dart:async';
import 'package:flutter/material.dart';
import '../services/transit_service.dart';

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

  const OpnvDialog({
    super.key,
    required this.transitService,
    required this.initialDepartures,
    required this.city,
    this.initialFrom,
    this.initialTo,
    this.initialArrivalTime,
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

    return Dialog(
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
// Header — icon + title + close
// ══════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final TabController tabController;
  final VoidCallback onClose;

  const _Header({required this.tabController, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.directions_bus, color: Colors.teal.shade700, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ÖPNV',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                ),
              ),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onClose),
            ],
          ),
          TabBar(
            controller: tabController,
            labelColor: Colors.teal.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade700,
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

    return Column(
      children: [
        // Location bar with accuracy indicator
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
          color: Colors.grey.shade50,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: accColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      locLabel.isNotEmpty ? locLabel : 'Standort wird ermittelt…',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (provider != null)
                    Text(provider.name, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  const SizedBox(width: 6),
                  if (_isLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.refresh, size: 18),
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
                      Text('• $sourceLabel', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  ],
                ),
              ),
            ],
          ),
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

  /// True if any departure here is a rail vehicle — S-Bahn, U-Bahn, tram,
  /// regional or long-distance train. Only rail stops have DB facility data.
  bool get _isRailwayStation => departures.any((d) =>
      d.productType == 'train' ||
      d.productType == 'regional' ||
      d.productType == 'suburban' ||
      d.productType == 'subway' ||
      d.productType == 'tram');

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_bus, size: 16, color: Colors.teal.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stop.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(_distStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (_isRailwayStation) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _openFacilitiesDialog(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🛗', style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 3),
                          Text('Aufzüge', style: TextStyle(fontSize: 10, color: Colors.teal.shade800, fontWeight: FontWeight.w600)),
                        ],
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
              child: Text('Keine Abfahrten in Kürze', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )
          else
            ...departures.take(6).map((d) => _DepartureRow(dep: d)),
        ],
      ),
    );
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
  const _DepartureRow({required this.dep});

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
    final mins = dep.minutesUntil;
    final isImminent = mins <= 2;
    final isSoon = mins <= 5;
    final isLive = dep.realtimeTime != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        color: isImminent ? Colors.red.shade50 : (isSoon ? Colors.orange.shade50 : null),
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
            Text(dep.platform!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
          ],
          // Live/Plan indicator
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: isLive ? Colors.green.shade500 : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isLive ? 'Live' : 'Plan',
            style: TextStyle(
              fontSize: 9,
              color: isLive ? Colors.green.shade700 : Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          // Time
          Text(
            dep.timeString,
            style: TextStyle(
              fontSize: 12, color: Colors.grey.shade700,
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
                color: isImminent ? Colors.red.shade700 : (isSoon ? Colors.orange.shade700 : Colors.teal.shade700),
              ),
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Daten: $providerName • GPS ⟳ 60s',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${lastUpdate.hour}:${lastUpdate.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
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
  const _VerbindungTab({
    required this.transitService,
    this.initialFrom,
    this.initialTo,
    this.initialArrivalTime,
  });

  @override
  State<_VerbindungTab> createState() => _VerbindungTabState();
}

class _VerbindungTabState extends State<_VerbindungTab> {
  TransitLocation? _from;
  TransitLocation? _to;
  DateTime _when = DateTime.now();
  bool _arriveBy = false;
  bool _searching = false;
  List<Journey>? _results;
  String? _error;

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
      );
      if (!mounted) return;
      setState(() {
        _results = journeys;
        _searching = false;
        if (journeys.isEmpty) _error = 'Keine Verbindungen gefunden';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Fehler: $e';
      });
    }
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
    return Column(
      children: [
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
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _searching ? null : _search,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
          ),
        Expanded(
          child: _results == null
              ? Center(
                  child: Text(
                    _searching ? 'Suche läuft…' : 'Von–Nach eingeben und suchen',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _results!.length,
                  itemBuilder: (_, i) => _JourneyCard(journey: _results![i]),
                ),
        ),
      ],
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

class _JourneyCard extends StatelessWidget {
  final Journey journey;
  const _JourneyCard({required this.journey});

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
    final vehicleLegs = journey.legs.where((l) => !l.isWalk).length;
    final transfers = vehicleLegs > 0 ? vehicleLegs - 1 : 0;
    final durMin = journey.duration.inMinutes;
    final durStr = durMin >= 60 ? '${durMin ~/ 60}h ${durMin % 60}m' : '${durMin}m';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(durStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    transfers == 0 ? 'direkt' : '$transfers ×',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
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
                  if (i > 0) Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
                  _LegChip(leg: journey.legs[i], color: _colorFor(journey.legs[i].productType)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${journey.legs.first.fromName} → ${journey.legs.last.toName}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
