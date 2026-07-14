import Foundation

/// Reads Supabase config from Info.plist keys backed by Config/Secrets.xcconfig.
/// `bundle` defaults to `.main` for real app usage; tests inject a synthetic
/// bundle instead of depending on Xcode's Info.plist generation pipeline.
enum AppConfig {
    static func supabaseURL(bundle: Bundle = .main) -> URL {
        guard let string = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: string) else {
            fatalError("SUPABASE_URL missing or invalid in Info.plist — check Config/Secrets.xcconfig")
        }
        return url
    }

    static func supabaseAnonKey(bundle: Bundle = .main) -> String {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY missing in Info.plist — check Config/Secrets.xcconfig")
        }
        return key
    }

    static var supabaseURL: URL { supabaseURL(bundle: .main) }
    static var supabaseAnonKey: String { supabaseAnonKey(bundle: .main) }

    /// Non-fatal presence check for the Supabase config. Unlike the accessors
    /// above (which `fatalError` when the keys are missing), this just reports
    /// whether they're present. Lets best-effort infrastructure — notably the
    /// remote log sink — no-op cleanly in contexts without the app's Info.plist
    /// (the unhosted unit-test process, whose `Bundle.main` is the test bundle)
    /// instead of crashing.
    static func isConfigured(bundle: Bundle = .main) -> Bool {
        guard let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              URL(string: urlString) != nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            return false
        }
        return true
    }

    static var isConfigured: Bool { isConfigured(bundle: .main) }
}
