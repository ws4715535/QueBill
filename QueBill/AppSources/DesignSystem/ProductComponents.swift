import SwiftUI

struct ProductScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.large) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, AppSpacing.xLarge)
        .frame(height: 94)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }
}

extension ProductScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct AccountContextStrip: View {
    let account: AppAccount

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Text(account.displayName)
                .fontWeight(.semibold)
            Text(account.dataLabel)
            Spacer()
            Text(Date.now.formatted(date: .numeric, time: .omitted))
            Text("·")
            Text(account.displayName)
        }
        .font(.caption2)
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, AppSpacing.large)
        .frame(height: 30)
        .background(AppColors.surface)
    }
}

struct StatusPill: View {
    let title: String
    var isActive = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(isActive ? AppColors.accentDefault : AppColors.textSecondary)
            .frame(minWidth: 72, minHeight: 28)
            .background(
                isActive ? AppColors.accentSubtle : AppColors.backgroundSubtle,
                in: Capsule()
            )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .productCard()
    }
}

struct KeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 14)
    }
}
