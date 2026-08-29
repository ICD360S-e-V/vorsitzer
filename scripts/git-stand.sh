#!/usr/bin/env bash
# Wie weit ist die lokale Arbeitskopie von origin/main entfernt — und welche
# der "geänderten" Dateien sind überhaupt noch echte Arbeit?
#
# ⚠️ Rein lesend. Ändert nichts, löscht nichts, checkt nichts aus.
#
# Warum es das gibt: origin/main läuft hier 10–40 Commits am Tag weiter, die
# Arbeit kommt über PRs herein, die in der Weboberfläche gemergt werden. Die
# lokale Kopie wird davon NIE angefasst — sie fällt zurück, ohne dass etwas
# fehlschlägt. Gleichzeitig bleiben in ihr unfertige Kopien von Arbeit liegen,
# die inzwischen längst gemergt ist. `git status` zeigt dann ein Dutzend
# "geänderte" Dateien, die wie lebende Arbeit aussehen und größtenteils
# veraltete Duplikate sind.
#
# Genau diese Verwechslung hat am 29.08.2026 dazu geführt, dass eine
# vermeintliche Reparatur (`git checkout -- <datei>`) für einen Datenverlust
# gehalten wurde — verloren war nichts, die Arbeit lag längst auf main.
set -u

cd "$(git rev-parse --show-toplevel)" || exit 1
git fetch origin --quiet --prune 2>/dev/null || echo "  (fetch fehlgeschlagen — Stand kann veraltet sein)"

zweig=$(git rev-parse --abbrev-ref HEAD)
vor=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo '?')
hinter=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?')

echo "Zweig: $zweig   —   $vor Commit(s) vor origin/main, $hinter dahinter"
[ "$hinter" != "0" ] && echo "  ⚠️  Zum Bauen eines PR IMMER von origin/main abzweigen, nie von HEAD."
echo

veraltet=0; echt=0
pruefe() {              # $1 = Pfad, $2 = "geaendert" | "neu"
  local f="$1" art="$2"
  if git cat-file -e "origin/main:$f" 2>/dev/null; then
    if diff -q <(git show "origin/main:$f") "$f" >/dev/null 2>&1; then
      printf '  veraltete Kopie   %s\n' "$f"; veraltet=$((veraltet+1)); return
    fi
    local nl nm
    nl=$(diff <(git show "origin/main:$f") "$f" | grep -c '^>')
    nm=$(diff <(git show "origin/main:$f") "$f" | grep -c '^<')
    if [ "$nl" -eq 0 ]; then
      printf '  main ist weiter   %s  (nur dort: %s Zeilen)\n' "$f" "$nm"; veraltet=$((veraltet+1))
    else
      printf '  ECHTE ARBEIT      %s  (nur lokal: %s, nur main: %s)\n' "$f" "$nl" "$nm"; echt=$((echt+1))
    fi
  else
    printf '  ECHTE ARBEIT      %s  (%s, auf main unbekannt)\n' "$f" "$art"; echt=$((echt+1))
  fi
}

echo "Geänderte Dateien:"
git diff --name-only | while read -r f; do pruefe "$f" geaendert; done
echo
echo "Neue Dateien:"
git ls-files --others --exclude-standard | while read -r f; do pruefe "$f" neu; done

echo
echo '⚠️  „veraltete Kopie“ heißt: identisch mit origin/main. Da ist'
echo '    nichts zu retten und nichts zu verlieren — die Datei steht nur'
echo '    deshalb als geändert da, weil HEAD alt ist.'
echo '⚠️  Bevor irgendetwas verworfen wird: scripts/git-sync.sh benutzen. Der'
echo '    sichert vorher. git checkout --, git restore und git clean kennen'
echo '    kein Zurueck.'
