import Foundation
import CoreBluetooth
import Accelerate

let DeviceInformation = CBUUID(string:"180A")
let ManufacturerName = CBUUID(string:"2A29")
let ModelName = CBUUID(string:"2A24")
let ExposureNotification = CBUUID(string:"FD6F")
let nameResolutionLogPath = "/tmp/BLEUnlock-name-resolution.log"

func appendNameResolutionLog(_ message: String) {
    let line = message + "\n"
    let data = Data(line.utf8)
    let fileManager = FileManager.default

    if !fileManager.fileExists(atPath: nameResolutionLogPath) {
        fileManager.createFile(atPath: nameResolutionLogPath, contents: nil)
    }

    guard let handle = FileHandle(forWritingAtPath: nameResolutionLogPath) else { return }
    handle.seekToEndOfFile()
    handle.write(data)
    handle.closeFile()
}

func getMACFromUUID(_ uuid: String) -> String? {
    guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") else { return nil }
    guard let cbcache = plist["CoreBluetoothCache"] as? NSDictionary else { return nil }
    guard let device = cbcache[uuid] as? NSDictionary else { return nil }
    return device["DeviceAddress"] as? String
}

func getNameFromMAC(_ mac: String) -> String? {
    guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") else { return nil }
    guard let devcache = plist["DeviceCache"] as? NSDictionary else { return nil }
    guard let device = devcache[mac] as? NSDictionary else { return nil }
    if let name = device["Name"] as? String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed == "" { return nil }
        return trimmed
    }
    return nil
}

class Device: NSObject {
    let uuid : UUID!
    var peripheral : CBPeripheral?
    var manufacture : String?
    var model : String?
    var advData: Data?
    var rssi: Int = 0
    var isVisible = false
    var scanTimer: Timer?
    var macAddr: String?
    var blName: String?
    var advertisedLocalName: String?
    var lastNameDebugSnapshot: String?

    func normalizedName(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespaces), !candidate.isEmpty else { return nil }
        return candidate
    }

    func looksLikeTemporaryBroadcastName(_ candidate: String) -> Bool {
        if candidate == "N/A" {
            return true
        }
        if candidate.count >= 12 && candidate.contains("/") && !candidate.contains(" ") {
            return true
        }

        if candidate.count < 16 {
            return false
        }

        let hasUpper = candidate.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = candidate.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasDigit = candidate.rangeOfCharacter(from: .decimalDigits) != nil
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_/"))
        let onlySimpleCharacters = candidate.rangeOfCharacter(from: allowed.inverted) == nil
        return onlySimpleCharacters && ((hasUpper && hasLower) || (hasUpper && hasDigit) || (hasLower && hasDigit))
    }

    func isGenericAppleName(_ name: String) -> Bool {
        name == "iPhone" || name == "iPad"
    }

    func updateNameIfNeeded(_ candidate: String?) {
        guard let candidate = normalizedName(candidate) else { return }
        if blName == nil || blName == uuid.description {
            blName = candidate
        }
    }

    func updateAdvertisedNameIfNeeded(_ candidate: String?) {
        guard let candidate = normalizedName(candidate) else { return }
        if looksLikeTemporaryBroadcastName(candidate),
           let peripheralName = normalizedName(peripheral?.name),
           peripheralName != candidate {
            return
        }
        updateNameIfNeeded(candidate)
    }

    func currentResolvedName() -> String? {
        let peripheralName = normalizedName(peripheral?.name)
        if let cachedName = normalizedName(blName),
           looksLikeTemporaryBroadcastName(cachedName),
           let peripheralName,
           peripheralName != cachedName {
            blName = peripheralName
            return peripheralName
        }

        if let name = normalizedName(blName) {
            return name
        }

        if let name = peripheralName {
            blName = name
            return name
        }

        if let manu = manufacture {
            if let mod = model {
                if manu == "Apple Inc.", let appleName = appleDeviceNames[mod] {
                    return appleName
                }
                return String(format: "%@/%@", manu, mod)
            } else {
                return manu
            }
        }

        if let mod = model {
            return mod
        }

        if macAddr == nil || blName == nil {
            if let info = getLEDeviceInfoFromUUID(uuid.description) {
                updateNameIfNeeded(info.name)
                macAddr = macAddr ?? info.macAddr
            }
        }

        if macAddr == nil {
            macAddr = getMACFromUUID(uuid.description)
        }

        if let mac = macAddr, blName == nil {
            blName = getNameFromMAC(mac)
        }

        if let adv = advData, adv.count >= 25 {
            var iBeaconPrefix : [uint16] = [0x004c, 0x01502]
            if adv[0...3] == Data(bytes: &iBeaconPrefix, count: 4) {
                let major = uint16(adv[20]) << 8 | uint16(adv[21])
                let minor = uint16(adv[22]) << 8 | uint16(adv[23])
                let tx = Int8(bitPattern: adv[24])
                let distance = pow(10, Double(Int(tx) - rssi)/20.0)
                let d = String(format:"%.1f", distance)
                return "iBeacon [\(major), \(minor)] \(d)m"
            }
        }

        if let name = blName {
            return name
        }

        if let mac = macAddr {
            return mac
        }

        return nil
    }

    func logNameResolutionIfNeeded(context: String) {
        let peripheralName = normalizedName(peripheral?.name)
        let leInfo = getLEDeviceInfoFromUUID(uuid.description)
        let leName = normalizedName(leInfo?.name)
        let leMac = leInfo?.macAddr
        let plistMac = getMACFromUUID(uuid.description)
        let plistName = normalizedName((plistMac ?? macAddr).flatMap(getNameFromMAC))
        let resolvedName = currentResolvedName()

        let finalSource: String
        if normalizedName(advertisedLocalName) != nil {
            finalSource = "advertisementData.localName"
        } else if peripheralName != nil {
            finalSource = "CBPeripheral.name"
        } else if manufacture != nil || model != nil {
            finalSource = "Device Information service"
        } else if leName != nil {
            finalSource = "Bluetooth database"
        } else if plistName != nil {
            finalSource = "Bluetooth plist cache"
        } else if resolvedName?.hasPrefix("iBeacon [") == true {
            finalSource = "iBeacon manufacturer data"
        } else if leMac != nil || plistMac != nil || macAddr != nil {
            finalSource = "MAC address only"
        } else {
            finalSource = "UUID fallback"
        }

        let snapshot = [
            "uuid=\(uuid!.uuidString)",
            "context=\(context)",
            "rssi=\(rssi)",
            "advLocalName=\(advertisedLocalName ?? "<nil>")",
            "peripheralName=\(peripheralName ?? "<nil>")",
            "manufacturer=\(manufacture ?? "<nil>")",
            "model=\(model ?? "<nil>")",
            "dbName=\(leName ?? "<nil>")",
            "dbMac=\(leMac ?? "<nil>")",
            "plistMac=\(plistMac ?? "<nil>")",
            "plistName=\(plistName ?? "<nil>")",
            "finalSource=\(finalSource)",
            "finalValue=\(resolvedName ?? uuid.uuidString)"
        ].joined(separator: " | ")

        guard snapshot != lastNameDebugSnapshot else { return }
        lastNameDebugSnapshot = snapshot
        let message = "[BLEUnlock][NameResolution] \(snapshot)"
        NSLog("%@", message)
        appendNameResolutionLog(message)
    }
    
    override var description: String {
        get {
            return currentResolvedName() ?? uuid.description
        }
    }

    init(uuid _uuid: UUID) {
        uuid = _uuid
    }
}

protocol BLEDelegate {
    func newDevice(device: Device)
    func updateDevice(device: Device)
    func removeDevice(device: Device)
    func updateRSSI(rssi: Int?, active: Bool)
    func updatePresence(shouldUnlock: Bool, shouldLock: Bool, reason: String)
    func bluetoothPowerWarn()
}

enum UnlockDeviceLogic: Int {
    case anyClose = 0
    case allClose = 1
}

enum LockDeviceLogic: Int {
    case allAway = 0
    case anyAway = 1
}

class MonitoredDeviceState {
    let uuid: UUID
    weak var peripheral: CBPeripheral?
    var proximityTimer: Timer?
    var signalTimer: Timer?
    var latestRSSIs: [Double] = []
    var lastReadAt = 0.0
    var activeModeTimer: Timer?
    var connectionTimer: Timer?
    var presence = true
    var lastRSSI: Int?

    init(uuid: UUID) {
        self.uuid = uuid
    }

    var active: Bool {
        activeModeTimer != nil
    }

    func invalidateTimers() {
        proximityTimer?.invalidate()
        signalTimer?.invalidate()
        activeModeTimer?.invalidate()
        connectionTimer?.invalidate()
        proximityTimer = nil
        signalTimer = nil
        activeModeTimer = nil
        connectionTimer = nil
    }
}

class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let UNLOCK_DISABLED = 1
    let LOCK_DISABLED = -100
    var centralMgr : CBCentralManager!
    var devices : [UUID : Device] = [:]
    var delegate: BLEDelegate?
    var scanMode = false
    var monitoredUUIDs: Set<UUID> = []
    var monitoredStates: [UUID: MonitoredDeviceState] = [:]
    var presence = false
    var shouldLock = false
    var unlockDeviceLogic: UnlockDeviceLogic = .anyClose
    var lockDeviceLogic: LockDeviceLogic = .allAway
    var lockRSSI = -80
    var unlockRSSI = -60
    var proximityTimeout = 5.0
    var signalTimeout = 60.0
    var powerWarn = true
    var passiveMode = false
    var thresholdRSSI = -70
    var latestN: Int = 5
    var lastAuthorizationRefreshAt = 0.0
    let minimumAuthorizationRefreshInterval = 2.0
    var monitoringSuspended = false

    var needsPermissionRecovery: Bool {
        guard scanMode || !monitoredUUIDs.isEmpty else { return false }
        switch centralMgr.state {
        case .unauthorized, .unknown, .resetting:
            return true
        default:
            return false
        }
    }

    func recoverAfterPermissionChangeIfNeeded() {
        guard !monitoringSuspended else { return }
        if centralMgr.state == .poweredOn {
            scanForPeripherals()
            return
        }
        guard needsPermissionRecovery else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastAuthorizationRefreshAt >= minimumAuthorizationRefreshInterval else { return }
        lastAuthorizationRefreshAt = now
        print("Refreshing Bluetooth authorization state")
        centralMgr.stopScan()
        centralMgr.delegate = nil
        centralMgr = CBCentralManager(delegate: self, queue: nil)
    }

    func scanForPeripherals() {
        guard !monitoringSuspended else { return }
        guard !centralMgr.isScanning else { return }
        guard centralMgr.state == .poweredOn else { return }
        centralMgr.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        //print("Start scanning")
    }

    func startScanning() {
        scanMode = true
        scanForPeripherals()
    }

    func stopScanning() {
        scanMode = false
        if monitoredStates.values.contains(where: { $0.active }) {
            centralMgr.stopScan()
        }
    }

    func setPassiveMode(_ mode: Bool) {
        passiveMode = mode
        if passiveMode {
            for state in monitoredStates.values {
                state.activeModeTimer?.invalidate()
                state.activeModeTimer = nil
                state.connectionTimer?.invalidate()
                state.connectionTimer = nil
                if let p = state.peripheral {
                    centralMgr.cancelPeripheralConnection(p)
                }
            }
        }
        scanForPeripherals()
    }

    func suspendMonitoringForSystemSleep() {
        guard !monitoringSuspended else { return }
        monitoringSuspended = true
        centralMgr.stopScan()

        for state in monitoredStates.values {
            state.invalidateTimers()
            state.lastRSSI = nil
            state.lastReadAt = 0
            state.latestRSSIs.removeAll()
            state.presence = false
            if let peripheral = state.peripheral, peripheral.state != .disconnected {
                centralMgr.cancelPeripheralConnection(peripheral)
            }
        }

        for device in devices.values {
            device.scanTimer?.invalidate()
            device.scanTimer = nil
            device.isVisible = false
            if !isMonitoring(uuid: device.uuid),
               let peripheral = device.peripheral,
               peripheral.state != .disconnected {
                centralMgr.cancelPeripheralConnection(peripheral)
            }
        }

        presence = false
        shouldLock = false
        updateAggregateRSSI()
    }

    func resumeMonitoringAfterSystemWake() {
        guard monitoringSuspended else { return }
        monitoringSuspended = false
        guard scanMode || !monitoredUUIDs.isEmpty else { return }
        scanForPeripherals()
    }

    func isMonitoring(uuid: UUID) -> Bool {
        monitoredUUIDs.contains(uuid)
    }

    func stopMonitoring(_ state: MonitoredDeviceState) {
        state.invalidateTimers()
        if let p = state.peripheral {
            centralMgr.cancelPeripheralConnection(p)
        }
    }

    func startMonitor(uuid: UUID) {
        startMonitor(uuids: Set([uuid]))
    }

    func startMonitor(uuids: Set<UUID>) {
        let removed = monitoredUUIDs.subtracting(uuids)
        for uuid in removed {
            if let state = monitoredStates.removeValue(forKey: uuid) {
                stopMonitoring(state)
            }
        }

        monitoredUUIDs = uuids
        for uuid in uuids {
            let state = monitoredStates[uuid] ?? MonitoredDeviceState(uuid: uuid)
            state.presence = true
            state.latestRSSIs.removeAll()
            state.proximityTimer?.invalidate()
            state.proximityTimer = nil

            if let device = devices[uuid] {
                state.peripheral = device.peripheral ?? state.peripheral
                state.lastRSSI = device.rssi
                state.latestRSSIs.append(Double(device.rssi))
            } else {
                state.lastRSSI = nil
            }

            monitoredStates[uuid] = state
            resetSignalTimer(for: state)
        }

        presence = !uuids.isEmpty
        shouldLock = false
        updateAggregateRSSI()
        scanForPeripherals()
    }

    func setUnlockDeviceLogic(_ logic: UnlockDeviceLogic) {
        unlockDeviceLogic = logic
        updateAggregatePresence(reason: "logic")
    }

    func setLockDeviceLogic(_ logic: LockDeviceLogic) {
        lockDeviceLogic = logic
        updateAggregatePresence(reason: "logic")
    }

    func updateAggregatePresence(reason: String, notify: Bool = true) {
        let states = monitoredUUIDs.compactMap { monitoredStates[$0] }
        let newPresence: Bool
        let newShouldLock: Bool
        if states.isEmpty {
            newPresence = false
            newShouldLock = false
        } else {
            switch unlockDeviceLogic {
            case .anyClose:
                newPresence = states.contains(where: { $0.presence })
            case .allClose:
                newPresence = states.allSatisfy { $0.presence }
            }
            switch lockDeviceLogic {
            case .allAway:
                newShouldLock = states.allSatisfy { !$0.presence }
            case .anyAway:
                newShouldLock = states.contains(where: { !$0.presence })
            }
        }
        guard newPresence != presence || newShouldLock != shouldLock else { return }
        presence = newPresence
        shouldLock = newShouldLock
        if notify {
            delegate?.updatePresence(shouldUnlock: newPresence, shouldLock: newShouldLock, reason: reason)
        }
    }

    func updateAggregateRSSI() {
        let visibleStates = monitoredStates.values.filter { $0.lastRSSI != nil }
        let bestRSSI = visibleStates.compactMap(\.lastRSSI).max()
        let active = visibleStates.contains(where: { $0.active })
        delegate?.updateRSSI(rssi: bestRSSI, active: active)
    }

    func resetSignalTimer(for state: MonitoredDeviceState) {
        state.signalTimer?.invalidate()
        state.signalTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in
            print("Device \(state.uuid) is lost")
            state.lastRSSI = nil
            state.activeModeTimer?.invalidate()
            state.activeModeTimer = nil
            state.connectionTimer?.invalidate()
            state.connectionTimer = nil
            state.latestRSSIs.removeAll()
            self.updateAggregateRSSI()
            if state.presence {
                state.presence = false
                self.updateAggregatePresence(reason: "lost")
            }
        })
        if let timer = state.signalTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on")
            lastAuthorizationRefreshAt = 0
            if !monitoringSuspended && !monitoredStates.values.contains(where: { $0.active }) {
                scanForPeripherals()
            }
            powerWarn = false
        case .poweredOff:
            print("Bluetooth powered off")
            lastAuthorizationRefreshAt = 0
            for state in monitoredStates.values {
                state.invalidateTimers()
                state.lastRSSI = nil
                state.latestRSSIs.removeAll()
                state.presence = false
            }
            presence = false
            shouldLock = false
            updateAggregateRSSI()
            if powerWarn {
                powerWarn = false
                delegate?.bluetoothPowerWarn()
            }
        default:
            break
        }
    }
    
    func getEstimatedRSSI(state: MonitoredDeviceState, rssi: Int) -> Int {
        if state.latestRSSIs.count >= latestN {
            state.latestRSSIs.removeFirst()
        }
        state.latestRSSIs.append(Double(rssi))
        var mean: Double = 0.0
        var sddev: Double = 0.0
        vDSP_normalizeD(state.latestRSSIs, 1, nil, 1, &mean, &sddev, vDSP_Length(state.latestRSSIs.count))
        return Int(mean)
    }

    func updateMonitoredState(_ state: MonitoredDeviceState, rssi: Int) {
        if rssi >= (unlockRSSI == UNLOCK_DISABLED ? lockRSSI : unlockRSSI) && !state.presence {
            print("Device \(state.uuid) is close")
            state.presence = true
            state.latestRSSIs.removeAll() // Avoid bouncing
            updateAggregatePresence(reason: "close")
        }

        let estimatedRSSI = getEstimatedRSSI(state: state, rssi: rssi)
        state.lastRSSI = estimatedRSSI
        updateAggregateRSSI()

        if estimatedRSSI >= (lockRSSI == LOCK_DISABLED ? unlockRSSI : lockRSSI) {
            if let timer = state.proximityTimer {
                timer.invalidate()
                print("Proximity timer canceled for \(state.uuid)")
                state.proximityTimer = nil
            }
        } else if state.presence && state.proximityTimer == nil {
            state.proximityTimer = Timer.scheduledTimer(withTimeInterval: proximityTimeout, repeats: false, block: { _ in
                print("Device \(state.uuid) is away")
                state.presence = false
                self.updateAggregatePresence(reason: "away")
                state.proximityTimer = nil
            })
            if let timer = state.proximityTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
            print("Proximity timer started for \(state.uuid)")
        }
        resetSignalTimer(for: state)
    }

    func monitoredState(for peripheral: CBPeripheral) -> MonitoredDeviceState? {
        monitoredStates[peripheral.identifier]
    }

    func connectMonitoredPeripheral(_ state: MonitoredDeviceState) {
        guard let p = state.peripheral else { return }
        guard !monitoringSuspended else { return }
        guard centralMgr.state == .poweredOn else { return }

        if p.state == .connected {
            p.delegate = self
            p.readRSSI()
            return
        }

        guard p.state == .disconnected else { return }
        print("Connecting \(state.uuid)")
        centralMgr.connect(p, options: nil)
        state.connectionTimer?.invalidate()
        state.connectionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false, block: { _ in
            if p.state == .connecting {
                print("Connection timeout \(state.uuid)")
                self.centralMgr.cancelPeripheralConnection(p)
            }
        })
        if let timer = state.connectionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func resetScanTimer(device: Device) {
        device.scanTimer?.invalidate()
        device.scanTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in
            device.isVisible = false
            self.delegate?.removeDevice(device: device)
            if let p = device.peripheral, !self.isMonitoring(uuid: device.uuid) {
                self.centralMgr.cancelPeripheralConnection(p)
            }
            if !self.isMonitoring(uuid: device.uuid) {
                self.devices.removeValue(forKey: device.uuid)
            }
        })
        if let timer = device.scanTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    //MARK:- CBCentralManagerDelegate start

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber)
    {
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        if let state = monitoredStates[peripheral.identifier], !monitoringSuspended {
            state.peripheral = peripheral
            if !state.active {
                updateMonitoredState(state, rssi: rssi)
                if !passiveMode {
                    connectMonitoredPeripheral(state)
                }
            }
        }

        if (scanMode) {
            if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                for uuid in uuids {
                    if uuid == ExposureNotification {
                        //print("Device \(peripheral.identifier) Exposure Notification")
                        return
                    }
                }
            }
            let dev = devices[peripheral.identifier]
            var device: Device
            if (dev == nil) {
                device = Device(uuid: peripheral.identifier)
                if (rssi >= thresholdRSSI) {
                    device.peripheral = peripheral
                    device.rssi = rssi
                    device.isVisible = true
                    device.advData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
                    device.advertisedLocalName = device.normalizedName(advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                    device.updateAdvertisedNameIfNeeded(device.advertisedLocalName)
                    devices[peripheral.identifier] = device
                    central.connect(peripheral, options: nil)
                    device.logNameResolutionIfNeeded(context: "discover:new")
                    delegate?.newDevice(device: device)
                }
            } else {
                device = dev!
                device.peripheral = peripheral
                device.rssi = rssi
                device.isVisible = true
                device.advData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? device.advData
                device.advertisedLocalName = device.normalizedName(advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? device.advertisedLocalName
                device.updateAdvertisedNameIfNeeded(device.advertisedLocalName)
                device.logNameResolutionIfNeeded(context: "discover:update")
                delegate?.updateDevice(device: device)
            }
            resetScanTimer(device: device)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral)
    {
        peripheral.delegate = self
        if scanMode {
            peripheral.discoverServices([DeviceInformation])
        }
        if monitoringSuspended {
            centralMgr.cancelPeripheralConnection(peripheral)
            return
        }
        if let state = monitoredState(for: peripheral), !passiveMode {
            print("Connected \(state.uuid)")
            state.connectionTimer?.invalidate()
            state.connectionTimer = nil
            peripheral.readRSSI()
        }
    }

    //MARK:CBCentralManagerDelegate end -
    
    //MARK:- CBPeripheralDelegate start

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard !monitoringSuspended else { return }
        guard let state = monitoredState(for: peripheral) else { return }
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        updateMonitoredState(state, rssi: rssi)
        state.lastReadAt = Date().timeIntervalSince1970

        if state.activeModeTimer == nil && !passiveMode {
            print("Entering active mode for \(state.uuid)")
            if !scanMode {
                centralMgr.stopScan()
            }
            state.activeModeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { _ in
                if Date().timeIntervalSince1970 > state.lastReadAt + 10 {
                    print("Falling back to passive mode for \(state.uuid)")
                    self.centralMgr.cancelPeripheralConnection(peripheral)
                    state.activeModeTimer?.invalidate()
                    state.activeModeTimer = nil
                    self.scanForPeripherals()
                } else if peripheral.state == .connected {
                    peripheral.readRSSI()
                } else {
                    self.connectMonitoredPeripheral(state)
                }
            })
            if let timer = state.activeModeTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == DeviceInformation {
                    peripheral.discoverCharacteristics([ManufacturerName, ModelName], for: service)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?)
    {
        if let chars = service.characteristics {
            for chara in chars {
                if chara.uuid == ManufacturerName || chara.uuid == ModelName {
                    peripheral.readValue(for:chara)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        if let value = characteristic.value {
            let str: String? = String(data: value, encoding: .utf8)
            if let s = str {
                if let device = devices[peripheral.identifier] {
                    if characteristic.uuid == ManufacturerName {
                        device.manufacture = s
                        device.logNameResolutionIfNeeded(context: "characteristic:manufacturer")
                        delegate?.updateDevice(device: device)
                    }
                    if characteristic.uuid == ModelName {
                        device.model = s
                        device.logNameResolutionIfNeeded(context: "characteristic:model")
                        delegate?.updateDevice(device: device)
                    }
                    if device.model != nil && device.model != nil && !isMonitoring(uuid: device.uuid) {
                        centralMgr.cancelPeripheralConnection(peripheral)
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didModifyServices invalidatedServices: [CBService])
    {
        peripheral.discoverServices([DeviceInformation])
    }
    //MARK:CBPeripheralDelegate end -

    override init() {
        super.init()
        centralMgr = CBCentralManager(delegate: self, queue: nil)
    }
}
