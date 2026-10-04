import SwiftUI
import SwiftUICharts

private enum ReportPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .week: "本周"
        case .month: "本月"
        }
    }
}

@MainActor
struct OperationsView: View {
    let viewModel: MachineDashboardViewModel

    @State private var period: ReportPeriod = .today

    private var settledSnapshots: [OrderSnapshot] {
        viewModel.orders.compactMap { viewModel.snapshot(orderID: $0.id) }.filter {
            $0.order.status == .completed && isIncluded($0.order.endedAt ?? $0.order.startedAt)
        }
    }

    private var revenue: Decimal {
        settledSnapshots.reduce(0) { $0 + ($1.bill?.finalAmount ?? 0) }
    }

    private var adjustments: Decimal {
        settledSnapshots.reduce(0) { $0 + ($1.bill?.adjustmentAmount ?? 0) }
    }

    private var revenueData: BarChartData { OperationsChartData.revenue(from: settledSnapshots) }
    private var trendData: LineChartData { OperationsChartData.trend(from: settledSnapshots) }
    private var sessionData: BarChartData { OperationsChartData.sessions(from: settledSnapshots) }
    private var revenuePoints: [(String, Double)] { OperationsChartData.revenueValues(from: settledSnapshots) }
    private var sessionPoints: [(String, Double)] { OperationsChartData.sessionValues(from: settledSnapshots) }
    private var machinePerformance: [MachinePerformance] {
        Dictionary(grouping: settledSnapshots, by: { $0.order.machineNumberSnapshot })
            .map { number, snapshots in
                MachinePerformance(
                    number: number,
                    orderCount: snapshots.count,
                    duration: snapshots.reduce(0) { $0 + ($1.bill?.effectiveDuration ?? 0) },
                    revenue: snapshots.reduce(0) { $0 + ($1.bill?.finalAmount ?? 0) }
                )
            }
            .sorted {
                if $0.duration == $1.duration { return $0.revenue > $1.revenue }
                return $0.duration > $1.duration
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProductScreenHeader("运营数据", subtitle: "营业趋势、时段分析和设备表现")

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Picker("统计范围", selection: $period) {
                        ForEach(ReportPeriod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    revenueHero

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: AppSpacing.medium)],
                        spacing: AppSpacing.medium
                    ) {
                        MetricCard(title: "结算订单", value: "\(settledSnapshots.count)", footnote: "按已结算订单")
                        MetricCard(title: "单均实收", value: averageRevenue.currencyText, footnote: "实收 / 订单数")
                        MetricCard(title: "优惠 / 调整", value: adjustments.currencyText, footnote: "已完成订单")
                        MetricCard(title: "使用最多", value: busiestMachine, footnote: "按结算订单统计")
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppSpacing.medium) {
                                chartCard(title: "营业额柱状图", subtitle: "按 4 小时汇总") {
                                ChartValueLegend(values: revenuePoints, prefix: "¥")
                                BarChart(chartData: revenueData)
                                    .xAxisGrid(chartData: revenueData)
                                    .yAxisGrid(chartData: revenueData)
                                    .xAxisLabels(chartData: revenueData)
                                    .touchOverlay(chartData: revenueData, specifier: "¥%.0f")
                                    .id(revenueData.id)
                            }
                            .frame(maxWidth: .infinity)

                            chartCard(title: "营业趋势", subtitle: "实收金额走势") {
                                ChartValueLegend(values: revenuePoints, prefix: "¥")
                                LineChart(chartData: trendData)
                                    .pointMarkers(chartData: trendData)
                                    .xAxisGrid(chartData: trendData)
                                    .yAxisGrid(chartData: trendData)
                                    .xAxisLabels(chartData: trendData)
                                    .touchOverlay(chartData: trendData, specifier: "¥%.0f")
                                    .id(trendData.id)
                            }
                            .frame(maxWidth: 440)
                        }

                        VStack(spacing: AppSpacing.medium) {
                            chartCard(title: "营业额柱状图", subtitle: "按 4 小时汇总") {
                                ChartValueLegend(values: revenuePoints, prefix: "¥")
                                BarChart(chartData: revenueData)
                                    .xAxisLabels(chartData: revenueData)
                                    .id(revenueData.id)
                            }
                            chartCard(title: "营业趋势", subtitle: "实收金额走势") {
                                ChartValueLegend(values: revenuePoints, prefix: "¥")
                                LineChart(chartData: trendData)
                                    .pointMarkers(chartData: trendData)
                                    .xAxisLabels(chartData: trendData)
                                    .id(trendData.id)
                            }
                        }
                    }

                    MachinePerformanceView(items: machinePerformance)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppSpacing.medium) {
                            chartCard(title: "开台时段分布", subtitle: "按订单实际开台时间 · 4小时区间") {
                                ChartValueLegend(values: sessionPoints, prefix: "")
                                BarChart(chartData: sessionData)
                                    .xAxisLabels(chartData: sessionData)
                                    .id(sessionData.id)
                            }
                            .frame(maxWidth: .infinity)

                            PaymentStructureView(snapshots: settledSnapshots)
                                .frame(maxWidth: 440)
                        }

                        VStack(spacing: AppSpacing.medium) {
                            chartCard(title: "开台时段分布", subtitle: "按订单实际开台时间 · 4小时区间") {
                                ChartValueLegend(values: sessionPoints, prefix: "")
                                BarChart(chartData: sessionData)
                                    .xAxisLabels(chartData: sessionData)
                                    .id(sessionData.id)
                            }
                            PaymentStructureView(snapshots: settledSnapshots)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xLarge)
                .padding(.vertical, 22)
            }
        }
        .background(AppColors.backgroundPrimary)
        .task { await viewModel.load() }
    }

    private var revenueHero: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("实收营业额，已结算订单")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.accentSubtle)
                Text(revenue.currencyText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Spacer()
            Text("来自 \(settledSnapshots.count) 笔已结算订单")
                .font(.caption)
                .foregroundStyle(AppColors.accentSubtle)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(AppColors.accentStrong, in: RoundedRectangle(cornerRadius: AppRadius.hero))
    }

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
            content()
                .frame(maxWidth: .infinity, minHeight: 170)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .leading)
        .productCard(radius: 14)
    }

    private var averageRevenue: Decimal {
        guard !settledSnapshots.isEmpty else { return 0 }
        return revenue / Decimal(settledSnapshots.count)
    }

    private var busiestMachine: String {
        guard let machine = machinePerformance.first else { return "-" }
        return "\(machine.number)号机"
    }

    private func isIncluded(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch period {
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            return calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: .now, toGranularity: .month)
        }
    }
}

private struct ChartValueLegend: View {
    let values: [(String, Double)]
    let prefix: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(valueText(item.1))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppColors.backgroundSubtle, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func valueText(_ value: Double) -> String {
        if prefix.isEmpty { return value.formatted(.number.precision(.fractionLength(0))) }
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(0))))"
    }
}

private struct PaymentStructureView: View {
    let snapshots: [OrderSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("收款结构")
                .font(.headline.bold())
                .foregroundStyle(AppColors.textPrimary)
            paymentRow(.weChat)
            paymentRow(.alipay)
            paymentRow(.cash)
            paymentRow(.memberBalance)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .productCard(radius: 14)
    }

    private func paymentRow(_ method: PaymentMethod) -> some View {
        let value = snapshots
            .flatMap(\.payments)
            .filter { $0.method == method }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let total = snapshots.flatMap(\.payments)
            .reduce(Decimal.zero) { $0 + $1.amount }
        let percent = total > 0
            ? NSDecimalNumber(decimal: value / total).doubleValue
            : 0
        return VStack(spacing: 7) {
            HStack {
                Text(method.title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(value.currencyText)  \((percent * 100).formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            }
            ProgressView(value: percent)
                .tint(AppColors.accentDefault)
        }
    }
}

private struct MachinePerformance: Identifiable {
    let number: String
    let orderCount: Int
    let duration: TimeInterval
    let revenue: Decimal

    var id: String { number }
}

private struct MachinePerformanceView: View {
    let items: [MachinePerformance]

    private var maximumDuration: TimeInterval {
        max(items.map(\.duration).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text("机器运营表现")
                    .font(.headline.bold())
                Text("按已结算订单的累计使用时长排序")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if items.isEmpty {
                ContentUnavailableView("暂无机器运营数据", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: AppSpacing.medium) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(index == 0 ? .white : AppColors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(index == 0 ? AppColors.accentStrong : AppColors.backgroundSubtle, in: Circle())

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("\(item.number)号机")
                                    .font(.subheadline.bold())
                                Text("\(item.orderCount) 笔订单")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                                Spacer()
                                Text(item.duration.durationText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            ProgressView(value: item.duration / maximumDuration)
                                .tint(AppColors.accentDefault)
                            HStack {
                                Text("累计使用时长")
                                Spacer()
                                Text("实收 \(item.revenue.currencyText)")
                            }
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    if item.id != items.last?.id { Divider() }
                }
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .productCard(radius: 14)
    }
}

@MainActor
private enum OperationsChartData {
    static func revenue(from snapshots: [OrderSnapshot]) -> BarChartData {
        let values = revenueValues(from: snapshots)
        return BarChartData(
            dataSets: BarDataSet(dataPoints: values.map {
                BarChartDataPoint(
                    value: $0.1,
                    xAxisLabel: $0.0,
                    description: $0.0,
                    colour: ColourStyle(colour: AppColors.accentDefault)
                )
            }),
            barStyle: BarStyle(
                barWidth: 0.24,
                colourFrom: .dataPoints,
                colour: ColourStyle(colour: AppColors.accentDefault)
            )
        )
    }

    static func trend(from snapshots: [OrderSnapshot]) -> LineChartData {
        let values = revenueValues(from: snapshots)
        let dataSet = LineDataSet(
            dataPoints: values.map {
                LineChartDataPoint(value: $0.1, xAxisLabel: $0.0, description: $0.0)
            },
            pointStyle: PointStyle(pointSize: 8, borderColour: AppColors.accentDefault, fillColour: AppColors.accentDefault),
            style: LineStyle(
                lineColour: ColourStyle(colour: AppColors.trend),
                lineType: .line,
                strokeStyle: Stroke(lineWidth: 2)
            )
        )
        return LineChartData(dataSets: dataSet)
    }

    static func sessions(from snapshots: [OrderSnapshot]) -> BarChartData {
        let values = sessionValues(from: snapshots)
        return BarChartData(
            dataSets: BarDataSet(dataPoints: values.map {
                BarChartDataPoint(
                    value: $0.1,
                    xAxisLabel: $0.0,
                    description: $0.0,
                    colour: ColourStyle(colour: AppColors.accentDefault)
                )
            }),
            barStyle: BarStyle(
                barWidth: 0.22,
                colourFrom: .dataPoints,
                colour: ColourStyle(colour: AppColors.accentDefault)
            )
        )
    }

    static func sessionValues(from snapshots: [OrderSnapshot]) -> [(String, Double)] {
        let calendar = Calendar.current
        return stride(from: 0, to: 24, by: 4).map { start in
            let count = snapshots.count {
                let hour = calendar.component(.hour, from: $0.order.startedAt)
                return hour >= start && hour < start + 4
            }
            return ("\(start)-\(start + 4)时", Double(count))
        }
    }

    static func revenueValues(from snapshots: [OrderSnapshot]) -> [(String, Double)] {
        let calendar = Calendar.current
        return stride(from: 0, to: 24, by: 4).map { start in
            let amount = snapshots.filter {
                let date = $0.order.endedAt ?? $0.order.startedAt
                let hour = calendar.component(.hour, from: date)
                return hour >= start && hour < start + 4
            }.reduce(Decimal.zero) { $0 + ($1.bill?.finalAmount ?? 0) }
            return ("\(start)时", NSDecimalNumber(decimal: amount).doubleValue)
        }
    }
}
