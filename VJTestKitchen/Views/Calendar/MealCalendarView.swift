import SwiftUI

/// Week-at-a-glance meal calendar rendered as a Google-Calendar-style
/// "Schedule" (agenda) list: one continuous list of the week's days, each day a
/// leading date column beside that day's holiday + meal entries. Adapts to the
/// space it has (`CalendarLayout`): a portrait phone stacks the Quick Planner
/// above the agenda in one scroll; iPad, wide compact screens (iPhone Duo's inner
/// display in landscape) and a book-style fold put the planner in a pane beside a
/// width-constrained agenda column — on iPhone Duo each pane wholly on one side
/// of the fold.
struct MealCalendarView: View {
    @State private var viewModel = MealCalendarViewModel()

    // Regular width always gets the planner-beside-agenda split; compact widths
    // get it too when there's room or a fold to respect (see CalendarLayout).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The calendar's measured width and whether a vertical fold crosses it —
    /// the inputs, with the size class, to `CalendarLayout.resolve`.
    @State private var containerWidth: CGFloat = 0
    @State private var hasVerticalFold = false
    /// Pane widths for the compact-width split, from its own measured width
    /// and fold position.
    @State private var panes = CalendarLayout.Panes(plannerWidth: 260, spacing: CalendarLayout.paneSpacing)
    // meal_plans is account-synced via Supabase, so re-sync when the app returns
    // to the foreground — edits made on another device then show up without a
    // manual pull-to-refresh.
    @Environment(\.scenePhase) private var scenePhase
    // The weather home location is set from the Settings *sheet* (or the
    // first-login prompt), which shares this app-root view model but doesn't
    // background the app or re-run this view's `.task`. Observe the saved
    // location directly so setting/changing/clearing it immediately fetches (or
    // clears) the forecast instead of only taking effect after a relaunch.
    @Environment(HomeLocationViewModel.self) private var homeLocationViewModel
    // Menu-bar / keyboard-shortcut command bus — ⌘R reloads the agenda.
    @Environment(AppCommands.self) private var appCommands
    // Optional so previews without the app root's injection still work. While
    /// Focuses the Quick Planner's recipe search when an empty day's "Add a meal"
    /// button is tapped, and a scroll trigger so the compact layout brings the
    /// planner (which sits above the agenda) into view first.
    @FocusState private var plannerSearchFocused: Bool
    @State private var pendingPlannerScroll = false
    /// The agenda day at the top of the scroll view. Owned here — above the
    /// compact/regular layout switch — and bound into both layouts' scroll views,
    /// so opening or closing iPhone Duo (which flips the size class and swaps the
    /// layout) keeps the user's place instead of jumping back to the top.
    @State private var scrollAnchorDay: String?

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
            switch layout {
            case .split: splitLayout
            case .stacked: compactLayout
            }
        }
        .background {
            GeometryReader { proxy in
                let key = LayoutInputs(width: proxy.size.width, hasVerticalFold: !activeVerticalFolds(in: proxy).isEmpty)
                Color.clear.onChange(of: key, initial: true) { _, key in
                    containerWidth = key.width
                    hasVerticalFold = key.hasVerticalFold
                }
            }
        }
        .screenBackground()
        .navigationTitle("Calendar")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.load() }
            }
        }
        .onChange(of: homeLocationViewModel.homeLocation) {
            Task { await viewModel.loadWeather() }
        }
        // ⌘R reloads the agenda when Calendar is the visible tab.
        .onChange(of: appCommands.refreshRequests) { _, _ in
            Task { await viewModel.load() }
        }
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
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

    private struct LayoutInputs: Equatable {
        var width: CGFloat
        var hasVerticalFold: Bool
    }

    private var layout: CalendarLayout {
        CalendarLayout.resolve(
            isRegularWidth: horizontalSizeClass == .regular,
            containerWidth: containerWidth,
            hasVerticalFold: hasVerticalFold
        )
    }

    /// iPhone: Quick Planner then the agenda list, one scroll.
    private var compactLayout: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    weekHeader
                    quickPlanner
                        .id(Self.plannerAnchor)
                    agendaList
                    weatherAttributionFooter
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition(id: $scrollAnchorDay, anchor: .top)
            // An empty day's "Add a meal" tap scrolls the planner (above the
            // agenda) into view before focusing its search field.
            .onChange(of: pendingPlannerScroll) { _, pending in
                guard pending else { return }
                withAnimation { proxy.scrollTo(Self.plannerAnchor, anchor: .top) }
                pendingPlannerScroll = false
            }
        }
    }

    private static let plannerAnchor = "quickPlanner"

    /// Start planning a meal on `date`: preselect it in the Quick Planner, bring
    /// the planner into view (compact), and focus its recipe search.
    private func beginPlanning(on date: String) {
        viewModel.selectedPlanningDate = date
        pendingPlannerScroll = true
        plannerSearchFocused = true
    }

    /// `CalendarLayout.split` (iPad, wide compact screens, a book-style fold): the Quick Planner and
    /// the agenda as two panes of a split arrangement — side by side, or stacked
    /// when the space is taller than wide — each wholly on one side of the fold
    /// when iPhone Duo is partially folded. Before iOS 27.1 (and on macOS) it's
    /// the planner sidebar beside the agenda. The agenda stays width-capped and
    /// centered within its pane.
    @ViewBuilder
    private var splitLayout: some View {
        if horizontalSizeClass == .regular {
            PlatformSplitArrangement(fallbackPrimaryWidth: 340) {
                plannerPane
            } secondary: {
                agendaPane
            }
            .padding(.horizontal)
        } else {
            compactSplit
        }
    }

    /// The compact-width split (iPhone Duo's inner display): `ArrangementView`
    /// keeps to the size class and shows only one pane in compact width, so the
    /// two panes are placed here — around the crease when the display is folded
    /// like a book (see `CalendarLayout.panes`).
    private var compactSplit: some View {
        HStack(alignment: .top, spacing: panes.spacing) {
            plannerPane.frame(width: panes.plannerWidth)
            agendaPane
        }
        .background {
            GeometryReader { proxy in
                let key = PaneInputs(width: proxy.size.width, folds: activeVerticalFolds(in: proxy))
                Color.clear.onChange(of: key, initial: true) { _, key in
                    panes = CalendarLayout.panes(
                        containerWidth: key.width,
                        verticalFolds: key.folds,
                        preferredPlannerWidth: 260
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private struct PaneInputs: Equatable {
        var width: CGFloat
        var folds: [ClosedRange<CGFloat>]
    }

    private var plannerPane: some View {
        ScrollView {
            quickPlanner
                .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var agendaPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                weekHeader
                agendaList
                weatherAttributionFooter
            }
            .frame(maxWidth: Self.agendaMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
        // Shared with the compact layout, so the same day stays at the top
        // when iPhone Duo opens or closes (the size class flips and the other
        // layout takes over).
        .scrollPosition(id: $scrollAnchorDay, anchor: .top)
    }

    // MARK: - Week header

    private var weekHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isCurrentWeek ? "This Week" : "Schedule")
                    .font(.title3.weight(.bold))
                Text(weekRangeLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            weekNavigation
        }
    }

    /// ‹ / › week stepper with a "Today" jump that appears only when the visible
    /// window has moved off the current week.
    private var weekNavigation: some View {
        HStack(spacing: 8) {
            weekArrow("chevron.left", label: "Previous week") { viewModel.goToPreviousWeek() }
            if !viewModel.isCurrentWeek {
                Button { viewModel.goToThisWeek() } label: {
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            weekArrow("chevron.right", label: "Next week") { viewModel.goToNextWeek() }
        }
    }

    private func weekArrow(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Agenda list

    /// The week's days as one grouped, glass-backed schedule list with a hairline
    /// divider between days (Google-Calendar "Schedule" style).
    private var agendaList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.weekDates.enumerated()), id: \.element) { index, date in
                dayRow(date)
                    .id(date)
                if index < viewModel.weekDates.count - 1 {
                    // Lines up with the meal column: row padding + date column + spacing.
                    Divider().padding(.leading, 64)
                }
            }
        }
        // Day rows are the scroll-position targets (see scrollAnchorDay).
        .scrollTargetLayout()
        .surface(.card, radius: Surface.Radius.large)
        // Clip per-row backgrounds (today's highlight) to the card's rounded
        // corners so they can't poke past the top/bottom edges.
        .clipShape(RoundedRectangle(cornerRadius: Surface.Radius.large, style: .continuous))
    }

    @ViewBuilder
    private func dayRow(_ date: String) -> some View {
        let plans = viewModel.mealPlans(for: date)
        let holiday = viewModel.holiday(for: date)
        let isToday = viewModel.isToday(date)
        let forecast = viewModel.forecast(for: date)

        HStack(alignment: .top, spacing: 12) {
            dateColumn(date, isToday: isToday)

            VStack(alignment: .leading, spacing: 8) {
                // The forecast is a small chip tucked into the day's top-right
                // corner — glanceable but no longer claiming a full-height column
                // beside every meal.
                if let forecast {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        weatherChip(forecast)
                    }
                }

                if let holiday {
                    holidayRow(holiday)
                }

                if plans.isEmpty {
                    // A single tappable "Add a meal" per empty day, instead of a
                    // dead "No meals planned" line: it points the Quick Planner at
                    // this day — scrolling it into view and focusing its search on
                    // compact — so adding takes one fewer step than hunting for the
                    // right day in the planner's picker.
                    Button {
                        beginPlanning(on: date)
                    } label: {
                        Label("Add a meal", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.brandSage)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .accessibilityLabel("Add a meal on \(Self.dayPickerLabel(for: date))")
                    .accessibilityHint("Opens the Quick Planner for this day")
                } else {
                    ForEach(plans) { plan in mealRow(plan) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(isToday ? AnyShapeStyle(Color.brandPrimary) : AnyShapeStyle(Color.clear))
                )
        }
        .frame(width: 40)
    }

    /// A compact, glanceable weather chip tucked into a day's top-right corner: a
    /// multicolor condition icon beside the high and low temperatures on a single
    /// line — the week-ahead "outlook" for planning meals around the weather,
    /// without reserving a full-height column beside the day's meals.
    private func weatherChip(_ forecast: DailyForecast) -> some View {
        HStack(spacing: 4) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.caption)
            Text(WeatherFormatting.temperatureLabel(forecast.highTemperature))
                .font(.caption.weight(.semibold))
            Text(WeatherFormatting.temperatureLabel(forecast.lowTemperature))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: Capsule())
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
            in: RoundedRectangle(cornerRadius: Surface.Radius.small, style: .continuous)
        )
    }

    /// A single planned meal. Removal is a visible trailing button (an
    /// understated hierarchical "minus" circle) so it's discoverable at a glance —
    /// a long-press context menu is kept as a secondary path, but the button is the
    /// primary, obvious affordance.
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

            Button {
                Task { await viewModel.deleteMealPlan(plan.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(plan.recipeTitle)")
        }
        .padding(.vertical, 2)
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

        return VStack(alignment: .leading, spacing: 10) {
            Label("Quick Planner", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandPrimary)

            // Segmented when all four meal types fit; a menu in a narrow pane
            // (one side of iPhone Duo's fold) instead of truncated segments.
            ViewThatFits(in: .horizontal) {
                mealTypePicker.pickerStyle(.segmented)
                mealTypePicker.pickerStyle(.menu)
            }

            Picker("Day", selection: $viewModel.selectedPlanningDate) {
                ForEach(viewModel.weekDates, id: \.self) { date in
                    Text(Self.dayPickerLabel(for: date)).tag(date)
                }
            }
            .pickerStyle(.menu)

            TextField("Search a recipe...", text: $viewModel.recipeSearchText)
                .textFieldStyle(.roundedBorder)
                .focused($plannerSearchFocused)

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
        .padding(14)
        .surface(.card, radius: Surface.Radius.large)
    }

    private var mealTypePicker: some View {
        @Bindable var viewModel = viewModel
        return Picker("Meal", selection: $viewModel.selectedMealType) {
            ForEach(MealCalendarViewModel.mealTypes, id: \.self) { type in
                Text(type).tag(type)
            }
        }
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
