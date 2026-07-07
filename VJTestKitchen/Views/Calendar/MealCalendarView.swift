import SwiftUI

struct MealCalendarView: View {
    @State private var viewModel = MealCalendarViewModel()

    // iPad gets a wider two-column layout (planner sidebar + week grid); iPhone
    // stays a single scrolling column. Same size-class gate as RecipesTab.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // meal_plans is account-synced via Supabase, so re-sync when the app returns
    // to the foreground — edits made on another device then show up without a
    // manual pull-to-refresh.
    @Environment(\.scenePhase) private var scenePhase

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
    private static let weekdayFormatter = utcFormatter("EEEE")
    private static let monthFormatter = utcFormatter("MMMM")
    private static let dayNumberFormatter = utcFormatter("d")

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

    /// iPhone: planner then a single stacked column of day cards.
    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                quickPlanner

                VStack(spacing: 16) {
                    ForEach(viewModel.weekDates, id: \.self) { dayCard($0) }
                }
            }
            .padding()
        }
    }

    /// iPad: a fixed planner sidebar beside a two-column week grid, using the
    /// extra width instead of one long scroll.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                quickPlanner
                    .padding(.vertical)
            }
            .frame(width: 340)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20),
                    ],
                    alignment: .leading,
                    spacing: 20
                ) {
                    ForEach(viewModel.weekDates, id: \.self) { dayCard($0) }
                }
                .padding(.vertical)
            }
        }
        .padding(.horizontal)
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

    // MARK: - Day card

    @ViewBuilder
    private func dayCard(_ date: String) -> some View {
        let plans = viewModel.mealPlans(for: date)
        let isToday = viewModel.isToday(date)

        VStack(alignment: .leading, spacing: 12) {
            dayHeader(date, isToday: isToday)

            if plans.isEmpty {
                Text("No meals planned")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(plans) { plan in mealRow(plan) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(Color.brandPrimary.opacity(isToday ? 0.16 : 0.05)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.brandPrimary.opacity(isToday ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    private func dayHeader(_ date: String, isToday: Bool) -> some View {
        HStack(spacing: 12) {
            dateBadge(date, isToday: isToday)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.weekdayFormatter.string(from: parsed(date)))
                    .font(.headline)
                Text(Self.monthFormatter.string(from: parsed(date)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isToday {
                Text("Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.brandPrimary, in: Capsule())
            }
        }
    }

    private func dateBadge(_ date: String, isToday: Bool) -> some View {
        Text(Self.dayNumberFormatter.string(from: parsed(date)))
            .font(.title3.weight(.semibold))
            .foregroundStyle(isToday ? .white : Color.brandPrimary)
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(isToday ? AnyShapeStyle(Color.brandPrimary) : AnyShapeStyle(Color.brandPrimary.opacity(0.12)))
            )
    }

    private func mealRow(_ plan: MealPlanWithRecipe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: MealTypeStyle.icon(for: plan.mealType))
                .font(.subheadline)
                .foregroundStyle(MealTypeStyle.tint(for: plan.mealType))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(plan.recipeTitle)
                    .font(.subheadline.weight(.medium))
                Text(plan.mealType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                Task { await viewModel.deleteMealPlan(plan.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            MealTypeStyle.tint(for: plan.mealType).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Formatting helpers

    private func parsed(_ date: String) -> Date {
        MealPlan.dateFormatter.date(from: date) ?? Date()
    }

    // Short "Mon 7" label for the day picker. UTC to match how the dates
    // were computed (see MealPlan.dateFormatter's note).
    private static let dayPickerFormatter = utcFormatter("EEE d")

    private static func dayPickerLabel(for date: String) -> String {
        guard let parsed = MealPlan.dateFormatter.date(from: date) else { return date }
        return dayPickerFormatter.string(from: parsed)
    }
}
