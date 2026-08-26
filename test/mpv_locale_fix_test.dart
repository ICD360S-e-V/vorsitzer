@TestOn('linux')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mpv_locale_fix.dart';

/// Liest die aktuelle Locale einer Kategorie: `setlocale(cat, NULL)`.
String _leseLocale(int kategorie) {
  final setlocale = DynamicLibrary.process().lookupFunction<
      Pointer<Utf8> Function(Int32, Pointer<Utf8>),
      Pointer<Utf8> Function(int, Pointer<Utf8>)>('setlocale');
  final p = setlocale(kategorie, nullptr);
  return p == nullptr ? '' : p.toDartString();
}

void main() {
  const lcNumeric = 1; // glibc, bits/locale.h
  const lcTime = 2;

  test('setzt LC_NUMERIC auf C — sonst bricht libmpv mit abort() ab', () {
    // Ausgangslage bewusst auf eine Komma-Locale stellen, also genau das,
    // was ein deutsch eingerichteter Desktop mitbringt.
    final setlocale = DynamicLibrary.process().lookupFunction<
        Pointer<Utf8> Function(Int32, Pointer<Utf8>),
        Pointer<Utf8> Function(int, Pointer<Utf8>)>('setlocale');
    final de = 'de_DE.UTF-8'.toNativeUtf8();
    final gesetzt = setlocale(lcNumeric, de);
    malloc.free(de);
    // Ohne installierte deutsche Locale gibt es nichts zu prüfen.
    if (gesetzt == nullptr) {
      markTestSkipped('de_DE.UTF-8 ist auf diesem Rechner nicht installiert');
      return;
    }
    expect(_leseLocale(lcNumeric), isNot('C'));

    mpvLocaleFix();

    expect(_leseLocale(lcNumeric), 'C');
  });

  test('fasst nur LC_NUMERIC an, nicht LC_TIME', () {
    final vorher = _leseLocale(lcTime);
    mpvLocaleFix();
    expect(_leseLocale(lcTime), vorher);
  });
}
