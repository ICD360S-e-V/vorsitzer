#!/usr/bin/env bash
# Bringt die lokale Arbeitskopie auf origin/main — mit Sicherung vorher.
#
# ⚠️ Dieses Skript ist der Ersatz für `git checkout -- <datei>`,
# `git restore`, `git stash drop` und `git clean`. Jene vier kennen kein
# Zurück; hier liegt vorher alles doppelt.
#
# Was es NICHT tut: es überschreibt keine eigenen Commits und es löscht
# nichts. Alles, was im Weg steht, wird beiseitegelegt, nicht entfernt.
#
# Hintergrund: origin/main läuft hier 10–40 Commits am Tag weiter, die Arbeit
# kommt über PRs herein. Die lokale Kopie wird davon nie angefasst und fällt
# still zurück. Am 29.08.2026 war sie 66 Commits hinterher, und ein Dutzend
# "geänderter" Dateien waren in Wahrheit Duplikate von längst gemergter
# Arbeit — ein Zustand, in dem jede Aufräumaktion nach Datenverlust aussieht.
set -eu

cd "$(git rev-parse --show-toplevel)"
git fetch origin --quiet --prune

vor=$(git rev-list --count origin/main..HEAD)
hinter=$(git rev-list --count HEAD..origin/main)

if [ "$vor" != "0" ]; then
  echo "ABBRUCH: der lokale Zweig hat $vor eigene Commit(s), die nicht auf"
  echo "origin/main sind. Die gehören in einen PR, nicht unter ein"
  echo "Fast-Forward. (git log origin/main..HEAD)"
  exit 1
fi
if [ "$hinter" = "0" ] && [ -z "$(git status --porcelain)" ]; then
  echo "Bereits auf dem Stand von origin/main, Arbeitsbaum sauber. Nichts zu tun."
  exit 0
fi

stempel=$(date +%Y%m%d-%H%M%S)
sicherung=".git/sync-backups/$stempel"
mkdir -p "$sicherung/dateien"

# 1) Alles sichern, bevor irgendetwas angefasst wird.
git diff > "$sicherung/geaenderte-dateien.patch" || true
git status --short > "$sicherung/status.txt"
# shellcheck disable=SC2046
tar czf "$sicherung/arbeitsbaum.tgz" $(git diff --name-only) \
    $(git ls-files --others --exclude-standard) 2>/dev/null || true
echo "Sicherung: $sicherung"

# 2) Verfolgte Änderungen in den Stash — dort bleiben sie in git greifbar.
if [ -n "$(git diff --name-only)" ]; then
  git stash push -m "vor git-sync.sh $stempel" >/dev/null
  echo "Verfolgte Änderungen: git stash list  ->  'vor git-sync.sh $stempel'"
fi

# 3) Neue Dateien, die dem Merge im Weg stehen, beiseitelegen — NICHT löschen.
#    Im Weg steht nur, was es auf origin/main auch gibt.
beiseite=0
while read -r f; do
  [ -z "$f" ] && continue
  if git cat-file -e "origin/main:$f" 2>/dev/null; then
    mkdir -p "$sicherung/dateien/$(dirname "$f")"
    mv "$f" "$sicherung/dateien/$f"
    beiseite=$((beiseite+1))
  fi
done < <(git ls-files --others --exclude-standard)
[ "$beiseite" -gt 0 ] && echo "Beiseitegelegt: $beiseite neue Datei(en) -> $sicherung/dateien/"

# 4) Erst jetzt der Merge, und nur als Fast-Forward.
git merge --ff-only origin/main

echo
echo "Stand: $(git log --oneline -1)"
echo "Version: $(grep -m1 '^version:' pubspec.yaml)"
echo
echo "⚠️  Nichts wurde gelöscht. Wiederherstellen:"
echo "    git stash list                       # verfolgte Änderungen"
echo "    tar xzf $sicherung/arbeitsbaum.tgz   # alles, wie es war"
