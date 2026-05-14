import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Reiseplanung — Journey Planner for Germany
/// Station search: int.bahn.de Web API (DB official, very reliable)
/// Journey planning: Transitous/MOTIS API (free, no auth, all Germany)
/// Supports: ICE, IC, RE, RB, S-Bahn, Bus, Tram, U-Bahn
class ReiseplanungScreen extends StatefulWidget {
  final VoidCallback onBack;

  const ReiseplanungScreen({super.key, required this.onBack});

  @override
  State<ReiseplanungScreen> createState() => _ReiseplanungScreenState();
}

class _ReiseplanungScreenState extends State<ReiseplanungScreen> {
  static const _bahnUrl = 'https://int.bahn.de/web/api';
  static const _transitousUrl = 'https://api.transitous.org/api/v1';
  final _client = http.Client();

  // Search controllers
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  // Selected stations
  _Station? _fromStation;
  _Station? _toStation;

  // Autocomplete results
  List<_Station> _fromSuggestions = [];
  List<_Station> _toSuggestions = [];
  bool _showFromSuggestions = false;
  bool _showToSuggestions = false;
  Timer? _fromDebounce;
  Timer? _toDebounce;
  bool _fromSearching = false;
  bool _toSearching = false;

  // Date/Time
  DateTime _departureTime = DateTime.now();
  bool _isDeparture = true; // true = Abfahrt, false = Ankunft

  // Results
  List<_Journey> _journeys = [];
  bool _isSearching = false;
  String? _error;

  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _showFromSuggestions = false);
        });
      }
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _showToSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    super.dispose();
  }

  // ── Station Search (int.bahn.de) ───────────────────────────

  Future<List<_Station>> _searchStations(String query) async {
    if (query.length < 2) return [];
    try {
      final uri = Uri.parse(
        '$_bahnUrl/reiseloesung/orte?suchbegriff=${Uri.encodeComponent(query)}&limit=6&typ=ALL',
      );
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data
            .where((s) => s['type'] == 'ST') // only stations/stops
            .map((s) => _Station(
                  id: s['extId']?.toString() ?? '',
                  name: s['name']?.toString() ?? '',
                  lat: (s['lat'] is num) ? (s['lat'] as num).toDouble() : double.tryParse(s['lat']?.toString() ?? '') ?? 0,
                  lon: (s['lon'] is num) ? (s['lon'] as num).toDouble() : double.tryParse(s['lon']?.toString() ?? '') ?? 0,
                  products: (s['products'] as List?)?.cast<String>() ?? [],
                ))
            .where((s) => s.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void _onFromChanged(String value) {
    _fromStation = null;
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (mounted) setState(() => _fromSearching = true);
      final results = await _searchStations(value);
      if (mounted) {
        setState(() {
          _fromSuggestions = results;
          _showFromSuggestions = results.isNotEmpty;
          _fromSearching = false;
        });
      }
    });
  }

  void _onToChanged(String value) {
    _toStation = null;
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (mounted) setState(() => _toSearching = true);
      final results = await _searchStations(value);
      if (mounted) {
        setState(() {
          _toSuggestions = results;
          _showToSuggestions = results.isNotEmpty;
          _toSearching = false;
        });
      }
    });
  }

  void _selectFromStation(_Station station) {
    setState(() {
      _fromStation = station;
      _fromController.text = station.name;
      _showFromSuggestions = false;
    });
  }

  void _selectToStation(_Station station) {
    setState(() {
      _toStation = station;
      _toController.text = station.name;
      _showToSuggestions = false;
    });
  }

  void _swapStations() {
    final tmpStation = _fromStation;
    final tmpText = _fromController.text;
    setState(() {
      _fromStation = _toStation;
      _fromController.text = _toController.text;
      _toStation = tmpStation;
      _toController.text = tmpText;
    });
  }

  // ── Journey Search (Transitous API) ────────────────────────

  /// Auto-resolve station from text input if user didn't select from dropdown
  Future<_Station?> _resolveStation(String text) async {
    if (text.trim().length < 2) return null;
    final results = await _searchStations(text.trim());
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> _searchJourneys({bool loadLater = false, bool loadEarlier = false}) async {
    // Auto-resolve stations if user typed text but didn't pick from dropdown
    if (_fromStation == null && _fromController.text.trim().isNotEmpty) {
      setState(() { _isSearching = true; _error = null; });
      final resolved = await _resolveStation(_fromController.text);
      if (resolved != null && mounted) {
        setState(() {
          _fromStation = resolved;
          _fromController.text = resolved.name;
        });
      }
    }
    if (_toStation == null && _toController.text.trim().isNotEmpty) {
      if (!_isSearching) setState(() { _isSearching = true; _error = null; });
      final resolved = await _resolveStation(_toController.text);
      if (resolved != null && mounted) {
        setState(() {
          _toStation = resolved;
          _toController.text = resolved.name;
        });
      }
    }

    if (_fromStation == null || _toStation == null) {
      setState(() {
        _isSearching = false;
        _error = _fromStation == null
            ? 'Startort nicht gefunden. Bitte erneut eingeben.'
            : 'Zielort nicht gefunden. Bitte erneut eingeben.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      if (!loadLater && !loadEarlier) {
        _journeys = [];
      }
    });

    try {
      // Calculate time for pagination
      DateTime searchTime = _departureTime;
      if (loadLater && _journeys.isNotEmpty) {
        searchTime = _journeys.last.arrival.add(const Duration(minutes: 1));
      } else if (loadEarlier && _journeys.isNotEmpty) {
        searchTime = _journeys.first.departure.subtract(const Duration(hours: 2));
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(searchTime);
      final timeStr = DateFormat('HH:mm').format(searchTime);

      final params = <String, String>{
        'fromPlace': '${_fromStation!.lat},${_fromStation!.lon}',
        'toPlace': '${_toStation!.lat},${_toStation!.lon}',
        'date': dateStr,
        'time': timeStr,
        'numItineraries': '5',
      };

      if (!_isDeparture) {
        params['arriveBy'] = 'true';
      }

      final uri = Uri.parse('$_transitousUrl/plan').replace(queryParameters: params);
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final itineraries = data['itineraries'] as List? ?? [];
        final parsed = itineraries.map((it) => _Journey.fromTransitous(it)).toList();

        if (mounted) {
          setState(() {
            if (loadLater) {
              // Filter out duplicates
              for (final j in parsed) {
                if (!_journeys.any((existing) =>
                    existing.departure.isAtSameMomentAs(j.departure) &&
                    existing.arrival.isAtSameMomentAs(j.arrival))) {
                  _journeys.add(j);
                }
              }
            } else if (loadEarlier) {
              final newJourneys = <_Journey>[];
              for (final j in parsed) {
                if (!_journeys.any((existing) =>
                    existing.departure.isAtSameMomentAs(j.departure) &&
                    existing.arrival.isAtSameMomentAs(j.arrival))) {
                  newJourneys.add(j);
                }
              }
              _journeys.insertAll(0, newJourneys);
            } else {
              _journeys = parsed;
            }
            _isSearching = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'API-Fehler: ${response.statusCode}';
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Verbindungsfehler: $e';
          _isSearching = false;
        });
      }
    }
  }

  // ── Date/Time Picker ─────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departureTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('de'),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _departureTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── Build UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 4),
              Icon(Icons.route, color: Colors.indigo.shade700, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Reiseplanung',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'Deutsche Bahn + DELFI',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Divider(height: 1),
        // Search form
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // From/To inputs
              Expanded(
                child: Column(
                  children: [
                    _buildStationInput(
                      controller: _fromController,
                      focusNode: _fromFocus,
                      label: 'Von',
                      icon: Icons.trip_origin,
                      color: Colors.green,
                      suggestions: _fromSuggestions,
                      showSuggestions: _showFromSuggestions,
                      onChanged: _onFromChanged,
                      onSelect: _selectFromStation,
                      selectedStation: _fromStation,
                      isSearching: _fromSearching,
                    ),
                    const SizedBox(height: 8),
                    _buildStationInput(
                      controller: _toController,
                      focusNode: _toFocus,
                      label: 'Nach',
                      icon: Icons.location_on,
                      color: Colors.red,
                      suggestions: _toSuggestions,
                      showSuggestions: _showToSuggestions,
                      onChanged: _onToChanged,
                      onSelect: _selectToStation,
                      selectedStation: _toStation,
                      isSearching: _toSearching,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Swap button
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: IconButton(
                  icon: const Icon(Icons.swap_vert, size: 28),
                  tooltip: 'Tauschen',
                  onPressed: _swapStations,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 8),
              // Date/Time + Search
              Column(
                children: [
                  // Departure/Arrival toggle
                  SizedBox(
                    width: 180,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Abfahrt', style: TextStyle(fontSize: 12))),
                        ButtonSegment(value: false, label: Text('Ankunft', style: TextStyle(fontSize: 12))),
                      ],
                      selected: {_isDeparture},
                      onSelectionChanged: (v) => setState(() => _isDeparture = v.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Date/Time picker
                  SizedBox(
                    width: 180,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(
                        DateFormat('dd.MM. HH:mm').format(_departureTime),
                        style: const TextStyle(fontSize: 13),
                      ),
                      onPressed: _pickDateTime,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Search button
                  SizedBox(
                    width: 180,
                    child: FilledButton.icon(
                      icon: _isSearching
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 18),
                      label: const Text('Suchen'),
                      onPressed: _isSearching ? null : () => _searchJourneys(),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Error
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
                ],
              ),
            ),
          ),
        // Results
        Expanded(
          child: _journeys.isEmpty && !_isSearching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.train, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Start und Ziel eingeben',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ICE, IC, RE, RB, S-Bahn, Bus, Tram, U-Bahn',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : _buildJourneyList(),
        ),
      ],
    );
  }

  // ── Station Input Widget ─────────────────────────────────────

  Widget _buildStationInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required Color color,
    required List<_Station> suggestions,
    required bool showSuggestions,
    required Function(String) onChanged,
    required Function(_Station) onSelect,
    required _Station? selectedStation,
    bool isSearching = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: color, size: 20),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : selectedStation != null
                    ? Icon(Icons.check_circle, color: Colors.green.shade400, size: 18)
                    : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 14),
        ),
        if (showSuggestions && suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(_stationIcon(s.products), size: 18, color: Colors.grey.shade600),
                  title: Text(s.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(s.productLabels, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  onTap: () => onSelect(s),
                );
              },
            ),
          ),
      ],
    );
  }

  IconData _stationIcon(List<String> products) {
    if (products.contains('ICE') || products.contains('IC')) return Icons.train;
    if (products.contains('S')) return Icons.directions_railway;
    if (products.contains('U')) return Icons.subway;
    if (products.contains('TRAM') || products.contains('STB')) return Icons.tram;
    if (products.contains('BUS')) return Icons.directions_bus;
    if (products.contains('REGIONAL') || products.contains('IR')) return Icons.directions_railway;
    return Icons.place;
  }

  // ── Journey Results List ─────────────────────────────────────

  Widget _buildJourneyList() {
    return Column(
      children: [
        // Earlier button
        if (_journeys.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            label: const Text('Frühere Verbindungen', style: TextStyle(fontSize: 12)),
            onPressed: _isSearching ? null : () => _searchJourneys(loadEarlier: true),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _journeys.length,
            itemBuilder: (_, i) => _buildJourneyCard(_journeys[i]),
          ),
        ),
        // Later button
        if (_journeys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              label: const Text('Spätere Verbindungen', style: TextStyle(fontSize: 12)),
              onPressed: _isSearching ? null : () => _searchJourneys(loadLater: true),
            ),
          ),
      ],
    );
  }

  Widget _buildJourneyCard(_Journey journey) {
    final df = DateFormat('HH:mm');
    final duration = journey.arrival.difference(journey.departure);
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${mins}min' : '${mins}min';
    final transitLegs = journey.legs.where((l) => !l.isWalking).toList();
    final transfers = transitLegs.length > 1 ? transitLegs.length - 1 : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        // Header: times + duration + transfers
        title: Row(
          children: [
            // Departure time
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(df.format(journey.departure), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(journey.legs.first.originName, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
              ],
            ),
            const SizedBox(width: 12),
            // Arrow + product icons
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...transitLegs.take(4).map((l) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _legColor(l.mode),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l.lineName ?? l.mode ?? '?',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade400),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  Text(
                    '$durationStr • ${transfers == 0 ? 'Direkt' : '$transfers ${transfers == 1 ? 'Umstieg' : 'Umstiege'}'}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Arrival time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(df.format(journey.arrival), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(journey.legs.last.destinationName, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
        // Expanded: leg details
        children: journey.legs.map((leg) => _buildLegRow(leg)).toList(),
      ),
    );
  }

  Widget _buildLegRow(_Leg leg) {
    final df = DateFormat('HH:mm');

    if (leg.isWalking) {
      final durMins = leg.arrival.difference(leg.departure).inMinutes;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 50),
            Icon(Icons.directions_walk, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(
              'Fußweg${durMins > 0 ? ' ($durMins min)' : ''}${leg.walkingDistance != null ? ' • ${leg.walkingDistance} m' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Times
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(df.format(leg.departure), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (leg.departureDelay > 0)
                  Text('+${leg.departureDelay}', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(df.format(leg.arrival), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (leg.arrivalDelay > 0)
                  Text('+${leg.arrivalDelay}', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Line indicator
          Column(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _legColor(leg.mode), width: 2),
                ),
              ),
              Container(width: 2, height: 40, color: _legColor(leg.mode)),
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _legColor(leg.mode),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Station names + line info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leg.originName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                if (leg.originPlatform != null)
                  Text('Gl. ${leg.originPlatform}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _legColor(leg.mode),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        leg.lineName ?? leg.mode ?? '?',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (leg.direction != null)
                      Expanded(
                        child: Text(
                          '→ ${leg.direction}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(leg.destinationName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                if (leg.destinationPlatform != null)
                  Text('Gl. ${leg.destinationPlatform}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _legColor(String? mode) {
    switch (mode) {
      case 'HIGHSPEED_RAIL':
      case 'LONG_DISTANCE':
        return Colors.red.shade700; // ICE, IC
      case 'REGIONAL_FAST_RAIL':
      case 'REGIONAL_RAIL':
        return Colors.blue.shade700; // RE, RB
      case 'SUBURBAN':
      case 'COMMUTER':
        return Colors.green.shade700; // S-Bahn
      case 'METRO':
        return Colors.blue.shade900; // U-Bahn
      case 'TRAM':
        return Colors.orange.shade700;
      case 'BUS':
      case 'COACH':
        return Colors.teal.shade700;
      case 'FERRY':
        return Colors.cyan.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}

// ══════════════════════════════════════════════════════════════
// Data Models
// ══════════════════════════════════════════════════════════════

class _Station {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final List<String> products;

  _Station({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.products,
  });

  String get productLabels {
    final mapping = {
      'ICE': 'ICE',
      'IC': 'IC',
      'IR': 'IR',
      'REGIONAL': 'RE/RB',
      'S': 'S',
      'U': 'U',
      'TRAM': 'Tram',
      'STB': 'Tram',
      'BUS': 'Bus',
    };
    final labels = <String>[];
    for (final p in products) {
      final mapped = mapping[p.toUpperCase()];
      if (mapped != null && !labels.contains(mapped)) {
        labels.add(mapped);
      }
    }
    return labels.join(' • ');
  }
}

class _Journey {
  final DateTime departure;
  final DateTime arrival;
  final List<_Leg> legs;

  _Journey({required this.departure, required this.arrival, required this.legs});

  factory _Journey.fromTransitous(Map<String, dynamic> json) {
    final legsList = json['legs'] as List? ?? [];
    final legs = legsList.map((l) => _Leg.fromTransitous(l)).toList();

    final startTime = DateTime.tryParse(json['startTime']?.toString() ?? '') ?? DateTime.now();
    final endTime = DateTime.tryParse(json['endTime']?.toString() ?? '') ?? DateTime.now();

    return _Journey(
      departure: startTime.toLocal(),
      arrival: endTime.toLocal(),
      legs: legs,
    );
  }
}

class _Leg {
  final String originName;
  final String destinationName;
  final DateTime departure;
  final DateTime arrival;
  final int departureDelay; // minutes
  final int arrivalDelay;   // minutes
  final String? originPlatform;
  final String? destinationPlatform;
  final String? lineName;
  final String? direction;
  final String? mode;
  final bool isWalking;
  final int? walkingDistance;

  _Leg({
    required this.originName,
    required this.destinationName,
    required this.departure,
    required this.arrival,
    this.departureDelay = 0,
    this.arrivalDelay = 0,
    this.originPlatform,
    this.destinationPlatform,
    this.lineName,
    this.direction,
    this.mode,
    this.isWalking = false,
    this.walkingDistance,
  });

  factory _Leg.fromTransitous(Map<String, dynamic> json) {
    final from = json['from'] as Map<String, dynamic>? ?? {};
    final to = json['to'] as Map<String, dynamic>? ?? {};
    final mode = json['mode']?.toString() ?? '';
    final isWalk = mode == 'WALK';

    // Parse times
    final depScheduled = DateTime.tryParse(from['scheduledDeparture']?.toString() ?? '') ?? DateTime.now();
    final depActual = DateTime.tryParse(from['departure']?.toString() ?? '');
    final arrScheduled = DateTime.tryParse(to['scheduledArrival']?.toString() ?? '') ?? DateTime.now();
    final arrActual = DateTime.tryParse(to['arrival']?.toString() ?? '');

    // Calculate delays in minutes
    int depDelay = 0;
    if (depActual != null) {
      depDelay = depActual.difference(depScheduled).inMinutes;
    }
    int arrDelay = 0;
    if (arrActual != null) {
      arrDelay = arrActual.difference(arrScheduled).inMinutes;
    }

    // Line name: use routeShortName or tripShortName
    String? lineName;
    if (!isWalk) {
      lineName = json['routeShortName']?.toString() ?? json['tripShortName']?.toString();
      if (lineName == null || lineName.isEmpty) {
        lineName = json['routeLongName']?.toString();
      }
    }

    return _Leg(
      originName: from['name']?.toString() ?? '',
      destinationName: to['name']?.toString() ?? '',
      departure: (depActual ?? depScheduled).toLocal(),
      arrival: (arrActual ?? arrScheduled).toLocal(),
      departureDelay: depDelay > 0 ? depDelay : 0,
      arrivalDelay: arrDelay > 0 ? arrDelay : 0,
      originPlatform: from['track']?.toString(),
      destinationPlatform: to['track']?.toString(),
      lineName: lineName,
      direction: isWalk ? null : json['headsign']?.toString(),
      mode: isWalk ? 'WALK' : mode,
      isWalking: isWalk,
      walkingDistance: isWalk ? json['distance'] as int? : null,
    );
  }
}
