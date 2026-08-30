# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep MainActivity
-keep class de.icd360sev.vorsitzer.MainActivity { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Flutter WebRTC
-keep class com.cloudwebrtc.webrtc.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep generic signatures (for Gson, etc.)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Google Play Core (referenced by Flutter but not used - GrapheneOS compatible)
-dontwarn com.google.android.play.core.**

# Keep line numbers for crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ─── Vosk + JNA: Namen MÜSSEN erhalten bleiben ──────────────────────────────
#
# 🔴 Ohne diese Regeln startet die Live-Mitschrift im Release-Bau nicht, und
# zwar mit einer Meldung, die auf `org.vosk.LibVosk` zeigt — obwohl dort nichts
# kaputt ist.
#
# Nachgewiesen am ausgelieferten APK 6.174.0:
#   * `libjnidispatch.so` sucht per JNI NACH NAMEN: `peer`, `memory`,
#     `nativeType`, `invoke`, die Klasse `com/sun/jna/Pointer` und
#     `com/sun/jna/Callback$UncaughtExceptionHandler`.
#   * Im APK hatte `com.sun.jna.Pointer` genau EIN Feld, und es hiess `j` —
#     R8 hatte `peer` umbenannt. `com.sun.jna.Structure` fehlte ganz.
#   * `Native.initIDs()` findet das Feld dann nicht, der statische
#     Initialisierer von `com.sun.jna.Native` scheitert, und weil
#     `LibVosk.<clinit>` ihn auslöst (`Native.register(LibVosk.class, "vosk")`),
#     steht am Ende `org.vosk.LibVosk` auf dem Schirm.
#
# ⚠️ Die offizielle JNA-Regel `-keep class com.sun.jna.* { *; }` mit EINEM
# Stern reicht hier nicht: sie deckt nur das oberste Paket, nicht
# `com.sun.jna.ptr` und `com.sun.jna.internal`. Deshalb zwei Sterne.
#
# ⚠️ Und es half nicht, dass R8 die Methodennamen von `LibVosk` behielt: es
# ENTFERNTE 14 der 21 nativen Methoden als unbenutzt. Das allein war harmlos —
# die Ursache lag eine Ebene tiefer, in JNA selbst. Wer hier je aufräumt,
# prüfe das am gebauten APK nach, nicht am Quelltext.
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { *; }
# JNA bringt Verweise auf java.awt mit, das es auf Android nicht gibt.
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
