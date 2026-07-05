import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/clothing_advice.dart';
import '../services/weather_service.dart';

/// Generates a paper-friendly weekly weather overview PDF for members without
/// a smartphone. Vorsitzer can print or hand out the PDF; each day gets a
/// short weather line, a temperature range, and a plain-language Anziehtipp
/// derived from `computeClothingAdvice`.
Future<void> generateAndShareWeatherPdf({
  required WeatherService service,
}) async {
  final week = service.dailyForecast;
  if (week.isEmpty) return;

  final doc = pw.Document();
  final city = service.currentWeather?.city ?? 'Deiner Region';
  final now = DateTime.now();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 40, 32, 40),
      header: (_) => _pdfHeader(city, now),
      footer: (ctx) => _pdfFooter(ctx),
      build: (_) => [
        pw.SizedBox(height: 8),
        pw.Text(
          'Wetter-Wochenübersicht für Ihre Termine',
          style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 16),
        _weekTable(week),
        pw.SizedBox(height: 20),
        pw.Text(
          'Anziehtipps im Detail',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        ...week.take(7).map((d) => _dayDetailBlock(d, now)),
        pw.SizedBox(height: 12),
        pw.Text(
          'Daten: Bright Sky (DWD) · Open-Meteo · CAMS. '
          'Wetter kann sich ändern — bei starken Warnungen bitte auf Nachrichten hören.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  // printing lets the OS driver handle the actual print dialog / share sheet.
  await Printing.sharePdf(bytes: await doc.save(), filename: 'wetter_woche.pdf');
}

pw.Widget _pdfHeader(String city, DateTime now) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ICD360S e.V. · Wetter-Wochenübersicht',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Text(
            'Stand: ${_dmy(now)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        city,
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
      ),
      pw.Divider(color: PdfColors.grey400, thickness: 0.5),
    ],
  );
}

pw.Widget _pdfFooter(pw.Context ctx) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'ICD360S e.V. · nur zur Information',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
      ),
      pw.Text(
        'Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
      ),
    ],
  );
}

pw.Widget _weekTable(List<DailyForecast> week) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    columnWidths: {
      0: const pw.FlexColumnWidth(1.4),
      1: const pw.FlexColumnWidth(1.0),
      2: const pw.FlexColumnWidth(2.4),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(1.4),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _th('Tag'),
          _th('Wetter'),
          _th('Beschreibung'),
          _th('Min – Max'),
          _th('Regen'),
        ],
      ),
      ...week.take(7).map((d) => pw.TableRow(children: [
            _td(_weekdayLong(d.date)),
            _td(d.icon, big: true),
            _td(d.description),
            _td('${d.tempMin.toStringAsFixed(0)} – ${d.tempMax.toStringAsFixed(0)} °C'),
            _td(d.precipitationSum > 0.5
                ? '${d.precipitationSum.toStringAsFixed(1)} mm'
                : '—'),
          ])),
    ],
  );
}

pw.Widget _dayDetailBlock(DailyForecast d, DateTime today) {
  final isToday = d.date.day == today.day && d.date.month == today.month;
  final advice = computeClothingAdvice(
    apparentTemp: d.tempMax,
    temp: d.tempMax,
    weatherCode: d.weatherCode,
    wind: d.windSpeedMax,
    precipProb:
        d.precipitationSum >= 2 ? 70 : (d.precipitationSum >= 0.5 ? 40 : 0),
    precip: d.precipitationSum / 24,
    durationMinutes: 60,
  );
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      borderRadius: pw.BorderRadius.circular(4),
      color: isToday ? PdfColors.blue50 : null,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${_weekdayLong(d.date)} · ${d.description} · '
          '${d.tempMin.toStringAsFixed(0)}–${d.tempMax.toStringAsFixed(0)} °C',
          style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: isToday ? PdfColors.blue900 : PdfColors.black),
        ),
        pw.SizedBox(height: 4),
        for (final item in advice.items)
          pw.Bullet(
            text: '${item.label}${item.detail != null ? " — ${item.detail}" : ""}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        if (advice.travelNote != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              advice.travelNote!,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.orange900),
            ),
          ),
        if (advice.warning != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              '⚠ ${advice.warning!}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.red900),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _th(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _td(String text, {bool big = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: big ? 14 : 10)),
    );

String _weekdayLong(DateTime d) {
  const names = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
    'Freitag', 'Samstag', 'Sonntag',
  ];
  return '${names[(d.weekday - 1) % 7]} ${_dmy(d)}';
}

String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year}';
