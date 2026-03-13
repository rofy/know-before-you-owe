import Foundation

@MainActor
final class AppState: ObservableObject {
    enum AppTab: Hashable {
        case inbox
        case subscriptions
        case settings
    }

    @Published var credentials = EmailCredentials(provider: .yahoo, email: "", password: "", host: "", port: 993)
    @Published var messages: [EmailMessage] = []
    @Published var subscriptions: [SubscriptionRecord] = []
    @Published var digest: FinancialDigest = .empty
    @Published var highlights: [String] = []
    @Published var loadingState: LoadingState = .idle
    @Published var isLoggedIn = false
    @Published var useDemoData = false
    @Published var lastSyncDate: Date?
    @Published var selectedTab: AppTab = .inbox
    @Published var backgroundSyncMessage: String?
    @Published var scanMode: ScanMode = .deep
    @Published var requestedSubscriptionID: String?
    @Published var yahooOAuthConfiguration = YahooOAuthConfiguration()
    @Published var yahooOAuthSession: YahooOAuthSession?
    @Published var googleOAuthConfiguration = GoogleOAuthConfiguration()
    @Published var googleOAuthSession: GoogleOAuthSession?
    @Published private(set) var demoCanceledSubscriptionIDs: Set<String> = []
    @Published private(set) var demoCanceledTrialCount = 0
    @Published private(set) var demoCanceledSubscriptionCount = 0
    @Published private(set) var demoSentEmailCount = 0
    @Published private(set) var demoActionHighlights: [String] = []
    @Published private(set) var demoAwaitingFeedbackSubscriptionIDs: Set<String> = []

    let productName = "Know Before You Owe"
    let initialInboxLookbackDays = 31
    let initialMessageLimit = 500
    let deepScanLookbackDays = 365
    let deepScanMessageLimit = 10_000

    private let imapClient = IMAPClient()
    private let smtpClient = SMTPClient()
    private let yahooOAuthClient = YahooOAuthClient()
    private let googleOAuthClient = GoogleOAuthClient()
    private let defaults = UserDefaults.standard
    private var deepScanTask: Task<Void, Never>?

    init() {
        loadPersistedState()
    }

    var primaryUnreadCount: Int {
        messages.filter { inboxBucket(for: $0) == .primary && $0.isUnread }.count
    }

    var isYahooOAuthConfigured: Bool {
        yahooOAuthConfiguration.isConfigured
    }

    var hasYahooOAuthSession: Bool {
        yahooOAuthSession != nil
    }

    var isGoogleOAuthConfigured: Bool {
        googleOAuthConfiguration.isConfigured
    }

    var hasGoogleOAuthSession: Bool {
        googleOAuthSession != nil
    }

    var availableBiometricType: BiometricType {
        BiometricAuth.availableType()
    }

    var canUseSavedPasswordForCurrentEmail: Bool {
        let email = credentials.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, availableBiometricType != .none else { return false }
        return KeychainStore.read(account: keychainAccountForCurrentEmail()) != nil
    }

    var assistantOverview: String {
        if subscriptions.isEmpty {
            return "Your assistant is ready to surface renewals, trial endings, price changes, and suspicious billing signals."
        }

        let recurring = digest.recurringCount
        let trials = digest.trialCount
        let increases = digest.increaseCount

        let base = "I found \(recurring) recurring charge\(recurring == 1 ? "" : "s"), \(trials) trial\(trials == 1 ? "" : "s"), and \(increases) price increase\(increases == 1 ? "" : "s")."
        if let actionSummary {
            return "\(base) \(actionSummary)"
        }
        return base
    }

    var topRecommendation: String {
        if let trial = recommendedSubscription, trial.status == .trial {
            let countdown = trial.countdownText ?? "an upcoming charge"
            return "Act now: \(trial.merchant) is still in trial and can be canceled before \(countdown.lowercased())."
        }

        if let increase = recommendedSubscription, increase.status == .increased {
            if demoAwaitingFeedbackSubscriptionIDs.contains(increase.id) {
                return "Awaiting feedback: I already emailed \(increase.merchant) about the pricing change and I’m tracking the case."
            }
            return "Review next: \(increase.merchant) appears to have raised its price, and the billing evidence is ready to review."
        }

        if let upcoming = recommendedSubscription, upcoming.badge == .upcoming {
            let dueDate = upcoming.nextDate?.formatted(date: .abbreviated, time: .omitted) ?? "soon"
            return "Coming up: \(upcoming.merchant) looks set to renew on \(dueDate)."
        }

        return highlights.first ?? "Your billing activity is organized and ready for review."
    }

    var recommendedSubscription: SubscriptionRecord? {
        if let trial = subscriptions
            .filter({ $0.status == .trial })
            .sorted(by: subscriptionPrioritySort)
            .first {
            return trial
        }
        if let increase = subscriptions
            .filter({ $0.status == .increased && !demoAwaitingFeedbackSubscriptionIDs.contains($0.id) })
            .sorted(by: subscriptionPrioritySort)
            .first {
            return increase
        }
        if let awaitingFeedback = subscriptions
            .filter({ demoAwaitingFeedbackSubscriptionIDs.contains($0.id) })
            .sorted(by: subscriptionPrioritySort)
            .first {
            return awaitingFeedback
        }
        if let upcoming = subscriptions
            .filter({ $0.badge == .upcoming })
            .sorted(by: subscriptionPrioritySort)
            .first {
            return upcoming
        }
        return subscriptions.sorted(by: subscriptionPrioritySort).first
    }

    var actionSummary: String? {
        var fragments: [String] = []
        if demoCanceledTrialCount > 0 {
            fragments.append("I already canceled \(demoCanceledTrialCount) trial\(demoCanceledTrialCount == 1 ? "" : "s").")
        }
        if demoCanceledSubscriptionCount > 0 {
            fragments.append("I already canceled \(demoCanceledSubscriptionCount) subscription\(demoCanceledSubscriptionCount == 1 ? "" : "s").")
        }
        if demoSentEmailCount > 0 {
            fragments.append("I already sent \(demoSentEmailCount) billing email\(demoSentEmailCount == 1 ? "" : "s").")
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: " ")
    }

    var totalAssistantActions: Int {
        demoCanceledTrialCount + demoCanceledSubscriptionCount + demoSentEmailCount
    }

    var celebrationTitle: String {
        if totalAssistantActions == 0 {
            return "Your assistant is ready"
        }
        return "Nice work. I already handled \(totalAssistantActions) action\(totalAssistantActions == 1 ? "" : "s")."
    }

    var celebrationBody: String {
        let fragments = [
            demoCanceledTrialCount > 0 ? "\(demoCanceledTrialCount) trial canceled" + (demoCanceledTrialCount == 1 ? "" : "s") : nil,
            demoCanceledSubscriptionCount > 0 ? "\(demoCanceledSubscriptionCount) subscription canceled" + (demoCanceledSubscriptionCount == 1 ? "" : "s") : nil,
            demoSentEmailCount > 0 ? "\(demoSentEmailCount) billing review email sent" + (demoSentEmailCount == 1 ? "" : "s") : nil
        ].compactMap { $0 }

        if fragments.isEmpty {
            return "Renewals, price increases, and trial endings are organized so you can act quickly."
        }

        return fragments.joined(separator: " • ")
    }

    var recommendationActionTitle: String {
        guard let subscription = recommendedSubscription else {
            return "Open Subscription Hub"
        }

        switch subscription.status {
        case .trial:
            return "Cancel \(subscription.merchant) before it bills"
        case .increased:
            if demoAwaitingFeedbackSubscriptionIDs.contains(subscription.id) {
                return "Open \(subscription.merchant) case"
            }
            return "Review \(subscription.merchant) price increase"
        case .active:
            return "Open \(subscription.merchant)"
        }
    }

    func setProvider(_ provider: EmailProvider) {
        useDemoData = false
        credentials.provider = provider
        if credentials.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider != .custom {
            credentials.host = provider.defaultHost
            credentials.port = provider.defaultPort
        }
        prefillEmail(for: provider)
    }

    func setScanMode(_ mode: ScanMode) {
        scanMode = mode
        persistState()
    }

    func hydrateSavedPasswordIfPossible() {
        guard !credentials.email.isEmpty else { return }
        if let saved = KeychainStore.read(account: keychainAccountForCurrentEmail()) {
            credentials.password = saved
        }
    }

    func signInAndSync() async {
        let trimmedEmail = credentials.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty || activeAccessToken != nil else {
            loadingState = .failed("Enter your email address to continue.")
            return
        }

        if activeAccessToken == nil && credentials.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadingState = .failed(passwordRequiredMessage(for: credentials.provider))
            return
        }

        if credentials.provider == .yahoo, activeAccessToken != nil, trimmedEmail.isEmpty {
            loadingState = .failed("Yahoo sign-in completed, but the account email could not be determined. Enter the Yahoo email address manually and try again.")
            return
        }

        loadingState = .loading("Connecting to \(credentials.resolvedHost)…")
        useDemoData = false

        do {
            let accessToken = try await preparedAccessTokenIfNeeded()
            if let accessToken {
                credentials.oauthAccessToken = accessToken
            } else {
                credentials.oauthAccessToken = ""
            }

            deepScanTask?.cancel()
            backgroundSyncMessage = nil

            let inbox = try await imapClient.fetchInbox(
                credentials: credentials,
                accessToken: accessToken,
                maxCount: initialMessageLimit,
                since: Calendar.current.date(byAdding: .day, value: -initialInboxLookbackDays, to: Date())
            )
            messages = inbox
            analyzeMessages()
            try? KeychainStore.save(credentials.password, account: keychainAccountForCurrentEmail())
            isLoggedIn = true
            lastSyncDate = Date()
            loadingState = .loaded
            persistState()

            if scanMode == .deep {
                let credentialsSnapshot = credentials
                backgroundSyncMessage = "Expanding scan to find older subscriptions..."
                deepScanTask = Task {
                    await self.runDeepScan(credentials: credentialsSnapshot, accessToken: accessToken)
                }
            }
        } catch {
            loadingState = .failed(friendlyErrorMessage(for: error, provider: credentials.provider))
            isLoggedIn = false
        }
    }

    func refreshInbox() async {
        guard isLoggedIn else { return }
        if useDemoData {
            applyDemoData()
            return
        }
        await signInAndSync()
    }

    func useOfflineDemo() {
        deepScanTask?.cancel()
        useDemoData = true
        backgroundSyncMessage = nil
        credentials.email = "rofaida@knowbeforeyouowe.ai"
        credentials.password = ""
        credentials.oauthAccessToken = ""
        resetDemoActions()
        applyDemoData()
        isLoggedIn = true
        loadingState = .loaded
        selectedTab = .inbox
        persistState()
    }

    func signInWithYahooOAuth() async {
        guard isYahooOAuthConfigured else {
            loadingState = .failed("Add a Yahoo OAuth client ID and secret in Settings before using Yahoo web sign-in.")
            return
        }

        loadingState = .loading("Opening Yahoo sign-in…")

        do {
            let session = try await yahooOAuthClient.authorize(using: yahooOAuthConfiguration)
            yahooOAuthSession = session
            credentials.provider = .yahoo
            credentials.email = session.email ?? credentials.email
            credentials.host = EmailProvider.yahoo.defaultHost
            credentials.port = EmailProvider.yahoo.defaultPort
            credentials.oauthAccessToken = session.accessToken
            loadingState = .loaded
            persistState()
        } catch {
            loadingState = .failed(error.localizedDescription)
        }
    }

    func signInWithGoogleOAuth() async {
        guard isGoogleOAuthConfigured else {
            loadingState = .failed("Add a Google OAuth client ID in Settings before using Google web sign-in.")
            return
        }

        loadingState = .loading("Opening Google sign-in…")

        do {
            let session = try await googleOAuthClient.authorize(using: googleOAuthConfiguration)
            googleOAuthSession = session
            credentials.provider = .gmail
            credentials.email = session.email ?? credentials.email
            credentials.host = EmailProvider.gmail.defaultHost
            credentials.port = EmailProvider.gmail.defaultPort
            credentials.oauthAccessToken = session.accessToken
            loadingState = .loaded
            persistState()
        } catch {
            loadingState = .failed(error.localizedDescription)
        }
    }

    func clearYahooOAuthSession() {
        yahooOAuthSession = nil
        credentials.oauthAccessToken = ""
        try? KeychainStore.delete(account: yahooOAuthSessionAccount)
        persistState()
    }

    func clearGoogleOAuthSession() {
        googleOAuthSession = nil
        credentials.oauthAccessToken = ""
        try? KeychainStore.delete(account: googleOAuthSessionAccount)
        persistState()
    }

    func saveYahooOAuthConfiguration(clientID: String, clientSecret: String) {
        yahooOAuthConfiguration.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        yahooOAuthConfiguration.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        persistState()
    }

    func saveGoogleOAuthConfiguration(clientID: String) {
        googleOAuthConfiguration.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        persistState()
    }

    func signOut() {
        deepScanTask?.cancel()
        isLoggedIn = false
        useDemoData = false
        messages = []
        subscriptions = []
        digest = .empty
        highlights = []
        loadingState = .idle
        selectedTab = .inbox
        backgroundSyncMessage = nil
        persistState()
    }

    func draft(for subscription: SubscriptionRecord, intent: DraftIntent) -> DraftEmail? {
        guard let recipient = subscription.contactEmail ?? subscription.latestEvidence?.replyToEmail ?? subscription.latestEvidence?.senderEmail else {
            return nil
        }

        let subject: String
        let body: String

        switch intent {
        case .refund:
            subject = refundSubject(for: subscription)
            body = refundBody(for: subscription)
        case .cancel:
            subject = cancellationSubject(for: subscription)
            body = cancellationBody(for: subscription)
        }

        return DraftEmail(
            to: recipient,
            subject: subject,
            body: body,
            intent: intent,
            merchant: subscription.merchant
        )
    }

    func send(_ draft: DraftEmail) async throws {
        if useDemoData {
            try await Task.sleep(for: .milliseconds(700))
            return
        }
        let accessToken = try await preparedAccessTokenIfNeeded()
        try await smtpClient.send(draft: draft, credentials: credentials, accessToken: accessToken)
    }

    func cancellationDestination(for subscription: SubscriptionRecord) -> CancellationDestination? {
        let emails = subscription.emails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        let directKeywords = ["cancel", "manage", "subscription", "billing", "account", "plan", "unsubscribe"]
        var bestCandidate: (url: URL, score: Int, subject: String)?

        for email in emails {
            for url in extractURLs(from: email.searchableText) {
                let absolute = url.absoluteString.lowercased()
                let score = directKeywords.reduce(into: 0) { partialResult, keyword in
                    if absolute.contains(keyword) {
                        partialResult += 2
                    }
                    if email.subject.lowercased().contains(keyword) || email.snippet.lowercased().contains(keyword) {
                        partialResult += 1
                    }
                }

                guard score > 0 else { continue }

                if bestCandidate == nil || score > (bestCandidate?.score ?? 0) {
                    bestCandidate = (url, score, email.subject)
                }
            }
        }

        if let bestCandidate {
            return CancellationDestination(url: bestCandidate.url, sourceSubject: bestCandidate.subject)
        }

        return fallbackCancellationDestination(for: subscription)
    }

    func inboxBucket(for message: EmailMessage) -> InboxBucket {
        let text = "\(message.subject) \(message.snippet) \(message.bodyPreview)".lowercased()
        let offerTerms = ["sale", "deal", "discount", "promo", "coupon", "limited time", "offer", "% off"]

        if offerTerms.contains(where: text.contains) {
            return .offers
        }

        if message.isUnread || relatedSubscription(for: message) != nil {
            return .primary
        }

        return .other
    }

    func filteredMessages(for bucket: InboxBucket) -> [EmailMessage] {
        switch bucket {
        case .all:
            return messages
        case .primary, .offers, .other:
            return messages.filter { inboxBucket(for: $0) == bucket }
        }
    }

    func count(for bucket: InboxBucket) -> Int {
        switch bucket {
        case .all:
            return messages.count
        case .primary, .offers, .other:
            return filteredMessages(for: bucket).count
        }
    }

    func relatedSubscription(for message: EmailMessage) -> SubscriptionRecord? {
        subscriptions.first(where: { subscription in
            subscription.emails.contains(where: { $0.uid == message.uid })
        })
    }

    func isDemoCanceled(_ subscription: SubscriptionRecord) -> Bool {
        demoCanceledSubscriptionIDs.contains(subscription.id)
    }

    func requestSubscriptionDetail(for subscription: SubscriptionRecord) {
        requestedSubscriptionID = subscription.id
        selectedTab = .subscriptions
    }

    func consumeRequestedSubscription() {
        requestedSubscriptionID = nil
    }

    func completeDemoCancellation(for subscription: SubscriptionRecord) {
        guard useDemoData else { return }
        guard demoCanceledSubscriptionIDs.insert(subscription.id).inserted else { return }
        demoAwaitingFeedbackSubscriptionIDs.remove(subscription.id)

        if subscription.status == .trial {
            demoCanceledTrialCount += 1
            noteDemoAction("I canceled the \(subscription.merchant) trial before the first paid charge.")
        } else {
            demoCanceledSubscriptionCount += 1
            noteDemoAction("I canceled the \(subscription.merchant) subscription from the billing path already on file.")
        }

        analyzeMessages()
    }

    func completeDemoEmailSent(for subscription: SubscriptionRecord, intent: DraftIntent, recipient: String) {
        guard useDemoData else { return }
        demoSentEmailCount += 1
        demoAwaitingFeedbackSubscriptionIDs.insert(subscription.id)

        switch intent {
        case .refund:
            noteDemoAction("I sent \(subscription.merchant) a billing review email at \(recipient) and I’m now waiting for a reply.")
        case .cancel:
            noteDemoAction("I sent a cancellation email to \(recipient) for \(subscription.merchant) and I’m waiting for confirmation.")
        }

        analyzeMessages()
    }

    func signInWithSavedPassword() async {
        let email = credentials.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            loadingState = .failed("Enter your email address first, then use \(availableBiometricType.title).")
            return
        }

        do {
            if let saved = try await KeychainStore.readAfterBiometricUnlock(
                account: keychainAccountForCurrentEmail(),
                reason: "Use \(availableBiometricType.title) to unlock your saved mailbox password."
            ) {
                credentials.password = saved
                await signInAndSync()
            } else {
                loadingState = .failed("No saved password was found for this email address.")
            }
        } catch {
            loadingState = .failed(error.localizedDescription)
        }
    }

    private var senderSignature: String {
        credentials.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Sent from Know Before You Owe"
            : credentials.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var senderDisplayName: String {
        let trimmed = credentials.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let localPart = trimmed.split(separator: "@").first else {
            return senderSignature
        }

        let pieces = localPart
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map { piece in
                piece.prefix(1).uppercased() + String(piece.dropFirst()).lowercased()
            }
            .filter { !$0.isEmpty }

        return pieces.isEmpty ? senderSignature : pieces.joined(separator: " ")
    }

    private func supportGreeting(for subscription: SubscriptionRecord) -> String {
        "Hello \(subscription.merchant) support team,"
    }

    private func refundSubject(for subscription: SubscriptionRecord) -> String {
        switch subscription.status {
        case .trial:
            return "Please review my recent \(subscription.merchant) trial charge"
        case .increased:
            return "Please review my recent \(subscription.merchant) price increase"
        case .active:
            return "Please review my recent \(subscription.merchant) subscription charge"
        }
    }

    private func cancellationSubject(for subscription: SubscriptionRecord) -> String {
        switch subscription.status {
        case .trial:
            return "Please cancel my \(subscription.merchant) trial before the first charge"
        case .increased, .active:
            return "Please cancel my \(subscription.merchant) subscription"
        }
    }

    private func refundBody(for subscription: SubscriptionRecord) -> String {
        let opening: String
        switch subscription.status {
        case .trial:
            opening = "I’m reaching out because it looks like my \(subscription.merchant) trial is converting into a paid plan, and I did not intend to keep it."
        case .increased:
            opening = "I noticed that my \(subscription.merchant) plan moved to a higher price, and I’d like help reviewing that increase before it becomes my new normal."
        case .active:
            opening = "I’m writing to ask for a review of the most recent \(subscription.merchant) charge on my account."
        }

        let ask: String
        switch subscription.status {
        case .trial:
            ask = "If the paid conversion has already gone through, I’d appreciate a refund to my original payment method. If it has not gone through yet, please stop it and confirm that I will not be billed."
        case .increased:
            ask = "Please let me know whether this higher-priced charge can be reversed, credited, or adjusted back to my prior rate. If there is a way to keep the earlier plan price, I would prefer that."
        case .active:
            ask = "Please let me know whether that charge can be refunded or credited back to my original payment method. If you need anything else from me to verify the account, I’m happy to provide it."
        }

        return """
        \(supportGreeting(for: subscription))

        \(opening)

        \(refundContext(for: subscription))

        \(ask)

        I’d appreciate a written confirmation once this has been reviewed.

        Thank you,
        \(senderDisplayName)
        """
    }

    private func cancellationBody(for subscription: SubscriptionRecord) -> String {
        let opening: String
        switch subscription.status {
        case .trial:
            opening = "I’d like to cancel my \(subscription.merchant) trial before it converts into a paid subscription."
        case .increased, .active:
            opening = "I’d like to cancel my \(subscription.merchant) subscription before the next renewal."
        }

        let ask: String
        switch subscription.status {
        case .trial:
            ask = "Please confirm that the trial has been canceled and that no paid conversion charge will be made."
        case .increased, .active:
            ask = "Please send me a quick confirmation once the cancellation is complete. If you need anything else from me to make sure no further charges are made, I’m happy to respond right away."
        }

        return """
        \(supportGreeting(for: subscription))

        \(opening)

        \(cancellationContext(for: subscription))

        \(ask)

        Thank you,
        \(senderDisplayName)
        """
    }

    private func billingContext(for subscription: SubscriptionRecord) -> String {
        var fragments: [String] = []

        if let amount = subscription.amount {
            fragments.append("The current amount I see in my billing emails is \(amount.currencyString).")
        }

        if let nextDate = subscription.nextDate {
            fragments.append("The next billing event appears to be \(nextDate.formatted(date: .long, time: .omitted)).")
        }

        if subscription.cadence.lowercased() != "unknown" {
            fragments.append("The plan appears to renew \(subscription.cadence.lowercased()).")
        }

        if subscription.status == .increased, subscription.priceHistory.count >= 2 {
            let sorted = subscription.priceHistory.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            if let first = sorted.first, let last = sorted.last, first.amount != last.amount {
                fragments.append("The price appears to have moved from \(first.amount.currencyString) to \(last.amount.currencyString).")
            }
        }

        return fragments.joined(separator: " ")
    }

    private func evidenceContext(for subscription: SubscriptionRecord) -> String {
        guard let latestEvidence = subscription.latestEvidence else {
            return "I’m basing this request on the recurring billing emails associated with my account."
        }

        let evidenceDate = latestEvidence.date?.formatted(date: .long, time: .omitted) ?? "a recent date"
        return "The most relevant email I have is \"\(latestEvidence.subject)\" from \(evidenceDate), which appears to be the latest billing-related notice from your team."
    }

    private func cancellationContext(for subscription: SubscriptionRecord) -> String {
        var fragments: [String] = []

        if let nextDate = subscription.nextDate, let amount = subscription.amount {
            fragments.append("Your latest billing email suggests the subscription is set to renew on \(nextDate.formatted(date: .long, time: .omitted)) for \(amount.currencyString).")
        } else if let nextDate = subscription.nextDate {
            fragments.append("Your latest billing email suggests the subscription is set to renew on \(nextDate.formatted(date: .long, time: .omitted)).")
        } else if let amount = subscription.amount {
            fragments.append("The current billed amount appears to be \(amount.currencyString).")
        }

        if let latestEvidence = subscription.latestEvidence {
            let date = latestEvidence.date?.formatted(date: .abbreviated, time: .omitted) ?? "recently"
            fragments.append("I’m basing this request on the billing email I received on \(date) with the subject \"\(latestEvidence.subject)\".")
        }

        return fragments.joined(separator: " ")
    }

    private func refundContext(for subscription: SubscriptionRecord) -> String {
        var fragments: [String] = []

        if let latestEvidence = subscription.latestEvidence {
            let date = latestEvidence.date?.formatted(date: .long, time: .omitted) ?? "a recent date"
            fragments.append("I’m basing this request on the billing email I received on \(date) with the subject \"\(latestEvidence.subject)\".")
        }

        if let amount = subscription.currentAmount, let nextDate = subscription.nextDate {
            fragments.append("The latest billing notice points to a \(amount.currencyString) charge tied to \(nextDate.formatted(date: .long, time: .omitted)).")
        } else if let amount = subscription.amount {
            fragments.append("The amount shown in the billing notice is \(amount.currencyString).")
        }

        if subscription.status == .increased, subscription.priceHistory.count >= 2 {
            let sorted = subscription.priceHistory.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            if let first = sorted.first, let last = sorted.last, first.amount != last.amount {
                fragments.append("From the billing emails in my inbox, it looks like the price moved from \(first.amount.currencyString) to \(last.amount.currencyString), which is the specific increase I’m asking you to review.")
            }
        }

        return fragments.joined(separator: " ")
    }

    private func applyDemoData() {
        messages = .mockMessages.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        analyzeMessages()
        lastSyncDate = Date()
    }

    private func analyzeMessages() {
        let output = EmailAnalyzer.build(from: messages)
        let visibleSubscriptions = output.subscriptions.filter { !demoCanceledSubscriptionIDs.contains($0.id) }
        subscriptions = visibleSubscriptions
        digest = FinancialDigest(
            recurringCount: visibleSubscriptions.count,
            trialCount: visibleSubscriptions.filter { $0.status == .trial }.count,
            increaseCount: visibleSubscriptions.filter { $0.status == .increased }.count
        )
        highlights = Array((demoActionHighlights + output.highlights).prefix(3))
    }

    private func resetDemoActions() {
        demoCanceledSubscriptionIDs = []
        demoCanceledTrialCount = 0
        demoCanceledSubscriptionCount = 0
        demoSentEmailCount = 0
        demoAwaitingFeedbackSubscriptionIDs = []
        demoActionHighlights = []
        requestedSubscriptionID = nil
    }

    private func noteDemoAction(_ message: String) {
        demoActionHighlights.removeAll(where: { $0 == message })
        demoActionHighlights.insert(message, at: 0)
        demoActionHighlights = Array(demoActionHighlights.prefix(3))
        lastSyncDate = Date()
    }

    private func subscriptionPrioritySort(lhs: SubscriptionRecord, rhs: SubscriptionRecord) -> Bool {
        subscriptionPriorityScore(lhs) > subscriptionPriorityScore(rhs)
    }

    private func subscriptionPriorityScore(_ subscription: SubscriptionRecord) -> Double {
        var score: Double

        switch subscription.status {
        case .trial:
            score = 10_000
        case .increased:
            score = 6_000 + max(subscription.priceIncreaseDelta, 0) * 100
            if demoAwaitingFeedbackSubscriptionIDs.contains(subscription.id) {
                score -= 2_500
            }
        case .active:
            score = subscription.badge == .upcoming ? 3_000 : 1_000
        }

        if let nextDate = subscription.nextDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 30
            score += Double(max(30 - days, 0))
        }

        return score
    }

    private func persistState() {
        if let encodedCreds = try? JSONEncoder().encode(PersistedCredentials(from: credentials)) {
            defaults.set(encodedCreds, forKey: DefaultsKeys.credentials)
        }
        defaults.set(useDemoData, forKey: DefaultsKeys.useDemoData)
        defaults.set(lastSyncDate, forKey: DefaultsKeys.lastSyncDate)
        defaults.set(scanMode.rawValue, forKey: DefaultsKeys.scanMode)
        defaults.set(yahooOAuthConfiguration.clientID, forKey: DefaultsKeys.yahooOAuthClientID)
        defaults.set(yahooOAuthConfiguration.redirectURI, forKey: DefaultsKeys.yahooOAuthRedirectURI)
        defaults.set(googleOAuthConfiguration.clientID, forKey: DefaultsKeys.googleOAuthClientID)
        defaults.set(googleOAuthConfiguration.redirectURI, forKey: DefaultsKeys.googleOAuthRedirectURI)
        try? KeychainStore.save(yahooOAuthConfiguration.clientSecret, account: yahooOAuthSecretAccount)
        if let yahooOAuthSession,
           let data = try? JSONEncoder().encode(yahooOAuthSession),
           let value = String(data: data, encoding: .utf8) {
            try? KeychainStore.save(value, account: yahooOAuthSessionAccount)
        } else {
            try? KeychainStore.delete(account: yahooOAuthSessionAccount)
        }
        if let googleOAuthSession,
           let data = try? JSONEncoder().encode(googleOAuthSession),
           let value = String(data: data, encoding: .utf8) {
            try? KeychainStore.save(value, account: googleOAuthSessionAccount)
        } else {
            try? KeychainStore.delete(account: googleOAuthSessionAccount)
        }
    }

    private func loadPersistedState() {
        if let credsData = defaults.data(forKey: DefaultsKeys.credentials),
           let saved = try? JSONDecoder().decode(PersistedCredentials.self, from: credsData) {
            credentials.provider = saved.provider
            credentials.email = saved.email
            credentials.host = saved.host
            credentials.port = saved.port
            hydrateSavedPasswordIfPossible()
        } else {
            credentials.host = credentials.provider.defaultHost
        }

        useDemoData = defaults.bool(forKey: DefaultsKeys.useDemoData)
        lastSyncDate = defaults.object(forKey: DefaultsKeys.lastSyncDate) as? Date
        scanMode = ScanMode(rawValue: defaults.string(forKey: DefaultsKeys.scanMode) ?? "") ?? .deep

        let bundleClientID = Bundle.main.object(forInfoDictionaryKey: "YahooOAuthClientID") as? String ?? ""
        let bundleClientSecret = Bundle.main.object(forInfoDictionaryKey: "YahooOAuthClientSecret") as? String ?? ""
        let bundleRedirectURI = Bundle.main.object(forInfoDictionaryKey: "YahooOAuthRedirectURI") as? String ?? "knowbeforeyouowe://oauth/yahoo"
        let bundleGoogleClientID = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? ""
        let bundleGoogleRedirectURI = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthRedirectURI") as? String ?? "knowbeforeyouowe://oauth/google"

        yahooOAuthConfiguration.clientID = defaults.string(forKey: DefaultsKeys.yahooOAuthClientID) ?? bundleClientID
        yahooOAuthConfiguration.redirectURI = defaults.string(forKey: DefaultsKeys.yahooOAuthRedirectURI) ?? bundleRedirectURI
        yahooOAuthConfiguration.clientSecret = KeychainStore.read(account: yahooOAuthSecretAccount) ?? bundleClientSecret
        googleOAuthConfiguration.clientID = defaults.string(forKey: DefaultsKeys.googleOAuthClientID) ?? bundleGoogleClientID
        googleOAuthConfiguration.redirectURI = defaults.string(forKey: DefaultsKeys.googleOAuthRedirectURI) ?? bundleGoogleRedirectURI

        if let storedSession = KeychainStore.read(account: yahooOAuthSessionAccount),
           let data = storedSession.data(using: .utf8),
           let savedSession = try? JSONDecoder().decode(YahooOAuthSession.self, from: data) {
            yahooOAuthSession = savedSession
            credentials.oauthAccessToken = savedSession.accessToken
            if credentials.provider == .yahoo, credentials.email.isEmpty {
                credentials.email = savedSession.email ?? ""
            }
        }

        if let storedGoogleSession = KeychainStore.read(account: googleOAuthSessionAccount),
           let data = storedGoogleSession.data(using: .utf8),
           let savedSession = try? JSONDecoder().decode(GoogleOAuthSession.self, from: data) {
            googleOAuthSession = savedSession
            if credentials.provider == .gmail {
                credentials.oauthAccessToken = savedSession.accessToken
                if credentials.email.isEmpty {
                    credentials.email = savedSession.email ?? ""
                }
            }
        }
    }

    private func keychainAccountForCurrentEmail() -> String {
        "mail-password-\(credentials.email.lowercased())"
    }

    private var yahooOAuthSecretAccount: String {
        "yahoo-oauth-client-secret"
    }

    private var yahooOAuthSessionAccount: String {
        "yahoo-oauth-session"
    }

    private var googleOAuthSessionAccount: String {
        "google-oauth-session"
    }

    private var activeAccessToken: String? {
        switch credentials.provider {
        case .yahoo:
            return yahooOAuthSession?.accessToken
        case .gmail:
            return googleOAuthSession?.accessToken
        default:
            return nil
        }
    }

    private func preparedAccessTokenIfNeeded() async throws -> String? {
        switch credentials.provider {
        case .yahoo:
            guard let session = yahooOAuthSession else { return nil }
            if !session.shouldRefreshSoon {
                return session.accessToken
            }
            guard isYahooOAuthConfigured else {
                return session.accessToken
            }
            let refreshed = try await yahooOAuthClient.refresh(session: session, using: yahooOAuthConfiguration)
            yahooOAuthSession = refreshed
            credentials.oauthAccessToken = refreshed.accessToken
            persistState()
            return refreshed.accessToken
        case .gmail:
            guard let session = googleOAuthSession else { return nil }
            if !session.shouldRefreshSoon {
                return session.accessToken
            }
            guard isGoogleOAuthConfigured else {
                return session.accessToken
            }
            let refreshed = try await googleOAuthClient.refresh(session: session, using: googleOAuthConfiguration)
            googleOAuthSession = refreshed
            credentials.oauthAccessToken = refreshed.accessToken
            persistState()
            return refreshed.accessToken
        default:
            return nil
        }
    }

    private func prefillEmail(for provider: EmailProvider) {
        guard let domain = provider.defaultEmailDomain else { return }
        let current = credentials.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if current.isEmpty {
            return
        }

        if let atIndex = current.firstIndex(of: "@") {
            let localPart = String(current[..<atIndex])
            credentials.email = "\(localPart)@\(domain)"
        } else {
            credentials.email = "\(current)@\(domain)"
        }
    }

    private func runDeepScan(credentials: EmailCredentials, accessToken: String?) async {
        do {
            let deepInbox = try await imapClient.fetchInboxProgressively(
                credentials: credentials,
                accessToken: accessToken,
                maxCount: deepScanMessageLimit,
                since: Calendar.current.date(byAdding: .day, value: -deepScanLookbackDays, to: Date()),
                onBatch: { [weak self] batch, processed, total in
                    guard let self else { return }
                    await MainActor.run {
                        self.messages = self.mergeMessages(existing: self.messages, incoming: batch)
                        self.analyzeMessages()
                        self.lastSyncDate = Date()
                        self.backgroundSyncMessage = self.deepScanProgressMessage(processed: processed, total: total)
                    }
                }
            )

            guard !Task.isCancelled else { return }

            messages = mergeMessages(existing: messages, incoming: deepInbox)
            analyzeMessages()
            lastSyncDate = Date()
            persistState()

            backgroundSyncMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            backgroundSyncMessage = "Deep scan stopped: \(error.localizedDescription)"
        }
    }

    private func mergeMessages(existing: [EmailMessage], incoming: [EmailMessage]) -> [EmailMessage] {
        var byUID: [String: EmailMessage] = Dictionary(uniqueKeysWithValues: existing.map { ($0.uid, $0) })
        for message in incoming {
            byUID[message.uid] = message
        }

        return byUID.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func deepScanProgressMessage(processed: Int, total: Int) -> String {
        let subscriptionsFound = subscriptions.count
        return "Deep scan \(processed.formatted()) of \(total.formatted()) emails. \(subscriptionsFound.formatted()) subscriptions found so far."
    }

    private func passwordRequiredMessage(for provider: EmailProvider) -> String {
        switch provider {
        case .gmail:
            return isGoogleOAuthConfigured
                ? "Use Sign in with Google, or enter a Google app password if you prefer the IMAP fallback."
                : "Google no longer accepts a normal Gmail password here. Use a Google app password, or add Google OAuth in Settings."
        case .yahoo:
            return "Enter your Yahoo app password, or sign in with Yahoo on the web first."
        default:
            return "Enter your mailbox password to continue."
        }
    }

    private func friendlyErrorMessage(for error: Error, provider: EmailProvider) -> String {
        if provider == .gmail,
           let transportError = error as? MailTransportError {
            switch transportError {
            case .authenticationFailed:
                return "Gmail rejected the sign-in. A normal Gmail password will not work here. Use Sign in with Google, or use a 16-digit Google app password."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func fallbackCancellationDestination(for subscription: SubscriptionRecord) -> CancellationDestination? {
        let knownPaths: [String: String] = [
            "spotify": "https://www.spotify.com/account/subscription/",
            "netflix": "https://www.netflix.com/cancelplan",
            "dropbox": "https://www.dropbox.com/account/plan",
            "hbo max": "https://play.max.com/settings/subscription",
            "max": "https://play.max.com/settings/subscription",
            "apple": "https://apps.apple.com/account/subscriptions"
        ]

        let normalizedMerchant = subscription.merchant.lowercased()
        if let match = knownPaths.first(where: { normalizedMerchant.contains($0.key) }),
           let url = URL(string: match.value) {
            return CancellationDestination(url: url, sourceSubject: "Known cancellation destination for \(subscription.merchant)")
        }

        guard let sender = subscription.latestEvidence?.senderEmail,
              let domain = sender.split(separator: "@").last
        else {
            return nil
        }

        let host = String(domain)
        guard let url = URL(string: "https://\(host)") else {
            return nil
        }
        return CancellationDestination(url: url, sourceSubject: "Latest billing sender for \(subscription.merchant)")
    }

    private func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }
}

private enum DefaultsKeys {
    static let credentials = "knowbeforeyouowe.credentials"
    static let useDemoData = "knowbeforeyouowe.useDemoData"
    static let lastSyncDate = "knowbeforeyouowe.lastSyncDate"
    static let scanMode = "knowbeforeyouowe.scanMode"
    static let yahooOAuthClientID = "knowbeforeyouowe.yahooOAuthClientID"
    static let yahooOAuthRedirectURI = "knowbeforeyouowe.yahooOAuthRedirectURI"
    static let googleOAuthClientID = "knowbeforeyouowe.googleOAuthClientID"
    static let googleOAuthRedirectURI = "knowbeforeyouowe.googleOAuthRedirectURI"
}
