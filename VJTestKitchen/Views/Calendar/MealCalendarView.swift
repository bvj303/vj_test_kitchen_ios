import SwiftUI

struct MealCalendarView: View {
    @State private var viewModel = MealCalendarViewModel()

    // Must share MealPlan.dateFormatter's UTC time zone — parsing a
    // "yyyy-MM-dd" string in UTC then displaying it in the local zone can
    // shift the shown calendar day by one (e.g. UTC midnight is still the
    // prior evening in US time zones).
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                quickPlanner

                ForEach(viewModel.weekDates, id: \.self) { date in
                    dayCard(date)
                }
            }
            .padding()
        }
        .navigationTitle("Calendar")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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
                    ForEach(viewModel.matchingRecipes.prefix(5)) { recipe in
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
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func dayCard(_ date: String) -> some View {
        let plans = viewModel.mealPlans(for: date)

        VStack(alignment: .leading, spacing: 8) {
            Text(Self.displayLabel(for: date))
                .font(.headline)
                .foregroundStyle(Color.brandSage)

            if plans.isEmpty {
                Text("No meals planned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plans) { plan in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(plan.recipeTitle).font(.subheadline.weight(.medium))
                            Text(plan.mealType).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await viewModel.deleteMealPlan(plan.id) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func displayLabel(for date: String) -> String {
        guard let parsed = MealPlan.dateFormatter.date(from: date) else { return date }
        return displayDateFormatter.string(from: parsed)
    }

    // Short "Mon 7" label for the day picker. UTC to match how the dates
    // were computed (see MealPlan.dateFormatter's note).
    private static let dayPickerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func dayPickerLabel(for date: String) -> String {
        guard let parsed = MealPlan.dateFormatter.date(from: date) else { return date }
        return dayPickerFormatter.string(from: parsed)
    }
}
