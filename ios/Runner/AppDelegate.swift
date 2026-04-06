import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var blurEffectView: UIVisualEffectView?
    private let CHANNEL = "de.icd360sev.vorsitzer/device_integrity"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Setup Platform Channel for device integrity checks
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)
            channel.setMethodCallHandler { [weak self] (call, result) in
                if call.method == "checkDeviceIntegrity" {
                    let threat = self?.checkDeviceIntegrity()
                    result(threat) // nil = clean, String = threat reason
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        // Listen for screenshot notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ==========================================================================
    // JAILBREAK DETECTION (Native Swift)
    // ==========================================================================

    /// Comprehensive iOS jailbreak detection.
    /// Returns nil if device is clean, or a German reason string if compromised.
    private func checkDeviceIntegrity() -> String? {
        return checkClassicPaths()
            ?? checkRootlessPaths()
            ?? checkSandboxEscape()
            ?? checkForkExecution()
            ?? checkDylibs()
            ?? checkEnvironment()
            ?? checkSymbolicLinks()
    }

    // =========================================================================
    // CHECK 1: Classic jailbreak file paths
    // =========================================================================
    private func checkClassicPaths() -> String? {
        let paths = [
            // App stores
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Installer.app",
            // Substrate / hooking
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/",
            // Binaries
            "/bin/bash",
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/usr/bin/ssh",
            "/usr/libexec/ssh-keysign",
            // APT package manager
            "/etc/apt",
            "/etc/apt/sources.list.d/",
            "/usr/bin/apt",
            // Cydia / jailbreak data
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/private/var/stash",
            "/private/var/tmp/cydia.log",
            "/usr/libexec/cydia/",
            "/var/cache/apt",
            "/var/lib/cydia",
        ]

        let fm = FileManager.default
        for path in paths {
            if fm.fileExists(atPath: path) {
                return "Jailbreak erkannt"
            }
        }
        return nil
    }

    // =========================================================================
    // CHECK 2: Rootless jailbreak paths (Dopamine 2, palera1n - iOS 15-18)
    // =========================================================================
    private func checkRootlessPaths() -> String? {
        let paths = [
            // Dopamine 2 rootless
            "/var/jb",
            "/var/jb/usr/bin/su",
            "/var/jb/Library/",
            "/var/jb/etc/apt",
            "/var/jb/Applications/Sileo.app",
            "/var/jb/Applications/Cydia.app",
            "/var/jb/usr/lib/TweakInject/",
            "/var/jb/basebin/",
            "/var/jb/basebin/jbctl",
            "/var/jb/basebin/launchdhook.dylib",
            "/var/jb/basebin/trustcache",
            "/var/jb/usr/lib/substitute/",
            "/var/jb/usr/lib/libsubstitute.dylib",
            "/var/jb/usr/lib/libellekit.dylib",
            "/var/jb/usr/sbin/sshd",
            // Dopamine preferences
            "/var/mobile/Library/Preferences/com.opa334.dopamine.plist",
            // palera1n
            "/cores/binpack/",
            "/cores/binpack/usr/bin/su",
            "/cores/binpack/usr/sbin/sshd",
            // TrollStore
            "/var/mobile/Library/Preferences/com.opa334.TrollStore.plist",
        ]

        let fm = FileManager.default
        for path in paths {
            if fm.fileExists(atPath: path) {
                return "Jailbreak erkannt (rootless)"
            }
        }

        // Check /private/preboot for jailbreak directories
        let fm2 = FileManager.default
        if let preboot = try? fm2.contentsOfDirectory(atPath: "/private/preboot") {
            for item in preboot {
                let subpath = "/private/preboot/\(item)"
                if let contents = try? fm2.contentsOfDirectory(atPath: subpath) {
                    for sub in contents {
                        if sub.hasPrefix("jb-") || sub == "procursus" || sub == "palera1n" {
                            return "Jailbreak erkannt (preboot)"
                        }
                    }
                }
            }
        }

        return nil
    }

    // =========================================================================
    // CHECK 3: Sandbox escape (write outside sandbox)
    // =========================================================================
    private func checkSandboxEscape() -> String? {
        let testPath = "/private/jb_test_\(Int(Date().timeIntervalSince1970))"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return "Sandbox-Escape erkannt"
        } catch {
            // Cannot write outside sandbox - GOOD
        }

        // Try reading /etc/fstab (modified by jailbreaks)
        if let fstab = try? String(contentsOfFile: "/etc/fstab", encoding: .utf8), !fstab.isEmpty {
            return "Jailbreak erkannt (fstab)"
        }

        return nil
    }

    // =========================================================================
    // CHECK 4: fork() execution (blocked on clean iOS)
    // =========================================================================
    private func checkForkExecution() -> String? {
        // fork() is restricted on sandboxed iOS apps
        let pid = fork()
        if pid >= 0 {
            // fork succeeded - jailbroken!
            if pid > 0 {
                // Parent process - kill the child
                kill(pid, SIGTERM)
            }
            return "Jailbreak erkannt (fork)"
        }
        // fork failed - GOOD, sandbox intact
        return nil
    }

    // =========================================================================
    // CHECK 5: Dynamic library injection detection
    // =========================================================================
    private func checkDylibs() -> String? {
        let suspiciousLibs = [
            "MobileSubstrate", "SubstrateLoader", "SubstrateInserter",
            "CydiaSubstrate", "TweakInject", "ElleKit", "libellekit",
            "substitute", "libsubstitute", "libhooker",
            "frida", "FridaGadget", "libgadget",
            "cycript", "SSLKillSwitch", "Shadow",
        ]

        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            if let imageName = _dyld_get_image_name(i) {
                let name = String(cString: imageName)
                for suspicious in suspiciousLibs {
                    if name.lowercased().contains(suspicious.lowercased()) {
                        return "Hooking-Framework erkannt (\(suspicious))"
                    }
                }
            }
        }

        // Check for hook symbols
        if let _ = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "MSHookFunction") {
            return "Hooking-Framework erkannt (Substrate)"
        }
        if let _ = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "substitute_hook_functions") {
            return "Hooking-Framework erkannt (Substitute)"
        }

        return nil
    }

    // =========================================================================
    // CHECK 6: Environment variables (injection indicators)
    // =========================================================================
    private func checkEnvironment() -> String? {
        let suspiciousVars = [
            "DYLD_INSERT_LIBRARIES",
            "_MSSafeMode",
            "SUBSTRATE_DYLIB",
            "_SubstrateBootstrap",
        ]

        for varName in suspiciousVars {
            if let _ = getenv(varName) {
                return "Hooking-Framework erkannt (\(varName))"
            }
        }

        return nil
    }

    // =========================================================================
    // CHECK 7: Suspicious symbolic links
    // =========================================================================
    private func checkSymbolicLinks() -> String? {
        let symlinkPaths = [
            "/var/lib/undecimus/apt",
            "/Applications",
            "/Library/Ringtones",
            "/Library/Wallpaper",
        ]

        let fm = FileManager.default
        for path in symlinkPaths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let type = attrs[.type] as? FileAttributeType,
                   type == .typeSymbolicLink {
                    return "Jailbreak erkannt (Symlink)"
                }
            }
        }
        return nil
    }

    // ==========================================================================
    // SCREENSHOT PROTECTION (existing)
    // ==========================================================================

    override func applicationWillResignActive(_ application: UIApplication) {
        addBlurEffect()
        super.applicationWillResignActive(application)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        removeBlurEffect()
        super.applicationDidBecomeActive(application)
    }

    @objc private func userDidTakeScreenshot() {
        print("Screenshot detected - content may be protected")
    }

    private func addBlurEffect() {
        guard blurEffectView == nil, let window = self.window else { return }
        let blurEffect = UIBlurEffect(style: .light)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = window.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.tag = 999
        window.addSubview(blurView)
        blurEffectView = blurView
    }

    private func removeBlurEffect() {
        blurEffectView?.removeFromSuperview()
        blurEffectView = nil
    }
}
