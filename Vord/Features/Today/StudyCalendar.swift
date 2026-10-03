import SwiftUI

struct StudyCalendar: View {
    var activity: StudyActivity
    @State private var period: ActivityPeriod = .year
    @State private var anchor = Date()
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var interval: DateInterval { activity.interval(period, anchor: anchor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(); periodChoices }
                VStack(alignment: .leading, spacing: 10) { title; periodChoices }
            }
            HStack(spacing: 8) {
                ChromeIconButton(symbol: "chevron.left", help: "Previous \(period.rawValue.lowercased())") { move(-1) }
                Text(rangeTitle).font(AppTypography.caption).monospacedDigit()
                ChromeIconButton(symbol: "chevron.right", help: "Next \(period.rawValue.lowercased())") { move(1) }
                    .disabled(interval.end > activity.now)
                Spacer()
                if !interval.contains(activity.now) { SubtleButton(title: "Today") { anchor = activity.now; selectedDate = nil } }
            }
            if period == .year {
                ScrollView(.horizontal) { yearGrid.padding(.vertical, 2) }.scrollIndicators(.hidden)
            } else if period == .month {
                monthGrid
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(activity.dates(in: interval), id: \.self) { date in
                        VStack(spacing: 7) {
                            Text(date, format: .dateTime.weekday(.abbreviated)).font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                            cell(date, size: 28)
                            Text(date, format: .dateTime.day()).font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { detail; Spacer(); legend }
                VStack(alignment: .leading, spacing: 10) { detail; legend }
            }
        }
        .animation(reducedMotion ? nil : AppMotion.quick, value: period)
        .help("Each square counts different words added, reviewed or practiced in completed dictation rounds that day. Repeated words count once.")
    }
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Learning activity").font(AppTypography.headline)
            Text("\(activity.activeDays(in: interval)) active days").font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
        }
    }
    private var periodChoices: some View {
        ChoiceTabs(name: "Activity range", selection: $period, choices: ActivityPeriod.allCases, label: { $0.rawValue })
            .fixedSize()
            .onChange(of: period) { _, _ in selectedDate = nil }
    }
    private var rangeTitle: String {
        switch period {
        case .year: return anchor.formatted(.dateTime.year())
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        case .week: return interval.start.formatted(.dateTime.month(.abbreviated).day()) + " – " + activity.calendar.date(byAdding: .day, value: -1, to: interval.end)!.formatted(.dateTime.month(.abbreviated).day())
        }
    }
    private var yearGrid: some View {
        let weeks = activity.weeks(in: interval)
        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                Color.clear.frame(width: 25, height: 16)
                ForEach(0..<7) { day in
                    Text(day % 2 == 1 ? weekday(day) : "").font(AppTypography.ui(size: 9))
                        .foregroundStyle(AppColors.tertiaryText).frame(width: 25, height: 12, alignment: .trailing)
                }
            }
            ForEach(weeks.indices, id: \.self) { column in
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthLabel(weeks[column])).font(AppTypography.ui(size: 9))
                        .foregroundStyle(AppColors.secondaryText).fixedSize().frame(width: 12, height: 16, alignment: .leading)
                    ForEach(0..<7) { row in
                        if let date = weeks[column][row] { cell(date, size: 12) }
                        else { Color.clear.frame(width: 12, height: 12).accessibilityHidden(true) }
                    }
                }.frame(width: 12, alignment: .leading)
            }
        }
    }
    private var monthGrid: some View {
        let weeks = activity.weeks(in: interval)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7) { day in Text(weekday(day)).font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText).frame(width: 28) }
            }
            ForEach(weeks.indices, id: \.self) { week in
                HStack(spacing: 6) {
                    ForEach(0..<7) { day in
                        if let date = weeks[week][day] { cell(date, size: 28) }
                        else { Color.clear.frame(width: 28, height: 28).accessibilityHidden(true) }
                    }
                }
            }
        }
    }
    private func cell(_ date: Date, size: CGFloat) -> some View {
        let day = activity.day(date), future = date > activity.calendar.startOfDay(for: activity.now)
        return Button { selectedDate = date } label: {
            RoundedRectangle(cornerRadius: size < 20 ? 2 : 5)
                .fill(shade(day.level)).opacity(future ? 0.35 : 1)
                .overlay {
                    if selectedDate == date { RoundedRectangle(cornerRadius: size < 20 ? 2 : 5).stroke(AppColors.primaryText, lineWidth: 1.5).padding(-2) }
                }.frame(width: size, height: size)
        }.buttonStyle(.plain).disabled(future)
            .help(date.formatted(date: .complete, time: .omitted) + " · \(day.count) words · \(day.added.count) added · \(day.reviewed.count) reviewed · \(day.practiced.count) in dictation")
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + ", \(day.count) words studied")
    }
    private var detail: some View {
        Group {
            if let selectedDate {
                let day = activity.day(selectedDate)
                Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()) + " · \(day.count) words · \(day.added.count) added · \(day.reviewed.count) reviewed · \(day.practiced.count) in dictation")
            } else {
                Text("\(activity.uniqueWords(in: interval)) words studied")
            }
        }.font(AppTypography.tertiary).foregroundStyle(AppColors.secondaryText)
    }
    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(AppTypography.ui(size: 10)).foregroundStyle(AppColors.tertiaryText)
            ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(shade(level)).frame(width: 10, height: 10) }
            Text("More").font(AppTypography.ui(size: 10)).foregroundStyle(AppColors.tertiaryText)
        }.accessibilityLabel("Darker squares mean more words studied")
    }
    private func shade(_ level: Int) -> Color {
        level == 0 ? AppColors.hover : AppColors.primaryText.opacity([0, 0.24, 0.44, 0.67, 0.9][level])
    }
    private func weekday(_ index: Int) -> String {
        let symbols = activity.calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(activity.calendar.firstWeekday - 1 + index) % 7]
    }
    private func monthLabel(_ dates: [Date?]) -> String {
        guard let date = dates.compactMap({ $0 }).first(where: { activity.calendar.component(.day, from: $0) == 1 }) else { return "" }
        return date.formatted(.dateTime.month(.abbreviated))
    }
    private func move(_ value: Int) {
        if let next = activity.calendar.date(byAdding: period.component, value: value, to: anchor) { anchor = next; selectedDate = nil }
    }
}
