import AppKit
import ServiceManagement

private enum Pref {
    static let enabled = "enabled"
    static let volume = "volume"
    static let pack = "pack"
    static let tone = "tone"
    static let spatial = "spatial"
    static let mouse = "mouse"
}

private let defaultPack = "Gateron Red"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var engine: SoundEngine?
    private let keyTap = KeyTap()
    private var permissionTimer: Timer?
    private let defaults = UserDefaults.standard

    private var enabled: Bool {
        get { defaults.bool(forKey: Pref.enabled) }
        set { defaults.set(newValue, forKey: Pref.enabled) }
    }
    private var volume: Float {
        get { defaults.float(forKey: Pref.volume) }
        set { defaults.set(newValue, forKey: Pref.volume) }
    }
    private var selectedPack: String {
        get { defaults.string(forKey: Pref.pack) ?? defaultPack }
        set { defaults.set(newValue, forKey: Pref.pack) }
    }
    private var tone: Float {
        get { defaults.float(forKey: Pref.tone) }
        set { defaults.set(newValue, forKey: Pref.tone) }
    }
    private var mouseClicks: Bool {
        get { defaults.bool(forKey: Pref.mouse) }
        set { defaults.set(newValue, forKey: Pref.mouse) }
    }
    private var spatial: Bool {
        get { defaults.bool(forKey: Pref.spatial) }
        set { defaults.set(newValue, forKey: Pref.spatial) }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Pref.enabled: true, Pref.volume: 0.7, Pref.pack: defaultPack,
                                     Pref.tone: 0.0, Pref.spatial: true, Pref.mouse: true])
        try? FileManager.default.createDirectory(at: PackLibrary.userPacksURL, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        do {
            engine = try SoundEngine()
        } catch {
            showError("Clackey couldn't start audio", error)
        }
        engine?.volume = volume
        engine?.tone = tone
        engine?.spatialWidth = spatial ? 0.6 : 0
        engine?.setEnabled(enabled)
        loadPack(named: selectedPack)
        if let url = PackLibrary.mouseSoundsURL {
            engine?.mouseSounds = try? SoundPack(url: url, format: SoundEngine.format, requireKeys: false)
        }

        keyTap.onKey = { [weak self] sound, pan in
            guard let self, self.enabled, self.mouseClicks || !sound.isMouse else { return }
            self.engine?.play(sound, pan: pan)
        }
        startListening()
    }

    /// Creates the key tap, or keeps retrying until Input Monitoring is granted.
    private func startListening() {
        if KeyTap.hasPermission, keyTap.start() {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            KeyTap.requestPermission()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, KeyTap.hasPermission, self.keyTap.start() else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.updateIcon()
                }
            }
        }
        updateIcon()
    }

    private func loadPack(named name: String) {
        let packs = PackLibrary.discover()
        guard let url = packs.first(where: { $0.lastPathComponent == name }) ?? packs.first else {
            showError("No sound packs found", ClackeyError("Expected packs in the app bundle or \(PackLibrary.userPacksURL.path)"))
            return
        }
        do {
            let pack = try SoundPack(url: url, format: SoundEngine.format)
            engine?.load(pack)
            selectedPack = pack.name
        } catch {
            showError("Couldn't load “\(url.lastPathComponent)”", error)
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if keyTap.isRunning {
            button.image = MenuBarIcon.fnKey()
        } else {
            let warning = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Clackey")
            warning?.isTemplate = true
            button.image = warning
        }
        button.appearsDisabled = !enabled
        button.toolTip = !keyTap.isRunning ? "Clackey needs Input Monitoring permission"
            : enabled ? "Clackey: on" : "Clackey: off"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !keyTap.isRunning {
            menu.addItem(item("Grant Input Monitoring…", #selector(openInputMonitoring)))
            menu.addItem(.separator())
        }

        let toggle = item("Sounds On", #selector(toggleEnabled), key: "e")
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(sectionLabel("Volume"))
        menu.addItem(sliderItem(value: volume, min: 0, max: 1, action: #selector(volumeChanged(_:))))
        menu.addItem(sectionLabel("Tone: Deep ↔ Bright"))
        menu.addItem(sliderItem(value: tone, min: -1, max: 1, action: #selector(toneChanged(_:))))
        let mouseItem = item("Mouse & Trackpad Clicks", #selector(toggleMouse))
        mouseItem.state = mouseClicks ? .on : .off
        menu.addItem(mouseItem)
        let spatialItem = item("Spatial Audio", #selector(toggleSpatial))
        spatialItem.state = spatial ? .on : .off
        menu.addItem(spatialItem)

        menu.addItem(.separator())
        let packsItem = NSMenuItem(title: "Sound Pack", action: nil, keyEquivalent: "")
        let packsMenu = NSMenu()
        for url in PackLibrary.discover() {
            let p = item(url.lastPathComponent, #selector(selectPack(_:)))
            p.representedObject = url.lastPathComponent
            p.state = url.lastPathComponent == selectedPack ? .on : .off
            packsMenu.addItem(p)
        }
        packsMenu.addItem(.separator())
        packsMenu.addItem(item("Open Packs Folder", #selector(openPacksFolder)))
        packsItem.submenu = packsMenu
        menu.addItem(packsItem)

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit Clackey", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target ?? self
        return i
    }

    private func sectionLabel(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func sliderItem(value: Float, min: Double, max: Double, action: Selector) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        let slider = NSSlider(value: Double(value), minValue: min, maxValue: max,
                              target: self, action: action)
        slider.frame = NSRect(x: 20, y: 4, width: 180, height: 20)
        slider.isContinuous = true
        view.addSubview(slider)
        let i = NSMenuItem()
        i.view = view
        return i
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        enabled.toggle()
        engine?.setEnabled(enabled)
        updateIcon()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        volume = sender.floatValue
        engine?.volume = volume
    }

    @objc private func toneChanged(_ sender: NSSlider) {
        // Snap to neutral near the middle so "as recorded" is easy to get back to.
        tone = abs(sender.floatValue) < 0.08 ? 0 : sender.floatValue
        engine?.tone = tone
    }

    @objc private func toggleMouse() {
        mouseClicks.toggle()
    }

    @objc private func toggleSpatial() {
        spatial.toggle()
        engine?.spatialWidth = spatial ? 0.6 : 0
    }

    @objc private func selectPack(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        loadPack(named: name)
        engine?.play(.down)   // preview
    }

    @objc private func openPacksFolder() {
        NSWorkspace.shared.open(PackLibrary.userPacksURL)
    }

    @objc private func openInputMonitoring() {
        KeyTap.requestPermission()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Couldn't change Launch at Login", error)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
