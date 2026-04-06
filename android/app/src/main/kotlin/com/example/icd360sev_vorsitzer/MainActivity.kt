package com.example.icd360sev_vorsitzer

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.Socket

class MainActivity : FlutterActivity() {
    private val CHANNEL = "de.icd360sev.vorsitzer/device_integrity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots and screen recording
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkDeviceIntegrity" -> {
                        val threat = checkDeviceIntegrity()
                        result.success(threat) // null = clean, String = threat reason
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Comprehensive Android root detection (native Kotlin).
     * Returns null if device is clean, or a German reason string if compromised.
     *
     * Safe for GrapheneOS (no false positives).
     */
    private fun checkDeviceIntegrity(): String? {
        return checkSuBinaries()
            ?: checkRootManagers()
            ?: checkKernelSU()
            ?: checkAPatch()
            ?: checkHookingFrameworks()
            ?: checkBuildProperties()
            ?: checkSELinux()
            ?: checkMountInfo()
            ?: checkProcMaps()
            ?: checkFrida()
            ?: checkEmulator()
    }

    // =========================================================================
    // CHECK 1: su binary in known locations (native File.exists - harder to hook)
    // =========================================================================
    private fun checkSuBinaries(): String? {
        val paths = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/data/local/xbin/su", "/data/local/bin/su", "/data/local/su",
            "/system/sd/xbin/su", "/system/bin/failsafe/su", "/su/bin/su",
            "/vendor/bin/su", "/product/bin/su", "/system_ext/bin/su",
            "/odm/bin/su", "/apex/com.android.runtime/bin/su"
        )
        for (path in paths) {
            if (File(path).exists()) return "Root-Zugriff erkannt (su)"
        }
        // Also check via which command
        try {
            val process = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val line = reader.readLine()
            process.waitFor()
            if (!line.isNullOrEmpty()) return "Root-Zugriff erkannt (su in PATH)"
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 2: Root management apps and hiding apps
    // =========================================================================
    private fun checkRootManagers(): String? {
        val paths = arrayOf(
            // SuperSU / Superuser
            "/system/app/Superuser.apk", "/system/app/SuperSU.apk",
            "/data/data/eu.chainfire.supersu",
            "/data/data/com.koushikdutta.superuser",
            "/data/data/com.noshufou.android.su",
            "/data/data/com.noshufou.android.su.elite",
            "/data/data/com.thirdparty.superuser",
            "/data/data/com.yellowes.su",
            // Magisk (standard + Alpha)
            "/data/data/com.topjohnwu.magisk",
            "/data/user/0/com.topjohnwu.magisk",
            "/data/data/io.github.vvb2060.magisk",
            // Magisk data
            "/data/adb/magisk", "/data/adb/magisk.db",
            "/data/adb/magisk/busybox", "/data/adb/magisk/magisk64",
            "/data/adb/magisk/magisk32", "/data/adb/magisk/magiskboot",
            "/data/adb/magisk/magiskinit",
            "/sbin/.magisk", "/cache/.disable_magisk",
            "/dev/.magisk.unblock", "/debug_ramdisk/.magisk",
            // Magisk modules
            "/data/adb/modules",
            // Root hiding apps
            "/data/data/com.amphoras.hidemyroot",
            "/data/data/com.formyhm.hideroot",
            "/data/data/com.zachspong.temprootremovejb",
            "/data/data/com.ramdroid.appquarantine",
            "/data/data/com.tsng.hidemyapplist"
        )
        for (path in paths) {
            try {
                if (File(path).exists()) return "Root-Software erkannt"
            } catch (_: Exception) {}
        }

        // Check installed packages via PackageManager
        val rootPackages = arrayOf(
            "com.topjohnwu.magisk", "io.github.vvb2060.magisk",
            "eu.chainfire.supersu", "com.noshufou.android.su",
            "com.koushikdutta.superuser", "com.thirdparty.superuser",
            "me.weishu.kernelsu", "me.bmax.apatch",
            "com.amphoras.hidemyroot", "com.formyhm.hideroot",
            "de.robv.android.xposed.installer", "org.lsposed.manager",
            "org.meowcat.edxposed.manager"
        )
        val pm = applicationContext.packageManager
        for (pkg in rootPackages) {
            try {
                pm.getPackageInfo(pkg, 0)
                return "Root-Software erkannt ($pkg)"
            } catch (_: Exception) {}
        }

        return null
    }

    // =========================================================================
    // CHECK 3: KernelSU detection (paths + /proc/version + prctl would be ideal)
    // =========================================================================
    private fun checkKernelSU(): String? {
        val paths = arrayOf(
            "/data/adb/ksu", "/data/adb/ksu/modules", "/data/adb/ksud",
            "/data/adb/ksu/ksu.db", "/data/adb/ksu/bin/su",
            "/data/adb/ksu/bin/busybox", "/sys/module/kernelsu"
        )
        for (path in paths) {
            try {
                if (File(path).exists()) return "KernelSU erkannt"
            } catch (_: Exception) {}
        }

        // Check /proc/version for KernelSU string
        try {
            val version = File("/proc/version").readText().lowercase()
            if (version.contains("ksu") || version.contains("kernelsu")) {
                return "KernelSU erkannt (Kernel)"
            }
        } catch (_: Exception) {}

        // Check for ksud process
        try {
            val procDir = File("/proc")
            procDir.listFiles()?.forEach { dir ->
                if (dir.isDirectory && dir.name.toIntOrNull() != null) {
                    try {
                        val cmdline = File("${dir.absolutePath}/cmdline").readText()
                        if (cmdline.contains("ksud")) return "KernelSU erkannt (Daemon)"
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 4: APatch detection
    // =========================================================================
    private fun checkAPatch(): String? {
        val paths = arrayOf(
            "/data/adb/ap", "/data/adb/ap/modules", "/data/adb/apd",
            "/data/adb/ap/package_config", "/data/adb/ap/su_path",
            "/data/adb/ap/bin/su"
        )
        for (path in paths) {
            try {
                if (File(path).exists()) return "APatch erkannt"
            } catch (_: Exception) {}
        }

        // Check for apd process
        try {
            val procDir = File("/proc")
            procDir.listFiles()?.forEach { dir ->
                if (dir.isDirectory && dir.name.toIntOrNull() != null) {
                    try {
                        val cmdline = File("${dir.absolutePath}/cmdline").readText()
                        if (cmdline.contains("apd")) return "APatch erkannt (Daemon)"
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 5: Xposed/LSPosed/EdXposed hooking frameworks
    // =========================================================================
    private fun checkHookingFrameworks(): String? {
        val paths = arrayOf(
            "/system/framework/XposedBridge.jar",
            "/system/bin/app_process.orig",
            "/data/adb/lspd",
            "/data/adb/modules/zygisk_lsposed",
            "/data/adb/modules/riru_lsposed",
            "/data/adb/modules/riru_edxposed"
        )
        for (path in paths) {
            try {
                if (File(path).exists()) return "Hooking-Framework erkannt"
            } catch (_: Exception) {}
        }

        // BusyBox (common on rooted devices)
        val busyboxPaths = arrayOf(
            "/system/xbin/busybox", "/system/bin/busybox",
            "/sbin/busybox", "/data/adb/magisk/busybox",
            "/data/adb/ksu/bin/busybox", "/data/local/bin/busybox"
        )
        for (path in busyboxPaths) {
            try {
                if (File(path).exists()) return "Root-Tools erkannt (BusyBox)"
            } catch (_: Exception) {}
        }

        return null
    }

    // =========================================================================
    // CHECK 6: Build properties
    // GrapheneOS: release-keys, user build, secure=1, not debuggable → safe
    // =========================================================================
    private fun checkBuildProperties(): String? {
        // test-keys
        try {
            val tags = getProp("ro.build.tags")
            if (tags.contains("test-keys")) return "Unsigniertes System erkannt"
        } catch (_: Exception) {}

        // Debuggable build
        try {
            val debuggable = getProp("ro.debuggable")
            if (debuggable == "1") {
                val buildType = getProp("ro.build.type")
                if (buildType == "userdebug" || buildType == "eng") {
                    return "Debug-System erkannt"
                }
            }
        } catch (_: Exception) {}

        // ro.secure should be 1
        try {
            val secure = getProp("ro.secure")
            if (secure == "0") return "Unsicheres System erkannt"
        } catch (_: Exception) {}

        // ADB running as root
        try {
            val adbRoot = getProp("service.adb.root")
            if (adbRoot == "1") return "ADB Root erkannt"
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 7: SELinux (GrapheneOS = Enforcing → safe)
    // =========================================================================
    private fun checkSELinux(): String? {
        // Method 1: getenforce
        try {
            val process = Runtime.getRuntime().exec("getenforce")
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val status = reader.readLine()?.trim()?.lowercase() ?: ""
            process.waitFor()
            if (status == "permissive" || status == "disabled") {
                return "Sicherheitssystem deaktiviert (SELinux)"
            }
        } catch (_: Exception) {}

        // Method 2: sysfs file
        try {
            val enforce = File("/sys/fs/selinux/enforce").readText().trim()
            if (enforce == "0") return "Sicherheitssystem deaktiviert (SELinux)"
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 8: /proc/self/mountinfo (MOST EFFECTIVE against Magisk DenyList)
    // =========================================================================
    private fun checkMountInfo(): String? {
        // Check /proc/self/mounts
        try {
            val mounts = File("/proc/self/mounts").readText().lowercase()
            if (mounts.contains("magisk") || mounts.contains("magiskfs")) {
                return "Root-Zugriff erkannt (Mount)"
            }
            if (mounts.contains("/data/adb/modules")) {
                return "Root-Module erkannt"
            }
        } catch (_: Exception) {}

        // Check /proc/self/mountinfo for overlays
        try {
            val mountInfo = File("/proc/self/mountinfo").readText()
            val lines = mountInfo.split("\n")
            val lower = mountInfo.lowercase()

            if (lower.contains("magisk") || lower.contains("ksu") || lower.contains("ap_modules")) {
                return "Root-Zugriff erkannt (Overlay)"
            }

            // Count suspicious bind mounts on /system
            var bindCount = 0
            for (line in lines) {
                if (line.contains("/system") && line.contains("master:")) {
                    bindCount++
                }
            }
            if (bindCount > 8) return "Root-Zugriff erkannt (Bind-Mounts)"
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 9: /proc/self/maps for injected libraries + debugger check
    // =========================================================================
    private fun checkProcMaps(): String? {
        try {
            val maps = File("/proc/self/maps").readText().lowercase()
            val suspicious = arrayOf(
                "frida", "gadget", "libfrida", "frida-agent",
                "xposed", "edxp", "lsposed", "substrate",
                "libgadget.so", "libc_malloc_debug"
            )
            for (lib in suspicious) {
                if (maps.contains(lib)) return "Hooking-Framework erkannt ($lib)"
            }
        } catch (_: Exception) {}

        // TracerPid check (debugger detection)
        try {
            val status = File("/proc/self/status").readText()
            val regex = Regex("TracerPid:\\s*(\\d+)")
            val match = regex.find(status)
            val tracerPid = match?.groupValues?.get(1)?.toIntOrNull() ?: 0
            if (tracerPid != 0) return "Debugger erkannt"
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 10: Frida detection (port scan + process check + thread names)
    // =========================================================================
    private fun checkFrida(): String? {
        // Check Frida default port
        try {
            val socket = Socket()
            socket.connect(java.net.InetSocketAddress("127.0.0.1", 27042), 500)
            socket.close()
            return "Frida erkannt (Port 27042)"
        } catch (_: Exception) {}

        // Check for frida-server process
        try {
            val procDir = File("/proc")
            procDir.listFiles()?.forEach { dir ->
                if (dir.isDirectory && dir.name.toIntOrNull() != null) {
                    try {
                        val cmdline = File("${dir.absolutePath}/cmdline").readText()
                        if (cmdline.contains("frida") || cmdline.contains("re.frida.server")) {
                            return "Frida erkannt (Prozess)"
                        }
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        // Check thread names for Frida indicators (gmain, gdbus, gum-js-loop)
        try {
            val taskDir = File("/proc/self/task")
            taskDir.listFiles()?.forEach { dir ->
                if (dir.isDirectory) {
                    try {
                        val comm = File("${dir.absolutePath}/comm").readText().trim().lowercase()
                        if (comm == "gmain" || comm == "gdbus" || comm == "gum-js-loop" || comm == "frida") {
                            return "Frida erkannt (Thread)"
                        }
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        return null
    }

    // =========================================================================
    // CHECK 11: Emulator detection
    // =========================================================================
    private fun checkEmulator(): String? {
        val checks = mapOf(
            "ro.hardware" to arrayOf("goldfish", "ranchu", "vbox86"),
            "ro.product.model" to arrayOf("sdk", "emulator", "android sdk"),
            "ro.kernel.qemu" to arrayOf("1"),
            "ro.hardware.chipname" to arrayOf("generic")
        )

        for ((prop, indicators) in checks) {
            try {
                val value = getProp(prop).lowercase()
                for (indicator in indicators) {
                    if (value.contains(indicator)) return "Emulator erkannt"
                }
            } catch (_: Exception) {}
        }

        // QEMU device files
        val emulatorFiles = arrayOf("/dev/qemu_pipe", "/dev/socket/qemud", "/dev/goldfish_pipe")
        for (path in emulatorFiles) {
            if (File(path).exists()) return "Emulator erkannt"
        }

        return null
    }

    // =========================================================================
    // HELPER: Get system property
    // =========================================================================
    private fun getProp(name: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("getprop", name))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val value = reader.readLine()?.trim() ?: ""
            process.waitFor()
            value
        } catch (_: Exception) { "" }
    }
}
