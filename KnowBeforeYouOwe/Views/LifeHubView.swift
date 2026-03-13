import SwiftUI

struct LifeHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var focusedSubscription: SubscriptionRecord?
    @State private var assistantToast: AgentToast?

    private var prioritizedSubscriptions: [SubscriptionRecord] {
        appState.subscriptions.sorted {
            priority(for: $0) < priority(for: $1)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if appState.subscriptions.isEmpty {
                    emptyState
                } else {
                    ForEach(prioritizedSubscriptions) { subscription in
                        NavigationLink {
                            if subscription.status == .trial {
                                TrialDetailView(subscription: subscription)
                            } else {
                                SubscriptionDetailView(subscription: subscription)
                            }
                        } label: {
                            subscriptionCard(subscription)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 34)
        }
        .background(background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(item: $focusedSubscription) { subscription in
            if subscription.status == .trial {
                TrialDetailView(subscription: subscription)
            } else {
                SubscriptionDetailView(subscription: subscription)
            }
        }
        .onAppear(perform: navigateToRequestedSubscriptionIfNeeded)
        .onChange(of: appState.requestedSubscriptionID) { _, _ in
            navigateToRequestedSubscriptionIfNeeded()
        }
        .overlay(alignment: .bottom) {
            if let assistantToast {
                AgentToastView(toast: assistantToast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [KBYOPalette.background, KBYOPalette.backgroundTint.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Know Before You Owe")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)
        }
        .padding(.top, 6)
    }

    private func subscriptionCard(_ subscription: SubscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(KBYOPalette.accentWash)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(subscription.merchant.prefix(1).uppercased())
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(KBYOPalette.accent)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(subscription.merchant)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(subscription.summary)
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let badge = subscription.badge {
                    Text(badge.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: badge.tintHex))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: badge.tintHex).opacity(0.12), in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: 10) {
                if subscription.status == .increased,
                   let current = subscription.currentAmount {
                    dataPoint(title: "New price", value: current.currencyString, tint: KBYOPalette.danger)
                    if let previous = subscription.previousAmount,
                       current != previous {
                        dataPoint(title: "Previous", value: previous.currencyString)
                    }
                } else {
                    dataPoint(title: "Amount", value: subscription.formattedAmount)
                }
                dataPoint(title: "Cadence", value: subscription.cadence)
                dataPoint(
                    title: "Next Date",
                    value: subscription.nextDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
                )
            }

            if let latestEvidence = subscription.latestEvidence {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KBYOPalette.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(latestEvidence.subject)
                            .font(AppFont.headline(15))
                            .foregroundStyle(KBYOPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(latestEvidence.date?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")
                            .font(AppFont.caption(13))
                            .foregroundStyle(KBYOPalette.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KBYOPalette.accent)
                }
                .padding(14)
                .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(20)
        .cardSurface()
    }

    private func dataPoint(title: String, value: String, tint: Color = KBYOPalette.ink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.caption(12))
                .foregroundStyle(KBYOPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(AppFont.headline(16))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No recurring subscriptions detected yet.")
                .font(AppFont.headline(20))
                .foregroundStyle(KBYOPalette.ink)

            Text("As recurring billing signals are found, they will appear here with suggested actions and supporting evidence.")
                .font(AppFont.body(15))
                .foregroundStyle(KBYOPalette.secondary)
        }
        .padding(20)
        .cardSurface()
    }

    private func priority(for subscription: SubscriptionRecord) -> Int {
        switch subscription.badge {
        case .trial:
            return 0
        case .increase:
            let awaitingOffset = appState.demoAwaitingFeedbackSubscriptionIDs.contains(subscription.id) ? 500 : 0
            return max(1, 200 - Int(subscription.priceIncreaseDelta * 100) + awaitingOffset)
        case .upcoming:
            return 2
        case .none:
            return 3
        }
    }

    private func handleRecommendationTapped() {
        guard let subscription = appState.recommendedSubscription else { return }

        if subscription.status == .trial {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                assistantToast = AgentToast(
                    systemImage: "sparkles",
                    title: "Assistant Working",
                    message: "I’m canceling \(subscription.merchant) before the first bill lands.",
                    tint: KBYOPalette.accent,
                    showsProgress: true
                )
            }

            Task {
                try? await Task.sleep(for: .seconds(2.6))
                await MainActor.run {
                    appState.completeDemoCancellation(for: subscription)
                    Haptics.success()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        assistantToast = AgentToast(
                            systemImage: "checkmark.seal.fill",
                            title: "Action Completed",
                            message: "\(subscription.merchant) trial canceled. I recorded the action and updated the case summary.",
                            tint: KBYOPalette.success
                        )
                    }
                }

                try? await Task.sleep(for: .seconds(5.6))
                await MainActor.run {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        assistantToast = nil
                    }
                }
            }
        } else {
            focusedSubscription = subscription
        }
    }

    private func navigateToRequestedSubscriptionIfNeeded() {
        guard let requestedID = appState.requestedSubscriptionID,
              let subscription = prioritizedSubscriptions.first(where: { $0.id == requestedID }) else {
            return
        }

        focusedSubscription = subscription
        appState.consumeRequestedSubscription()
    }
}
