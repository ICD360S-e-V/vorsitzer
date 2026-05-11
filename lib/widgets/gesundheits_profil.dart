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
  bool _showBack = false;

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
          // Body silhouette with swipe rotation
          SizedBox(
            width: 200,
            child: Column(children: [
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    setState(() => _showBack = !_showBack);
                  }
                },
                onTap: () => setState(() => _showBack = !_showBack),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    final rotate = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
                    return ScaleTransition(scale: rotate, child: FadeTransition(opacity: animation, child: child));
                  },
                  child: Container(
                    key: ValueKey(_showBack),
                    width: 180,
                    height: 380,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Stack(children: [
                      CustomPaint(size: const Size(180, 380), painter: _BodyPainter(isMale: isMale, showBack: _showBack)),
                      Positioned(top: 8, right: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.rotate_left, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text(_showBack ? 'Rücken' : 'Vorne', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                        ]),
                      )),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('← Wischen oder Tippen zum Drehen →', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
              const SizedBox(height: 6),
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
              const SizedBox(height: 8),
              _buildGesundheitsCriteria(bmi, age, isMale),
              const SizedBox(height: 12),
            ],
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600))),
          ])),
        ],
      ),
    );
  }

  Widget _buildGesundheitsCriteria(double bmi, int age, bool isMale) {
    // Optimal BMI ranges by age and gender
    double optMin, optMax;
    if (isMale) {
      if (age < 25) { optMin = 19; optMax = 24; }
      else if (age < 35) { optMin = 20; optMax = 25; }
      else if (age < 45) { optMin = 21; optMax = 26; }
      else if (age < 55) { optMin = 22; optMax = 27; }
      else if (age < 65) { optMin = 23; optMax = 28; }
      else { optMin = 24; optMax = 29; }
    } else {
      if (age < 25) { optMin = 18; optMax = 23; }
      else if (age < 35) { optMin = 19; optMax = 24; }
      else if (age < 45) { optMin = 20; optMax = 25; }
      else if (age < 55) { optMin = 21; optMax = 26; }
      else if (age < 65) { optMin = 22; optMax = 27; }
      else { optMin = 23; optMax = 28; }
    }

    final kg = double.tryParse(_gewichtC.text) ?? 0;
    final cm = int.tryParse(_groesseC.text) ?? 0;
    final m = cm / 100.0;
    final idealMin = optMin * m * m;
    final idealMax = optMax * m * m;

    // Broca: Normalgewicht = Größe(cm) - 100; Idealgewicht = Broca - 10%(M) / 15%(W)
    final brocaNormal = (cm - 100).toDouble();
    final brocaIdeal = isMale ? brocaNormal * 0.9 : brocaNormal * 0.85;

    // 10 criteria evaluation
    final criteria = <Map<String, dynamic>>[
      {'name': 'BMI-Klassifikation (WHO)', 'icon': Icons.monitor_weight,
        'status': bmi < 18.5 ? 'gelb' : (bmi <= 24.9 ? 'gruen' : (bmi <= 29.9 ? 'gelb' : 'rot')),
        'text': '${bmi.toStringAsFixed(1)} — ${bmi < 18.5 ? 'Untergewicht' : (bmi <= 24.9 ? 'Normalgewicht' : (bmi <= 29.9 ? 'Präadipositas' : (bmi <= 34.9 ? 'Adipositas Grad I' : (bmi <= 39.9 ? 'Adipositas Grad II' : 'Adipositas Grad III'))))}'},
      {'name': 'Altersgerechter BMI (${age}J, ${isMale ? "M" : "W"})', 'icon': Icons.cake,
        'status': (bmi >= optMin && bmi <= optMax) ? 'gruen' : ((bmi >= optMin - 2 && bmi <= optMax + 2) ? 'gelb' : 'rot'),
        'text': 'Optimal für ${age}J: BMI ${optMin.toStringAsFixed(0)}–${optMax.toStringAsFixed(0)} | Aktuell: ${bmi.toStringAsFixed(1)}'},
      {'name': 'Idealgewicht nach BMI (${cm} cm)', 'icon': Icons.fitness_center,
        'status': (kg >= idealMin && kg <= idealMax) ? 'gruen' : ((kg >= idealMin - 5 && kg <= idealMax + 5) ? 'gelb' : 'rot'),
        'text': '${idealMin.toStringAsFixed(0)}–${idealMax.toStringAsFixed(0)} kg bei ${cm} cm | Aktuell: ${kg.toStringAsFixed(0)} kg'},
      {'name': 'Broca-Index (${cm} cm)', 'icon': Icons.straighten,
        'status': (kg >= brocaIdeal - 5 && kg <= brocaNormal + 3) ? 'gruen' : ((kg >= brocaIdeal - 10 && kg <= brocaNormal + 10) ? 'gelb' : 'rot'),
        'text': 'Normalgewicht: ${brocaNormal.toStringAsFixed(0)} kg | Ideal: ${brocaIdeal.toStringAsFixed(0)} kg | Aktuell: ${kg.toStringAsFixed(0)} kg'},
      {'name': 'Gewichtsabweichung vom Ideal', 'icon': Icons.trending_flat,
        'status': (kg >= idealMin && kg <= idealMax) ? 'gruen' : ((kg - idealMax).abs() <= 5 || (idealMin - kg).abs() <= 5 ? 'gelb' : 'rot'),
        'text': kg > idealMax ? '+${(kg - idealMax).toStringAsFixed(1)} kg über Ideal bei ${cm} cm' : (kg < idealMin ? '${(idealMin - kg).toStringAsFixed(1)} kg unter Ideal bei ${cm} cm' : 'Im Idealbereich für ${cm} cm')},
      {'name': 'Adipositas-Risiko', 'icon': Icons.warning,
        'status': bmi < 30 ? 'gruen' : (bmi < 35 ? 'gelb' : 'rot'),
        'text': bmi < 25 ? 'Kein erhöhtes Risiko' : (bmi < 30 ? 'Leicht erhöht' : (bmi < 35 ? 'Erhöht (Grad I)' : (bmi < 40 ? 'Hoch (Grad II)' : 'Sehr hoch (Grad III)')))},
      {'name': 'Herz-Kreislauf-Risiko', 'icon': Icons.favorite,
        'status': bmi <= 25 ? 'gruen' : (bmi <= 30 ? 'gelb' : 'rot'),
        'text': '${kg.toStringAsFixed(0)} kg bei ${cm} cm → ${bmi <= 25 ? 'Normales Risiko' : (bmi <= 30 ? 'Leicht erhöht' : 'Deutlich erhöht')}'},
      {'name': 'Diabetes-Typ-2-Risiko', 'icon': Icons.bloodtype,
        'status': bmi < 25 ? 'gruen' : (bmi < 30 ? 'gelb' : 'rot'),
        'text': bmi < 25 ? 'Normales Risiko' : (bmi < 30 ? 'Erhöhtes Risiko' : 'Stark erhöhtes Risiko')},
      {'name': 'Gelenkbelastung (Knie, Hüfte)', 'icon': Icons.accessibility_new,
        'status': bmi < 25 ? 'gruen' : (bmi < 30 ? 'gelb' : 'rot'),
        'text': bmi < 25 ? 'Normale Belastung' : (bmi < 30 ? 'Erhöhte Belastung (${(kg - idealMax).toStringAsFixed(0)} kg Mehrgewicht)' : 'Stark erhöht — ${(kg - idealMax).toStringAsFixed(0)} kg über Ideal')},
      {'name': age >= 65 ? 'Altersempfehlung 65+ (DGE)' : 'Stoffwechsel-Indikator', 'icon': age >= 65 ? Icons.elderly : Icons.local_fire_department,
        'status': age >= 65
          ? ((bmi >= 22 && bmi <= 27) ? 'gruen' : ((bmi >= 20 && bmi <= 29) ? 'gelb' : 'rot'))
          : ((bmi >= 18.5 && bmi <= 27) ? 'gruen' : ((bmi >= 16 && bmi <= 30) ? 'gelb' : 'rot')),
        'text': age >= 65
          ? (bmi >= 22 && bmi <= 27 ? 'Im empfohlenen Bereich für 65+ (DGE: BMI 22–27)' : 'DGE empfiehlt BMI 22–27 für Senioren')
          : (bmi < 18.5 ? 'Mögliche Unterversorgung' : (bmi <= 27 ? 'Ausgewogener Stoffwechsel' : 'Belasteter Stoffwechsel'))},
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Gesundheits-Check (Gewicht ↔ Größe ↔ Alter ↔ Geschlecht)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 4),
      Text('Bewertung basiert auf dem Verhältnis: ${kg.toStringAsFixed(0)} kg bei ${cm} cm, ${age} Jahre, ${isMale ? "männlich" : "weiblich"}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      const SizedBox(height: 8),
      ...criteria.map((c) {
        final status = c['status'] as String;
        final color = status == 'gruen' ? Colors.green : (status == 'gelb' ? Colors.orange : Colors.red);
        final icon = status == 'gruen' ? Icons.check_circle : (status == 'gelb' ? Icons.warning : Icons.cancel);
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: color.shade200)),
          child: Row(children: [
            Icon(icon, size: 16, color: color.shade700),
            const SizedBox(width: 8),
            Icon(c['icon'] as IconData, size: 14, color: color.shade600),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800)),
              Text(c['text'] as String, style: TextStyle(fontSize: 10, color: color.shade700)),
            ])),
          ]),
        );
      }),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Hinweis: Diese Auswertung basiert auf BMI-Richtwerten der WHO und DGE. '
            'Sie ersetzt keine ärztliche Diagnose. Individuelle Faktoren (Muskelmasse, '
            'Körperbau, Gesundheitszustand) werden nicht berücksichtigt.',
            style: TextStyle(fontSize: 9, color: Colors.blue.shade800, height: 1.3),
          )),
        ]),
      ),
    ]);
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
  final bool showBack;
  _BodyPainter({required this.isMale, this.showBack = false});

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

    if (showBack) {
      // Spine line
      final spine = Paint()..color = (isMale ? Colors.blue : Colors.pink).shade400..strokeWidth = 2..style = PaintingStyle.stroke;
      final spinePath = Path();
      spinePath.moveTo(cx, neckY + 5);
      spinePath.cubicTo(cx - 2, waistY * 0.6, cx + 2, waistY * 0.8, cx, waistY);
      spinePath.lineTo(cx, hipY - 5);
      canvas.drawPath(spinePath, spine);
      // Vertebrae dots
      for (double y = neckY + 15; y < hipY - 10; y += 14) {
        canvas.drawCircle(Offset(cx, y), 2.5, Paint()..color = (isMale ? Colors.blue : Colors.pink).shade300);
      }
      // Scapula lines
      final scap = Paint()..color = (isMale ? Colors.blue : Colors.pink).shade300..strokeWidth = 1.5..style = PaintingStyle.stroke;
      canvas.drawArc(Rect.fromCenter(center: Offset(cx - 25, shoulderY + 15), width: 30, height: 20), -0.5, 2, false, scap);
      canvas.drawArc(Rect.fromCenter(center: Offset(cx + 25, shoulderY + 15), width: 30, height: 20), 1.6, 2, false, scap);
    } else {
      // Front details - chest line
      final detail = Paint()..color = (isMale ? Colors.blue : Colors.pink).shade300..strokeWidth = 1..style = PaintingStyle.stroke;
      // Navel
      canvas.drawCircle(Offset(cx, waistY - 10), 3, detail);
      if (!isMale) {
        // Chest curves for female
        canvas.drawArc(Rect.fromCenter(center: Offset(cx - 15, shoulderY + 25), width: 22, height: 16), 0.3, 2.5, false, detail);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx + 15, shoulderY + 25), width: 22, height: 16), 0.3, 2.5, false, detail);
      } else {
        // Pectoral lines for male
        canvas.drawArc(Rect.fromCenter(center: Offset(cx - 18, shoulderY + 18), width: 28, height: 10), 0.2, 2.6, false, detail);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx + 18, shoulderY + 18), width: 28, height: 10), 0.2, 2.6, false, detail);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) => oldDelegate.isMale != isMale || oldDelegate.showBack != showBack;
}
