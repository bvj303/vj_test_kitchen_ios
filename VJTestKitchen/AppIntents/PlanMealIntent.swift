import AppIntents

/// Lets Siri/Shortcuts ask Kitchen Concierge directly ("Hey Siri, ask VJ
/// Test Kitchen to plan a healthy dinner") without opening the app. Runs in
/// the main app's process (no separate Intents extension target exists),
/// so it reuses the same signed-in Supabase session as the in-app chat —
/// no extra Keychain-sharing setup needed.
struct PlanMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Kitchen Concierge"
    static let description = IntentDescription(
        "Ask the Kitchen Concierge to plan a meal or find a recipe from your VJ Test Kitchen collection."
    )

    @Parameter(title: "What would you like to cook?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Kitchen Concierge: \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await AIService().sendMessage(query)
            return .result(dialog: IntentDialog(stringLiteral: response))
        } catch {
            return .result(dialog: IntentDialog(
                stringLiteral: "Sorry, I couldn't reach Kitchen Concierge. Open VJ Test Kitchen and make sure you're signed in, then try again."
            ))
        }
    }
}

struct VJTestKitchenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlanMealIntent(),
            phrases: [
                "Ask \(.applicationName) to plan a meal",
                "Ask \(.applicationName) for a recipe",
                "\(.applicationName) plan my dinner",
            ],
            shortTitle: "Plan a Meal",
            systemImageName: "sparkles"
        )
    }
}
