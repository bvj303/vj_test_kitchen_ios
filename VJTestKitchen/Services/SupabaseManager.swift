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
            ),
            // Opt into supabase-swift's forthcoming (next-major) behavior now:
            // always emit the locally stored session as the initial session,
            // regardless of validity. Silences the current default's warning and
            // sidesteps the future breaking change. AuthService.userIdChanges
            // guards the .initialSession event with `session.isExpired` so an
            // expired stored session still resolves to signed-out. See PR
            // supabase/supabase-swift#822.
            auth: SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
