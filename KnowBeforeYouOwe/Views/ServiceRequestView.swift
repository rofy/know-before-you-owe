import SwiftUI

struct SubscriptionDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var cancelToast: AgentToast?
    @State private var cancelErrorMessage: String?

    let subscription: SubscriptionRecord

    private var isCanceled: Bool {
        appState.isDemoCanceled(subscription)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                detailHero
                billingStoryCard
                actionCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, bottomActionClearance)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle(subscription.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let cancelToast {
                AgentToastView(toast: cancelToast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Cancellation path unavailable", isPresented: cancelErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelErrorMessage ?? "No direct cancellation path was found in the synced billing emails yet.")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [KBYOPalette.background, KBYOPalette.backgroundTint.opacity(0.65)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.merchant)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)

                    Text(subscription.summary)
                        .font(AppFont.body(16))
                        .foregroundStyle(KBYOPalette.secondary)
                }

                Spacer()

                if let badge = subscription.badge {
                    Text(badge.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: badge.tintHex))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: badge.tintHex).opacity(0.12), in: Capsule())
                }
            }

            Text(subscriptionInsight)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(KBYOPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: metricColumns, spacing: 10) {
                metricTile(title: "Amount", value: subscription.formattedAmount)
                metricTile(title: "Cadence", value: subscription.cadence)
                metricTile(
                    title: "Next date",
                    value: subscription.nextDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
                )
                metricTile(
                    title: "Start date",
                    value: subscription.startDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
                )
            }

            if subscription.status == .increased,
               let current = subscription.currentAmount,
               let previous = subscription.previousAmount,
               current != previous {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KBYOPalette.danger)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("New price \(current.currencyString)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(KBYOPalette.danger)
                        Text("Previously \(previous.currencyString)")
                            .font(AppFont.body(15))
                            .foregroundStyle(KBYOPalette.secondary)
                    }

                    Spacer()
                }
                .padding(16)
                .background(Color(hex: "FFF4F3"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var billingStoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Billing Story")
                        .font(AppFont.headline(22))
                        .foregroundStyle(KBYOPalette.ink)

                    Text("Amounts and source emails in one connected timeline.")
                        .font(AppFont.body(14))
                        .foregroundStyle(KBYOPalette.secondary)
                }

                Spacer()

                Text("\(billingStoryItems.count) items")
                    .font(AppFont.caption(13))
                    .foregroundStyle(KBYOPalette.secondary)
            }

            if billingStoryItems.isEmpty {
                Text("No billing evidence was extracted yet.")
                    .font(AppFont.body(15))
                    .foregroundStyle(KBYOPalette.secondary)
            } else {
                ForEach(Array(billingStoryItems.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .price(let point):
                        billingTimelineRow(
                            isLast: index == billingStoryItems.count - 1,
                            tint: KBYOPalette.accent
                        ) {
                            priceTimelineContent(for: point)
                        }
                    case .email(let email):
                        NavigationLink {
                            EmailEvidenceView(email: email)
                        } label: {
                            billingTimelineRow(
                                isLast: index == billingStoryItems.count - 1,
                                tint: KBYOPalette.secondary
                            ) {
                                evidenceTimelineContent(for: email)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(AppFont.headline(22))
                .foregroundStyle(KBYOPalette.ink)

            NavigationLink {
                DraftComposerView(subscription: subscription, intent: .refund)
                    .environmentObject(appState)
            } label: {
                actionButtonLabel(
                    title: refundActionTitle,
                    subtitle: refundActionSubtitle,
                    prominent: false
                )
            }
            .buttonStyle(.plain)

            Button {
                handleCancelTapped()
            } label: {
                PrimaryCTAButton(
                    title: isCanceled ? "\(subscription.merchant) Canceled" : "Cancel \(subscription.merchant)",
                    tint: isCanceled ? KBYOPalette.success : KBYOPalette.accent
                )
            }
            .buttonStyle(PressableSpringButtonStyle())
            .disabled(isCanceled)
        }
        .padding(20)
        .cardSurface()
    }

    private var billingStoryItems: [BillingStoryItem] {
        let priceItems = subscription.priceHistory.map(BillingStoryItem.price)
        let emailItems = subscription.emails.prefix(3).map(BillingStoryItem.email)

        return (priceItems + emailItems).sorted { lhs, rhs in
            (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    private func billingTimelineRow<Content: View>(
        isLast: Bool,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(KBYOPalette.line)
                    .frame(width: 2, height: isLast ? 0 : 42)
            }
            .padding(.top, 6)

            content()
        }
    }

    private func priceTimelineContent(for point: PricePoint) -> some View {
        let isCurrentIncrease = subscription.status == .increased &&
            subscription.currentAmount == point.amount &&
            subscription.previousAmount != point.amount

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                timelinePill(isCurrentIncrease ? "NEW PRICE" : "AMOUNT", tint: isCurrentIncrease ? KBYOPalette.danger : KBYOPalette.accent)

                Text(point.amount.currencyString)
                    .font(AppFont.headline(22))
                    .foregroundStyle(pricePointTint(for: point))

                Text(point.sourceSubject)
                    .font(AppFont.body(14))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(point.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func evidenceTimelineContent(for email: EvidenceEmail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                timelinePill("EMAIL", tint: KBYOPalette.secondary)

                Text(email.subject)
                    .font(AppFont.headline(22))
                    .foregroundStyle(KBYOPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(email.snippet)
                    .font(AppFont.body(14))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(email.date?.formatted(date: .abbreviated, time: .shortened) ?? "")
                    .font(AppFont.caption(13))
                    .foregroundStyle(KBYOPalette.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KBYOPalette.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subscriptionInsight: String {
        if subscription.status == .increased {
            return "I found billing evidence that \(subscription.merchant) increased from its earlier rate. Review the timeline now and act before the next charge posts."
        }
        if subscription.status == .trial {
            return "I found an active \(subscription.merchant) trial. If you do not want the conversion charge, I can take you straight to the cancellation flow before it ends."
        }
        return "I found a recurring \(subscription.merchant) charge with enough evidence to explain the billing pattern and help you take action."
    }

    private var refundActionTitle: String {
        subscription.status == .increased ? "Request Billing Review" : "Request Refund"
    }

    private var refundActionSubtitle: String {
        subscription.status == .increased
            ? "Draft a polished billing review email using the price change evidence I found"
            : "Draft a polished refund email using the billing evidence I found"
    }

    private var metricColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.caption(12))
                .foregroundStyle(KBYOPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(AppFont.headline(16))
                .foregroundStyle(KBYOPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func timelinePill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var cancelErrorPresented: Binding<Bool> {
        Binding(
            get: { cancelErrorMessage != nil },
            set: { if !$0 { cancelErrorMessage = nil } }
        )
    }

    private func handleCancelTapped() {
        guard let destination = appState.cancellationDestination(for: subscription) ?? demoCancellationDestination else {
            cancelErrorMessage = "No direct cancellation link was found in the synced billing emails for \(subscription.merchant) yet. Try a refresh or deep scan."
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            cancelToast = AgentToast(
                systemImage: "sparkles",
                title: "Assistant Working",
                message: "Working on canceling \(subscription.merchant). I’m following the merchant billing path now.",
                tint: KBYOPalette.accent,
                showsProgress: true
            )
        }

        Task {
            try? await Task.sleep(for: .seconds(2.6))

            if !appState.useDemoData {
                openURL(destination.url)
            }

            if appState.useDemoData {
                await MainActor.run {
                    appState.completeDemoCancellation(for: subscription)
                }
            }

            Haptics.success()
            showToast(
                message: appState.useDemoData
                    ? "\(subscription.merchant) canceled. I used the merchant billing path already linked in your inbox."
                    : "Opened \(subscription.merchant)'s cancellation flow from \"\(destination.sourceSubject)\"."
            )
        }
    }

    private func showToast(message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            cancelToast = AgentToast(
                systemImage: "checkmark.seal.fill",
                title: "Action Completed",
                message: message,
                tint: KBYOPalette.success
            )
        }

        Task {
            try? await Task.sleep(for: .seconds(5.6))
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    cancelToast = nil
                }
            }
        }
    }

    private func pricePointTint(for point: PricePoint) -> Color {
        if subscription.status == .increased,
           let current = subscription.currentAmount,
           point.amount == current {
            return KBYOPalette.danger
        }
        return KBYOPalette.ink
    }

    private var demoCancellationDestination: CancellationDestination? {
        let host = subscription.merchant.replacingOccurrences(of: " ", with: "").lowercased()
        guard let url = URL(string: "https://www.\(host).com/account") else { return nil }
        return CancellationDestination(
            url: url,
            sourceSubject: subscription.latestEvidence?.subject ?? "latest billing email"
        )
    }
}

private enum BillingStoryItem: Identifiable {
    case price(PricePoint)
    case email(EvidenceEmail)

    var id: String {
        switch self {
        case .price(let point):
            return "price-\(point.id)"
        case .email(let email):
            return "email-\(email.id)"
        }
    }

    var date: Date? {
        switch self {
        case .price(let point):
            return point.date
        case .email(let email):
            return email.date
        }
    }
}

struct TrialDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var cancelToast: AgentToast?
    @State private var cancelErrorMessage: String?

    let subscription: SubscriptionRecord

    private var isCanceled: Bool {
        appState.isDemoCanceled(subscription)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                trialHero
                trialEvidenceCard

                Button {
                    handleCancelTapped()
                } label: {
                    PrimaryCTAButton(
                        title: isCanceled ? "\(subscription.merchant) Trial Canceled" : "Cancel \(subscription.merchant)",
                        tint: isCanceled ? KBYOPalette.success : KBYOPalette.accent
                    )
                }
                .buttonStyle(PressableSpringButtonStyle())
                .disabled(isCanceled)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, bottomActionClearance)
        }
        .background(
            LinearGradient(
                colors: [KBYOPalette.background, KBYOPalette.backgroundTint.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(subscription.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let cancelToast {
                AgentToastView(toast: cancelToast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Cancellation path unavailable", isPresented: cancelErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelErrorMessage ?? "No direct cancellation path was found in the synced billing emails yet.")
        }
    }

    private var trialHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.merchant)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)

                    Text("Trial detail")
                        .font(AppFont.headline(18))
                        .foregroundStyle(KBYOPalette.accent)

                    Text(subscription.summary)
                        .font(AppFont.body(16))
                        .foregroundStyle(KBYOPalette.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                trialMetricTile(title: "Countdown", value: subscription.countdownText ?? "Unknown")
                trialMetricTile(title: "Expected charge", value: subscription.formattedAmount)
                trialMetricTile(
                    title: "Trial end",
                    value: subscription.nextDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
                )
                trialMetricTile(title: "Cadence", value: subscription.cadence)
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var trialEvidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
                    Text("Evidence")
                        .font(AppFont.headline(22))
                        .foregroundStyle(KBYOPalette.ink)

                    Text("These messages are why I believe this trial will convert into a paid charge.")
                        .font(AppFont.body(14))
                        .foregroundStyle(KBYOPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(subscription.emails.prefix(3))) { email in
                NavigationLink {
                    EmailEvidenceView(email: email)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(email.subject)
                            .font(AppFont.headline(17))
                            .foregroundStyle(KBYOPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(email.snippet)
                            .font(AppFont.body(14))
                            .foregroundStyle(KBYOPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .cardSurface()
    }

    private func trialMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.caption(12))
                .foregroundStyle(KBYOPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(AppFont.headline(16))
                .foregroundStyle(KBYOPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cancelErrorPresented: Binding<Bool> {
        Binding(
            get: { cancelErrorMessage != nil },
            set: { if !$0 { cancelErrorMessage = nil } }
        )
    }

    private func handleCancelTapped() {
        guard let destination = appState.cancellationDestination(for: subscription) ?? demoCancellationDestination else {
            cancelErrorMessage = "No direct cancellation link was found in the synced billing emails for \(subscription.merchant) yet. Try a refresh or deep scan."
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            cancelToast = AgentToast(
                systemImage: "sparkles",
                title: "Assistant Working",
                message: "Working on canceling \(subscription.merchant). I’m stopping the trial before the first charge.",
                tint: KBYOPalette.accent,
                showsProgress: true
            )
        }

        Task {
            try? await Task.sleep(for: .seconds(2.6))

            if !appState.useDemoData {
                openURL(destination.url)
            }

            if appState.useDemoData {
                await MainActor.run {
                    appState.completeDemoCancellation(for: subscription)
                }
            }

            Haptics.success()
            showToast(
                message: appState.useDemoData
                    ? "\(subscription.merchant) trial canceled. I confirmed the first paid charge will not go through."
                    : "Opened \(subscription.merchant)'s trial cancellation flow from \"\(destination.sourceSubject)\"."
            )
        }
    }

    private func showToast(message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            cancelToast = AgentToast(
                systemImage: "checkmark.seal.fill",
                title: "Action Completed",
                message: message,
                tint: KBYOPalette.success
            )
        }

        Task {
            try? await Task.sleep(for: .seconds(5.6))
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    cancelToast = nil
                }
            }
        }
    }

    private var demoCancellationDestination: CancellationDestination? {
        let host = subscription.merchant.replacingOccurrences(of: " ", with: "").lowercased()
        guard let url = URL(string: "https://www.\(host).com/account") else { return nil }
        return CancellationDestination(
            url: url,
            sourceSubject: subscription.latestEvidence?.subject ?? "latest billing email"
        )
    }
}

struct DraftComposerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let subscription: SubscriptionRecord
    let intent: DraftIntent

    @State private var to: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var sendToast: AgentToast?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                editorCard
                sendCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, bottomActionClearance)
        }
        .background(
            LinearGradient(
                colors: [KBYOPalette.background, KBYOPalette.backgroundTint.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(subject.isEmpty ? subscription.merchant : subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: preload)
        .overlay(alignment: .bottom) {
            if let sendToast {
                AgentToastView(toast: sendToast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            composerInfoRow(label: "To", value: to)
            VStack(alignment: .leading, spacing: 6) {
                Text("Subject")
                    .font(AppFont.caption(13))
                    .foregroundStyle(KBYOPalette.secondary)
                TextField("Subject", text: $subject, axis: .vertical)
                    .font(AppFont.body(15))
                    .foregroundStyle(KBYOPalette.ink)
                    .textInputAutocapitalization(.sentences)
                    .padding(14)
                    .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Text(preparationLine)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .cardSurface()
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $bodyText)
                .font(.system(size: 16))
                .frame(minHeight: 300)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(20)
        .cardSurface()
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sendError {
                Text(sendError)
                    .font(AppFont.body(14))
                    .foregroundStyle(KBYOPalette.danger)
            }

            Button {
                Task { await sendDraft() }
            } label: {
                HStack(spacing: 10) {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSending ? "Sending..." : intent.buttonTitle)
                        .font(AppFont.headline(20))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(KBYOPalette.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableSpringButtonStyle())
            .disabled(isSending || to.isEmpty || subject.isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text(appState.useDemoData
                 ? "Your assistant sends this instantly and records the action as completed for the case."
                 : "Your assistant sends this instantly from the connected mailbox.")
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .cardSurface()
    }

    private func composerInfoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
            Text(value.isEmpty ? "Unknown" : value)
                .font(AppFont.body(15))
                .foregroundStyle(KBYOPalette.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var preparationLine: String {
        if let latestEvidence = subscription.latestEvidence,
           let date = latestEvidence.date?.formatted(date: .abbreviated, time: .omitted) {
            return "Prepared from your \(date) billing email so it reads like a send-ready note grounded in the exact evidence I found."
        }

        return "Prepared from the synced billing evidence so it feels ready to send, not like a generic template."
    }

    private func preload() {
        guard to.isEmpty, let draft = appState.draft(for: subscription, intent: intent) else {
            if to.isEmpty {
                sendError = "No valid merchant contact address was found in the synced evidence emails."
            }
            return
        }

        to = draft.to
        subject = draft.subject
        bodyText = draft.body
    }

    private func sendDraft() async {
        guard !isSending else { return }
        sendError = nil
        isSending = true

        let draft = DraftEmail(
            to: to,
            subject: subject,
            body: bodyText,
            intent: intent,
            merchant: subscription.merchant
        )

        do {
            try await appState.send(draft)
            appState.completeDemoEmailSent(for: subscription, intent: intent, recipient: to)
            Haptics.success()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                sendToast = AgentToast(
                    systemImage: "checkmark.seal.fill",
                    title: intent == .refund ? "Billing Review Sent" : "Email Sent",
                    message: "\(intent == .refund ? "Billing review" : "Email") sent to \(to). I logged the action and updated the case summary.",
                    tint: KBYOPalette.success
                )
            }
            Task {
                try? await Task.sleep(for: .seconds(4.6))
                await MainActor.run {
                    dismiss()
                }
            }
        } catch {
            sendError = error.localizedDescription
        }

        isSending = false
    }
}

struct EmailEvidenceView: View {
    let email: EvidenceEmail

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                heroHeader
                metaCard
                previewCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, bottomActionClearance)
        }
        .background(
            LinearGradient(
                colors: [KBYOPalette.background, KBYOPalette.backgroundTint.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Source Email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(email.subject)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Text(email.snippet)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(KBYOPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .cardSurface()
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message")
                .font(AppFont.headline(20))
                .foregroundStyle(KBYOPalette.ink)

            metaRow(label: "From", value: email.senderDisplay)
            metaRow(label: "Reply-to", value: email.replyToEmail ?? email.senderEmail ?? "Unknown")
            metaRow(label: "Date", value: email.date?.formatted(date: .complete, time: .shortened) ?? "Unknown date")
        }
        .padding(20)
        .cardSurface()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(AppFont.headline(20))
                .foregroundStyle(KBYOPalette.ink)

            Text(email.bodyPreview)
                .font(AppFont.body(17))
                .foregroundStyle(KBYOPalette.ink)
        }
        .padding(20)
        .cardSurface()
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
            Text(value)
                .font(AppFont.body(15))
                .foregroundStyle(KBYOPalette.ink)
        }
    }
}

private let bottomActionClearance: CGFloat = 166

struct AgentToast: Equatable {
    let systemImage: String
    let title: String
    let message: String
    let tint: Color
    var showsProgress: Bool = false
}

struct AgentToastView: View {
    let toast: AgentToast
    @State private var animateProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 50, height: 50)
                    Image(systemName: toast.systemImage)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(iconForeground)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(toast.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)
                    Text(toast.message)
                        .font(AppFont.body(16))
                        .foregroundStyle(KBYOPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if toast.showsProgress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(hex: "E8EBF2"))
                            .frame(height: 10)

                        Capsule()
                            .fill(toast.tint)
                            .frame(width: max(64, proxy.size.width * (animateProgress ? 0.96 : 0.28)), height: 10)
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard toast.showsProgress else { return }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                animateProgress = true
            }
        }
    }

    private var iconBackground: Color {
        toast.showsProgress ? toast.tint.opacity(0.16) : toast.tint
    }

    private var iconForeground: Color {
        toast.showsProgress ? toast.tint : .white
    }

    private var borderColor: Color {
        toast.showsProgress ? toast.tint.opacity(0.22) : toast.tint.opacity(0.16)
    }
}

struct ServiceRequestView: View {
    var body: some View {
        EmptyView()
    }
}

private struct PrimaryCTAButton: View {
    let title: String
    var tint: Color = KBYOPalette.accent

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(title)
                .font(AppFont.headline(19))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private extension SubscriptionDetailView {
    func actionButtonLabel(title: String, subtitle: String, prominent: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.headline(18))
                    .foregroundStyle(prominent ? .white : KBYOPalette.ink)
                Text(subtitle)
                    .font(AppFont.body(14))
                    .foregroundStyle(prominent ? .white.opacity(0.84) : KBYOPalette.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(prominent ? .white : KBYOPalette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            prominent ? AnyShapeStyle(KBYOPalette.accent) : AnyShapeStyle(Color(hex: "F8F9FC")),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}
