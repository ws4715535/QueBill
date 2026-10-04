import Foundation

struct BillingContext: Sendable {
    let order: Order
    let pauses: [OrderPause]
    let pricing: PricingConfiguration
    let calculatedAt: Date
}

protocol BillingService: Sendable {
    func preview(context: BillingContext) throws -> Bill
}

struct StandardBillingService: BillingService {
    func preview(context: BillingContext) throws -> Bill {
        let calendar = Calendar.mainlandChina
        let businessDayCategory = context.pricing.dayCategory(
            for: context.order.businessDay.date,
            calendar: calendar
        )
        let intervals = activeIntervals(
            from: context.order.startedAt,
            to: context.calculatedAt,
            pauses: context.pauses
        )
        var buckets: [SegmentKey: SegmentBucket] = [:]

        for interval in intervals {
            var cursor = interval.start
            while cursor < interval.end {
                let segment = classify(
                    cursor,
                    pricing: context.pricing,
                    businessDayCategory: businessDayCategory,
                    calendar: calendar
                )
                let end = min(interval.end, segment.ruleEnd)
                guard end > cursor else { break }
                var bucket = buckets[segment.key] ?? SegmentBucket(
                    key: segment.key,
                    startedAt: cursor,
                    endedAt: end,
                    effectiveDuration: 0
                )
                bucket.startedAt = min(bucket.startedAt, cursor)
                bucket.endedAt = max(bucket.endedAt, end)
                bucket.effectiveDuration += end.timeIntervalSince(cursor)
                buckets[segment.key] = bucket
                cursor = end
            }
        }

        let lines = buckets.values
            .sorted { $0.startedAt < $1.startedAt }
            .flatMap { bucket in
                makeLines(
                    bucket: bucket,
                    order: context.order,
                    pricing: context.pricing
                )
            }
        let originalAmount = roundedCurrency(lines.reduce(0) { $0 + $1.amount })
        let snapshot = try JSONEncoder().encode(context.pricing)
        let effectiveDuration = intervals.reduce(0) { $0 + $1.duration }

        return Bill(
            id: UUID(),
            orderID: context.order.id,
            startedAt: context.order.startedAt,
            endedAt: context.calculatedAt,
            effectiveDuration: effectiveDuration,
            lines: lines,
            originalAmount: originalAmount,
            adjustmentAmount: 0,
            finalAmount: originalAmount,
            playerAmounts: splitCurrency(originalAmount, count: context.order.playerCount),
            priceRuleSnapshot: snapshot,
            createdAt: context.calculatedAt
        )
    }

    private func makeLines(
        bucket: SegmentBucket,
        order: Order,
        pricing: PricingConfiguration
    ) -> [BillLine] {
        let playerCount = Decimal(order.playerCount)

        switch bucket.key {
        case .early:
            return [BillLine(
                id: UUID(), title: "早场包时",
                startedAt: bucket.startedAt, endedAt: bucket.endedAt,
                amount: roundedCurrency(pricing.earlyPricePerPlayer * playerCount)
            )]
        case .night:
            return [BillLine(
                id: UUID(), title: "夜场包时",
                startedAt: bucket.startedAt, endedAt: bucket.endedAt,
                amount: roundedCurrency(pricing.nightPricePerPlayer * playerCount)
            )]
        case let .daytime(_, category):
            let rate = pricing.daytimeRate(machineType: order.machineTypeSnapshot, category: category)
            let cap = pricing.daytimeCap(category: category)
            let uncappedPerPlayer = rate * Decimal(bucket.effectiveDuration / 3_600)
            let title = category == .weekday ? "工作日日间" : "周末 / 节假日日间"
            guard rate > 0, uncappedPerPlayer >= cap else {
                return [BillLine(
                    id: UUID(), title: title,
                    startedAt: bucket.startedAt, endedAt: bucket.endedAt,
                    amount: roundedCurrency(uncappedPerPlayer * playerCount)
                )]
            }
            let capDuration = NSDecimalNumber(decimal: cap / rate).doubleValue * 3_600
            let capReachedAt = min(
                bucket.endedAt,
                bucket.startedAt.addingTimeInterval(capDuration)
            )
            if uncappedPerPlayer == cap {
                return [BillLine(
                    id: UUID(), title: "\(title) · 刚好达到封顶",
                    startedAt: bucket.startedAt, endedAt: bucket.endedAt,
                    amount: roundedCurrency(cap * playerCount)
                )]
            }
            return [
                BillLine(
                    id: UUID(), title: "\(title) · 达到封顶",
                    startedAt: bucket.startedAt, endedAt: capReachedAt,
                    amount: roundedCurrency(cap * playerCount)
                ),
                BillLine(
                    id: UUID(), title: "日间封顶后继续使用",
                    startedAt: capReachedAt, endedAt: bucket.endedAt,
                    amount: 0
                )
            ]
        }
    }

    private func classify(
        _ date: Date,
        pricing: PricingConfiguration,
        businessDayCategory: DayCategory,
        calendar: Calendar
    ) -> ClassifiedSegment {
        let dayStart = calendar.startOfDay(for: date)
        let earlyStart = calendar.date(byAdding: .hour, value: pricing.earlyStartHour, to: dayStart) ?? dayStart
        let earlyEnd = calendar.date(byAdding: .hour, value: pricing.earlyEndHour, to: dayStart) ?? dayStart
        let nightStart = calendar.date(byAdding: .hour, value: pricing.nightStartHour, to: dayStart) ?? dayStart

        if date >= earlyStart && date < earlyEnd {
            return ClassifiedSegment(key: .early(dayStart), ruleEnd: earlyEnd)
        }
        if date >= nightStart {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let nightEnd = calendar.date(byAdding: .hour, value: pricing.nightEndHour, to: nextDay) ?? nextDay
            return ClassifiedSegment(key: .night(dayStart), ruleEnd: nightEnd)
        }
        let nightEndToday = calendar.date(byAdding: .hour, value: pricing.nightEndHour, to: dayStart) ?? dayStart
        if date < nightEndToday {
            let anchor = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
            return ClassifiedSegment(key: .night(anchor), ruleEnd: nightEndToday)
        }

        return ClassifiedSegment(
            key: .daytime(dayStart, businessDayCategory),
            ruleEnd: nightStart
        )
    }

    private func activeIntervals(
        from start: Date,
        to end: Date,
        pauses: [OrderPause]
    ) -> [DateInterval] {
        guard end > start else { return [] }
        var intervals = [DateInterval(start: start, end: end)]
        for pause in pauses {
            let pauseInterval = DateInterval(
                start: max(start, pause.startedAt),
                end: min(end, pause.endedAt ?? end)
            )
            guard pauseInterval.duration > 0 else { continue }
            intervals = intervals.flatMap { interval -> [DateInterval] in
                guard interval.intersects(pauseInterval) else { return [interval] }
                var result: [DateInterval] = []
                if interval.start < pauseInterval.start {
                    result.append(DateInterval(start: interval.start, end: min(interval.end, pauseInterval.start)))
                }
                if pauseInterval.end < interval.end {
                    result.append(DateInterval(start: max(interval.start, pauseInterval.end), end: interval.end))
                }
                return result
            }
        }
        return intervals
    }

    private func roundedCurrency(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .bankers)
        return result
    }

    private func splitCurrency(_ amount: Decimal, count: Int) -> [Decimal] {
        guard count > 0 else { return [] }
        let cents = NSDecimalNumber(decimal: amount * 100).intValue
        let base = cents / count
        let remainder = cents % count
        return (0..<count).map { index in
            Decimal(base + (index < remainder ? 1 : 0)) / 100
        }
    }

}

private enum SegmentKey: Hashable {
    case early(Date)
    case night(Date)
    case daytime(Date, DayCategory)
}

private struct SegmentBucket {
    let key: SegmentKey
    var startedAt: Date
    var endedAt: Date
    var effectiveDuration: TimeInterval
}

private struct ClassifiedSegment {
    let key: SegmentKey
    let ruleEnd: Date
}
