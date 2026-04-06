class User {
  final int id;
  final String mitgliedernummer;
  final String email;
  final String name;
  final String? vorname;
  final String? vorname2;
  final String? nachname;
  final String? geburtsdatum;
  final String? geburtsort;
  final String? staatsangehoerigkeit;
  final String? muttersprache;
  final String? strasse;
  final String? hausnummer;
  final String? plz;
  final String? ort;
  final String? bundesland;
  final String? land;
  final String? geschlecht;
  final String? familienstand;
  final String? telefonMobil;
  final String? telefonFix;
  final String status;
  final String role;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final DateTime? mitgliedschaftDatum;
  final String? mitgliedsart;
  final String? zahlungsmethode;
  final int? zahlungstag;
  final DateTime? deactivatedAt;
  final String? deactivationReason;

  User({
    required this.id,
    required this.mitgliedernummer,
    required this.email,
    required this.name,
    this.vorname,
    this.vorname2,
    this.nachname,
    this.geburtsdatum,
    this.geburtsort,
    this.staatsangehoerigkeit,
    this.muttersprache,
    this.strasse,
    this.hausnummer,
    this.plz,
    this.ort,
    this.bundesland,
    this.land,
    this.geschlecht,
    this.familienstand,
    this.telefonMobil,
    this.telefonFix,
    required this.status,
    required this.role,
    this.createdAt,
    this.lastLogin,
    this.mitgliedschaftDatum,
    this.mitgliedsart,
    this.zahlungsmethode,
    this.zahlungstag,
    this.deactivatedAt,
    this.deactivationReason,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id'].toString()) ?? 0),
      mitgliedernummer: json['mitgliedernummer'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      vorname: json['vorname'],
      vorname2: json['vorname2'],
      nachname: json['nachname'],
      geburtsdatum: json['geburtsdatum'],
      geburtsort: json['geburtsort'],
      staatsangehoerigkeit: json['staatsangehoerigkeit'],
      muttersprache: json['muttersprache'],
      strasse: json['strasse'],
      hausnummer: json['hausnummer'],
      plz: json['plz'],
      ort: json['ort'],
      bundesland: json['bundesland'],
      land: json['land'],
      geschlecht: json['geschlecht'],
      familienstand: json['familienstand'],
      telefonMobil: json['telefon_mobil'],
      telefonFix: json['telefon_fix'],
      status: json['status'] ?? 'active',
      role: json['role'] ?? 'vorsitzer',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      lastLogin: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'])
          : null,
      mitgliedschaftDatum: json['mitgliedschaft_datum'] != null
          ? DateTime.tryParse(json['mitgliedschaft_datum'])
          : null,
      mitgliedsart: json['mitgliedsart'],
      zahlungsmethode: json['zahlungsmethode'],
      zahlungstag: json['zahlungstag'] != null ? int.tryParse(json['zahlungstag'].toString()) : null,
      deactivatedAt: json['deactivated_at'] != null
          ? DateTime.tryParse(json['deactivated_at'])
          : null,
      deactivationReason: json['deactivation_reason'],
    );
  }

  bool get isNichtVerifiziert => status == 'nicht_verifiziert';
  bool get isActive => status == 'active';
  bool get isNeu => status == 'neu';
  bool get isPassiv => status == 'passiv';
  bool get isRuhend => status == 'ruhend';
  bool get isGesperrt => status == 'gesperrt' || status == 'suspended';
  bool get isSuspended => status == 'suspended' || status == 'gesperrt';
  bool get isDeleted => status == 'deleted';
  bool get isGekuendigt => status == 'gekuendigt' || status == 'gekuendigt_selbst' || status == 'gekuendigt_verein';
  bool get isAusgeschlossen => status == 'ausgeschlossen';
  bool get isVerstorben => status == 'verstorben';
  bool get isVorsitzer => role == 'vorsitzer';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mitgliedernummer': mitgliedernummer,
      'email': email,
      'name': name,
      'vorname': vorname,
      'vorname2': vorname2,
      'nachname': nachname,
      'geburtsdatum': geburtsdatum,
      'geburtsort': geburtsort,
      'staatsangehoerigkeit': staatsangehoerigkeit,
      'muttersprache': muttersprache,
      'strasse': strasse,
      'hausnummer': hausnummer,
      'plz': plz,
      'ort': ort,
      'bundesland': bundesland,
      'land': land,
      'geschlecht': geschlecht,
      'familienstand': familienstand,
      'telefon_mobil': telefonMobil,
      'telefon_fix': telefonFix,
      'status': status,
      'role': role,
      'created_at': createdAt?.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
      'mitgliedschaft_datum': mitgliedschaftDatum?.toIso8601String(),
      'mitgliedsart': mitgliedsart,
      'zahlungsmethode': zahlungsmethode,
      'zahlungstag': zahlungstag,
      'deactivated_at': deactivatedAt?.toIso8601String(),
      'deactivation_reason': deactivationReason,
    };
  }

  User copyWith({
    int? id,
    String? mitgliedernummer,
    String? email,
    String? name,
    String? vorname,
    String? vorname2,
    String? nachname,
    String? geburtsdatum,
    String? geburtsort,
    String? staatsangehoerigkeit,
    String? muttersprache,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? bundesland,
    String? land,
    String? geschlecht,
    String? familienstand,
    String? telefonMobil,
    String? telefonFix,
    String? status,
    String? role,
    DateTime? createdAt,
    DateTime? lastLogin,
    DateTime? mitgliedschaftDatum,
    String? mitgliedsart,
    String? zahlungsmethode,
    int? zahlungstag,
    DateTime? deactivatedAt,
    String? deactivationReason,
  }) {
    return User(
      id: id ?? this.id,
      mitgliedernummer: mitgliedernummer ?? this.mitgliedernummer,
      email: email ?? this.email,
      name: name ?? this.name,
      vorname: vorname ?? this.vorname,
      vorname2: vorname2 ?? this.vorname2,
      nachname: nachname ?? this.nachname,
      geburtsdatum: geburtsdatum ?? this.geburtsdatum,
      geburtsort: geburtsort ?? this.geburtsort,
      staatsangehoerigkeit: staatsangehoerigkeit ?? this.staatsangehoerigkeit,
      muttersprache: muttersprache ?? this.muttersprache,
      strasse: strasse ?? this.strasse,
      hausnummer: hausnummer ?? this.hausnummer,
      plz: plz ?? this.plz,
      ort: ort ?? this.ort,
      bundesland: bundesland ?? this.bundesland,
      land: land ?? this.land,
      geschlecht: geschlecht ?? this.geschlecht,
      familienstand: familienstand ?? this.familienstand,
      telefonMobil: telefonMobil ?? this.telefonMobil,
      telefonFix: telefonFix ?? this.telefonFix,
      status: status ?? this.status,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      mitgliedschaftDatum: mitgliedschaftDatum ?? this.mitgliedschaftDatum,
      mitgliedsart: mitgliedsart ?? this.mitgliedsart,
      zahlungsmethode: zahlungsmethode ?? this.zahlungsmethode,
      zahlungstag: zahlungstag ?? this.zahlungstag,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      deactivationReason: deactivationReason ?? this.deactivationReason,
    );
  }
}
