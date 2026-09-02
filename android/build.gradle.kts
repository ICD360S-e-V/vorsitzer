allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// ⚠️ AGP 9 macht aus einer Warnung einen FEHLER: ein Plugin darf nicht gegen
// ein aelteres compileSdk uebersetzen als das, was seine androidx-Abhaengigkeiten
// verlangen. `flutter_ringtone_player` steht auf android-33.
//
// ⚠️ Muss VOR `evaluationDependsOn(":app")` stehen und in `afterEvaluate`:
// frueher ist das Plugin noch nicht ausgewertet, spaeter wirft Gradle
// "Cannot run Project.afterEvaluate when the project is already evaluated".
//
// ⚠️ NUR dieses eine Plugin. Ein flaechendeckendes compileSdk ueber alle
// Subprojekte liess file_picker und workmanager keine Klassen mehr erzeugen.
val pluginsMitZuAltemCompileSdk = setOf("flutter_ringtone_player")

subprojects {
    if (name in pluginsMitZuAltemCompileSdk) {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
                ?.compileSdk = 37
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    project.plugins.whenPluginAdded {
        if (this is com.android.build.gradle.LibraryPlugin) {
            val androidExt = project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
            if (androidExt.namespace.isNullOrEmpty()) {
                val manifest = project.file("src/main/AndroidManifest.xml")
                if (manifest.exists()) {
                    val pkg = Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
                    if (!pkg.isNullOrEmpty()) {
                        androidExt.namespace = pkg
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
