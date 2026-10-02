import SwiftUI

/// The single page: greeting and currency, headline balance, chart, range picker and breakdown.
struct DashboardView: View {
    @EnvironmentObject private var store: SnapshotStore
    let snapshot: Snapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currency = "CAD"
    @State private var period: Period
    @State private var selectedIndex: Int?
    @State private var chartPoints: [ChartPoint]
    @State private var plotPoints: [PlotPoint]
    @State private var plotFrame: CGRect = .zero
    @State private var morph: ChartMorphState?

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        let initial = Self.defaultPeriod(for: snapshot)
        _period = State(initialValue: initial)
        let points = HistoryProjection.points(snapshot: snapshot, currency: "CAD", period: initial)
        _chartPoints = State(initialValue: points)
        _plotPoints = State(initialValue: ChartMorph.plotted(points))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    headline
                }
                VStack(spacing: 18) {
                    chart
                    Picker("Time range", selection: $period) {
                        ForEach(availablePeriods) { range in Text(range.label).tag(range).accessibilityLabel(range.title) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .onChange(of: period) { _, _ in updatePoints() }
                    .onChange(of: snapshot) { _, _ in
                        if !availablePeriods.contains(period) { period = Self.defaultPeriod(for: snapshot) }
                        updatePoints()
                    }
                }
                BreakdownCard(rows: snapshot.breakdown(in: currency))
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, Theme.pagePadding).padding(.bottom, Theme.sectionSpacing)
        }
        .refreshable { await store.refresh() }
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Theme.background)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currency)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Text(Format.greeting()).font(Theme.title)
                .lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
            Spacer(minLength: 0)
            Picker("Currency", selection: $currency) {
                Text("USD").tag("USD")
                Text("CAD").tag("CAD")
            }
            .pickerStyle(.segmented).frame(width: 116)
            .onChange(of: currency) { _, _ in updatePoints() }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Format.money(displayedBalance))
                .font(Theme.headline).monospacedDigit()
                .contentTransition(.numericText(value: displayedBalance))
                .animation(numberAnimation, value: displayedBalance)
                .minimumScaleFactor(0.65).lineLimit(1)
                .accessibilityAction(named: Text("Refresh snapshot")) { Task { await store.refresh() } }
            HStack(spacing: 5) {
                Image(systemName: changeAmount < 0 ? "arrow.down.right" : "arrow.up.right").font(.caption.weight(.semibold))
                rollingNumber(hasComparison ? Format.money(changeAmount) : "—", value: changeAmount)
                rollingNumber(hasComparison ? Format.percent(changePercent) : "", value: changePercent)
                Text(period.label).font(Theme.label).foregroundStyle(.secondary)
            }
            .foregroundStyle(changeAmount < 0 ? Theme.loss : Theme.gain)
        }
    }

    private func rollingNumber(_ text: String, value: Double) -> some View {
        Text(text).font(Theme.number(.subheadline)).monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(numberAnimation, value: value)
    }

    private var chart: some View {
        VStack(spacing: 12) {
            ZStack {
                NetWorthPlot(target: plotPoints, domain: chartDomain, morph: morph, showsLatestMarker: selectedIndex == nil,
                             selection: selection, onPlotFrame: { if plotFrame != $0 { plotFrame = $0 } })
                    .equatable()
                ChartSelectionOverlay(point: selectedIndex.map { plotPoints[$0] }, domain: chartDomain, plotFrame: plotFrame)
            }
            .frame(height: 205)
            .task(id: morph?.start) {
                guard let start = morph?.start else { return }
                try? await Task.sleep(for: .seconds(ChartMorph.duration))
                if morph?.start == start { morph = nil }
            }
            .onChange(of: selectedIndex) { oldIndex, newIndex in
                if let newIndex, newIndex != oldIndex { AppHaptics.selection() }
            }
            .accessibilityLabel("Net worth history for \(period.title)")
            ChartDateRow(start: Format.monthYear.format(chartPoints.first?.date ?? endDate), end: Format.shortDate.format(endDate),
                         selected: selectedIndex.map { (Format.shortDate.format(chartPoints[$0].date), plotPoints[$0].position) },
                         plotFrame: plotFrame)
        }
    }

    // MARK: Values

    private var endDate: Date { Snapshot.date(snapshot.asOf) ?? Date() }
    private var chartDomain: ClosedRange<Double> { HistoryProjection.domain(chartPoints) }
    private var displayedBalance: Double { selectedIndex.map { chartPoints[$0].value } ?? snapshot.total(in: currency) }
    private var changeAmount: Double { displayedBalance - (chartPoints.first?.value ?? displayedBalance) }
    private var changePercent: Double {
        guard let start = chartPoints.first?.value, start != 0 else { return 0 }
        return changeAmount / abs(start) * 100
    }
    private var hasComparison: Bool { chartPoints.count > 1 && chartPoints.first?.value != 0 }
    /// Numbers track the finger instantly while scrubbing and roll only when
    /// the selection is released or the range, currency or snapshot changes.
    private var numberAnimation: Animation? { reduceMotion || selectedIndex != nil ? nil : .easeInOut(duration: 0.2) }

    // MARK: Ranges and selection

    private var availablePeriods: [Period] { Self.availablePeriods(for: snapshot) }
    private static func availablePeriods(for snapshot: Snapshot) -> [Period] {
        Period.available(history: HistoryProjection.points(snapshot: snapshot, currency: "USD", period: .all))
    }
    private static func defaultPeriod(for snapshot: Snapshot) -> Period {
        let available = availablePeriods(for: snapshot)
        return available.contains(.ytd) ? .ytd : available.last ?? .all
    }

    private func updatePoints() {
        if !reduceMotion {
            let now = Date()
            if let morph {
                let progress = ChartMorph.progress(elapsed: now.timeIntervalSince(morph.start))
                self.morph = ChartMorphState(points: ChartMorph.points(from: morph.points, to: plotPoints, progress: progress),
                                             domain: ChartMorph.domain(from: morph.domain, to: chartDomain, progress: progress), start: now)
            } else {
                morph = ChartMorphState(points: plotPoints, domain: chartDomain, start: now)
            }
        }
        chartPoints = HistoryProjection.points(snapshot: snapshot, currency: currency, period: period)
        plotPoints = ChartMorph.plotted(chartPoints)
        selectedIndex = nil
    }

    /// Snaps the chart's continuous selection to the nearest real point and only writes state when
    /// that point changes, so a moving finger doesn't invalidate the page on every frame.
    private var selection: Binding<Double?> {
        Binding(get: { selectedIndex.map { plotPoints[$0].position } }, set: { position in
            let index = position.map { ChartMorph.nearestIndex(to: $0, in: plotPoints) }
            if index != selectedIndex { selectedIndex = index }
        })
    }
}
