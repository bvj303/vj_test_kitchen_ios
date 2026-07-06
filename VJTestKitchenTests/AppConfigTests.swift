import Foundation
import Testing
@testable import VJTestKitchen

/// Builds a real Bundle backed by a temp directory + Info.plist, so these
/// tests exercise AppConfig's own parsing/validation logic rather than
/// depending on Xcode's Info.plist generation pipeline (which does not
/// support arbitrary custom keys via GENERATE_INFOPLIST_FILE).
private func makeBundle(infoPlist: [String: Any]) throws -> Bundle {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let plistURL = dir.appendingPathComponent("Info.plist")
    let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
    try data.write(to: plistURL)
    guard let bundle = Bundle(path: dir.path) else {
        throw NSError(domain: "AppConfigTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load synthetic bundle"])
    }
    return bundle
}

struct AppConfigTests {
    @Test func supabaseURLParsesValidHTTPSURLFromInfoPlist() throws {
        let bundle = try makeBundle(infoPlist: ["SUPABASE_URL": "https://aviyhrmjsqygoyzjprii.supabase.co"])
        let url = AppConfig.supabaseURL(bundle: bundle)
        #expect(url.scheme == "https")
        #expect(url.host == "aviyhrmjsqygoyzjprii.supabase.co")
    }

    @Test func supabaseAnonKeyReadsNonEmptyStringFromInfoPlist() throws {
        let bundle = try makeBundle(infoPlist: ["SUPABASE_ANON_KEY": "sb_publishable_test123"])
        #expect(AppConfig.supabaseAnonKey(bundle: bundle) == "sb_publishable_test123")
    }
}
