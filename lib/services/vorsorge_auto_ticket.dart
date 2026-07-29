import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'ticket_service.dart';

/// Single source of truth for the automatic Vorsorge reminder tickets that the
/// doctor screens used to create inline from `build()`.
///
/// Why this exists
/// ---------------
/// Every doctor detail screen (Hausarzt, Zahnarzt, HNO, Augenarzt, …) renders
/// the same Vorsorge tab. The old code created the reminder ticket as a side
/// effect of building that tab and stored the "already sent" flag in
/// `_gesundheitData[type]`, i.e. inside the `user_behoerde_data` row of that one
/// doctor. The flag was therefore doctor-scoped while the ticket is
/// member-scoped: opening a member's Zahnarzt tab re-sent every reminder the
/// Hausarzt tab had already sent. Members ended up with 9-10 copies of the same
/// "Neue Vorsorge: …" ticket — one per doctor row that had ever been opened —
/// and 259 such duplicates were deleted from production on 2026-07-26.
///
/// The ledger is keyed per member ([ledgerType], one row for the whole member)
/// and every create goes through `dedupeSubject: true`, so the server refuses a
/// second open ticket with the same subject even if two screens race.
///
/// [planReminders] holds the whole decision; [sync] is only the I/O around it.
class VorsorgeAutoTicket {
  VorsorgeAutoTicket._();

  /// `user_behoerde_data.behoerde_type` of the member-scoped ledger row.
  /// Must also be listed in `$validTypes` of `api/admin/gesundheit_get.php`
  /// and `api/admin/gesundheit_save.php`.
  static const String ledgerType = 'gesundheit_vorsorge_flags';

  /// Sentinel guard used when no previous analysis is on file. The old
  /// Blutanalyse code put `DateTime.now()` in the guard, so the string changed
  /// every day and the reminder re-fired daily (one member collected 29 in a
  /// single day).
  static const String noAnalysisSentinel = 'keine-analyse';

  /// In-memory ledger per member, so several tabs opened in one session do not
  /// each hit the network — and so the UI can read the state synchronously.
  static final Map<int, Map<String, dynamic>> _ledgerCache = {};

  /// Members whose sync is in flight, to keep concurrent tab opens from racing
  /// each other into a double create.
  static final Set<int> _inFlight = {};

  @visibleForTesting
  static void resetCache() {
    _ledgerCache.clear();
    _inFlight.clear();
  }

  /// Whether the ledger already records a reminder for [screeningKey].
  ///
  /// Synchronous read of the cache [sync] fills, so the doctor screens can show
  /// their "Ticket erstellt" badge from build(). False until the first sync for
  /// that member completed.
  static bool wasSent(int userId, String screeningKey) {
    final ledger = _ledgerCache[userId];
    if (ledger == null) return false;
    return _section(ledger, 'age_sent')[screeningKey] == true ||
        _section(ledger, 'frist_sent').containsKey(screeningKey);
  }

  /// The due date the interval reminder was last sent for, or null while none
  /// is on file. Lets the UI say *which* control the ticket covers, so a moved
  /// date reads as "not sent yet" instead of a stale green check.
  static String? fristSentFor(int userId, String screeningKey) {
    final ledger = _ledgerCache[userId];
    if (ledger == null) return null;
    return _section(ledger, 'frist_sent')[screeningKey] as String?;
  }

  /// The appointment date a [VorsorgeTerminSlot] ticket was last sent for, or
  /// null while none is on file. Lets the planner tab show "Ticket erstellt"
  /// next to the slot — and show it going stale the moment the date is moved.
  static String? terminSentFor(int userId, String screeningKey, String slotKey) {
    final ledger = _ledgerCache[userId];
    if (ledger == null) return null;
    return _section(ledger, 'termin_sent')['$screeningKey.$slotKey'] as String?;
  }

  static Map<String, dynamic> _section(Map<String, dynamic> ledger, String name) {
    final raw = ledger[name];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static String _fmtDe(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static String _fmtIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Decides which reminders are due. Pure — no clock, no network.
  ///
  /// [ledger] is not mutated; the returned [VorsorgePlan.ledger] is a copy with
  /// the legacy seeds already folded in.
  @visibleForTesting
  static VorsorgePlan planReminders({
    required List<VorsorgeScreeningSpec> screenings,
    required Map<String, dynamic> ledger,
    required DateTime? geburtsdatum,
    required String? geschlecht,
    required DateTime now,
    Map<String, String> letztesDatumByKey = const {},

    /// Manually chosen next-control date per screening (ISO). Wins over
    /// `letztes_datum + Intervall` — a Schlafapnoe follow-up is set by the
    /// doctor at 6 or 12 months, not at the catalogue's fixed 24.
    Map<String, String> naechsterTerminByKey = const {},

    /// Dates of the screening's [VorsorgeScreeningSpec.terminSlots], as
    /// `screeningKey -> slotKey -> ISO date`.
    Map<String, Map<String, String>> terminDatenByKey = const {},
    Set<String> legacyAgeSent = const {},
    Set<String> legacyFristSent = const {},
  }) {
    final ageSent = _section(ledger, 'age_sent');
    final fristSent = _section(ledger, 'frist_sent');
    final terminSent = _section(ledger, 'termin_sent');
    final planned = <VorsorgePlannedTicket>[];
    var seeded = false;

    if (geburtsdatum == null) {
      return VorsorgePlan._(const [], Map<String, dynamic>.from(ledger), false);
    }
    final alter = now.difference(geburtsdatum).inDays ~/ 365;

    final g = geschlecht?.toLowerCase() ?? '';
    final isFrau = g == 'weiblich' || g == 'w' || g == 'frau';
    final isMann = g == 'männlich' || g == 'm' || g == 'herr';

    for (final s in screenings) {
      if (s.nurFrauen && !isFrau) continue;
      if (s.nurMaenner && !isMann) continue;
      if (alter < s.abAlter) continue;

      final letztes = letztesDatumByKey[s.key] ?? '';
      final manuell = DateTime.tryParse(naechsterTerminByKey[s.key] ?? '');
      final useAlt = s.altersgrenze > 0 && alter >= s.altersgrenze;
      final intervall = useAlt ? s.intervallAlt : s.intervallJung;
      final beschreibung = useAlt ? s.beschreibungAlt : s.beschreibungJung;

      // ── Migration seed ──
      // Before this ledger existed the flags lived on each doctor blob. Adopt
      // them instead of re-sending: without this the first sync after the
      // deploy would send every reminder one final time, and dedupeSubject
      // cannot help once the Vorsitzer has closed the old ticket.
      if (legacyAgeSent.contains(s.key) && ageSent[s.key] != true) {
        ageSent[s.key] = true;
        seeded = true;
      }

      // ── Age eligibility: a lifetime one-off per member ──
      // Skipped while a control date is planned: "Sie haben nun Anspruch" is
      // noise next to an appointment the Vorsitzer has already booked. Not
      // marked as sent, so clearing the date brings the reminder back.
      if (letztes.isEmpty && manuell == null && ageSent[s.key] != true) {
        planned.add(VorsorgePlannedTicket._(
          screeningKey: s.key,
          kind: VorsorgeReminderKind.age,
          subject: 'Neue Vorsorge: ${s.label} (ab ${s.abAlter} Jahren)',
          message: 'Sehr geehrtes Mitglied,\n\n'
              'Sie haben das ${s.abAlter}. Lebensjahr erreicht und haben nun '
              'Anspruch auf folgende Vorsorgeuntersuchung:\n\n'
              '${s.label}\n$beschreibung\n\n'
              'Die Kosten werden von Ihrer Krankenkasse übernommen.\n\n'
              'Mit freundlichen Grüßen',
          priority: 'low',
          scheduledDate: _fmtIso(now),
        ));
      }

      // ── Appointment slots: one ticket per slot per chosen date ──
      // These are real dates somebody booked, so the ticket goes out as soon as
      // the date is entered rather than a month before it.
      for (final slot in s.terminSlots) {
        final ledgerKey = '${s.key}.${slot.key}';
        final datum = (terminDatenByKey[s.key] ?? const {})[slot.key] ?? '';
        final d = datum.isEmpty ? null : DateTime.tryParse(datum);
        if (d == null) {
          // Date cleared: drop the record so re-entering the same date is a new
          // appointment again instead of a silent no-op.
          if (terminSent.remove(ledgerKey) != null) seeded = true;
          continue;
        }
        if (terminSent[ledgerKey] == datum) continue;
        planned.add(VorsorgePlannedTicket._(
          screeningKey: s.key,
          kind: VorsorgeReminderKind.termin,
          terminSlotKey: slot.key,
          // The date belongs in the subject: dedupe_subject only blocks a
          // second *open* ticket with the same text, so without it a moved
          // appointment would be swallowed as a duplicate of the old one.
          subject: '${slot.ticketBetreff} am ${_fmtDe(d)}',
          message: 'Sehr geehrtes Mitglied,\n\n'
              'für Sie wurde folgender Termin eingetragen:\n\n'
              '${slot.label}\n'
              'Datum: ${_fmtDe(d)}\n\n'
              '${slot.beschreibung}\n\n'
              'Mit freundlichen Grüßen',
          priority: 'medium',
          scheduledDate: datum,
          terminDatum: datum,
        ));
      }

      // ── Frist reminder: one per due date, starting a month before ──
      DateTime? naechst = manuell;
      if (naechst == null) {
        if (letztes.isEmpty || intervall <= 0) continue;
        final l = DateTime.tryParse(letztes);
        if (l == null) continue;
        naechst = DateTime(l.year, l.month + intervall, l.day);
      }
      final reminderDate = DateTime(naechst.year, naechst.month - 1, naechst.day);
      if (!now.isAfter(reminderDate)) continue;

      final dueKey = _fmtIso(naechst);
      if (fristSent[s.key] == dueKey) continue;

      // Migration seed: the legacy flag was a plain bool with no due date, and
      // it never re-sent. Adopt it for the due date in effect now.
      if (legacyFristSent.contains(s.key) && !fristSent.containsKey(s.key)) {
        fristSent[s.key] = dueKey;
        seeded = true;
        continue;
      }

      final overdue = now.isAfter(naechst);
      planned.add(VorsorgePlannedTicket._(
        screeningKey: s.key,
        kind: VorsorgeReminderKind.frist,
        // Due date in the subject for the same reason as the slot tickets: a
        // rescheduled control must not look like a duplicate of the old one.
        subject: '${s.label} fällig am ${_fmtDe(naechst)}',
        message: 'Sehr geehrtes Mitglied,\n\n'
            'Ihre nächste Vorsorgeuntersuchung "${s.label}" '
            '${overdue ? 'war' : 'ist'} am ${_fmtDe(naechst)} fällig.\n\n'
            '$beschreibung\n\n'
            'Bitte vereinbaren Sie zeitnah einen Termin.\n\n'
            'Mit freundlichen Grüßen',
        priority: overdue ? 'high' : 'medium',
        scheduledDate: dueKey,
        fristDueKey: dueKey,
      ));
    }

    final next = Map<String, dynamic>.from(ledger)
      ..['age_sent'] = ageSent
      ..['frist_sent'] = fristSent
      ..['termin_sent'] = terminSent;
    return VorsorgePlan._(planned, next, seeded);
  }

  /// Records a sent reminder in [ledger].
  @visibleForTesting
  static void markSent(Map<String, dynamic> ledger, VorsorgePlannedTicket t) {
    switch (t.kind) {
      case VorsorgeReminderKind.age:
        (ledger['age_sent'] as Map)[t.screeningKey] = true;
      case VorsorgeReminderKind.frist:
        (ledger['frist_sent'] as Map)[t.screeningKey] = t.fristDueKey;
      case VorsorgeReminderKind.termin:
        (ledger['termin_sent'] as Map)['${t.screeningKey}.${t.terminSlotKey}'] =
            t.terminDatum;
    }
  }

  /// Creates whatever Vorsorge reminders are due for [userId] and records them
  /// in the member-scoped ledger.
  ///
  /// Safe to call repeatedly and from several screens at once — a no-op once
  /// the ledger says the reminder went out. Call it *after* a load completes,
  /// never from `build()`.
  static Future<void> sync({
    required ApiService apiService,
    required TicketService ticketService,
    required int userId,
    required String memberMitgliedernummer,
    required String adminMitgliedernummer,
    required List<VorsorgeScreeningSpec> screenings,
    required DateTime? geburtsdatum,
    required String? geschlecht,

    /// `letztes_datum` per screening key, as recorded on the doctor blob that
    /// triggered this sync. Missing keys simply mean "nothing on file here".
    Map<String, String> letztesDatumByKey = const {},

    /// Manually chosen next-control date per screening (`naechster_termin` on
    /// the doctor blob). Overrides the catalogue interval.
    Map<String, String> naechsterTerminByKey = const {},

    /// `screeningKey -> slotKey -> ISO date` for the screenings that declare
    /// [VorsorgeScreeningSpec.terminSlots].
    Map<String, Map<String, String>> terminDatenByKey = const {},

    /// Screening keys whose legacy per-doctor flag says the age reminder is
    /// already out (`vorsorge_<key>_age_ticket_sent`).
    Set<String> legacyAgeSent = const {},

    /// Same for the Frist reminder (`vorsorge_<key>_ticket_sent`).
    Set<String> legacyFristSent = const {},
    DateTime? now,
  }) async {
    if (_inFlight.contains(userId)) return;
    _inFlight.add(userId);
    try {
      final loaded = await _loadLedger(apiService, userId);
      final plan = planReminders(
        screenings: screenings,
        ledger: loaded,
        geburtsdatum: geburtsdatum,
        geschlecht: geschlecht,
        now: now ?? DateTime.now(),
        letztesDatumByKey: letztesDatumByKey,
        naechsterTerminByKey: naechsterTerminByKey,
        terminDatenByKey: terminDatenByKey,
        legacyAgeSent: legacyAgeSent,
        legacyFristSent: legacyFristSent,
      );

      final ledger = plan.ledger;
      _ledgerCache[userId] = ledger;
      var dirty = plan.ledgerChanged;

      for (final t in plan.tickets) {
        final ok = await _create(
          ticketService,
          adminMitgliedernummer: adminMitgliedernummer,
          memberMitgliedernummer: memberMitgliedernummer,
          ticket: t,
        );
        if (ok) {
          markSent(ledger, t);
          dirty = true;
        }
      }

      if (dirty) await _saveLedger(apiService, userId, ledger);
    } finally {
      _inFlight.remove(userId);
    }
  }

  static Future<Map<String, dynamic>> _loadLedger(
    ApiService apiService,
    int userId,
  ) async {
    final cached = _ledgerCache[userId];
    if (cached != null) return cached;
    try {
      final result = await apiService.getGesundheitData(userId, ledgerType);
      final data = result['data'];
      final ledger = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      _ledgerCache[userId] = ledger;
      return ledger;
    } catch (_) {
      // A failed load must not cause a re-send storm. Cache the empty ledger so
      // this session stops retrying; dedupeSubject is the remaining backstop.
      final empty = <String, dynamic>{};
      _ledgerCache[userId] = empty;
      return empty;
    }
  }

  static Future<void> _saveLedger(
    ApiService apiService,
    int userId,
    Map<String, dynamic> ledger,
  ) async {
    _ledgerCache[userId] = ledger;
    try {
      await apiService.saveGesundheitData(userId, ledgerType, ledger);
    } catch (_) {
      // Keep the in-memory copy so the session stays de-duplicated even if the
      // write failed.
    }
  }

  /// Creates the ticket with server-side subject de-duplication.
  ///
  /// True when the reminder is on file — whether this call inserted it or the
  /// server reported an existing open one. Both mean "stop asking".
  static Future<bool> _create(
    TicketService ticketService, {
    required String adminMitgliedernummer,
    required String memberMitgliedernummer,
    required VorsorgePlannedTicket ticket,
  }) async {
    try {
      final res = await ticketService.createTicketForMember(
        adminMitgliedernummer: adminMitgliedernummer,
        memberMitgliedernummer: memberMitgliedernummer,
        subject: ticket.subject,
        message: ticket.message,
        priority: ticket.priority,
        scheduledDate: ticket.scheduledDate,
        systemAuto: true,
        dedupeSubject: true,
      );
      return res['ticket'] != null || res['duplicate'] == true;
    } catch (_) {
      return false;
    }
  }
}

enum VorsorgeReminderKind { age, frist, termin }

/// Outcome of [VorsorgeAutoTicket.planReminders].
@immutable
class VorsorgePlan {
  final List<VorsorgePlannedTicket> tickets;

  /// Copy of the input ledger with legacy flags folded in.
  final Map<String, dynamic> ledger;

  /// True when the seeding alone changed the ledger and it needs saving even if
  /// no ticket goes out.
  final bool ledgerChanged;

  const VorsorgePlan._(this.tickets, this.ledger, this.ledgerChanged);
}

@immutable
class VorsorgePlannedTicket {
  final String screeningKey;
  final VorsorgeReminderKind kind;
  final String subject;
  final String message;
  final String priority;
  final String scheduledDate;

  /// Due date this Frist reminder is for; null for age reminders.
  final String? fristDueKey;

  /// Which [VorsorgeTerminSlot] this is for; null unless [kind] is
  /// [VorsorgeReminderKind.termin].
  final String? terminSlotKey;

  /// Appointment date (ISO) of the slot ticket; null for the other kinds.
  final String? terminDatum;

  const VorsorgePlannedTicket._({
    required this.screeningKey,
    required this.kind,
    required this.subject,
    required this.message,
    required this.priority,
    required this.scheduledDate,
    this.fristDueKey,
    this.terminSlotKey,
    this.terminDatum,
  });
}

/// One bookable appointment attached to a screening.
///
/// Schlafapnoe is the case this exists for: the polygraphy device is handed
/// out, checked, returned, and only then are the findings discussed — four
/// dates the member has to show up for, none of which fits the
/// "last exam + interval" model the rest of the catalogue uses.
@immutable
class VorsorgeTerminSlot {
  /// Stable key; the ledger records `<screeningKey>.<slotKey>`, so renaming one
  /// re-sends its ticket.
  final String key;

  /// Shown in the planner and in the ticket body.
  final String label;

  /// Subject prefix; the date is appended by the planner. Carries the screening
  /// name because a ticket list has no dialog title for context.
  final String ticketBetreff;

  /// One line telling the member what the appointment is for.
  final String beschreibung;

  const VorsorgeTerminSlot({
    required this.key,
    required this.label,
    required this.ticketBetreff,
    required this.beschreibung,
  });
}

/// The non-visual half of a screening definition. The doctor screens keep their
/// own records for icon/colour and map them onto this for the ticket logic.
@immutable
class VorsorgeScreeningSpec {
  final String key;
  final String label;
  final bool nurFrauen;
  final bool nurMaenner;
  final int abAlter;
  final int intervallJung;
  final int intervallAlt;

  /// Age at which interval and description switch to the "alt" variant.
  /// 0 means there is no switch.
  final int altersgrenze;
  final String beschreibungJung;
  final String beschreibungAlt;

  /// Appointments this screening can have on top of the interval reminder.
  /// Empty for the plain GKV screenings.
  final List<VorsorgeTerminSlot> terminSlots;

  const VorsorgeScreeningSpec({
    required this.key,
    required this.label,
    required this.nurFrauen,
    required this.nurMaenner,
    required this.abAlter,
    required this.intervallJung,
    required this.intervallAlt,
    required this.altersgrenze,
    required this.beschreibungJung,
    required this.beschreibungAlt,
    this.terminSlots = const [],
  });
}
