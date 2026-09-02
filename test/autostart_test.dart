import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/autostart.dart';

void main() {
  const a = AutoStart(
    appName: 'ICD360S e.V',
    exePfad: '/opt/icd 360/vorsitzer',
    args: ['--autostart'],
  );

  test('Der Dateiname der Autostart-Datei ist klein und ohne Sonderzeichen', () {
    expect(a.desktopDateiName, 'icd360s-e-v.desktop');
  });

  test('Exec= escapt Leerzeichen im Pfad, statt ihn zu zitieren', () {
    final z = a.desktopInhalt.split('\n');
    expect(z, contains(r'Exec=/opt/icd\ 360/vorsitzer --autostart'));
    expect(z, contains('Type=Application'));
    expect(z, contains('Name=ICD360S e.V'));
    // ⚠️ Anfuehrungszeichen waeren hier FALSCH: der Desktop-Entry-Standard
    // kennt sie nicht, GNOME startet dann gar nichts.
    expect(a.desktopInhalt, isNot(contains('Exec="')));
  });

  test('Der Windows-Befehl zitiert den Pfad, sonst frisst ein Leerzeichen ihn auf', () {
    // Ohne Anfuehrungszeichen liest Windows `/opt/icd` als Programm und
    // `360/vorsitzer` als Argument.
    expect(a.windowsBefehl, r'"/opt/icd 360/vorsitzer" --autostart');
  });

  test('Ohne Argumente bleibt kein Leerzeichen am Ende haengen', () {
    const b = AutoStart(appName: 'X', exePfad: '/usr/bin/x');
    expect(b.windowsBefehl, '"/usr/bin/x"');
    expect(b.desktopInhalt, contains('Exec=/usr/bin/x\n'));
  });
}
