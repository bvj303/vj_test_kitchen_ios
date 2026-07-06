import Foundation
import Supabase

enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            db: SupabaseClientOptions.DatabaseOptions(
                encoder: SupabaseDecoding.encoder,
                decoder: SupabaseDecoding.decoder
            )
        )
    )
}
