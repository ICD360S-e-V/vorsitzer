import 'package:flutter/material.dart';

/// The generic GKV preventive-screening catalogue.
///
/// Shared because the Vorsorge tab renders under every non-specialty doctor
/// (Hausarzt, Zahnarzt, Urologie, Onkologie, Krankenhaus, …) and the entitlement
/// depends on the member's age and sex, not on which doctor is open. HNO and
/// Augenarzt deliberately keep their own specialty catalogues instead.
///
/// Kept as a plain record list so the screens can read `.icon` / `.color` for
/// the UI; [VorsorgeScreeningSpec] carries the same fields minus the visuals for
/// the ticket logic in `services/vorsorge_auto_ticket.dart`.
const gkvVorsorgeScreenings = [
    (key: 'hpv', label: 'Gebärmutterhalskrebs (HPV/Pap)', icon: Icons.health_and_safety, color: Colors.pink, nurFrauen: true, nurMaenner: false, abAlter: 20, intervallJung: 12, intervallAlt: 36, altersgrenze: 35, beschreibungJung: 'Jährlich Pap-Abstrich', beschreibungAlt: 'Alle 3 Jahre Ko-Testung (Pap + HPV)'),
    (key: 'brust', label: 'Brustkrebs-Tastuntersuchung', icon: Icons.favorite, color: Colors.purple, nurFrauen: true, nurMaenner: false, abAlter: 30, intervallJung: 12, intervallAlt: 12, altersgrenze: 0, beschreibungJung: 'Jährlich beim Frauenarzt', beschreibungAlt: 'Jährlich beim Frauenarzt'),
    (key: 'mammographie', label: 'Mammographie-Screening', icon: Icons.monitor_heart, color: Colors.deepPurple, nurFrauen: true, nurMaenner: false, abAlter: 50, intervallJung: 24, intervallAlt: 24, altersgrenze: 0, beschreibungJung: 'Alle 2 Jahre (50–75 J.)', beschreibungAlt: 'Alle 2 Jahre (50–75 J.)'),
    (key: 'hautkrebs', label: 'Hautkrebs-Screening', icon: Icons.wb_sunny, color: Colors.orange, nurFrauen: false, nurMaenner: false, abAlter: 35, intervallJung: 24, intervallAlt: 24, altersgrenze: 0, beschreibungJung: 'Alle 2 Jahre', beschreibungAlt: 'Alle 2 Jahre'),
    (key: 'darmkrebs', label: 'Darmkrebs-Screening', icon: Icons.medical_information, color: Colors.teal, nurFrauen: false, nurMaenner: false, abAlter: 50, intervallJung: 24, intervallAlt: 120, altersgrenze: 55, beschreibungJung: 'Alle 2 Jahre Stuhltest (iFOBT)', beschreibungAlt: 'Alle 10 J. Darmspiegelung oder 2 J. iFOBT'),
    (key: 'prostata', label: 'Prostata-/Genitaluntersuchung', icon: Icons.man, color: Colors.blue, nurFrauen: false, nurMaenner: true, abAlter: 45, intervallJung: 12, intervallAlt: 12, altersgrenze: 0, beschreibungJung: 'Jährlich beim Urologen', beschreibungAlt: 'Jährlich beim Urologen'),
    (key: 'checkup', label: 'Gesundheits-Check-up', icon: Icons.monitor_heart, color: Colors.indigo, nurFrauen: false, nurMaenner: false, abAlter: 35, intervallJung: 36, intervallAlt: 36, altersgrenze: 0, beschreibungJung: 'Alle 3 Jahre beim Hausarzt', beschreibungAlt: 'Alle 3 Jahre beim Hausarzt'),
    (key: 'bauchaorta', label: 'Bauchaortenaneurysma', icon: Icons.bloodtype, color: Colors.red, nurFrauen: false, nurMaenner: true, abAlter: 65, intervallJung: 0, intervallAlt: 0, altersgrenze: 0, beschreibungJung: 'Einmalig ab 65 (Ultraschall)', beschreibungAlt: 'Einmalig ab 65 (Ultraschall)'),
];
