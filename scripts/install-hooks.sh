#!/usr/bin/env bash
# Aktiviert den pre-commit-Hook (gitleaks) für diese Klone.
#
#   ./scripts/install-hooks.sh        einmal pro Klon
#
# ⚠️ WARUM ES DIESE DATEI GIBT
#
# Daneben liegt install-hooks.ps1 — PowerShell, also Windows. Auf einem
# Linux-Rechner gab es keinen Weg, und die Folge war nicht etwa eine
# Fehlermeldung, sondern Stille: `core.hooksPath` blieb ungesetzt, der Hook
# lief nie, und jeder Commit ging ungeprüft durch. In einem ÖFFENTLICHEN Repo,
# in das über aufgezeichnete Antworten schon dreimal Zugangsdaten geraten sind.
#
# ⚠️ Und selbst mit gesetztem hooksPath wurde der Hook auf Linux übergangen:
# `.githooks/pre-commit` lag mit Modus 644 im Index. Git meldet das nur als
# `hint:` und committet weiter. Der Modus ist jetzt 755 im Index
# (`git update-index --chmod=+x`), damit jede frische Klone und jeder
# `git worktree` ihn ausführbar bekommt — auf Windows ist das Bit
# bedeutungslos, dort ändert sich nichts.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks fehlt. Installieren:"
  echo "  Debian/Ubuntu/Mint:  sudo apt install gitleaks"
  echo "  oder Binärdatei:     https://github.com/gitleaks/gitleaks/releases"
  echo "  macOS:               brew install gitleaks"
  echo
  echo "Danach nochmal: ./scripts/install-hooks.sh"
  exit 1
fi
echo "gitleaks: $(command -v gitleaks) ($(gitleaks version 2>/dev/null || echo '?'))"

chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
echo "core.hooksPath = $(git config --get core.hooksPath)"

# ⚠️ Gegenprobe statt Zusicherung. Ein Hook, der nur „eingerichtet" gemeldet
# wird, ist genau der Zustand, aus dem dieses Problem entstanden ist.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
probe=".hook_selbsttest_$$.txt"
# ⚠️ Das Testgeheimnis wird ZUR LAUFZEIT zusammengesetzt. Stünde es hier als
# zusammenhängende Zeichenkette, bliebe diese Datei selbst an gitleaks hängen
# und liesse sich nicht committen — beim ersten Versuch genau so passiert.
teil_a="gh"; teil_b="p_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
printf '%s%s\n' "$teil_a" "$teil_b" > "$probe"
git add -- "$probe"
if git -c user.name=selbsttest -c user.email=selbsttest@local \
       commit -q -m "hook-selbsttest" >/dev/null 2>&1; then
  git reset -q --soft HEAD~1
  git restore --staged -- "$probe" 2>/dev/null || true
  rm -f -- "$probe"
  echo "❌ Der Hook hat ein Testgeheimnis DURCHGELASSEN — er wirkt nicht."
  exit 1
fi
git restore --staged -- "$probe" 2>/dev/null || true
rm -f -- "$probe"
echo "✅ Selbsttest bestanden: ein Testgeheimnis wird blockiert."
echo
echo "Notausgang (NIE für echte Geheimnisse):  git commit --no-verify"
