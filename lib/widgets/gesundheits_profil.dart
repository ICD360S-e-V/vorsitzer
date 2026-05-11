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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header centered
        Center(child: Text('Gesundheitsprofil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Left: Person info
          SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const SizedBox(height: 40),
            _sideInfo(Icons.person, widget.vorname, isMale),
            _sideInfo(Icons.person_outline, widget.nachname, isMale),
            _sideInfo(Icons.cake, age > 0 ? '$age Jahre' : '—', isMale),
            _sideInfo(isMale ? Icons.male : Icons.female, isMale ? 'Männlich' : 'Weiblich', isMale),
          ])),
          const SizedBox(width: 12),
          // Center: Body
          Expanded(child: Column(children: [
            GestureDetector(
              onHorizontalDragEnd: (details) { if (details.primaryVelocity != null) setState(() => _showBack = !_showBack); },
              onTap: () => setState(() => _showBack = !_showBack),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => ScaleTransition(scale: Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                  child: FadeTransition(opacity: anim, child: child)),
                child: Container(
                  key: ValueKey(_showBack),
                  width: 220,
                  height: 440,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [isMale ? Colors.blue.shade50 : Colors.pink.shade50, Colors.white]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (isMale ? Colors.blue : Colors.pink).shade200),
                  ),
                  child: Stack(children: [
                    CustomPaint(size: const Size(220, 440), painter: _BodyPainter(isMale: isMale, showBack: _showBack)),
                    Positioned(top: 8, left: 0, right: 0, child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: (isMale ? Colors.blue : Colors.pink).shade100.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
                      child: Text(_showBack ? 'Rückenansicht' : 'Vorderansicht', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: (isMale ? Colors.blue : Colors.pink).shade800)),
                    ))),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('← Tippen zum Drehen →', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          ])),
          const SizedBox(width: 12),
          // Right: Body data
          SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 40),
            _sideData(Icons.monitor_weight, 'Gewicht', _gewichtC.text.isNotEmpty ? '${_gewichtC.text} kg' : '—', isMale),
            _sideData(Icons.height, 'Größe', _groesseC.text.isNotEmpty ? '${_groesseC.text} cm' : '—', isMale),
            if (bmi > 0) _sideData(Icons.speed, 'BMI', bmi.toStringAsFixed(1), isMale),
            if (bmi > 0) _sideData(Icons.favorite, 'Status', bmi < 18.5 ? 'Untergewicht' : (bmi < 25 ? 'Normal' : (bmi < 30 ? 'Übergewicht' : 'Adipositas')), isMale,
              statusColor: bmi < 18.5 ? Colors.orange : (bmi < 25 ? Colors.green : (bmi < 30 ? Colors.orange : Colors.red))),
          ])),
        ]),
        const SizedBox(height: 20),
        // Input fields
        Row(children: [
          Expanded(child: TextField(controller: _gewichtC, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Gewicht (kg)', isDense: true, prefixIcon: const Icon(Icons.monitor_weight, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => setState(() {}))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _groesseC, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Größe (cm)', isDense: true, prefixIcon: const Icon(Icons.height, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => setState(() {}))),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 16), label: const Text('Speichern', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600)),
        ]),
        if (bmi > 0) ...[
          const SizedBox(height: 16),
          _buildGesundheitsCriteria(bmi, age, isMale),
        ],
      ]),
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

  Widget _sideInfo(IconData icon, String text, bool isMale) {
    final c = isMale ? Colors.blue : Colors.pink;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade800)),
        const SizedBox(width: 6),
        Icon(icon, size: 14, color: c.shade600),
      ]),
    );
  }

  Widget _sideData(IconData icon, String label, String value, bool isMale, {MaterialColor? statusColor}) {
    final c = statusColor ?? (isMale ? Colors.blue : Colors.pink);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c.shade600),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 9, color: c.shade600)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c.shade800)),
        ]),
      ]),
    );
  }

  Widget _buildBmiCard(double bmi) {
    String kategorie;
    MaterialColor color;
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

// Realistic body silhouette painter
class _BodyPainter extends CustomPainter {
  final bool isMale;
  final bool showBack;
  _BodyPainter({required this.isMale, this.showBack = false});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isMale ? Colors.blue : Colors.pink;
    final skinPaint = Paint()..color = baseColor.shade100..style = PaintingStyle.fill;
    final outlinePaint = Paint()..color = baseColor.shade400..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final detailPaint = Paint()..color = baseColor.shade300..style = PaintingStyle.stroke..strokeWidth = 1.2;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Proportions (head = 1/8 of height)
    final headH = h * 0.09;
    final headW = headH * 0.75;
    final headY = h * 0.06;
    final neckY = headY + headH;
    final shoulderY = h * 0.17;
    final chestY = h * 0.25;
    final waistY = h * 0.38;
    final hipY = h * 0.44;
    final crotchY = h * 0.50;
    final kneeY = h * 0.70;
    final ankleY = h * 0.88;
    final footY = h * 0.93;

    final shoulderW = isMale ? w * 0.38 : w * 0.30;
    final waistW = isMale ? w * 0.20 : w * 0.17;
    final hipW = isMale ? w * 0.22 : w * 0.28;
    final neckW = w * 0.06;

    // Head — oval
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, headY + headH * 0.45), width: headW * 2, height: headH * 1.1), skinPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, headY + headH * 0.45), width: headW * 2, height: headH * 1.1), outlinePaint);

    // Body path with smooth curves
    final body = Path();
    // Left side: neck → shoulder → arm → hand → back to torso → waist → hip → leg → foot
    body.moveTo(cx - neckW, neckY);
    body.quadraticBezierTo(cx - shoulderW * 0.7, shoulderY * 0.95, cx - shoulderW, shoulderY); // neck to shoulder
    // Left arm
    body.quadraticBezierTo(cx - shoulderW - 8, shoulderY + (waistY - shoulderY) * 0.3, cx - shoulderW - 12, waistY * 0.85); // upper arm
    body.quadraticBezierTo(cx - shoulderW - 14, waistY * 0.95, cx - shoulderW - 10, waistY); // elbow
    body.lineTo(cx - shoulderW - 6, hipY * 0.95); // forearm
    body.lineTo(cx - shoulderW - 8, hipY); // hand
    body.lineTo(cx - shoulderW - 2, hipY); // hand width
    body.lineTo(cx - shoulderW + 2, waistY + 5); // back to body
    // Torso left
    body.quadraticBezierTo(cx - waistW - 2, waistY, cx - waistW, waistY); // chest to waist
    body.quadraticBezierTo(cx - hipW + 2, hipY * 0.98, cx - hipW, hipY); // waist to hip
    // Left leg
    body.quadraticBezierTo(cx - hipW + 3, crotchY, cx - hipW + 5, crotchY + 5);
    body.quadraticBezierTo(cx - w * 0.16, kneeY, cx - w * 0.13, kneeY); // thigh to knee
    body.quadraticBezierTo(cx - w * 0.12, (kneeY + ankleY) / 2, cx - w * 0.08, ankleY); // shin
    body.lineTo(cx - w * 0.12, footY); // foot
    body.lineTo(cx - w * 0.02, footY); // foot sole
    body.lineTo(cx - w * 0.02, crotchY + 10);
    // Right leg (mirror)
    body.lineTo(cx + w * 0.02, crotchY + 10);
    body.lineTo(cx + w * 0.02, footY);
    body.lineTo(cx + w * 0.12, footY);
    body.lineTo(cx + w * 0.08, ankleY);
    body.quadraticBezierTo(cx + w * 0.12, (kneeY + ankleY) / 2, cx + w * 0.13, kneeY);
    body.quadraticBezierTo(cx + w * 0.16, kneeY, cx + hipW - 5, crotchY + 5);
    body.quadraticBezierTo(cx + hipW - 3, crotchY, cx + hipW, hipY);
    // Right torso
    body.quadraticBezierTo(cx + hipW - 2, hipY * 0.98, cx + waistW, waistY);
    body.lineTo(cx + shoulderW - 2, waistY + 5);
    body.lineTo(cx + shoulderW + 2, hipY);
    body.lineTo(cx + shoulderW + 8, hipY);
    body.lineTo(cx + shoulderW + 6, hipY * 0.95);
    body.lineTo(cx + shoulderW + 10, waistY);
    body.quadraticBezierTo(cx + shoulderW + 14, waistY * 0.95, cx + shoulderW + 12, waistY * 0.85);
    body.quadraticBezierTo(cx + shoulderW + 8, shoulderY + (waistY - shoulderY) * 0.3, cx + shoulderW, shoulderY);
    body.quadraticBezierTo(cx + shoulderW * 0.7, shoulderY * 0.95, cx + neckW, neckY);
    body.close();

    canvas.drawPath(body, skinPaint);
    canvas.drawPath(body, outlinePaint);

    // Details
    if (showBack) {
      // Spine
      final spinePath = Path();
      spinePath.moveTo(cx, neckY + 5);
      for (double y = neckY + 5; y < hipY; y += 12) {
        canvas.drawCircle(Offset(cx, y), 2, Paint()..color = baseColor.shade300);
      }
      // Spine line
      canvas.drawLine(Offset(cx, neckY + 5), Offset(cx, hipY - 5), detailPaint);
      // Scapula
      canvas.drawArc(Rect.fromCenter(center: Offset(cx - shoulderW * 0.45, chestY), width: shoulderW * 0.5, height: h * 0.06), -0.3, 2.2, false, detailPaint);
      canvas.drawArc(Rect.fromCenter(center: Offset(cx + shoulderW * 0.45, chestY), width: shoulderW * 0.5, height: h * 0.06), 1.2, 2.2, false, detailPaint);
      // Lower back dimples
      canvas.drawCircle(Offset(cx - 8, hipY - 8), 2, detailPaint);
      canvas.drawCircle(Offset(cx + 8, hipY - 8), 2, detailPaint);
    } else {
      // Navel
      canvas.drawCircle(Offset(cx, waistY + 5), 2.5, detailPaint);
      // Abs line
      canvas.drawLine(Offset(cx, chestY + 10), Offset(cx, waistY - 5), Paint()..color = baseColor.shade200..strokeWidth = 0.8);
      if (isMale) {
        // Pectoral
        canvas.drawArc(Rect.fromCenter(center: Offset(cx - shoulderW * 0.35, chestY + 5), width: shoulderW * 0.55, height: h * 0.035), 0.2, 2.5, false, detailPaint);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx + shoulderW * 0.35, chestY + 5), width: shoulderW * 0.55, height: h * 0.035), 0.4, 2.5, false, detailPaint);
      } else {
        // Chest
        canvas.drawArc(Rect.fromCenter(center: Offset(cx - shoulderW * 0.3, chestY + 8), width: shoulderW * 0.45, height: h * 0.045), 0.3, 2.5, false, detailPaint);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx + shoulderW * 0.3, chestY + 8), width: shoulderW * 0.45, height: h * 0.045), 0.3, 2.5, false, detailPaint);
      }
      // Knee caps
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - w * 0.13, kneeY + 3), width: 10, height: 8), detailPaint);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + w * 0.13, kneeY + 3), width: 10, height: 8), detailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) => oldDelegate.isMale != isMale || oldDelegate.showBack != showBack;
}
