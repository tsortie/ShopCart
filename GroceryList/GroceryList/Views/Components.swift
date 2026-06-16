import SwiftUI

// MARK: - App Theme
enum AppTheme {
    static var primary:      Color { Color("AppGreen") }
    static var primaryLight: Color { Color("AppGreenLight") }
    static var accent:       Color { Color("AppAccent") }
    static var destructive:  Color { .red }

    static let cornerRadius:     CGFloat = 14
    static let smallRadius:      CGFloat = 8
    static let cardShadowRadius: CGFloat = 4
    static let cardShadowY:      CGFloat = 2
}

// MARK: - QuantityStepper
struct QuantityStepper: View {
    let value: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    var minValue: Int = 1

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(value <= minValue ? .secondary : AppTheme.primary)
            }
            .disabled(value <= minValue)

            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(minWidth: 24)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(AppTheme.primary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - RadioButton
struct RadioButton: View {
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .stroke(isActive ? Color(.systemGray4) : AppTheme.primary, lineWidth: 2)
                    .frame(width: 24, height: 24)

                if !isActive {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - EmptyStateView
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Color(.systemGray4).opacity(0.6))

            VStack(spacing: 6) {
                Text("Your list is empty")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                Text("Tap + Add Item below to get started")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                Text("Tap the menu in the top right to learn more")
                    .font(.system(size: 13))
            }
            .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SectionHeader
struct SectionHeader: View {
    let title: String
    let count: Int
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(.systemGray3)))

            Spacer()

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.destructive)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
