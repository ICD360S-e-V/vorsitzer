// Test pentru fix-ul de "click pe document deschide viewer in-app"
// (in loc de download la temp + snackbar).
//
// Verifica direct ca FileViewerDialog.showFromBytes deschide un dialog
// pentru un PNG real. Daca asta merge -> click handler-ul din
// _buildBerichtDokumente, care nu face decat sa apeleze aceasta metoda,
// va merge si el.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/file_viewer_dialog.dart';

// 1x1 transparent PNG (minimal valid PNG)
final Uint8List _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('PNG byte stream -> FileViewerDialog opens', (tester) async {
    bool dialogOpened = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return Center(
            child: ElevatedButton(
              key: const Key('btn'),
              onPressed: () async {
                final ok = await FileViewerDialog.showFromBytes(
                  ctx, _onePixelPng, 'phone-call-evidence.png');
                dialogOpened = ok;
              },
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));

    await tester.tap(find.byKey(const Key('btn')));
    await tester.pump();

    // FileViewerDialog should be on the widget tree now
    expect(find.byType(FileViewerDialog), findsOneWidget);
    expect(find.text('phone-call-evidence.png'), findsOneWidget);

    // Close it (Navigator.pop) and verify showFromBytes returned true
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(dialogOpened, isTrue,
      reason: 'showFromBytes should return true for supported file types');
  });

  testWidgets('Unsupported extension -> returns false, no dialog', (tester) async {
    bool dialogOpened = true;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return ElevatedButton(
            key: const Key('btn'),
            onPressed: () async {
              dialogOpened = await FileViewerDialog.showFromBytes(
                ctx, _onePixelPng, 'evidence.xyz');
            },
            child: const Text('open'),
          );
        }),
      ),
    ));

    await tester.tap(find.byKey(const Key('btn')));
    await tester.pumpAndSettle();

    expect(find.byType(FileViewerDialog), findsNothing);
    expect(dialogOpened, isFalse);
  });
}
