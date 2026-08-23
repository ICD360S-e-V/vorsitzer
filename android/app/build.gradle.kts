import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties for release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "de.icd360sev.vorsitzer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "de.icd360sev.vorsitzer"
        minSdk = 29 // WebRTC braucht >=24; 29 = OWASP/MobSF-Sicherheitsuntergrenze (unter Android 10 keine Patches mehr), keiner unserer aktiven Geraete ist darunter
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // MultiDex support for large apps
        multiDexEnabled = true

        // ⚠️ Ohne das hier reicht `--target-platform android-arm64` NICHT.
        //
        // Gemessen an v6.120.12: mit dem Schalter allein kam ein APK von
        // 118 MB heraus, in dem armeabi-v7a und x86_64 weiterhin steckten.
        // Der Schalter steuert nur, fuer welche Architekturen FLUTTER seinen
        // Dart-Code uebersetzt (libapp.so, ~40 MB je Architektur) — die
        // fertig mitgelieferten Bibliotheken der Plugins packt das Android
        // Gradle Plugin unabhaengig davon fuer alles ein, was im Paket liegt:
        // libdartcv (OpenCV, bis 27 MB), libjingle_peerconnection (WebRTC,
        // bis 15 MB), libflutter (bis 12 MB), libpdfium (bis 6 MB).
        //
        // Erst abiFilters wirft die ueberzaehligen wirklich raus. Beides
        // gehoert zusammen: der Schalter spart die Uebersetzungszeit,
        // abiFilters die Paketgroesse.
        //
        // Entscheidung des Users (19.08.2026): 32 Bit faellt weg, alle Geraete
        // des Vereins laufen auf Android 14/15/16 und aufwaerts.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    // ⚠️ ndk.abiFilters allein reicht AUCH nicht. Lokal nachgemessen an einem
    // vollstaendigen Release-Build: damit blieben 22,1 MB uebrig, verteilt auf
    // je fuenf Dateien fuer x86_64 und armeabi-v7a —
    //
    //   15,32 MB  lib/x86_64/libjingle_peerconnection_so.so
    //    6,51 MB  lib/armeabi-v7a/libjingle_peerconnection_so.so
    //    0,27 MB  libdartjni, libdatastore_shared_counter,
    //              libimage_processing_util_jni, libsurface_util_jni
    //
    // Diese kommen als fertige Bibliotheken aus AAR-Abhaengigkeiten (WebRTC,
    // CameraX, DataStore). abiFilters greift dort nicht zuverlaessig; die
    // Ausnahme beim Packen dagegen wirkt unabhaengig davon, woher eine Datei
    // stammt. Beides steht bewusst nebeneinander: abiFilters fuer alles, was
    // wir selbst bauen, die Ausnahme als letzte Instanz vor dem Zippen.
    packaging {
        jniLibs {
            excludes += setOf(
                "lib/x86/**",
                "lib/x86_64/**",
                "lib/armeabi-v7a/**",
            )
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Enable ProGuard/R8 for release builds
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
