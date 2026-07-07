// Account deletion — required by App Store Guideline 5.1.1(v): any app that
// supports account creation must let the user delete the account in-app.
//
// Zero external imports, same constraint as ai-chat (see its index.ts) —
// Deno.serve/Deno.env/fetch are runtime built-ins, so there's nothing for the
// bundler to resolve over a network that may lack egress. ./handler.ts is a
// local relative import, not a bundled package.
//
// The caller's own JWT (verified by the platform before this code runs, see
// config.toml) only proves who they are — deleting an auth.users row needs
// the Admin API, which requires the service_role key. That key never reaches
// the client; it's read here from the env, same as GEMINI_API_KEY in
// ai-chat. All app tables' user_id columns are `on delete cascade`/`set null`
// against auth.users (see the initial_schema migration), so deleting the
// auth user cleans up the user's recipes/ratings/meal plans/profile too.
import { handleDeleteAccount } from "./handler.ts";

Deno.serve((req: Request) =>
  handleDeleteAccount(req, {
    supabaseUrl: Deno.env.get("SUPABASE_URL"),
    anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  })
);
