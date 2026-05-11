import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GesundheitsProfilTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String vorname;
  final String nachname;
  final String geschlecht;
  final String geburtsdatum;

  const GesundheitsProfilTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vorname,
    required this.nachname,
    required this.geschlecht,
    required this.geburtsdatum,
  });

  @override
  State<GesundheitsProfilTab> createState() => _GesundheitsProfilTabState();
}

class _GesundheitsProfilTabState extends State<GesundheitsProfilTab> {
  final _gewichtC = TextEditingController();
  final _groesseC = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gewichtC.dispose();
    _groesseC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.getGesundheitsProfil(widget.userId);
      if (res['success'] == true) {
        _gewichtC.text = res['gewicht_kg']?.toString() ?? '';
        _groesseC.text = res['groesse_cm']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await widget.apiService.saveGesundheitsProfil(widget.userId, {
      'gewicht_kg': double.tryParse(_gewichtC.text) ?? 0,
      'groesse_cm': int.tryParse(_groesseC.text) ?? 0,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
  }

  int _calcAge() {
    if (widget.geburtsdatum.isEmpty) return 0;
    try {
      DateTime birth;
      if (widget.geburtsdatum.contains('-')) {
        birth = DateTime.parse(widget.geburtsdatum);
      } else if (widget.geburtsdatum.contains('.')) {
        final p = widget.geburtsdatum.split('.');
        birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      } else {
        return 0;
      }
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
      return age;
    } catch (_) {
      return 0;
    }
  }

  double _calcBmi() {
    final kg = double.tryParse(_gewichtC.text) ?? 0;
    final cm = int.tryParse(_groesseC.text) ?? 0;
    if (kg <= 0 || cm <= 0) return 0;
    final m = cm / 100.0;
    return kg / (m * m);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final isMale = widget.geschlecht == 'M';
    final age = _calcAge();
    final bmi = _calcBmi();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body silhouette
          SizedBox(
            width: 200,
            child: Column(children: [
              Container(
                width: 180,
                height: 380,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: CustomPaint(painter: _BodyPainter(isMale: isMale)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: isMale ? Colors.blue.shade50 : Colors.pink.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isMale ? Icons.male : Icons.female, size: 18, color: isMale ? Colors.blue.shade700 : Colors.pink.shade700),
                  const SizedBox(width: 4),
                  Text(isMale ? 'Männlich' : 'Weiblich', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isMale ? Colors.blue.shade700 : Colors.pink.shade700)),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: 24),
          // Info + fields
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Gesundheitsprofil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
            const SizedBox(height: 16),
            _infoCard(Icons.person, 'Vorname', widget.vorname),
            _infoCard(Icons.person_outline, 'Nachname', widget.nachname),
            _infoCard(Icons.cake, 'Alter', age > 0 ? '$age Jahre' : 'Unbekannt'),
            _infoCard(isMale ? Icons.male : Icons.female, 'Geschlecht', isMale ? 'Männlich' : 'Weiblich'),
            const SizedBox(height: 16),
            Text('Körperdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _gewichtC, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Gewicht (kg)', isDense: true, prefixIcon: const Icon(Icons.monitor_weight, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                onChanged: (_) => setState(() {}))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _groesseC, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Größe (cm)', isDense: true, prefixIcon: const Icon(Icons.height, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                onChanged: (_) => setState(() {}))),
            ]),
            const SizedBox(height: 12),
            if (bmi > 0) ...[
              _buildBmiCard(bmi),
              const SizedBox(height: 12),
            ],
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600))),
          ])),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.teal.shade700), const SizedBox(width: 10),
        Text('$label:', style: TextStyle(fontSize: 12, color: Colors.teal.shade600)), const SizedBox(width: 8),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
      ]),
    );
  }

  Widget _buildBmiCard(double bmi) {
    String kategorie;
    Color color;
    if (bmi < 18.5) { kategorie = 'Untergewicht'; color = Colors.blue; }
    else if (bmi < 25) { kategorie = 'Normalgewicht'; color = Colors.green; }
    else if (bmi < 30) { kategorie = 'Übergewicht'; color = Colors.orange; }
    else { kategorie = 'Adipositas'; color = Colors.red; }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
      child: Row(children: [
        Icon(Icons.monitor_weight, size: 20, color: color.shade700),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BMI: ${bmi.toStringAsFixed(1)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800)),
          Text(kategorie, style: TextStyle(fontSize: 11, color: color.shade700)),
        ]),
      ]),
    );
  }
}

// Body silhouette painter
class _BodyPainter extends CustomPainter {
  final bool isMale;
  _BodyPainter({required this.isMale});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isMale ? Colors.blue.shade200 : Colors.pink.shade200
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = isMale ? Colors.blue.shade400 : Colors.pink.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final cx = size.width / 2;
    final headR = size.width * 0.1;
    final headY = size.height * 0.08;

    // Head
    canvas.drawCircle(Offset(cx, headY), headR, paint);
    canvas.drawCircle(Offset(cx, headY), headR, outline);

    // Body path
    final body = Path();
    final shoulderW = isMale ? size.width * 0.35 : size.width * 0.28;
    final waistW = isMale ? size.width * 0.22 : size.width * 0.18;
    final hipW = isMale ? size.width * 0.24 : size.width * 0.30;
    final neckY = headY + headR + 4;
    final shoulderY = size.height * 0.2;
    final waistY = size.height * 0.45;
    final hipY = size.height * 0.55;
    final legEndY = size.height * 0.92;

    // Neck to shoulders
    body.moveTo(cx - 8, neckY);
    body.lineTo(cx - shoulderW, shoulderY);
    // Arms left
    body.lineTo(cx - shoulderW - 15, size.height * 0.42);
    body.lineTo(cx - shoulderW - 10, size.height * 0.42);
    body.lineTo(cx - shoulderW + 5, shoulderY + 10);
    // Torso left
    body.lineTo(cx - waistW, waistY);
    body.lineTo(cx - hipW, hipY);
    // Left leg
    body.lineTo(cx - hipW + 5, legEndY);
    body.lineTo(cx - 5, legEndY);
    body.lineTo(cx - 5, hipY + 10);
    // Right leg
    body.lineTo(cx + 5, hipY + 10);
    body.lineTo(cx + 5, legEndY);
    body.lineTo(cx + hipW - 5, legEndY);
    // Hip right
    body.lineTo(cx + hipW, hipY);
    body.lineTo(cx + waistW, waistY);
    // Arms right
    body.lineTo(cx + shoulderW - 5, shoulderY + 10);
    body.lineTo(cx + shoulderW + 10, size.height * 0.42);
    body.lineTo(cx + shoulderW + 15, size.height * 0.42);
    body.lineTo(cx + shoulderW, shoulderY);
    // Neck
    body.lineTo(cx + 8, neckY);
    body.close();

    canvas.drawPath(body, paint);
    canvas.drawPath(body, outline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
