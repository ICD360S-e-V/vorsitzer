import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../models/user.dart';
import 'finanzen_bank.dart';
import 'finanzen_kredit.dart';

class FinanzenTabContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final TicketService ticketService;
  final String adminMitgliedernummer;

  const FinanzenTabContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.ticketService,
    required this.adminMitgliedernummer,
  });

  @override
  State<FinanzenTabContent> createState() => _FinanzenTabContentState();
}

class _FinanzenTabContentState extends State<FinanzenTabContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data maps per sub-tab
  final Map<String, Map<String, dynamic>> _data = {};
  final Map<String, bool> _loading = {};
  final Map<String, bool> _saving = {};
  List<Map<String, dynamic>> _bankenDb = [];
  Map<String, dynamic>? _pkontoData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData('finanzen_bank');
    _loadData('finanzen_kredit');
    _loadBanken();
    _loadPKontoFreibetrag();
  }

  Future<void> _loadBanken() async {
    final list = await widget.apiService.getBanken();
    if (mounted) setState(() => _bankenDb = list);
  }

  Future<void> _loadPKontoFreibetrag() async {
    final result = await widget.apiService.getPKontoFreibetrag();
    if (mounted && result['success'] == true && result['aktuell'] is Map) {
      setState(() => _pkontoData = Map<String, dynamic>.from(result['aktuell'] as Map));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData(String type) async {
    setState(() => _loading[type] = true);
    try {
      final result = await widget.apiService.getFinanzenData(widget.user.id, type);
      if (result['success'] == true && result['data'] is Map) {
        setState(() => _data[type] = Map<String, dynamic>.from(result['data'] as Map));
      } else {
        setState(() => _data[type] = {});
      }
    } catch (e) {
      setState(() => _data[type] = {});
    }
    setState(() => _loading[type] = false);
  }

  Future<void> _saveData(String type, Map<String, dynamic> data) async {
    setState(() => _saving[type] = true);
    try {
      final result = await widget.apiService.saveFinanzenData(widget.user.id, type, data);
      if (result['success'] == true) {
        setState(() => _data[type] = Map<String, dynamic>.from(data));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Gespeichert'), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _saving[type] = false);
  }

  Future<void> _autoSaveField(String type, String field, dynamic value) async {
    final current = Map<String, dynamic>.from(_data[type] ?? {});
    current[field] = value;
    _data[type] = current;
    try {
      await widget.apiService.saveFinanzenData(widget.user.id, type, current);
    } catch (_) {}
  }

  Map<String, dynamic> _getData(String type) => _data[type] ?? {};
  bool _isLoading(String type) => _loading[type] ?? false;
  bool _isSaving(String type) => _saving[type] ?? false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            border: Border(bottom: BorderSide(color: Colors.teal.shade200)),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet, size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Text('Finanzen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              const Spacer(),
              Text(widget.user.mitgliedernummer, style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
            ],
          ),
        ),
        // Sub-tabs
        Container(
          color: Colors.teal.shade50,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.teal.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade700,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.account_balance, size: 18), text: 'Hausbank'),
              Tab(icon: Icon(Icons.credit_card, size: 18), text: 'Kredit'),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              FinanzenBankWidget(
                getData: _getData,
                saveData: _saveData,
                loadData: _loadData,
                isLoading: _isLoading,
                isSaving: _isSaving,
                autoSaveField: _autoSaveField,
                bankenDb: _bankenDb,
                user: widget.user,
                pkontoData: _pkontoData,
                onCreateTicket: (subject, message) async {
                  await widget.ticketService.createTicket(
                    mitgliedernummer: widget.adminMitgliedernummer,
                    subject: subject,
                    message: message,
                    priority: 'high',
                  );
                },
              ),
              FinanzenKreditWidget(
                getData: _getData,
                saveData: _saveData,
                loadData: _loadData,
                isLoading: _isLoading,
                isSaving: _isSaving,
                autoSaveField: _autoSaveField,
                apiService: widget.apiService,
                userId: widget.user.id,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
