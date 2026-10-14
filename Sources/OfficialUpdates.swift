import Foundation
import SwiftUI

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        let tokens = value.split(separator: ".", omittingEmptySubsequences: false)
        guard tokens.count == 3, tokens.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              tokens.compactMap({ Int($0) }).count == 3 else { return nil }
        parts = tokens.compactMap { Int($0) }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
struct OfficialRelease: Codable, Identifiable {
    let id: String
    let version: String
    let notes: String
    var title: String { id == "mouse" ? "鼠标固件" : id == "dongle" ? "接收器固件" : "官方 Mac 驱动" }
    var officialURL: URL { URL(string: id == "driver" ? "https://www.angrymiao.com/cn/am-master/" : "https://ammaster.angrymiao.com/mouse")! }
}

actor OfficialUpdateService {
    static let driverURL = "https://diy.angrymiao.com/api/version-manager/history-version?app_code=AM_Master&platform=mac"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 35
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()
    private func fetch(_ url: URL, body: Data? = nil) async throws -> Data {
        let hosts: Set<String> = ["ammaster.angrymiao.com", "diy.angrymiao.com"]
        guard url.scheme == "https", hosts.contains(url.host ?? "") else { throw MouseError.message("更新来源不在官方域名中") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        if let body { request.httpMethod = "POST"; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", hosts.contains(response.url?.host ?? ""), data.count < 8_000_000 else {
            throw MouseError.message("官方更新接口暂时不可用")
        }
        return data
    }
    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    func firmware() async throws -> [OfficialRelease] {
        // Read the public client manifest selector in memory; never execute or persist site scripts.
        let base = URL(string: "https://ammaster.angrymiao.com/mouse/")!
        let html = String(decoding: try await fetch(base), as: UTF8.self)
        guard let path = Self.capture(#"src="([^"]*assets/index-[^\"]+\.js)""#, in: html),
              let scriptURL = URL(string: path, relativeTo: base)?.absoluteURL, scriptURL.host == base.host else {
            throw MouseError.message("官方页面结构已变化，固件检查需要适配")
        }
        let script = String(decoding: try await fetch(scriptURL), as: UTF8.self)
        var results: [OfficialRelease] = []
        for kind in ["mouse", "dongle"] {
            let key = "AM_35_" + kind.uppercased()
            guard let selector = Self.capture("key:\"" + key + "\",password:\"([^\"]+)\"", in: script) else {
                throw MouseError.message("官方固件查询格式已变化")
            }
            let body = try JSONSerialization.data(withJSONObject: ["key": key, "password": selector])
            let data = try await fetch(URL(string: "https://diy.angrymiao.com/api/firmware/check")!, body: body)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? String, ReleaseVersion(version) != nil else { throw MouseError.message("官方固件版本格式无效") }
            results.append(OfficialRelease(id: kind, version: version, notes: "通过官方固件接口查询。升级请前往官方设置页面。"))
        }
        return results
    }
    static func parseDriver(_ data: Data) throws -> OfficialRelease {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = object["data"] as? [[String: Any]] else { throw MouseError.message("官方驱动列表格式无效") }
        let releases = entries.compactMap { entry -> OfficialRelease? in
            guard let version = entry["version"] as? String, ReleaseVersion(version) != nil else { return nil }
            return OfficialRelease(id: "driver", version: version, notes: String((entry["description"] as? String ?? "").prefix(2000)))
        }
        guard let newest = releases.max(by: { ReleaseVersion($0.version)! < ReleaseVersion($1.version)! }) else { throw MouseError.message("官方未返回有效驱动版本") }
        return newest
    }
    func driver() async throws -> OfficialRelease { try Self.parseDriver(await fetch(URL(string: Self.driverURL)!)) }
}

@MainActor final class UpdateModel: ObservableObject {
    @Published var releases: [OfficialRelease] = []
    @Published var checking = false
    @Published var errors: [String] = []
    @Published var current: [String: String] = [:]
    @Published var checkedAt: Date?
    @Published var acknowledged: [String: String]
    private let service = OfficialUpdateService()
    private let defaults = UserDefaults.standard
    init() {
        acknowledged = UserDefaults.standard.dictionary(forKey: "updates.seen") as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: "updates.cache"), let cache = try? JSONDecoder().decode([OfficialRelease].self, from: data) { releases = cache }
        checkedAt = UserDefaults.standard.object(forKey: "updates.checkedAt") as? Date
        errors = UserDefaults.standard.stringArray(forKey: "updates.errors") ?? []
    }
    var due: Bool { defaults.object(forKey: "updates.automatic") as? Bool != false && Date().timeIntervalSince(checkedAt ?? .distantPast) >= 86400 }
    func isNew(_ release: OfficialRelease) -> Bool {
        guard let latest = ReleaseVersion(release.version) else { return false }
        if let local = current[release.id].flatMap(ReleaseVersion.init), latest > local { return true }
        return acknowledged[release.id].flatMap(ReleaseVersion.init).map { latest > $0 } ?? false
    }
    var newCount: Int { releases.filter(isNew).count }
    func setCurrent(_ current: [String: String]) {
        self.current = current
        if let bundle = Bundle(path: "/Applications/AM_Master.app"), let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           let parsed = ReleaseVersion(v), parsed.parts != [0,0,0] { self.current["driver"] = v }
    }
    func check(current: [String: String]) async {
        guard !checking else { return }; checking = true; errors = []; setCurrent(current)
        defer { checking = false }
        var fetched: [OfficialRelease] = []
        do { fetched += try await service.firmware() } catch { errors.append("固件：" + error.localizedDescription) }
        do { fetched.append(try await service.driver()) } catch { errors.append("驱动：" + error.localizedDescription) }
        for release in fetched {
            releases.removeAll { $0.id == release.id }; releases.append(release)
            if acknowledged[release.id] == nil { acknowledged[release.id] = release.version }
        }
        releases.sort { $0.id < $1.id }
        checkedAt = Date()
        defaults.set(checkedAt, forKey: "updates.checkedAt")
        defaults.set(errors, forKey: "updates.errors")
        defaults.set(try? JSONEncoder().encode(releases), forKey: "updates.cache")
        defaults.set(acknowledged, forKey: "updates.seen")
    }
    func acknowledge() {
        for release in releases { acknowledged[release.id] = release.version }
        defaults.set(acknowledged, forKey: "updates.seen")
    }
}
