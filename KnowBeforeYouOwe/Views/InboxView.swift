import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var selectedBreakdown: DigestBreakdown?
    @State private var assistantToast: AgentToast?
    @State private var animateRecommendation = false
    
    private var inboxMessages: [EmailMessage] {
        appState.messages
    }

    private var prioritySubscriptions: [SubscriptionRecord] {
        let sorted = appState.subscriptions.sorted { lhs, rhs in
            digestPriority(for: lhs) > digestPriority(for: rhs)
        }

        let focused = sorted.filter {
            $0.status == .increased || $0.status == .trial || $0.badge == .upcoming
        }

        if focused.isEmpty {
            return Array(sorted.prefix(2))
        }

        return Array(focused.prefix(3))
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar

                if appState.messages.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            digestHeader

                            VStack(spacing: 4) {
                                ForEach(Array(inboxMessages.enumerated()), id: \.element.id) { index, message in
                                    VStack(spacing: 0) {
                                        NavigationLink {
                                            EmailEvidenceView(email: message.asEvidenceEmail)
                                        } label: {
                                            messageRow(message)
                                        }
                                        .buttonStyle(.plain)

                                        if index < inboxMessages.count - 1 {
                                            Divider()
                                                .overlay(KBYOPalette.line)
                                                .padding(.leading, 89)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                        }
                        .padding(.bottom, 26)
                    }
                    .refreshable {
                        await appState.refreshInbox()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedBreakdown) { breakdown in
            DigestBreakdownSheet(breakdown: breakdown, subscriptions: appState.subscriptions)
        }
        .overlay(alignment: .bottom) {
            if let assistantToast {
                AgentToastView(toast: assistantToast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                animateRecommendation = true
            }
        }
    }

    private var background: some View {
        KBYOPalette.background.ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Circle()
                .fill(Color(hex: "59BEE8"))
                .frame(width: 42, height: 42)
                .overlay(
                    Text(String(appState.credentials.email.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                )

            Spacer()

            Text("Home")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Spacer()

            Circle()
                .fill(KBYOPalette.accent)
                .frame(width: 42, height: 42)
                .overlay(
                    Text("y+")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                )
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var digestHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                summaryHeroCard

                if !prioritySubscriptions.isEmpty || appState.highlights.first != nil || appState.backgroundSyncMessage != nil {
                    needsAttentionCard
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .padding(.top, 4)
        .background(background)
    }

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recurring Services Snapshot")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(appState.assistantOverview)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Haptics.selection()
                    appState.selectedTab = .subscriptions
                } label: {
                    Text("Open")
                        .font(AppFont.headline(16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                summaryStatChip(value: appState.digest.recurringCount, label: "Recurring", breakdown: .recurring)
                summaryStatChip(value: appState.digest.trialCount, label: "Trials", breakdown: .trials)
                summaryStatChip(value: appState.digest.increaseCount, label: "Increases", breakdown: .increases)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(animateRecommendation ? 1.08 : 0.94)
                        .opacity(animateRecommendation ? 1 : 0.8)
                    Text("Assistant Recommendation")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(appState.topRecommendation)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    runRecommendationAction()
                } label: {
                    Text(appState.recommendationActionTitle)
                        .font(AppFont.headline(15))
                        .foregroundStyle(KBYOPalette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.white.opacity(animateRecommendation ? 0.28 : 0.08), radius: animateRecommendation ? 14 : 4, x: 0, y: 0)
                }
                .buttonStyle(PressableSpringButtonStyle())
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [KBYOPalette.accent, Color(hex: "8E2DFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: KBYOPalette.accent.opacity(0.18), radius: 16, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            Haptics.selection()
            appState.selectedTab = .subscriptions
        }
    }

    private var needsAttentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needs Attention")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            if let highlight = appState.highlights.first {
                Text(highlight)
                    .font(AppFont.body(14))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(prioritySubscriptions) { subscription in
                Button {
                    Haptics.selection()
                    appState.requestSubscriptionDetail(for: subscription)
                } label: {
                    digestSubscriptionRow(subscription)
                }
                .buttonStyle(.plain)
            }

            if let backgroundSyncMessage = appState.backgroundSyncMessage {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(KBYOPalette.accent)
                    Text(backgroundSyncMessage)
                        .font(AppFont.caption(13))
                        .foregroundStyle(KBYOPalette.secondary)
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func digestChip(value: Int, label: String, breakdown: DigestBreakdown) -> some View {
        summaryStatChip(value: value, label: label, breakdown: breakdown)
    }

    private func summaryStatChip(value: Int, label: String, breakdown: DigestBreakdown) -> some View {
        Button {
            Haptics.selection()
            selectedBreakdown = breakdown
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(AppFont.caption(12))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func digestSubscriptionRow(_ subscription: SubscriptionRecord) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(KBYOPalette.accentSoft)
                .frame(width: 46, height: 46)
                .overlay(
                    Text(subscription.merchant.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KBYOPalette.accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(subscription.merchant)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .layoutPriority(2)

                    Spacer(minLength: 4)

                    if let badge = subscription.badge {
                        Text(badge.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: badge.tintHex))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(subscription.summary)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            amountSummary(for: subscription)
        }
        .padding(14)
        .background(Color(hex: "F6F7FB"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func amountSummary(for subscription: SubscriptionRecord) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if subscription.status == .increased,
               let current = subscription.currentAmount {
                Text("NEW PRICE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(KBYOPalette.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(hex: "FFF0EE"), in: Capsule())

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(current.currencyString)
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundStyle(KBYOPalette.danger)

                if let previous = subscription.previousAmount,
                   current != previous {
                    Text("was \(previous.currencyString)")
                        .font(AppFont.caption(12))
                        .foregroundStyle(KBYOPalette.secondary)
                }
            } else {
                Text(subscription.formattedAmount)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KBYOPalette.ink)
            }

            Text(subscription.nextDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
        }
    }

    private func messageRow(_ message: EmailMessage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(message.isUnread ? KBYOPalette.unreadDot : KBYOPalette.backgroundTint)
                .frame(width: 11, height: 11)
                .padding(.top, 18)

            Circle()
                .fill(avatarColor(for: message))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(message.senderDisplay.prefix(1).uppercased())
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.senderDisplay)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    HStack(spacing: 9) {
                        if showsAttachment(for: message) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(KBYOPalette.tertiary)
                        }

                        Text(relativeTimestamp(for: message.date))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(KBYOPalette.secondary)

                        Image(systemName: appState.relatedSubscription(for: message) == nil ? "star" : "star.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(appState.relatedSubscription(for: message) == nil ? KBYOPalette.tertiary : Color(hex: "F97316"))
                    }
                }

                Text(message.subject)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(KBYOPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.snippet)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subscription = appState.relatedSubscription(for: message) {
                    HStack(spacing: 8) {
                        Text(subscription.badge?.rawValue ?? "RECURRING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(KBYOPalette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(KBYOPalette.accentSoft, in: Capsule())

                        if subscription.status == .increased,
                           let current = subscription.currentAmount,
                           let previous = subscription.previousAmount,
                           current != previous {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.forward.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(current.currencyString)
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(KBYOPalette.danger)
                        } else if let amount = subscription.amount {
                            Text(amount.currencyString)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KBYOPalette.secondary)
                        }
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.001))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(KBYOPalette.secondary)

            Text("No messages loaded")
                .font(AppFont.headline(22))
                .foregroundStyle(KBYOPalette.ink)

            Text("Your assistant will populate this view as billing signals, renewals, and recurring charges are identified.")
                .font(AppFont.body(16))
                .foregroundStyle(KBYOPalette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func avatarColor(for message: EmailMessage) -> Color {
        let colors: [Color] = [
            Color(hex: "B57917"),
            Color(hex: "6277C0"),
            Color(hex: "3E97A9"),
            Color(hex: "8A8F98"),
            Color(hex: "2B6CB0")
        ]
        let index = abs(message.senderDisplay.hashValue) % colors.count
        return colors[index]
    }

    private func showsAttachment(for message: EmailMessage) -> Bool {
        let text = "\(message.subject) \(message.snippet) \(message.bodyPreview)".lowercased()
        return text.contains("invoice") || text.contains("receipt") || text.contains("pdf") || text.contains("attached")
    }

    private func relativeTimestamp(for date: Date?) -> String {
        guard let date else { return "" }

        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 6 {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func digestPriority(for subscription: SubscriptionRecord) -> Int {
        switch subscription.status {
        case .increased:
            let awaitingPenalty = appState.demoAwaitingFeedbackSubscriptionIDs.contains(subscription.id) ? 100 : 0
            return 300 + Int(subscription.priceIncreaseDelta * 100) - awaitingPenalty
        case .trial:
            return 200
        case .active:
            return subscription.badge == .upcoming ? 100 : 0
        }
    }

    private func runRecommendationAction() {
        guard let subscription = appState.recommendedSubscription else {
            appState.selectedTab = .subscriptions
            return
        }

        if subscription.status == .trial {
            performCancellation(for: subscription, context: "trial")
        } else {
            Haptics.selection()
            appState.requestSubscriptionDetail(for: subscription)
        }
    }

    private func performCancellation(for subscription: SubscriptionRecord, context: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            assistantToast = AgentToast(
                systemImage: "sparkles",
                title: "Assistant Working",
                message: "Working on canceling \(subscription.merchant). I’m following the billing path I found in the inbox.",
                tint: KBYOPalette.accent,
                showsProgress: true
            )
        }

        Task {
            try? await Task.sleep(for: .seconds(2.6))

            if appState.useDemoData {
                appState.completeDemoCancellation(for: subscription)
                await MainActor.run {
                    Haptics.success()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        assistantToast = AgentToast(
                            systemImage: "checkmark.seal.fill",
                            title: "Action Completed",
                            message: "\(subscription.merchant) \(context) canceled. I updated your summary and removed the next bill from view.",
                            tint: KBYOPalette.success
                        )
                    }
                }
            } else if let destination = appState.cancellationDestination(for: subscription) {
                openURL(destination.url)
                await MainActor.run {
                    Haptics.success()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        assistantToast = AgentToast(
                            systemImage: "checkmark.circle.fill",
                            title: "Action Opened",
                            message: "Opened \(subscription.merchant)'s cancellation flow from the latest billing email.",
                            tint: KBYOPalette.success
                        )
                    }
                }
            }

            try? await Task.sleep(for: .seconds(5.6))
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    assistantToast = nil
                }
            }
        }
    }
}

private enum DigestBreakdown: String, Identifiable {
    case recurring
    case trials
    case increases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recurring: return "Recurring Charges"
        case .trials: return "Trials Ending Soon"
        case .increases: return "Price Increases"
        }
    }

    var subtitle: String {
        switch self {
        case .recurring: return "These are the subscriptions the assistant believes are actively renewing."
        case .trials: return "These are still in trial and can be stopped before the first paid charge."
        case .increases: return "These appear to be merchants that raised their price and may deserve review."
        }
    }
}

private struct DigestBreakdownSheet: View {
    let breakdown: DigestBreakdown
    let subscriptions: [SubscriptionRecord]

    private var filteredSubscriptions: [SubscriptionRecord] {
        switch breakdown {
        case .recurring:
            return subscriptions
        case .trials:
            return subscriptions.filter { $0.status == .trial }
        case .increases:
            return subscriptions.filter { $0.status == .increased }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(breakdown.title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(KBYOPalette.ink)

                        Text(breakdown.subtitle)
                            .font(AppFont.body(16))
                            .foregroundStyle(KBYOPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(filteredSubscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(subscription.merchant)
                                .font(AppFont.headline(18))
                                .foregroundStyle(KBYOPalette.ink)
                            Text(subscription.summary)
                                .font(AppFont.body(14))
                                .foregroundStyle(KBYOPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(KBYOPalette.background.ignoresSafeArea())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension EmailMessage {
    var asEvidenceEmail: EvidenceEmail {
        EvidenceEmail(
            uid: uid,
            senderDisplay: senderDisplay,
            senderEmail: senderEmail,
            replyToEmail: replyToEmail,
            subject: subject,
            date: date,
            snippet: snippet,
            bodyPreview: bodyPreview
        )
    }
}
