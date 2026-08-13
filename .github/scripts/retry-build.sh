#!/usr/bin/env bash
#
# Wiederholt einen Build-Befehl, wenn er an der Netzwerkanbindung gescheitert
# ist — und NUR dann.
#
# Anlass: am 01.08.2026 riss der Android-Build von v6.89.7 ab, weil
# repo.maven.apache.org auf die Anfrage nach kotlin-stdlib mit
# "429 Too Many Requests" antwortete. Am Code lag es nicht; ein zweiter Anlauf
# lief sauber durch. Flutter hat zwar eine eigene Wiederholung, aber sie wartet
# 100 Millisekunden ("Retrying Gradle Build: #1, wait time: 100ms") — gegen ein
# Ratenlimit ist das wirkungslos.
#
# Bewusst NICHT stumpf alles wiederholen: ein echter Übersetzungsfehler soll
# sofort auffliegen. Würde er dreimal wiederholt, kostete das je Build mehrere
# Minuten und die eigentliche Fehlermeldung stünde ganz oben im Protokoll,
# unter zwei weiteren Fehlschlägen begraben.
#
# Aufruf:  .github/scripts/retry-build.sh flutter build apk --release …
#
# Stellschrauben (Umgebungsvariablen):
#   BUILD_RETRIES        Anzahl Versuche insgesamt (Vorgabe 3)
#   RETRY_BASE_SECONDS   Wartezeit-Schritt, linear (Vorgabe 60 -> 60s, 120s)

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "::error::retry-build.sh ohne Befehl aufgerufen"
  exit 2
fi

MAX="${BUILD_RETRIES:-3}"
BASIS="${RETRY_BASE_SECONDS:-60}"

# Fehlerbilder, bei denen ein weiterer Versuch überhaupt Sinn ergibt: alles,
# was zwischen Runner und Paketspiegel schiefgehen kann. Absichtlich breit —
# eine unnötige Wiederholung kostet Minuten, ein fälschlich roter Build kostet
# einen Menschen, der ihn von Hand neu startet.
#
# ⚠️ Die Liste war bis zum 13.08.2026 auf Gradle und Maven zugeschnitten, weil
# sie aus dem 429-Vorfall entstanden ist. Es gibt aber einen zweiten Weg, auf
# dem ein Build ins Netz greift: die Build-Hooks der Dart-Pakete („native
# assets"). `pdfium_dart` lädt in seinem hook/build.dart eine vorgebaute
# Bibliothek von den GitHub-Releases — und das läuft nicht über Gradle,
# sondern über package:http. Dessen Fehler heißen anders, und keiner davon
# stand hier:
#
#     ClientException: Connection closed before full header was received,
#     uri=https://github.com/bblanchon/pdfium-binaries/releases/download/…/
#         pdfium-android-arm64.tgz
#
# Das war v6.101.1: ein abgerissener Download, vom Skript als Codefehler
# eingestuft und ohne zweiten Anlauf rot gemeldet. Genau der Fall, für den es
# das Skript gibt.
#
# ⚠️ `ClientException` ist bewusst als GANZE Klasse aufgenommen und nicht nur
# der eine Wortlaut: package:http wirft sie ausschließlich für Fehler auf der
# Transportstrecke. Ein Übersetzungsfehler kann sie nicht auslösen — das
# Muster kann also keinen echten Codefehler verschlucken.
NETZFEHLER='Too Many Requests|Could not resolve|Could not GET|Could not HEAD|Could not download|Connection reset|Connection timed out|Read timed out|Premature end of Content-Length|error while downloading artifacts|502 Bad Gateway|503 Service Unavailable|504 Gateway|Gateway Time-out|Temporary failure in name resolution|Network is unreachable|peer not authenticated|Remote host (terminated|closed)|SocketException|Failed to download|ClientException|HandshakeException|HttpException|Connection closed (before|while)'

protokoll="$(mktemp)"
trap 'rm -f "$protokoll"' EXIT

for versuch in $(seq 1 "$MAX"); do
  # tee, damit die Ausgabe wie gewohnt im Actions-Protokoll steht UND
  # durchsuchbar ist. PIPESTATUS[0] ist der Rückgabewert des Builds, nicht der
  # von tee.
  "$@" 2>&1 | tee "$protokoll"
  rc="${PIPESTATUS[0]}"

  if [ "$rc" -eq 0 ]; then
    [ "$versuch" -gt 1 ] && echo "::notice::Build im $versuch. Anlauf erfolgreich."
    exit 0
  fi

  if ! grep -qE "$NETZFEHLER" "$protokoll"; then
    echo "::error::Build fehlgeschlagen (Rückgabewert $rc) — kein Netzwerkfehler erkennbar, deshalb kein weiterer Versuch."
    exit "$rc"
  fi

  if [ "$versuch" -ge "$MAX" ]; then
    echo "::error::Build auch nach $MAX Versuchen an der Netzwerkanbindung gescheitert."
    exit "$rc"
  fi

  warte=$(( versuch * BASIS ))
  echo "::warning::Netzwerkfehler im Build (Versuch $versuch von $MAX) — neuer Anlauf in ${warte}s"
  sleep "$warte"
done
