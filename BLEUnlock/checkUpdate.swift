import Cocoa

private let KEY = "lastUpdateCheck"
private let INTERVAL = 24.0 * 60 * 60
private var notified = false
private var lastCheckAt = UserDefaults.standard.double(forKey: KEY)

func checkUpdate() {
    guard !notified else { return }
    let now = NSDate().timeIntervalSince1970
    guard now - lastCheckAt >= INTERVAL else { return }
    doCheckUpdate()
}

private func doCheckUpdate() {
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/Skyearn/BLEUnlock/releases/latest")!)
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
        if let jsondata = data {
            if let json = try? JSONSerialization.jsonObject(with: jsondata) {
                if let dict = json as? [String:Any] {
                    if let version = dict["tag_name"] as? String {
                        lastCheckAt = NSDate().timeIntervalSince1970
                        UserDefaults.standard.set(lastCheckAt, forKey: KEY)
                        compareVersionsAndNotify(version)
                    }
                }
            }
        }
    })
    task.resume()
}

private func normalizedVersion(_ version: String) -> String {
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasPrefix("v") {
        return String(trimmed.dropFirst())
    }
    return trimmed
}

private func compareVersionsAndNotify(_ latestVersion: String) {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        if normalizedVersion(version) != normalizedVersion(latestVersion) {
            notify()
            notified = true
        }
    }
}

private func notify() {
    notifyUpdateAvailable()
}
