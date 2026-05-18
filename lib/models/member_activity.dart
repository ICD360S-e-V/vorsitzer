/// Per-member activity flags for the "Diese Woche" indicator strip in
/// Mitgliederverwaltung. Each flag is true when the member has at least
/// one item of that kind active in the current calendar week.
class MemberActivity {
  final bool hasTermin;
  final bool hasTicket;
  final bool hasRoutine;

  const MemberActivity({
    this.hasTermin = false,
    this.hasTicket = false,
    this.hasRoutine = false,
  });

  static const empty = MemberActivity();
}
