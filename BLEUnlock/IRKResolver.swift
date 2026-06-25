// IRK-based Resolvable Private Address (RPA) resolution for paired BLE devices.
// IRKs are stored in UserDefaults (deviceIRKs) after a one-time import from
// Keychain Access — the app does not read the System keychain directly because
// that triggers repeated administrator password prompts.

import Foundation
import IOBluetooth

struct IRKBinding: Equatable {
    let name: String
    let publicMAC: String
    let irk: Data
}

enum IRKImportResult {
    case success(name: String, mac: String)
    case failure(String)
}

enum IRKResolver {
    private static let prefsKey = "deviceIRKs"
    private static let cacheTTL: TimeInterval = 120
    private static var cachedBindings: [IRKBinding]?
    private static var cacheTimestamp: TimeInterval = 0

    // MARK: - Public API

    static func refreshBindings(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, cachedBindings != nil, now - cacheTimestamp < cacheTTL {
            return
        }
        cacheTimestamp = now
        cachedBindings = loadBindings()
        macInheritLog("IRKResolver: loaded \(cachedBindings?.count ?? 0) binding(s)")
        for b in cachedBindings ?? [] {
            macInheritLog("  IRK binding: \(b.name) publicMAC=\(b.publicMAC)")
        }
    }

    /// Paired classic-Bluetooth devices available for IRK import UI.
    static func pairedDevicesForImport() -> [(mac: String, name: String)] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.compactMap { dev in
            guard let addr = dev.addressString else { return nil }
            return (canonicalMAC(addr), dev.name ?? canonicalMAC(addr))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func storedIRKHex(forMAC mac: String) -> String? {
        guard let dict = UserDefaults.standard.dictionary(forKey: prefsKey) as? [String: String] else {
            return nil
        }
        return dict[canonicalMAC(mac)]
    }

    /// Parse pasted Keychain XML, base64, or hex and persist for `mac`.
    static func importIRK(forMAC mac: String, pastedContent: String) -> IRKImportResult {
        let canonical = canonicalMAC(mac)
        guard let irk = extractRemoteIRK(from: pastedContent.data(using: .utf8))
            ?? parseIRKHex(pastedContent.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? parseIRKBase64(pastedContent.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure("Could not find a valid Remote IRK in the pasted text.")
        }

        let hex = irk.map { String(format: "%02x", $0) }.joined()
        var dict = UserDefaults.standard.dictionary(forKey: prefsKey) as? [String: String] ?? [:]
        dict[canonical] = hex
        UserDefaults.standard.set(dict, forKey: prefsKey)

        invalidateCache()
        refreshBindings(force: true)

        let name = nameForPublicMAC(canonical) ?? canonical
        macInheritLog("IRKResolver: imported IRK for \(name) (\(canonical))")
        return .success(name: name, mac: canonical)
    }

    static func removeIRK(forMAC mac: String) {
        let canonical = canonicalMAC(mac)
        guard var dict = UserDefaults.standard.dictionary(forKey: prefsKey) as? [String: String] else { return }
        dict.removeValue(forKey: canonical)
        UserDefaults.standard.set(dict, forKey: prefsKey)
        invalidateCache()
    }

    /// Resolve stable identity from CoreBluetooth plist cache + IRK for a peripheral UUID.
    static func stableIdentityForPeripheralUUID(_ uuid: String) -> (mac: String, name: String)? {
        refreshBindings()
        guard let addr = getMACFromUUID(uuid) else { return nil }
        if let stable = resolveStableIdentity(forBLEAddress: addr) {
            return stable
        }
        let normalized = canonicalMAC(addr)
        for binding in cachedBindings ?? [] where binding.publicMAC == normalized {
            return (binding.publicMAC, binding.name)
        }
        return nil
    }

    /// When exactly one IRK is configured, map Fast Pair `Android-XXXX` beacons to it.
    static func soleBindingIfAvailable() -> (mac: String, name: String)? {
        refreshBindings()
        guard let bindings = cachedBindings, bindings.count == 1, let b = bindings.first else { return nil }
        return (b.publicMAC, b.name)
    }

    /// Given a BLE address (often an RPA from CoreBluetooth cache), return the
    /// stable public MAC and device name when an IRK match is found.
    static func resolveStableIdentity(forBLEAddress address: String) -> (mac: String, name: String)? {
        guard let bytes = macToBytes(address) else { return nil }
        guard isResolvablePrivateAddress(bytes) else { return nil }

        refreshBindings()
        guard let bindings = cachedBindings, !bindings.isEmpty else { return nil }

        for binding in bindings {
            if rpaMatches(irk: binding.irk, addressBytes: bytes) {
                macInheritLog("IRKResolver: RPA \(address) -> \(binding.name) (\(binding.publicMAC))")
                return (binding.publicMAC, binding.name)
            }
            let reversed = Data(binding.irk.reversed())
            if rpaMatches(irk: reversed, addressBytes: bytes) {
                macInheritLog("IRKResolver: RPA \(address) -> \(binding.name) (\(binding.publicMAC)) [byte-reversed IRK]")
                return (binding.publicMAC, binding.name)
            }
        }
        return nil
    }

    /// Scan CoreBluetooth cache entries and return UUID → stable identity for RPAs.
    static func resolvedIdentitiesFromBluetoothCache() -> [String: (mac: String, name: String)] {
        refreshBindings()
        guard cachedBindings?.isEmpty == false else { return [:] }

        let (_, ledevices) = cachedBTResources()
        var result: [String: (mac: String, name: String)] = [:]
        for (uuid, device) in ledevices {
            guard let addr = device["DeviceAddress"] as? String,
                  let stable = resolveStableIdentity(forBLEAddress: addr) else { continue }
            result[uuid] = stable
        }
        return result
    }

    // MARK: - RPA cryptography (Bluetooth Core Spec ah function)

    private static func invalidateCache() {
        cachedBindings = nil
        cacheTimestamp = 0
    }

    private static func isResolvablePrivateAddress(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 6 else { return false }
        return (bytes[0] & 0xC0) == 0x40
    }

    private static func rpaMatches(irk: Data, addressBytes: [UInt8]) -> Bool {
        guard irk.count == 16, addressBytes.count == 6 else { return false }
        let prand = Array(addressBytes[3...5])
        guard let hash = ah(irk: irk, prand: prand) else { return false }
        return hash[0] == addressBytes[0] && hash[1] == addressBytes[1] && hash[2] == addressBytes[2]
    }

    private static func ah(irk: Data, prand: [UInt8]) -> [UInt8]? {
        guard prand.count == 3, irk.count == 16 else { return nil }
        var block = [UInt8](repeating: 0, count: 16)
        block[0] = prand[0]
        block[1] = prand[1]
        block[2] = prand[2]

        var out = [UInt8](repeating: 0, count: 16)
        let status = irk.withUnsafeBytes { keyPtr in
            block.withUnsafeBytes { blockPtr in
                out.withUnsafeMutableBytes { outPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, kCCKeySizeAES128,
                        nil,
                        blockPtr.baseAddress, 16,
                        outPtr.baseAddress, 16,
                        nil
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Array(out.prefix(3))
    }

    // MARK: - IRK loading (UserDefaults only)

    private static func loadBindings() -> [IRKBinding] {
        var byMAC: [String: IRKBinding] = [:]

        for (mac, irk) in loadStoredIRKs() {
            let canonical = canonicalMAC(mac)
            let name = nameForPublicMAC(canonical) ?? canonical
            byMAC[canonical] = IRKBinding(name: name, publicMAC: canonical, irk: irk)
        }

        return Array(byMAC.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func loadStoredIRKs() -> [(String, Data)] {
        guard let dict = UserDefaults.standard.dictionary(forKey: prefsKey) as? [String: String] else {
            return []
        }
        var result: [(String, Data)] = []
        for (mac, hex) in dict {
            if let data = parseIRKHex(hex) {
                result.append((mac, data))
            }
        }
        return result
    }

    static func extractRemoteIRK(from data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }

        if data.count == 16 { return data }

        if let xml = String(data: data, encoding: .utf8) {
            if let irk = parseRemoteIRKFromXML(xml) { return irk }
        }

        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for key in ["Remote IRK", "RemoteIRK", "remoteIRK", "Local IRK", "LocalIRK"] {
                if let value = plist[key] as? Data, value.count == 16 { return value }
                if let b64 = plist[key] as? String, let irk = parseIRKBase64(b64) { return irk }
            }
            if let remote = plist["Remote Encryption"] as? [String: Any] {
                for key in ["Identity Resolving Key", "IRK", "Remote IRK"] {
                    if let value = remote[key] as? Data, value.count == 16 { return value }
                    if let b64 = remote[key] as? String, let irk = parseIRKBase64(b64) { return irk }
                }
            }
        }

        return nil
    }

    private static func parseRemoteIRKFromXML(_ xml: String) -> Data? {
        guard let range = xml.range(of: "Remote IRK", options: .caseInsensitive) else { return nil }
        let tail = xml[range.upperBound...]
        guard let dataOpen = tail.range(of: "<data>"),
              let dataClose = tail.range(of: "</data>") else { return nil }
        let b64 = String(tail[dataOpen.upperBound..<dataClose.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parseIRKBase64(b64)
    }

    private static func parseIRKBase64(_ b64: String) -> Data? {
        guard let raw = Data(base64Encoded: b64), raw.count == 16 else { return nil }
        return raw
    }

    private static func parseIRKHex(_ hex: String) -> Data? {
        let cleaned = hex.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count == 32, let data = dataFromHex(cleaned) else { return nil }
        return data
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next <= hex.endIndex else { return nil }
            let byte = hex[index..<next]
            guard let value = UInt8(byte, radix: 16) else { return nil }
            data.append(value)
            index = next
        }
        return data
    }

    private static func nameForPublicMAC(_ mac: String) -> String? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let target = canonicalMAC(mac)
        for dev in paired {
            guard let addr = dev.addressString else { continue }
            if canonicalMAC(addr) == target {
                return dev.name
            }
        }
        return getNameFromMAC(mac)
    }

    private static func macToBytes(_ mac: String) -> [UInt8]? {
        let parts = canonicalMAC(mac).split(separator: "-")
        guard parts.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part, radix: 16) else { return nil }
            bytes.append(value)
        }
        return bytes
    }
}
