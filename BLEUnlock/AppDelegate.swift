import Cocoa
import CoreGraphics
import ServiceManagement
import UserNotifications

func t(_ key: String) -> String {
    return NSLocalizedString(key, comment: "")
}

private let currentAppBundleIdentifier = "com.github.Skyearn.BLEUnlock"
private let legacyMainBundleIdentifiers = ["jp.sone.BLEUnlock"]
private let lockNotificationID = "com.github.Skyearn.BLEUnlock.lock"
private let updateNotificationID = "com.github.Skyearn.BLEUnlock.update"
private let notificationKindKey = "kind"
private let launcherBundleIDSuffix = ".Launcher"
private let unlockLogicMenuItemKind = "unlockLogic"
private let lockLogicMenuItemKind = "lockLogic"
private let unlockRSSIMenuItemKind = "unlockRSSI"
private let lockRSSIMenuItemKind = "lockRSSI"
private let pauseNowPlayingNoticeShownKey = "pauseNowPlayingNoticeShown"
private let autoCheckUpdatesKey = "autoCheckUpdates"
private let legacyBundleIDMigrationKey = "legacyBundleIDMigrationComplete"

private enum AppNotificationKind: String {
    case lock
    case update
}

enum ManagedMediaApp: String, CaseIterable, Hashable {
    case music
    case quickTimePlayer
    case spotify
    case safari

    var bundleIdentifier: String {
        switch self {
        case .music:
            return "com.apple.Music"
        case .quickTimePlayer:
            return "com.apple.QuickTimePlayerX"
        case .spotify:
            return "com.spotify.client"
        case .safari:
            return "com.apple.Safari"
        }
    }

    var displayName: String {
        switch self {
        case .music:
            return "Music"
        case .quickTimePlayer:
            return "QuickTime Player"
        case .spotify:
            return "Spotify"
        case .safari:
            return "Safari"
        }
    }
}

private func requestNotificationAuthorization() {
    if #available(macOS 10.14, *) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization failed: \(error.localizedDescription)")
                return
            }
            print("Notification authorization granted: \(granted)")
        }
    }
}

private func removeDeliveredNotification(identifier: String) {
    if #available(macOS 10.14, *) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    } else if let appDelegate = NSApp.delegate as? AppDelegate, let notification = appDelegate.userNotification {
        NSUserNotificationCenter.default.removeDeliveredNotification(notification)
        appDelegate.userNotification = nil
    }
}

private func enqueueNotification(identifier: String,
                                 kind: AppNotificationKind,
                                 title: String,
                                 subtitle: String? = nil,
                                 informativeText: String? = nil,
                                 after delay: TimeInterval? = nil,
                                 sound: Bool = true)
{
    if #available(macOS 10.14, *) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        if let informativeText = informativeText {
            content.body = informativeText
        }
        if sound {
            content.sound = .default
        }
        content.userInfo = [notificationKindKey: kind.rawValue]

        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification \(identifier): \(error.localizedDescription)")
            }
        }
    } else {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.informativeText = informativeText
        if sound {
            notification.soundName = NSUserNotificationDefaultSoundName
        }
        if let delay = delay {
            notification.deliveryDate = Date().addingTimeInterval(delay)
        }
        NSUserNotificationCenter.default.deliver(notification)
        if kind == .lock, let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.userNotification = notification
        }
    }
}

func notifyUpdateAvailable() {
    if #available(macOS 10.14, *) {
        enqueueNotification(identifier: updateNotificationID,
                            kind: .update,
                            title: "BLEUnlock",
                            subtitle: t("notification_update_available"),
                            sound: false)
    } else {
        let notification = NSUserNotification()
        notification.title = "BLEUnlock"
        notification.subtitle = t("notification_update_available")
        NSUserNotificationCenter.default.deliver(notification)
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, NSUserNotificationCenterDelegate, UNUserNotificationCenterDelegate, BLEDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let ble = BLE()
    let mainMenu = NSMenu()
    let deviceMenu = NSMenu()
    let unlockSettingsMenu = NSMenu()
    let lockSettingsMenu = NSMenu()
    let timeoutMenu = NSMenu()
    let lockDelayMenu = NSMenu()
    let updateMenu = NSMenu()
    var updateMenuItem: NSMenuItem?
    var checkForUpdatesMenuItem: NSMenuItem?
    var automaticUpdateChecksMenuItem: NSMenuItem?
    var deviceDict: [UUID: NSMenuItem] = [:]
    var deviceCheckboxDict: [UUID: NSButton] = [:]
    var monitorDetailItems: [UUID: NSMenuItem] = [:]
    var monitorMenuItem : NSMenuItem?
    var lockNowMenuItem: NSMenuItem?
    let prefs = UserDefaults.standard
    var displaySleep = false
    var systemSleep = false
    var connected = false
    var userNotification: NSUserNotification?
    var userNotificationID: String?
    var pausedMediaApps: Set<ManagedMediaApp> = []
    let pausedMediaAppsLock = NSLock()
    var aboutBox: AboutBox? = nil
    var manualLock = false
    var unlockedAt = 0.0
    var inScreensaver = false
    var lastRSSI: Int? = nil
    var deviceMenuIsOpen = false
    var deviceMenuNeedsRefresh = false
    var automationPermissionPromptedApps: Set<ManagedMediaApp> = []
    let mediaControlQueue = DispatchQueue(label: "com.github.Skyearn.BLEUnlock.media-control", qos: .userInitiated)
    var systemWakeTimer: Timer?
    var wakeUnlockTimer: Timer?
    var postUnlockRetryTimer: Timer?
    var permissionRecoveryTimer: Timer?
    var lastWakeAt = 0.0
    var lastDisplayWakeRequestAt = 0.0
    var lastSystemSleepStartedAt = 0.0
    var lastScreensaverStartedAt = 0.0
    let minimumWakeRequestInterval = 15.0
    let conservativeWakeSleepThreshold = 60.0
    let conservativeWakeUnlockDelay = 1.5
    let screensaverEscapeRetryDelay = 0.35
    let wakeUnlockRetryDelay = 0.5
    let wakeUnlockMaxRetries = 8

    func menuWillOpen(_ menu: NSMenu) {
        if menu == deviceMenu {
            deviceMenuIsOpen = false
            refreshDeviceMenuSelectionStates()
            deviceMenuNeedsRefresh = false
            deviceMenuIsOpen = true
            ble.startScanning()
        } else if menu == unlockSettingsMenu {
            updateSettingsMenu(menu,
                               logicKind: unlockLogicMenuItemKind,
                               selectedLogic: ble.unlockDeviceLogic.rawValue,
                               rssiKind: unlockRSSIMenuItemKind,
                               selectedRSSI: ble.unlockRSSI)
        } else if menu == lockSettingsMenu {
            updateSettingsMenu(menu,
                               logicKind: lockLogicMenuItemKind,
                               selectedLogic: ble.lockDeviceLogic.rawValue,
                               rssiKind: lockRSSIMenuItemKind,
                               selectedRSSI: ble.lockRSSI)
        } else if menu == timeoutMenu {
            for item in menu.items {
                if item.tag == Int(ble.signalTimeout) {
                    item.state = .on
                } else {
                    item.state = .off
                }
            }
        } else if menu == lockDelayMenu {
            for item in menu.items {
                if item.tag == Int(ble.proximityTimeout) {
                    item.state = .on
                } else {
                    item.state = .off
                }
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let kind = menuItem.representedObject as? String {
            if kind == unlockLogicMenuItemKind || kind == lockLogicMenuItemKind {
                return ble.monitoredUUIDs.count > 1
            }
            if kind == lockRSSIMenuItemKind {
                return menuItem.tag <= ble.unlockRSSI
            }
            if kind == unlockRSSIMenuItemKind {
                return menuItem.tag >= ble.lockRSSI
            }
        }
        return true
    }
    
    func menuDidClose(_ menu: NSMenu) {
        if menu == deviceMenu {
            deviceMenuIsOpen = false
            ble.stopScanning()
            if deviceMenuNeedsRefresh {
                refreshDeviceMenuSelectionStates()
                deviceMenuNeedsRefresh = false
            }
        }
    }
    
    func menuItemTitle(device: Device) -> String {
        var desc : String!
        if let mac = device.macAddr {
            let prettifiedMac = mac.replacingOccurrences(of: "-", with: ":").uppercased()
            desc = String(format: "%@ (%@)", device.description, prettifiedMac)
        } else {
            desc = device.description
        }
        if let rssi = displayedRSSI(for: device.uuid) {
            return menuItemTitle(title: desc, rssi: rssi)
        }
        return menuItemTitleNotDetected(title: desc)
    }

    func menuItemTitleNotDetected(title: String) -> String {
        "\(title) (\(t("not_detected")))"
    }

    func menuItemTitleNotDetected(device: Device) -> String {
        menuItemTitleNotDetected(title: device.description)
    }

    func menuItemTitle(title: String, rssi: Int) -> String {
        String(format: "%@ (%ddBm)", title, rssi)
    }

    func displayedRSSI(for uuid: UUID) -> Int? {
        if let monitoredRSSI = ble.monitoredStates[uuid]?.lastRSSI {
            return monitoredRSSI
        }
        if let device = ble.devices[uuid], device.isVisible {
            return device.rssi
        }
        return nil
    }

    func configuredDeviceCheckbox(uuid: UUID, title: String) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleDeviceCheckbox(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(uuid.uuidString)
        checkbox.state = ble.isMonitoring(uuid: uuid) ? .on : .off
        checkbox.font = NSFont.menuFont(ofSize: 0)
        checkbox.alignment = .left
        return checkbox
    }

    func configureDeviceMenuView(_ menuItem: NSMenuItem, uuid: UUID, title: String) -> NSButton {
        let checkbox = configuredDeviceCheckbox(uuid: uuid, title: title)
        let fittingSize = checkbox.fittingSize
        let height = max(24, fittingSize.height + 4)
        let width = max(300, fittingSize.width + 28)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        checkbox.frame = NSRect(x: 14, y: (height - fittingSize.height) / 2, width: fittingSize.width, height: fittingSize.height)
        container.addSubview(checkbox)
        menuItem.view = container
        return checkbox
    }

    func updateDeviceCheckbox(_ checkbox: NSButton, uuid: UUID, title: String) {
        checkbox.title = title
        checkbox.state = ble.isMonitoring(uuid: uuid) ? .on : .off
        let fittingSize = checkbox.fittingSize
        if let container = checkbox.superview {
            let height = max(24, fittingSize.height + 4)
            let width = max(300, fittingSize.width + 28)
            container.frame.size = NSSize(width: width, height: height)
            checkbox.frame = NSRect(x: 14, y: (height - fittingSize.height) / 2, width: fittingSize.width, height: fittingSize.height)
        }
    }

    func ensureMonitoredDeviceMenuItems() {
        let orderedUUIDs = ble.monitoredUUIDs.sorted {
            monitoredDeviceTitle(uuid: $0).localizedStandardCompare(monitoredDeviceTitle(uuid: $1)) == .orderedAscending
        }
        for uuid in orderedUUIDs where deviceDict[uuid] == nil {
            let menuItem = deviceMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            let checkbox = configureDeviceMenuView(menuItem,
                                                   uuid: uuid,
                                                   title: menuItemTitleNotDetected(title: monitoredDeviceTitle(uuid: uuid)))
            deviceDict[uuid] = menuItem
            deviceCheckboxDict[uuid] = checkbox
        }
    }
    
    func newDevice(device: Device) {
        if let checkbox = deviceCheckboxDict[device.uuid] {
            updateDeviceCheckbox(checkbox, uuid: device.uuid, title: menuItemTitle(device: device))
            updateMonitorStatusItems()
            return
        }
        let menuItem = deviceMenu.addItem(withTitle: "", action:nil, keyEquivalent: "")
        let checkbox = configureDeviceMenuView(menuItem, uuid: device.uuid, title: menuItemTitle(device: device))
        deviceDict[device.uuid] = menuItem
        deviceCheckboxDict[device.uuid] = checkbox
        updateMonitorStatusItems()
    }
    
    func updateDevice(device: Device) {
        if let checkbox = deviceCheckboxDict[device.uuid] {
            updateDeviceCheckbox(checkbox, uuid: device.uuid, title: menuItemTitle(device: device))
        } else {
            let menuItem = deviceMenu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            let checkbox = configureDeviceMenuView(menuItem, uuid: device.uuid, title: menuItemTitle(device: device))
            deviceDict[device.uuid] = menuItem
            deviceCheckboxDict[device.uuid] = checkbox
        }
        updateMonitorStatusItems()
    }
    
    func removeDevice(device: Device) {
        if ble.isMonitoring(uuid: device.uuid) {
            if let checkbox = deviceCheckboxDict[device.uuid] {
                let title: String
                if displayedRSSI(for: device.uuid) != nil {
                    title = menuItemTitle(device: device)
                } else {
                    title = menuItemTitleNotDetected(device: device)
                }
                updateDeviceCheckbox(checkbox, uuid: device.uuid, title: title)
            }
            updateMonitorStatusItems()
            return
        }
        if let menuItem = deviceDict[device.uuid] {
            menuItem.menu?.removeItem(menuItem)
        }
        deviceDict.removeValue(forKey: device.uuid)
        deviceCheckboxDict.removeValue(forKey: device.uuid)
        updateMonitorStatusItems()
    }

    func loadMonitoredUUIDs() -> Set<UUID> {
        if let values = prefs.array(forKey: "devices") as? [String] {
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        if let value = prefs.string(forKey: "device"), let uuid = UUID(uuidString: value) {
            let uuids: Set<UUID> = [uuid]
            saveMonitoredUUIDs(uuids)
            return uuids
        }
        return []
    }

    func saveMonitoredUUIDs(_ uuids: Set<UUID>) {
        prefs.set(uuids.map(\.uuidString).sorted(), forKey: "devices")
        prefs.removeObject(forKey: "device")
    }

    func refreshDeviceMenuSelectionStates() {
        ensureMonitoredDeviceMenuItems()
        var staleUUIDs: [UUID] = []
        for (uuid, menuItem) in deviceDict {
            let monitoring = ble.isMonitoring(uuid: uuid)
            menuItem.state = monitoring ? .on : .off
            if let device = ble.devices[uuid] {
                if !monitoring && !device.isVisible {
                    staleUUIDs.append(uuid)
                } else if let checkbox = deviceCheckboxDict[uuid] {
                    updateDeviceCheckbox(checkbox, uuid: uuid, title: menuItemTitle(device: device))
                }
            } else if let checkbox = deviceCheckboxDict[uuid] {
                if monitoring {
                    let title: String
                    if let rssi = displayedRSSI(for: uuid) {
                        title = menuItemTitle(title: monitoredDeviceTitle(uuid: uuid), rssi: rssi)
                    } else {
                        title = menuItemTitleNotDetected(title: monitoredDeviceTitle(uuid: uuid))
                    }
                    updateDeviceCheckbox(checkbox, uuid: uuid, title: title)
                } else {
                    staleUUIDs.append(uuid)
                }
            }
        }
        for uuid in staleUUIDs {
            if let menuItem = deviceDict[uuid] {
                menuItem.menu?.removeItem(menuItem)
            }
            deviceDict.removeValue(forKey: uuid)
            deviceCheckboxDict.removeValue(forKey: uuid)
        }
    }

    func monitoredDeviceTitle(uuid: UUID) -> String {
        if let device = ble.devices[uuid] {
            return device.description
        }
        if let name = ble.monitoredStates[uuid]?.peripheral?.name?.trimmingCharacters(in: .whitespaces),
           !name.isEmpty {
            return name
        }
        return uuid.uuidString
    }

    func monitoredDeviceStatusTitle(uuid: UUID) -> String {
        let title = monitoredDeviceTitle(uuid: uuid)
        if let rssi = displayedRSSI(for: uuid) {
            let state = ble.monitoredStates[uuid]
            let activeSuffix = state?.active == true ? t("monitor_status_active_suffix") : ""
            return String(format: t("monitor_status_device_detected"), title, rssi, activeSuffix)
        }
        return String(format: t("monitor_status_device_not_detected"), title, t("not_detected"))
    }

    func monitoredSummaryTitle() -> String {
        let orderedUUIDs = ble.monitoredUUIDs.sorted {
            monitoredDeviceTitle(uuid: $0).localizedStandardCompare(monitoredDeviceTitle(uuid: $1)) == .orderedAscending
        }
        guard !orderedUUIDs.isEmpty else {
            return t("device_not_set")
        }

        let visibleDevices = orderedUUIDs.compactMap { uuid -> (UUID, Int)? in
            guard let rssi = displayedRSSI(for: uuid) else { return nil }
            return (uuid, rssi)
        }

        if let strongest = visibleDevices.max(by: { $0.1 < $1.1 }) {
            let detected = visibleDevices.count
            return String(format: t("monitor_status_strongest_detected"), detected, orderedUUIDs.count, strongest.1)
        }
        return String(format: t("monitor_status_not_detected"), 0, orderedUUIDs.count)
    }

    func refreshMonitorStatusItems() {
        for item in monitorDetailItems.values {
            mainMenu.removeItem(item)
        }
        monitorDetailItems.removeAll()

        monitorMenuItem?.title = monitoredSummaryTitle()
        if let monitorMenuItem, mainMenu.index(of: monitorMenuItem) == -1 {
            mainMenu.insertItem(monitorMenuItem, at: 0)
        }
    }

    func updateMonitorStatusItems() {
        if !monitorDetailItems.isEmpty {
            refreshMonitorStatusItems()
            return
        }
        if let monitorMenuItem {
            monitorMenuItem.title = monitoredSummaryTitle()
        }
    }

    func updateRSSI(rssi: Int?, active: Bool) {
        if let r = rssi {
            lastRSSI = r
            updateMonitorStatusItems()
            if (!connected) {
                connected = true
                statusItem.button?.image = NSImage(named: "StatusBarConnected")
            }
        } else {
            updateMonitorStatusItems()
            if (connected) {
                connected = false
                statusItem.button?.image = NSImage(named: "StatusBarDisconnected")
            }
        }
    }

    func bluetoothPowerWarn() {
        errorModal(t("bluetooth_power_warn"))
    }

    func notifyUser(_ reason: String) {
        var subtitle: String?
        if reason == "lost" {
            subtitle = t("notification_lost_signal")
        } else if reason == "away" {
            subtitle = t("notification_device_away")
        }
        enqueueNotification(identifier: lockNotificationID,
                            kind: .lock,
                            title: "BLEUnlock",
                            subtitle: subtitle,
                            informativeText: t("notification_locked"),
                            after: 1)
        userNotificationID = lockNotificationID
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter,
                                didActivate notification: NSUserNotification) {
        if notification != userNotification {
            NSWorkspace.shared.open(URL(string: "https://github.com/Skyearn/BLEUnlock/releases")!)
            NSUserNotificationCenter.default.removeDeliveredNotification(notification)
        }
    }

    @available(macOS 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kind = notification.request.content.userInfo[notificationKindKey] as? String
        if #available(macOS 11.0, *) {
            if kind == AppNotificationKind.update.rawValue {
                completionHandler([.banner, .list])
            } else {
                completionHandler([.banner, .list, .sound])
            }
        } else {
            if kind == AppNotificationKind.update.rawValue {
                completionHandler([.alert])
            } else {
                completionHandler([.alert, .sound])
            }
        }
    }

    @available(macOS 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let kind = response.notification.request.content.userInfo[notificationKindKey] as? String
        if kind == AppNotificationKind.update.rawValue {
            NSWorkspace.shared.open(URL(string: "https://github.com/Skyearn/BLEUnlock/releases")!)
            removeDeliveredNotification(identifier: updateNotificationID)
        }
        completionHandler()
    }

    func runScript(_ arg: String) {
        guard let directory = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let file = directory.appendingPathComponent("event")
        let process = Process()
        process.executableURL = file
        if let r = lastRSSI {
            process.arguments = [arg, String(r)]
        } else {
            process.arguments = [arg]
        }
        try? process.run()
    }

    func isRunning(_ app: ManagedMediaApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    @discardableResult
    func runAppleScript(_ source: String, label: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            print("AppleScript compile failed for \(label)")
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            print("AppleScript \(label) failed: \(error)")
            return nil
        }

        if let stringValue = result.stringValue {
            return stringValue
        }
        if result.descriptorType == typeSInt32 {
            return String(result.int32Value)
        }
        return nil
    }

    func automationPermissionStatus(for app: ManagedMediaApp, askUserIfNeeded: Bool) -> OSStatus {
        guard #available(macOS 10.14, *) else { return noErr }
        return BLEUnlockDeterminePermissionToAutomateBundleID(app.bundleIdentifier as CFString, askUserIfNeeded)
    }

    func hasAutomationPermission(for app: ManagedMediaApp) -> Bool {
        let status = automationPermissionStatus(for: app, askUserIfNeeded: false)
        if status == noErr {
            return true
        }

        if status == OSStatus(procNotFound) {
            return false
        }

        if #available(macOS 10.14, *) {
            let consentRequired = OSStatus(errAEEventWouldRequireUserConsent)
            let eventNotPermitted = OSStatus(errAEEventNotPermitted)
            let targetNotPermitted = OSStatus(errAETargetAddressNotPermitted)
            if status == consentRequired || status == eventNotPermitted || status == targetNotPermitted {
                return false
            }
        }

        print("Automation permission check for \(app.displayName) returned \(status)")
        return false
    }

    func requestAutomationPermissionsIfNeeded() {
        guard prefs.bool(forKey: "pauseItunes") else { return }

        for app in ManagedMediaApp.allCases where isRunning(app) && !hasAutomationPermission(for: app) {
            guard !automationPermissionPromptedApps.contains(app) else { continue }
            automationPermissionPromptedApps.insert(app)

            let status = automationPermissionStatus(for: app, askUserIfNeeded: true)
            if status == noErr {
                print("Automation permission granted for \(app.displayName)")
            } else {
                print("Automation permission request for \(app.displayName) returned \(status)")
            }
        }
    }

    func pauseScript(for app: ManagedMediaApp) -> String {
        switch app {
        case .music:
            return """
            tell application "Music"
                if player state is playing then
                    pause
                    return "paused"
                end if
                return "noop"
            end tell
            """
        case .quickTimePlayer:
            return """
            tell application "QuickTime Player"
                set didPause to false
                repeat with aDocument in documents
                    try
                        if playing of aDocument then
                            pause aDocument
                            set didPause to true
                        end if
                    end try
                end repeat
                if didPause then
                    return "paused"
                end if
                return "noop"
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                if player state is playing then
                    pause
                    return "paused"
                end if
                return "noop"
            end tell
            """
        case .safari:
            return """
            tell application "Safari"
                set pausedCount to 0
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        try
                            set tabResult to do JavaScript "
                                (() => {
                                    let paused = 0;
                                    for (const media of document.querySelectorAll('video, audio')) {
                                        if (!media.paused) {
                                            media.dataset.bleunlockPaused = '1';
                                            media.pause();
                                            paused += 1;
                                        }
                                    }
                                    return String(paused);
                                })();
                            " in aTab
                            set pausedCount to pausedCount + (tabResult as integer)
                        end try
                    end repeat
                end repeat
                return pausedCount as string
            end tell
            """
        }
    }

    func resumeScript(for app: ManagedMediaApp) -> String {
        switch app {
        case .music:
            return """
            tell application "Music"
                if player state is paused then
                    play
                    return "played"
                end if
                return "noop"
            end tell
            """
        case .quickTimePlayer:
            return """
            tell application "QuickTime Player"
                set didPlay to false
                repeat with aDocument in documents
                    try
                        if not playing of aDocument then
                            play aDocument
                            set didPlay to true
                        end if
                    end try
                end repeat
                if didPlay then
                    return "played"
                end if
                return "noop"
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                if player state is paused then
                    play
                    return "played"
                end if
                return "noop"
            end tell
            """
        case .safari:
            return """
            tell application "Safari"
                set resumedCount to 0
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        try
                            set tabResult to do JavaScript "
                                (() => {
                                    let resumed = 0;
                                    for (const media of document.querySelectorAll('video, audio')) {
                                        if (media.dataset.bleunlockPaused === '1') {
                                            delete media.dataset.bleunlockPaused;
                                            media.play();
                                            resumed += 1;
                                        }
                                    }
                                    return String(resumed);
                                })();
                            " in aTab
                            set resumedCount to resumedCount + (tabResult as integer)
                        end try
                    end repeat
                end repeat
                return resumedCount as string
            end tell
            """
        }
    }

    func didPauseMediaApp(_ app: ManagedMediaApp, result: String?) -> Bool {
        guard let result else { return false }
        switch app {
        case .safari:
            return (Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
        default:
            return result == "paused"
        }
    }

    func didResumeMediaApp(_ app: ManagedMediaApp, result: String?) -> Bool {
        guard let result else { return false }
        switch app {
        case .safari:
            return (Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
        default:
            return result == "played"
        }
    }

    func pauseNowPlaying() {
        guard prefs.bool(forKey: "pauseItunes") else { return }

        mediaControlQueue.async {
            self.pausedMediaAppsLock.lock()
            self.pausedMediaApps.removeAll()
            self.pausedMediaAppsLock.unlock()
            for app in ManagedMediaApp.allCases {
                guard self.isRunning(app) else { continue }
                guard self.hasAutomationPermission(for: app) else { continue }
                let result = self.runAppleScript(self.pauseScript(for: app), label: "pause \(app.displayName)")
                if self.didPauseMediaApp(app, result: result) {
                    self.pausedMediaAppsLock.lock()
                    self.pausedMediaApps.insert(app)
                    self.pausedMediaAppsLock.unlock()
                    print("Paused \(app.displayName)")
                }
            }
        }
    }
    
    func playNowPlaying() {
        guard prefs.bool(forKey: "pauseItunes") else { return }
        mediaControlQueue.asyncAfter(deadline: .now() + 0.5) {
            self.pausedMediaAppsLock.lock()
            let appsToResume = self.pausedMediaApps
            self.pausedMediaApps.removeAll()
            self.pausedMediaAppsLock.unlock()
            guard !appsToResume.isEmpty else { return }

            for app in ManagedMediaApp.allCases where appsToResume.contains(app) && self.isRunning(app) {
                guard self.hasAutomationPermission(for: app) else { continue }
                let result = self.runAppleScript(self.resumeScript(for: app), label: "resume \(app.displayName)")
                if self.didResumeMediaApp(app, result: result) {
                    print("Resumed \(app.displayName)")
                }
            }
        }
    }

    func lockOrSaveScreenAsync() {
        DispatchQueue.main.async {
            self.lockOrSaveScreen()
        }
    }

    func lockOrSaveScreen() {
        if prefs.bool(forKey: "screensaver") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
        } else {
            if SACLockScreenImmediate() != 0 {
                print("Failed to lock screen")
            }
            if prefs.bool(forKey: "sleepDisplay") {
                print("sleep display")
                sleepDisplay()
            }
        }
    }

    func updatePresence(shouldUnlock: Bool, shouldLock: Bool, reason: String) {
        if manualLock && shouldLock {
            manualLock = false
            if shouldUnlock {
                return
            }
        }

        if shouldUnlock {
            if ble.unlockRSSI != ble.UNLOCK_DISABLED {
                if let identifier = userNotificationID {
                    removeDeliveredNotification(identifier: identifier)
                    userNotificationID = nil
                }
                if let notification = userNotification {
                    NSUserNotificationCenter.default.removeDeliveredNotification(notification)
                    userNotification = nil
                }
                if displaySleep && !systemSleep && prefs.bool(forKey: "wakeOnProximity") {
                    let now = Date().timeIntervalSince1970
                    if now - lastDisplayWakeRequestAt >= minimumWakeRequestInterval {
                        print("Waking display")
                        lastDisplayWakeRequestAt = now
                        wakeDisplay()
                    } else {
                        print("Skipping wake display retry while display wake is still pending")
                    }
                }
                tryUnlockScreen()
            }
        } else if shouldLock {
            if (!isScreenLocked() && ble.lockRSSI != ble.LOCK_DISABLED) {
                pauseNowPlaying()
                lockOrSaveScreenAsync()
                notifyUser(reason)
                runScript(reason)
            }
            manualLock = false
        }
    }

    func fakeKeyStrokes(_ string: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        // Send 20 characters per keyboard event. That seems to be the limit.
        let PER = 20
        let uniCharCount = string.utf16.count
        var strIndex = string.utf16.startIndex
        for offset in stride(from: 0, to: uniCharCount, by: PER) {
            let pressEvent = CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: true)
            let len = offset + PER < uniCharCount ? PER : uniCharCount - offset
            let buffer = UnsafeMutablePointer<UniChar>.allocate(capacity: len)
            for i in 0..<len {
                buffer[i] = string.utf16[strIndex]
                strIndex = string.utf16.index(after: strIndex)
            }
            pressEvent?.keyboardSetUnicodeString(stringLength: len, unicodeString: buffer)
            pressEvent?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 49, keyDown: false)?.post(tap: .cghidEventTap)
            buffer.deallocate()
        }
        
        // Return key
        CGEvent(keyboardEventSource: src, virtualKey: 52, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 52, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func sendEscapeKey() {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func isScreenLocked() -> Bool {
        if let dict = CGSessionCopyCurrentDictionary() as? [String : Any] {
            if let locked = dict["CGSSessionScreenIsLocked"] as? Int {
                return locked == 1
            }
        }
        return false
    }

    func recentlyWoke() -> Bool {
        Date().timeIntervalSince1970 - lastWakeAt < 5
    }

    func conservativeWakeUnlockNeeded() -> Bool {
        guard recentlyWoke() else { return false }
        let now = Date().timeIntervalSince1970
        let sleepReference = max(lastSystemSleepStartedAt, lastScreensaverStartedAt)
        guard sleepReference > 0 else { return false }
        return now - sleepReference >= conservativeWakeSleepThreshold
    }
    
    func tryUnlockScreen(retryCount: Int = 0) {
        guard !manualLock else { return }
        guard ble.presence else { return }
        guard ble.unlockRSSI != ble.UNLOCK_DISABLED else { return }
        guard !systemSleep else { return }
        guard !displaySleep else { return }
        guard !self.prefs.bool(forKey: "wakeWithoutUnlocking") else { return }
        let recentlyWoke = recentlyWoke()
        let conservativeWakeUnlock = conservativeWakeUnlockNeeded()

        if inScreensaver && !recentlyWoke && retryCount == 0 {
            // Only dismiss a live screensaver outside the fragile wake window.
            sendEscapeKey()
            scheduleWakeUnlock(after: screensaverEscapeRetryDelay, retryCount: retryCount + 1)
            return
        } else if inScreensaver && recentlyWoke {
            print("Skipping Escape key during wake recovery")
        }

        guard isScreenLocked() else {
            if (recentlyWoke || inScreensaver) && retryCount < wakeUnlockMaxRetries {
                scheduleWakeUnlock(after: wakeUnlockRetryDelay, retryCount: retryCount + 1)
            }
            return
        }

        let unlockDelay = conservativeWakeUnlock ? conservativeWakeUnlockDelay : (recentlyWoke ? 0.75 : 0.5)
        wakeUnlockTimer?.invalidate()
        wakeUnlockTimer = Timer.scheduledTimer(withTimeInterval: unlockDelay, repeats: false, block: { [weak self] _ in
            guard let self = self else { return }
            self.wakeUnlockTimer = nil
            guard self.isScreenLocked() else {
                if (recentlyWoke || self.inScreensaver) && retryCount < self.wakeUnlockMaxRetries {
                    self.scheduleWakeUnlock(after: self.wakeUnlockRetryDelay, retryCount: retryCount + 1)
                }
                return
            }
            guard let password = self.fetchPassword(warn: true) else { return }
            
            self.unlockedAt = Date().timeIntervalSince1970
            self.fakeKeyStrokes(password)
            self.playNowPlaying()
            self.runScript("unlocked")

            // On wake, the first attempt can land before the login UI is fully ready.
            if (recentlyWoke || self.inScreensaver) && retryCount < self.wakeUnlockMaxRetries {
                self.postUnlockRetryTimer?.invalidate()
                let retryDelay = conservativeWakeUnlock ? 2.0 : 1.5
                self.postUnlockRetryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false, block: { [weak self] _ in
                    guard let self = self else { return }
                    self.postUnlockRetryTimer = nil
                    guard self.isScreenLocked() else { return }
                    self.scheduleWakeUnlock(after: self.wakeUnlockRetryDelay, retryCount: retryCount + 1)
                })
            }
        })
    }

    func cancelWakeRelatedTimers() {
        systemWakeTimer?.invalidate()
        systemWakeTimer = nil
        wakeUnlockTimer?.invalidate()
        wakeUnlockTimer = nil
        postUnlockRetryTimer?.invalidate()
        postUnlockRetryTimer = nil
    }

    func scheduleWakeUnlock(after delay: TimeInterval, retryCount: Int = 0) {
        wakeUnlockTimer?.invalidate()
        wakeUnlockTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { [weak self] _ in
            guard let self = self else { return }
            self.wakeUnlockTimer = nil
            self.tryUnlockScreen(retryCount: retryCount)
        })
    }

    @objc func onDisplayWake() {
        print("display wake")
        //unlockedAt = Date().timeIntervalSince1970
        displaySleep = false
        lastWakeAt = Date().timeIntervalSince1970
        lastDisplayWakeRequestAt = 0
        scheduleWakeUnlock(after: 0.75)
    }

    @objc func onDisplaySleep() {
        print("display sleep")
        displaySleep = true
        cancelWakeRelatedTimers()
    }

    @objc func onSystemWake() {
        print("system wake")
        systemWakeTimer?.invalidate()
        systemWakeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { [weak self] _ in
            guard let self = self else { return }
            self.systemWakeTimer = nil
            print("delayed system wake job")
            NSApp.setActivationPolicy(.accessory) // Hide Dock icon again
            self.systemSleep = false
            self.ble.resumeMonitoringAfterSystemWake()
            self.lastWakeAt = Date().timeIntervalSince1970
            self.scheduleWakeUnlock(after: 1.0)
        })
    }
    
    @objc func onSystemSleep() {
        print("system sleep")
        systemSleep = true
        lastSystemSleepStartedAt = Date().timeIntervalSince1970
        cancelWakeRelatedTimers()
        ble.suspendMonitoringForSystemSleep()
        // Set activation policy to regular, so the CBCentralManager can scan for peripherals
        // when the Bluetooth will become on again.
        // This enables Dock icon but the screen is off anyway.
        NSApp.setActivationPolicy(.regular)
    }

    @objc func onUnlock() {
        cancelWakeRelatedTimers()
        inScreensaver = false
        lastSystemSleepStartedAt = 0
        lastScreensaverStartedAt = 0
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { [weak self] _ in
            guard let self = self else { return }
            print("onUnlock")
            if Date().timeIntervalSince1970 >= self.unlockedAt + 10 {
                if self.ble.unlockRSSI != self.ble.UNLOCK_DISABLED {
                    self.runScript("intruded")
                }
                self.playNowPlaying()
            }
        })
        manualLock = false
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { [weak self] _ in
            self?.runAutomaticUpdateCheck()
        })
    }

    @objc func onScreensaverStart() {
        print("screensaver start")
        inScreensaver = true
        lastScreensaverStartedAt = Date().timeIntervalSince1970
    }

    @objc func onScreensaverStop() {
        print("screensaver stop")
        inScreensaver = false
        lastScreensaverStartedAt = 0
    }

    @objc func toggleDeviceCheckbox(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let uuid = UUID(uuidString: rawValue) else { return }
        var uuids = ble.monitoredUUIDs
        if uuids.contains(uuid) {
            uuids.remove(uuid)
        } else {
            uuids.insert(uuid)
        }
        saveMonitoredUUIDs(uuids)
        monitorDevices(uuids: uuids)
    }

    func monitorDevice(uuid: UUID) {
        monitorDevices(uuids: Set([uuid]))
    }

    func monitorDevices(uuids: Set<UUID>) {
        connected = false
        statusItem.button?.image = NSImage(named: "StatusBarDisconnected")
        ble.startMonitor(uuids: uuids)
        refreshDeviceMenuSelectionStates()
        refreshSettingsMenus()
        refreshMonitorStatusItems()
    }

    func errorModal(_ msg: String, info: String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = info ?? ""
        alert.window.title = "BLEUnlock"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func infoModal(_ msg: String, info: String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = info ?? ""
        alert.window.title = "BLEUnlock"
        alert.addButton(withTitle: t("ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func showPauseNowPlayingNoticeIfNeeded() {
        guard !prefs.bool(forKey: pauseNowPlayingNoticeShownKey) else { return }

        let alert = NSAlert()
        alert.messageText = "Pause Now Playing Setup"
        alert.informativeText = """
        BLEUnlock can pause Music, QuickTime Player, Spotify, and Safari when your Mac locks.

        macOS may ask you to allow BLEUnlock to control those apps. Safari also requires enabling:
        Develop > Allow JavaScript from Apple Events
        """
        alert.window.title = "BLEUnlock"
        alert.addButton(withTitle: t("ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        prefs.set(true, forKey: pauseNowPlayingNoticeShownKey)
    }

    func keychainQuery(service: String) -> [String: Any] {
        [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): NSUserName(),
            String(kSecAttrService): service,
        ]
    }

    func currentKeychainServiceIdentifier() -> String {
        Bundle.main.bundleIdentifier ?? currentAppBundleIdentifier
    }

    func keychainServiceIdentifiersForLookup() -> [String] {
        [currentKeychainServiceIdentifier()] + legacyMainBundleIdentifiers
    }

    func retrievePasswordData(service: String) -> (status: OSStatus, data: Data?) {
        var query = keychainQuery(service: service)
        query[String(kSecReturnData)] = kCFBooleanTrue!
        query[String(kSecMatchLimit)] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }
    
    func storePassword(_ password: String) {
        guard let pw = password.data(using: .utf8) else {
            errorModal("Failed to encode password")
            return
        }
        
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): NSUserName(),
            String(kSecAttrService): currentKeychainServiceIdentifier(),
            String(kSecAttrLabel): "BLEUnlock",
            String(kSecAttrAccessible): kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            String(kSecValueData): pw,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            let err = SecCopyErrorMessageString(status, nil)
            errorModal("Failed to store password to Keychain", info: err as String? ?? "Status \(status)")
            return
        }
    }

    func fetchPassword(warn: Bool = false) -> String? {
        var lastFailureStatus: OSStatus?

        for service in keychainServiceIdentifiersForLookup() {
            let result = retrievePasswordData(service: service)
            if result.status == errSecItemNotFound {
                continue
            }
            guard result.status == errSecSuccess else {
                lastFailureStatus = result.status
                continue
            }
            guard let data = result.data else {
                errorModal("Failed to convert password")
                return nil
            }
            guard let password = String(data: data, encoding: .utf8) else {
                errorModal("Stored password is unreadable", info: "The Keychain item may be corrupted. Please set the password again.")
                return nil
            }

            if service != currentKeychainServiceIdentifier() {
                storePassword(password)
            }
            return password
        }

        if let status = lastFailureStatus {
            let info = SecCopyErrorMessageString(status, nil)
            errorModal("Failed to retrieve password", info: info as String? ?? "Status \(status)")
            return nil
        }

        print("Password is not stored")
        if warn {
            errorModal(t("password_not_set"))
        }
        return nil
    }

    func migrateLegacyDefaultsIfNeeded() {
        guard !prefs.bool(forKey: legacyBundleIDMigrationKey) else { return }

        for legacyBundleIdentifier in legacyMainBundleIdentifiers {
            guard let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier),
                  let legacyDomain = legacyDefaults.persistentDomain(forName: legacyBundleIdentifier) else {
                continue
            }

            for (key, value) in legacyDomain where prefs.object(forKey: key) == nil {
                prefs.set(value, forKey: key)
            }
        }

        prefs.set(true, forKey: legacyBundleIDMigrationKey)
    }

    func legacyLauncherBundleIdentifiers() -> [String] {
        legacyMainBundleIdentifiers.map { $0 + launcherBundleIDSuffix }
    }

    func disableLegacyLoginItems() {
        for legacyLauncherBundleIdentifier in legacyLauncherBundleIdentifiers() {
            _ = SMLoginItemSetEnabled(legacyLauncherBundleIdentifier as CFString, false)
            if #available(macOS 13.0, *) {
                let service = SMAppService.loginItem(identifier: legacyLauncherBundleIdentifier)
                try? service.unregister()
            }
        }
    }

    func migrateLegacyAppDataIfNeeded() {
        migrateLegacyDefaultsIfNeeded()
        disableLegacyLoginItems()
    }
    
    @objc func askPassword() {
        let msg = NSAlert()
        msg.addButton(withTitle: t("ok"))
        msg.addButton(withTitle: t("cancel"))
        msg.messageText = t("enter_password")
        msg.informativeText = t("password_info")
        msg.window.title = "BLEUnlock"

        let txt = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 20))
        msg.accessoryView = txt
        txt.becomeFirstResponder()
        NSApp.activate(ignoringOtherApps: true)
        let response = msg.runModal()
        
        if (response == .alertFirstButtonReturn) {
            let pw = txt.stringValue
            storePassword(pw)
        }
    }
    
    @objc func setRSSIThreshold() {
        let msg = NSAlert()
        msg.addButton(withTitle: t("ok"))
        msg.addButton(withTitle: t("cancel"))
        msg.messageText = t("enter_rssi_threshold")
        msg.informativeText = t("enter_rssi_threshold_info")
        msg.window.title = "BLEUnlock"
        
        let txt = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 20))
        txt.placeholderString = String(ble.thresholdRSSI)
        msg.accessoryView = txt
        txt.becomeFirstResponder()
        NSApp.activate(ignoringOtherApps: true)
        let response = msg.runModal()
        
        if (response == .alertFirstButtonReturn) {
            let val = txt.intValue
            ble.thresholdRSSI = Int(val)
            prefs.set(val, forKey: "thresholdRSSI")
        }
    }

    @objc func toggleWakeOnProximity(_ menuItem: NSMenuItem) {
        let value = !prefs.bool(forKey: "wakeOnProximity")
        menuItem.state = value ? .on : .off
        prefs.set(value, forKey: "wakeOnProximity")
    }

    @objc func setLockRSSI(_ menuItem: NSMenuItem) {
        let value = menuItem.tag
        prefs.set(value, forKey: "lockRSSI")
        ble.lockRSSI = value
    }
    
    @objc func setUnlockRSSI(_ menuItem: NSMenuItem) {
        let value = menuItem.tag
        prefs.set(value, forKey: "unlockRSSI")
        ble.unlockRSSI = value
    }

    @objc func setTimeout(_ menuItem: NSMenuItem) {
        let value = menuItem.tag
        prefs.set(value, forKey: "timeout")
        ble.signalTimeout = Double(value)
    }

    @objc func setLockDelay(_ menuItem: NSMenuItem) {
        let value = menuItem.tag
        prefs.set(value, forKey: "lockDelay")
        ble.proximityTimeout = Double(value)
    }

    @objc func setUnlockDeviceLogic(_ menuItem: NSMenuItem) {
        guard let logic = UnlockDeviceLogic(rawValue: menuItem.tag) else { return }
        prefs.set(logic.rawValue, forKey: "unlockDeviceLogic")
        ble.setUnlockDeviceLogic(logic)
    }

    @objc func setLockDeviceLogic(_ menuItem: NSMenuItem) {
        guard let logic = LockDeviceLogic(rawValue: menuItem.tag) else { return }
        prefs.set(logic.rawValue, forKey: "lockDeviceLogic")
        ble.setLockDeviceLogic(logic)
    }

    @objc func toggleLaunchAtLogin(_ menuItem: NSMenuItem) {
        let launchAtLogin = !isLaunchAtLoginEnabled()
        if setLaunchAtLogin(launchAtLogin) {
            prefs.set(launchAtLogin, forKey: "launchAtLogin")
            menuItem.state = launchAtLogin ? .on : .off
        } else {
            menuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        }
    }

    @objc func togglePauseNowPlaying(_ menuItem: NSMenuItem) {
        let pauseNowPlaying = !prefs.bool(forKey: "pauseItunes")
        prefs.set(pauseNowPlaying, forKey: "pauseItunes")
        menuItem.state = pauseNowPlaying ? .on : .off
        if pauseNowPlaying {
            showPauseNowPlayingNoticeIfNeeded()
            requestAutomationPermissionsIfNeeded()
        }
    }
    
    @objc func toggleUseScreensaver(_ menuItem: NSMenuItem) {
        let value = !prefs.bool(forKey: "screensaver")
        prefs.set(value, forKey: "screensaver")
        menuItem.state = value ? .on : .off
    }

    @objc func toggleSleepDisplay(_ menuItem: NSMenuItem) {
        let value = !prefs.bool(forKey: "sleepDisplay")
        prefs.set(value, forKey: "sleepDisplay")
        menuItem.state = value ? .on : .off
    }
    
    @objc func togglePassiveMode(_ menuItem: NSMenuItem) {
        let passiveMode = !prefs.bool(forKey: "passiveMode")
        prefs.set(passiveMode, forKey: "passiveMode")
        menuItem.state = passiveMode ? .on : .off
        ble.setPassiveMode(passiveMode)
    }

    @objc func toggleWakeWithoutUnlocking(_ menuItem: NSMenuItem) {
        let wakeWithoutUnlocking = !prefs.bool(forKey: "wakeWithoutUnlocking")
        prefs.set(wakeWithoutUnlocking, forKey: "wakeWithoutUnlocking")
        menuItem.state = wakeWithoutUnlocking ? .on : .off
    }

    @objc func toggleAutomaticUpdateChecks(_ menuItem: NSMenuItem) {
        let enabled = !automaticUpdateChecksEnabled()
        prefs.set(enabled, forKey: autoCheckUpdatesKey)
        menuItem.state = enabled ? .on : .off
        if !enabled {
            clearPendingUpdate()
        }
        refreshUpdateMenuItems()
    }

    @objc func lockNow() {
        guard !isScreenLocked() else { return }
        manualLock = true
        pauseNowPlaying()
        lockOrSaveScreenAsync()
    }
    
    @objc func showAboutBox() {
        AboutBox.showAboutBox()
    }

    @objc func checkForUpdates() {
        checkUpdate(force: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .available(let version, let downloadURL, let releaseURL):
                    savePendingUpdate(version: version, downloadURL: downloadURL, releaseURL: releaseURL)
                    self.refreshUpdateMenuItems()
                    let alert = NSAlert()
                    alert.messageText = t("update_available_title")
                    alert.informativeText = String(format: t("update_available_message"), version)
                    alert.window.title = "BLEUnlock"
                    if downloadURL != nil {
                        alert.addButton(withTitle: t("download_update"))
                    }
                    alert.addButton(withTitle: t("open_releases"))
                    alert.addButton(withTitle: t("cancel"))
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        if let downloadURL {
                            NSWorkspace.shared.open(downloadURL)
                        } else {
                            NSWorkspace.shared.open(releaseURL)
                        }
                    } else if downloadURL != nil && response == .alertSecondButtonReturn {
                        NSWorkspace.shared.open(releaseURL)
                    }
                case .upToDate:
                    clearPendingUpdate()
                    self.refreshUpdateMenuItems()
                    self.infoModal(t("update_up_to_date"))
                case .failure(let message):
                    self.errorModal(t("update_check_failed"), info: message)
                }
            }
        }
    }

    func runAutomaticUpdateCheck() {
        checkUpdate { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard automaticUpdateChecksEnabled() else {
                    clearPendingUpdate()
                    self.refreshUpdateMenuItems()
                    return
                }

                switch result {
                case .available(let version, let downloadURL, let releaseURL):
                    savePendingUpdate(version: version, downloadURL: downloadURL, releaseURL: releaseURL)
                case .upToDate:
                    clearPendingUpdate()
                case .failure:
                    break
                }
                self.refreshUpdateMenuItems()
            }
        }
    }

    func refreshUpdateMenuItems() {
        let hasPendingUpdate = pendingUpdate() != nil
        updateMenuItem?.title = hasPendingUpdate ? t("updates_available") : t("updates")
        checkForUpdatesMenuItem?.title = t("check_for_updates")
        automaticUpdateChecksMenuItem?.state = automaticUpdateChecksEnabled() ? .on : .off
    }

    func updateSettingsMenu(_ menu: NSMenu, logicKind: String, selectedLogic: Int, rssiKind: String, selectedRSSI: Int) {
        let logicEnabled = ble.monitoredUUIDs.count > 1
        for item in menu.items {
            guard let kind = item.representedObject as? String else {
                item.state = .off
                continue
            }

            if kind == logicKind {
                item.state = item.tag == selectedLogic ? .on : .off
                item.isEnabled = logicEnabled
            } else if kind == rssiKind {
                item.state = item.tag == selectedRSSI ? .on : .off
                if kind == lockRSSIMenuItemKind {
                    item.isEnabled = item.tag <= ble.unlockRSSI
                } else if kind == unlockRSSIMenuItemKind {
                    item.isEnabled = item.tag >= ble.lockRSSI
                }
            } else {
                item.state = .off
            }
        }
    }

    func refreshSettingsMenus() {
        updateSettingsMenu(unlockSettingsMenu,
                           logicKind: unlockLogicMenuItemKind,
                           selectedLogic: ble.unlockDeviceLogic.rawValue,
                           rssiKind: unlockRSSIMenuItemKind,
                           selectedRSSI: ble.unlockRSSI)
        updateSettingsMenu(lockSettingsMenu,
                           logicKind: lockLogicMenuItemKind,
                           selectedLogic: ble.lockDeviceLogic.rawValue,
                           rssiKind: lockRSSIMenuItemKind,
                           selectedRSSI: ble.lockRSSI)
        unlockSettingsMenu.update()
        lockSettingsMenu.update()
    }

    @discardableResult
    func addSettingsItem(_ menu: NSMenu, title: String, action: Selector, tag: Int, kind: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.tag = tag
        item.representedObject = kind
        return item
    }

    func constructRSSISection(_ menu: NSMenu, _ action: Selector, kind: String, disabledTag: Int, disabledFirst: Bool) {
        if disabledFirst {
            addSettingsItem(menu, title: t("disabled"), action: action, tag: disabledTag, kind: kind)
        }

        menu.addItem(withTitle: t("closer"), action: nil, keyEquivalent: "")
        for proximity in stride(from: -30, to: -100, by: -5) {
            addSettingsItem(menu, title: String(format: "%ddBm", proximity), action: action, tag: proximity, kind: kind)
        }
        menu.addItem(withTitle: t("farther"), action: nil, keyEquivalent: "")

        if !disabledFirst {
            addSettingsItem(menu, title: t("disabled"), action: action, tag: disabledTag, kind: kind)
        }

        menu.delegate = self
    }
    
    func constructMenu() {
        monitorMenuItem = mainMenu.addItem(withTitle: t("device_not_set"), action: nil, keyEquivalent: "")
        
        var item: NSMenuItem

        item = mainMenu.addItem(withTitle: t("lock_now"), action: #selector(lockNow), keyEquivalent: "")
        lockNowMenuItem = item
        mainMenu.addItem(NSMenuItem.separator())

        item = mainMenu.addItem(withTitle: t("device"), action: nil, keyEquivalent: "")
        item.submenu = deviceMenu
        deviceMenu.delegate = self
        deviceMenu.addItem(withTitle: t("scanning"), action: nil, keyEquivalent: "")

        let unlockSettingsItem = mainMenu.addItem(withTitle: t("unlock_settings"), action: nil, keyEquivalent: "")
        unlockSettingsItem.submenu = unlockSettingsMenu
        addSettingsItem(unlockSettingsMenu, title: t("any_short"), action: #selector(setUnlockDeviceLogic), tag: UnlockDeviceLogic.anyClose.rawValue, kind: unlockLogicMenuItemKind)
        addSettingsItem(unlockSettingsMenu, title: t("all_short"), action: #selector(setUnlockDeviceLogic), tag: UnlockDeviceLogic.allClose.rawValue, kind: unlockLogicMenuItemKind)
        unlockSettingsMenu.addItem(NSMenuItem.separator())
        constructRSSISection(unlockSettingsMenu,
                             #selector(setUnlockRSSI),
                             kind: unlockRSSIMenuItemKind,
                             disabledTag: ble.UNLOCK_DISABLED,
                             disabledFirst: true)

        let lockSettingsItem = mainMenu.addItem(withTitle: t("lock_settings"), action: nil, keyEquivalent: "")
        lockSettingsItem.submenu = lockSettingsMenu
        addSettingsItem(lockSettingsMenu, title: t("any_short"), action: #selector(setLockDeviceLogic), tag: LockDeviceLogic.anyAway.rawValue, kind: lockLogicMenuItemKind)
        addSettingsItem(lockSettingsMenu, title: t("all_short"), action: #selector(setLockDeviceLogic), tag: LockDeviceLogic.allAway.rawValue, kind: lockLogicMenuItemKind)
        lockSettingsMenu.addItem(NSMenuItem.separator())
        constructRSSISection(lockSettingsMenu,
                             #selector(setLockRSSI),
                             kind: lockRSSIMenuItemKind,
                             disabledTag: ble.LOCK_DISABLED,
                             disabledFirst: false)

        let lockDelayItem = mainMenu.addItem(withTitle: t("lock_delay"), action: nil, keyEquivalent: "")
        lockDelayItem.submenu = lockDelayMenu
        lockDelayMenu.addItem(withTitle: "2 " + t("seconds"), action: #selector(setLockDelay), keyEquivalent: "").tag = 2
        lockDelayMenu.addItem(withTitle: "5 " + t("seconds"), action: #selector(setLockDelay), keyEquivalent: "").tag = 5
        lockDelayMenu.addItem(withTitle: "15 " + t("seconds"), action: #selector(setLockDelay), keyEquivalent: "").tag = 15
        lockDelayMenu.addItem(withTitle: "30 " + t("seconds"), action: #selector(setLockDelay), keyEquivalent: "").tag = 30
        lockDelayMenu.addItem(withTitle: "1 " + t("minute"), action: #selector(setLockDelay), keyEquivalent: "").tag = 60
        lockDelayMenu.addItem(withTitle: "2 " + t("minutes"), action: #selector(setLockDelay), keyEquivalent: "").tag = 120
        lockDelayMenu.addItem(withTitle: "5 " + t("minutes"), action: #selector(setLockDelay), keyEquivalent: "").tag = 300
        lockDelayMenu.delegate = self

        let timeoutItem = mainMenu.addItem(withTitle: t("timeout"), action: nil, keyEquivalent: "")
        timeoutItem.submenu = timeoutMenu
        timeoutMenu.addItem(withTitle: "30 " + t("seconds"), action: #selector(setTimeout), keyEquivalent: "").tag = 30
        timeoutMenu.addItem(withTitle: "1 " + t("minute"), action: #selector(setTimeout), keyEquivalent: "").tag = 60
        timeoutMenu.addItem(withTitle: "2 " + t("minutes"), action: #selector(setTimeout), keyEquivalent: "").tag = 120
        timeoutMenu.addItem(withTitle: "5 " + t("minutes"), action: #selector(setTimeout), keyEquivalent: "").tag = 300
        timeoutMenu.addItem(withTitle: "10 " + t("minutes"), action: #selector(setTimeout), keyEquivalent: "").tag = 600
        timeoutMenu.delegate = self

        item = mainMenu.addItem(withTitle: t("wake_on_proximity"), action: #selector(toggleWakeOnProximity), keyEquivalent: "")
        if prefs.bool(forKey: "wakeOnProximity") {
            item.state = .on
        }

        item = mainMenu.addItem(withTitle: t("wake_without_unlocking"), action: #selector(toggleWakeWithoutUnlocking), keyEquivalent: "")
        if prefs.bool(forKey: "wakeWithoutUnlocking") {
            item.state = .on
        }

        item = mainMenu.addItem(withTitle: t("pause_now_playing"), action: #selector(togglePauseNowPlaying), keyEquivalent: "")
        if prefs.bool(forKey: "pauseItunes") {
            item.state = .on
        }

        item = mainMenu.addItem(withTitle: t("use_screensaver_to_lock"), action: #selector(toggleUseScreensaver), keyEquivalent: "")
        if prefs.bool(forKey: "screensaver") {
            item.state = .on
        }

        item = mainMenu.addItem(withTitle: t("sleep_display"), action: #selector(toggleSleepDisplay), keyEquivalent: "")
        if prefs.bool(forKey: "sleepDisplay") {
            item.state = .on
        }
        
        mainMenu.addItem(withTitle: t("set_password"), action: #selector(askPassword), keyEquivalent: "")

        item = mainMenu.addItem(withTitle: t("passive_mode"), action: #selector(togglePassiveMode), keyEquivalent: "")
        item.state = prefs.bool(forKey: "passiveMode") ? .on : .off
        
        item = mainMenu.addItem(withTitle: t("launch_at_login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.state = isLaunchAtLoginEnabled() ? .on : .off
        
        mainMenu.addItem(withTitle: t("set_rssi_threshold"), action: #selector(setRSSIThreshold),
                         keyEquivalent: "")
        let updateItem = mainMenu.addItem(withTitle: t("updates"), action: nil, keyEquivalent: "")
        updateMenuItem = updateItem
        updateItem.submenu = updateMenu
        item = updateMenu.addItem(withTitle: t("automatically_check_for_updates"), action: #selector(toggleAutomaticUpdateChecks), keyEquivalent: "")
        automaticUpdateChecksMenuItem = item
        item.state = automaticUpdateChecksEnabled() ? .on : .off
        checkForUpdatesMenuItem = updateMenu.addItem(withTitle: t("check_for_updates"), action: #selector(checkForUpdates),
                                                     keyEquivalent: "")
        refreshUpdateMenuItems()

        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(withTitle: t("about"), action: #selector(showAboutBox), keyEquivalent: "")
        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(withTitle: t("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = mainMenu
    }

    @discardableResult
    func checkAccessibility(showPrompt: Bool = true) -> Bool {
        let trusted: Bool
        if showPrompt {
            let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
            trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            trusted = AXIsProcessTrusted()
        }
        if !trusted && showPrompt {
            // Sometimes Prompt option above doesn't work.
            // Actually trying to send key may open that dialog.
            let src = CGEventSource(stateID: .hidSystemState)
            // "Fn" key down and up
            CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: false)?.post(tap: .cghidEventTap)
        }
        return trusted
    }

    func requiresAccessibilityPermission() -> Bool {
        ble.unlockRSSI != ble.UNLOCK_DISABLED && !prefs.bool(forKey: "wakeWithoutUnlocking")
    }

    func refreshPermissionRecovery() {
        let accessibilityTrusted = !requiresAccessibilityPermission() || checkAccessibility(showPrompt: false)
        ble.recoverAfterPermissionChangeIfNeeded()
        guard !accessibilityTrusted || ble.needsPermissionRecovery else {
            permissionRecoveryTimer?.invalidate()
            permissionRecoveryTimer = nil
            return
        }
        guard permissionRecoveryTimer == nil else { return }
        permissionRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { [weak self] _ in
            self?.refreshPermissionRecovery()
        })
        if let timer = permissionRecoveryTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func startPermissionRecovery(promptAccessibility: Bool) {
        if requiresAccessibilityPermission() {
            _ = checkAccessibility(showPrompt: promptAccessibility)
        }
        refreshPermissionRecovery()
    }

    func launcherBundleIdentifier() -> String {
        (Bundle.main.bundleIdentifier ?? currentAppBundleIdentifier) + launcherBundleIDSuffix
    }

    func disableLegacyLoginItem() {
        disableLegacyLoginItems()
        _ = SMLoginItemSetEnabled(launcherBundleIdentifier() as CFString, false)
    }

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: launcherBundleIdentifier())
            switch service.status {
            case .enabled, .requiresApproval:
                return true
            case .notRegistered, .notFound:
                return false
            @unknown default:
                return prefs.bool(forKey: "launchAtLogin")
            }
        }
        return prefs.bool(forKey: "launchAtLogin")
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool, showErrors: Bool = true) -> Bool {
        if #available(macOS 13.0, *) {
            disableLegacyLoginItem()
            let service = SMAppService.loginItem(identifier: launcherBundleIdentifier())
            do {
                if enabled {
                    try service.register()
                    if service.status == .requiresApproval && showErrors {
                        errorModal("BLEUnlock needs approval in Login Items.",
                                   info: "Open System Settings > General > Login Items and allow BLEUnlock.")
                    }
                } else {
                    try service.unregister()
                }
                return true
            } catch {
                if enabled && service.status == .enabled {
                    return true
                }
                if !enabled && service.status == .notRegistered {
                    return true
                }
                if showErrors {
                    errorModal("Failed to update Launch at Login", info: error.localizedDescription)
                } else {
                    print("Launch at Login update failed: \(error.localizedDescription)")
                }
                return false
            }
        }

        let ok = SMLoginItemSetEnabled(launcherBundleIdentifier() as CFString, enabled)
        if !ok && showErrors {
            errorModal("Failed to update Launch at Login")
        }
        return ok
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        migrateLegacyAppDataIfNeeded()

        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarDisconnected")
            constructMenu()
        }
        ble.delegate = self
        let monitoredUUIDs = loadMonitoredUUIDs()
        if !monitoredUUIDs.isEmpty {
            monitorDevices(uuids: monitoredUUIDs)
        }
        if prefs.object(forKey: "unlockDeviceLogic") != nil,
           let logic = UnlockDeviceLogic(rawValue: prefs.integer(forKey: "unlockDeviceLogic")) {
            ble.unlockDeviceLogic = logic
        } else if prefs.object(forKey: "multiDeviceLogic") != nil,
                  let legacyLogic = UnlockDeviceLogic(rawValue: prefs.integer(forKey: "multiDeviceLogic")) {
            ble.unlockDeviceLogic = legacyLogic
        }
        if prefs.object(forKey: "lockDeviceLogic") != nil,
           let logic = LockDeviceLogic(rawValue: prefs.integer(forKey: "lockDeviceLogic")) {
            ble.lockDeviceLogic = logic
        } else if prefs.object(forKey: "multiDeviceLogic") != nil {
            let legacyValue = prefs.integer(forKey: "multiDeviceLogic")
            ble.lockDeviceLogic = legacyValue == 0 ? .allAway : .anyAway
        }
        let lockRSSI = prefs.integer(forKey: "lockRSSI")
        if lockRSSI != 0 {
            ble.lockRSSI = lockRSSI
        }
        let unlockRSSI = prefs.integer(forKey: "unlockRSSI")
        if unlockRSSI != 0 {
            ble.unlockRSSI = unlockRSSI
        }
        let timeout = prefs.integer(forKey: "timeout")
        if timeout != 0 {
            ble.signalTimeout = Double(timeout)
        }
        ble.setPassiveMode(prefs.bool(forKey: "passiveMode"))
        let thresholdRSSI = prefs.integer(forKey: "thresholdRSSI")
        if thresholdRSSI != 0 {
            ble.thresholdRSSI = thresholdRSSI
        }
        let lockDelay = prefs.integer(forKey: "lockDelay")
        if lockDelay != 0 {
            ble.proximityTimeout = Double(lockDelay)
        }

        if #available(macOS 10.14, *) {
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.delegate = self
            requestNotificationAuthorization()
        } else {
            NSUserNotificationCenter.default.delegate = self
        }

        let nc = NSWorkspace.shared.notificationCenter;
        nc.addObserver(self, selector: #selector(onDisplaySleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(onDisplayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(onSystemSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(onSystemWake), name: NSWorkspace.didWakeNotification, object: nil)

        let dnc = DistributedNotificationCenter.default
        dnc.addObserver(self, selector: #selector(onUnlock), name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)
        dnc.addObserver(self, selector: #selector(onScreensaverStart), name: NSNotification.Name(rawValue: "com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(onScreensaverStop), name: NSNotification.Name(rawValue: "com.apple.screensaver.didstop"), object: nil)

        if ble.unlockRSSI != ble.UNLOCK_DISABLED && !prefs.bool(forKey: "wakeWithoutUnlocking") && fetchPassword() == nil {
            askPassword()
        }
        if prefs.bool(forKey: "launchAtLogin") {
            _ = setLaunchAtLogin(true, showErrors: false)
        }
        startPermissionRecovery(promptAccessibility: true)
        runAutomaticUpdateCheck()
        if prefs.bool(forKey: "pauseItunes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.requestAutomationPermissionsIfNeeded()
            }
        }

        // Hide dock icon.
        // This is required because we can't have LSUIElement set to true in Info.plist,
        // otherwise CBCentralManager.scanForPeripherals won't work.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissionRecovery()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = nil
    }
}
