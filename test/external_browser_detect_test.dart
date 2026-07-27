import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/external_browser_service.dart';

/// Regression guard for the Online-Termin button on Linux.
///
/// Every launch candidate used to be prefixed with `flatpak-spawn --host`.
/// That binary exists ONLY inside a Flatpak sandbox, so the native /opt build
/// (what runs on the Linux Mint XFCE box over xrdp) threw a ProcessException on
/// each of the seven attempts and reported "Kein Chromium-Browser gefunden" —
/// while /usr/bin/chromium sat there working fine.
void main() {
  final inFlatpak = File('/.flatpak-info').existsSync() ||
      Platform.environment.containsKey('FLATPAK_ID');

  group('ExternalBrowserService browser detection', () {
    test('prefixes with flatpak-spawn only inside a Flatpak sandbox', () async {
      final cmds = await ExternalBrowserService.debugDetectBrowsers();
      for (final cmd in cmds) {
        expect(cmd, isNotEmpty);
        if (inFlatpak) {
          expect(cmd.first, 'flatpak-spawn',
              reason: 'inside the sandbox the host needs flatpak-spawn');
        } else {
          expect(cmd.first, isNot('flatpak-spawn'),
              reason: 'flatpak-spawn does not exist outside the sandbox — '
                  'prefixing it here is what broke Online-Termin');
        }
      }
    }, skip: !Platform.isLinux);

    test('finds the host chromium when one is installed', () async {
      final which = await Process.run('which', ['chromium']);
      if (which.exitCode != 0) {
        return; // no system chromium on this machine — nothing to assert
      }
      final cmds = await ExternalBrowserService.debugDetectBrowsers();
      expect(cmds, isNotEmpty,
          reason: '/usr/bin/chromium exists, so detection must return it');
      expect(cmds.any((c) => c.contains('chromium')), isTrue);
    }, skip: !Platform.isLinux || inFlatpak);

    test('only returns commands whose executable resolves', () async {
      final cmds = await ExternalBrowserService.debugDetectBrowsers();
      for (final cmd in cmds) {
        // Under Flatpak the real executable is the 3rd token
        // (flatpak-spawn --host <bin> ...); natively it is the 1st.
        final bin = cmd.first == 'flatpak-spawn' ? cmd[2] : cmd.first;
        final r = await Process.run('which', [bin]);
        expect(r.exitCode, 0,
            reason: 'detection returned "$bin", which is not on PATH — '
                'a candidate that cannot run burns a full CDP timeout');
      }
    }, skip: !Platform.isLinux || inFlatpak);
  });
}
