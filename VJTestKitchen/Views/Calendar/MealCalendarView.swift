import SwiftUI

/// Week-at-a-glance meal calendar rendered as a Google-Calendar-style
/// "Schedule" (agenda) list: one continuous list of the week's days, each day a
/// leading date column beside that day's holiday + meal entries. Adapts to
/// width via the horizontal size class — iPhone stacks the Quick Planner above
/// the agenda in one scroll; iPad (including landscape) puts the planner in a
/// fixed sidebar beside a width-constrained agenda column so wide screens stay
/// readable instead of stretching rows edge to edge.
struct MealCalendarView: View {
    @State private var viewModel = MealCalendarViewModel()

    // iPad gets the sidebar-beside-agenda layout; iPhone stays a single
    // scrolling column. Same size-class gate as RecipesTab.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // meal_plans is account-synced via Supabase, so re-sync when the app returns
    // to the foreground — edits made on another device then show up without a
    // manual pull-to-refresh.
    @Environment(\.scenePhase) private var scenePhase
    // The weather outlook is toggled in the Settings *sheet*, which shares this
    // app-root view model but doesn't background the app or re-run this view's
    // `.task`. Observe the preference directly so flipping it on immediately
    // fetches (or clears) the forecast instead of only taking effect after a
    // relaunch.
    @Environment(SettingsViewModel.self) private var settingsViewModel

    /// Caps the agenda column's width so a landscape iPad reads as a centered
    /// schedule column rather than rows spanning the whole display.
    private static let agendaMaxWidth: CGFloat = 640

    // Must share MealPlan.dateFormatter's UTC time zone — parsing a
    // "yyyy-MM-dd" string in UTC then displaying it in the local zone can
    // shift the shown calendar day by one (e.g. UTC midnight is still the
    // prior evening in US time zones).
    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
    private static let weekdayShortFormatter = utcFormatter("EEE")
    private static let dayNumberFormatter = utcFormatter("d")
    private static let rangeFormatter = utcFormatter("MMM d")
    private static let rangeYearFormatter = utcFormatter("MMM d, yyyy")

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle("Calendar")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.load() }
            }
        }
        .onChange(of: settingsViewModel.useCurrentLocationForWeather) {
            Task { await viewModel.loadWeather() }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Layouts

    /// iPhone: Quick Planner then the agenda list, one scroll.
    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                weekHeader
                quickPlanner
                agendaList
                weatherAttributionFooter
            }
            .padding()
        }
    }

    /// iPad (portrait and landscape): a fixed planner sidebar beside a
    /// width-constrained, centered agenda column.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                quickPlanner
                    .padding(.vertical)
            }
            .frame(width: 340)

            ScrollView {
                VStack(spacing: 20) {
                    weekHeader
                    agendaList
                    weatherAttributionFooter
                }
                .frame(maxWidth: Self.agendaMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Week header

    private var weekHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule")
                    .font(.title2.weight(.bold))
                Text(weekRangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Agenda list

    /// The week's days as one grouped, glass-backed schedule list with a hairline
    /// divider between days (Google-Calendar "Schedule" style).
    private var agendaList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.weekDates.enumerated()), id: \.element) { index, date in
                dayRow(date)
                if index < viewModel.weekDates.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .glassEffect(
            .regular.tint(Color.brandPrimary.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        // Clip per-row backgrounds (today's highlight) to the card's rounded
        // corners so they can't poke past the top/bottom edges.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func dayRow(_ date: String) -> some View {
        let plans = viewModel.mealPlans(for: date)
        let holiday = viewModel.holiday(for: date)
        let isToday = viewModel.isToday(date)
        let forecast = viewModel.forecast(for: date)

        HStack(alignment: .top, spacing: 16) {
            dateColumn(date, isToday: isToday)

            VStack(alignment: .leading, spacing: 8) {
                if let holiday {
                    holidayRow(holiday)
                }

                if plans.isEmpty {
                    Text("No meals planned")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(plans) { plan in mealRow(plan) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let forecast {
                weatherBadge(forecast)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            (isToday ? Color.brandPrimary.opacity(0.07) : .clear)
        )
        // A slim accent bar on the leading edge marks the current day, echoing
        // Google Calendar's "now" indicator.
        .overlay(alignment: .leading) {
            if isToday {
                Capsule()
                    .fill(Color.brandPrimary)
                    .frame(width: 3)
                    .padding(.vertical, 10)
            }
        }
    }

    /// Leading date column: weekday abbreviation over the day number, with the
    /// number in a filled brand circle on today.
    private func dateColumn(_ date: String, isToday: Bool) -> some View {
        let parsedDate = parsed(date)
        return VStack(spacing: 3) {
            Text(Self.weekdayShortFormatter.string(from: parsedDate).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.brandPrimary : .secondary)
            Text(Self.dayNumberFormatter.string(from: parsedDate))
                .font(.title3.weight(.semibold))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(isToday ? AnyShapeStyle(Color.brandPrimary) : AnyShapeStyle(Color.clear))
                )
        }
        .frame(width: 46)
    }

    /// A trailing, glanceable weather badge for a day: a multicolor condition
    /// icon (WeatherKit's own SF Symbol) over the high and low temperatures — the
    /// week-ahead "outlook" for planning meals around the weather.
    private func weatherBadge(_ forecast: DailyForecast) -> some View {
        VStack(spacing: 2) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
            Text(WeatherFormatting.temperatureLabel(forecast.highTemperature))
                .font(.caption.weight(.semibold))
            Text(WeatherFormatting.temperatureLabel(forecast.lowTemperature))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(forecast.condition), high \(WeatherFormatting.temperatureLabel(forecast.highTemperature)), low \(WeatherFormatting.temperatureLabel(forecast.lowTemperature))"
        )
    }

    /// Open-Meteo's data is CC-BY 4.0 and asks for a credit + link wherever it's
    /// shown. Displayed only when a forecast is actually loaded.
    @ViewBuilder
    private var weatherAttributionFooter: some View {
        if !viewModel.forecastByDate.isEmpty {
            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text("Weather data by Open-Meteo.com")
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func holidayRow(_ holiday: Holiday) -> some View {
        HStack(spacing: 12) {
            Image(systemName: holiday.symbol)
                .font(.footnote)
                .foregroundStyle(Color.brandSaffron)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(holiday.name)
                    .font(.subheadline.weight(.semibold))
                Text("Holiday")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.brandSaffron.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    /// A single planned meal. Deletion lives in a long-press context menu rather
    /// than a visible trash button — the row stays clean and uncluttered, matching
    /// the native "press to reveal actions" pattern (Reminders, Calendar). The whole
    /// row is the target, so it reads as one tappable object with hidden actions.
    private func mealRow(_ plan: MealPlanWithRecipe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: MealTypeStyle.icon(for: plan.mealType))
                .font(.footnote)
                .foregroundStyle(MealTypeStyle.tint(for: plan.mealType))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(plan.recipeTitle)
                    .font(.subheadline.weight(.medium))
                Text(plan.mealType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        // Make the full row width the long-press target, not just the text.
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                Task { await viewModel.deleteMealPlan(plan.id) }
            } label: {
                Label("Remove from Calendar", systemImage: "trash")
            }
        }
    }

    // MARK: - Quick Planner

    private var quickPlanner: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 12) {
            Label("Quick Planner", systemImage: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(Color.brandPrimary)

            Picker("Meal", selection: $viewModel.selectedMealType) {
                ForEach(MealCalendarViewModel.mealTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Picker("Day", selection: $viewModel.selectedPlanningDate) {
                ForEach(viewModel.weekDates, id: \.self) { date in
                    Text(Self.dayPickerLabel(for: date)).tag(date)
                }
            }
            .pickerStyle(.menu)

            TextField("Search a recipe...", text: $viewModel.recipeSearchText)
                .textFieldStyle(.roundedBorder)

            if !viewModel.matchingRecipes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.matchingRecipes) { recipe in
                        Button {
                            Task {
                                await viewModel.addMealPlan(date: viewModel.selectedPlanningDate, recipeId: recipe.id)
                                viewModel.recipeSearchText = ""
                            }
                        } label: {
                            HStack {
                                Text(recipe.title)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.brandSage)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .padding()
        .glassEffect(
            .regular.tint(Color.brandPrimary.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    // MARK: - Formatting helpers

    private func parsed(_ date: String) -> Date {
        MealPlan.dateFormatter.date(from: date) ?? Date()
    }

    /// "Jul 5 – 11, 2026" style range for the visible week (year shown once).
    private var weekRangeLabel: String {
        guard let first = viewModel.weekDates.first,
              let last = viewModel.weekDates.last,
              let start = MealPlan.dateFormatter.date(from: first),
              let end = MealPlan.dateFormatter.date(from: last)
        else { return "" }
        return "\(Self.rangeFormatter.string(from: start)) – \(Self.rangeYearFormatter.string(from: end))"
    }

    // Short "Mon 7" label for the day picker. UTC to match how the dates
    // were computed (see MealPlan.dateFormatter's note).
    private static let dayPickerFormatter = utcFormatter("EEE d")

    private static func dayPickerLabel(for date: String) -> String {
        guard let parsed = MealPlan.dateFormatter.date(from: date) else { return date }
        return dayPickerFormatter.string(from: parsed)
    }
}
