/// Per-member activity flags for the "Diese Woche" indicator strip in
/// Mitgliederverwaltung. Each flag is true when the member has at least
/// one item of that kind active in the current calendar week.
class MemberActivity {
  final bool hasTermin;
  final bool hasTicket;
  final bool hasRoutine;
  /// Open urgent ticket exists for this member — used as the Notfall flag.
  /// Notfälle are stored as tickets with `priority == 'urgent'` so we don't
  /// need a separate `notfaelle` table on the server.
  final bool hasNotfall;

  const MemberActivity({
    this.hasTermin = false,
    this.hasTicket = false,
    this.hasRoutine = false,
    this.hasNotfall = false,
  });

  static const empty = MemberActivity();
}
