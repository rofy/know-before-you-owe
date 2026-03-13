import Foundation

enum EmailAnalyzer {
    private struct Signal {
        let merchant: String
        let amount: Double?
        let cadence: String?
        let nextDate: Date?
        let isTrial: Bool
        let isPriceIncrease: Bool
        let isRecurring: Bool
        let message: EmailMessage
    }

    private struct Group {
        let merchant: String
        var signals: [Signal]
    }

    private static let recurringTerms = [
        "subscription", "membership", "monthly", "yearly", "annual", "renews", "renewal",
        "auto-renew", "next bill", "next billing", "payment received", "charged", "receipt",
        "recurring", "plan", "premium", "trial", "free trial"
    ]

    private static let trialTerms = [
        "trial", "free trial", "trial ends", "cancel before", "starts billing"
    ]

    private static let increaseTerms = [
        "price increase", "increase from", "new price", "raising", "will increase", "updated price"
    ]

    static func build(from messages: [EmailMessage]) -> AnalyzerOutput {
        guard !messages.isEmpty else {
            return AnalyzerOutput(
                subscriptions: [],
                digest: .empty,
                highlights: ["Watch for renewals, expiring trials, price changes, and billing signals that may need action."]
            )
        }

        var groups: [String: Group] = [:]

        for message in messages {
            guard let signal = extractSignal(from: message) else { continue }
            var group = groups[signal.merchant] ?? Group(merchant: signal.merchant, signals: [])
            group.signals.append(signal)
            groups[signal.merchant] = group
        }

        let subscriptions = groups.values.compactMap(makeSubscription(from:))
            .sorted(by: subscriptionSort)

        let digest = FinancialDigest(
            recurringCount: subscriptions.count,
            trialCount: subscriptions.filter { $0.status == .trial }.count,
            increaseCount: subscriptions.filter { $0.status == .increased }.count
        )

        return AnalyzerOutput(
            subscriptions: subscriptions,
            digest: digest,
            highlights: buildHighlights(subscriptions: subscriptions, messages: messages)
        )
    }

    private static func makeSubscription(from group: Group) -> SubscriptionRecord? {
        let signals = group.signals.sorted { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
        let recurringSignalCount = signals.filter { $0.isRecurring || $0.amount != nil }.count
        let strongSingleSignal = signals.contains { $0.isRecurring && $0.amount != nil && $0.nextDate != nil }

        guard recurringSignalCount >= 2 || strongSingleSignal || signals.contains(where: { $0.isTrial || $0.isPriceIncrease }) else {
            return nil
        }

        let sortedEmails = signals.map {
            EvidenceEmail(
                uid: $0.message.uid,
                senderDisplay: $0.message.senderDisplay,
                senderEmail: $0.message.senderEmail,
                replyToEmail: $0.message.replyToEmail,
                subject: $0.message.subject,
                date: $0.message.date,
                snippet: $0.message.snippet,
                bodyPreview: $0.message.bodyPreview
            )
        }

        let dedupedEmails = deduplicateEmails(sortedEmails)
        let evidenceEmails = Array(dedupedEmails.prefix(3))
        let startDate = signals.compactMap { $0.message.date }.min()
        let cadence = resolveCadence(from: signals)
        let nextDate = resolveNextDate(from: signals, cadence: cadence)
        let amount = resolveAmount(from: signals)
        let status = resolveStatus(from: signals, amount: amount, nextDate: nextDate)
        let badge = resolveBadge(for: status, nextDate: nextDate)
        let priceHistory = buildPriceHistory(from: signals)
        let summary = buildSummary(
            merchant: group.merchant,
            amount: amount,
            cadence: cadence,
            status: status,
            nextDate: nextDate,
            priceHistory: priceHistory
        )
        let contactEmail = signals.compactMap { $0.message.preferredReplyAddress }.first

        return SubscriptionRecord(
            merchant: group.merchant,
            amount: amount,
            cadence: cadence,
            status: status,
            nextDate: nextDate,
            startDate: startDate,
            emails: evidenceEmails,
            priceHistory: priceHistory,
            summary: summary,
            contactEmail: contactEmail,
            badge: badge
        )
    }

    private static func resolveStatus(from signals: [Signal], amount: Double?, nextDate: Date?) -> SubscriptionStatus {
        if signals.contains(where: \.isPriceIncrease) {
            return .increased
        }

        if signals.contains(where: \.isTrial),
           let nextDate,
           nextDate >= Calendar.current.startOfDay(for: Date()) {
            return .trial
        }

        let history = buildPriceHistory(from: signals)
        if history.count >= 2,
           let latest = history.first?.amount, let previous = history.dropFirst().first?.amount, latest > previous {
            return .increased
        }

        if amount == nil && nextDate == nil {
            return .active
        }

        return .active
    }

    private static func resolveBadge(for status: SubscriptionStatus, nextDate: Date?) -> SubscriptionBadge? {
        switch status {
        case .trial:
            return .trial
        case .increased:
            return .increase
        case .active:
            guard let nextDate else { return nil }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 99
            return days <= 10 ? .upcoming : nil
        }
    }

    private static func resolveAmount(from signals: [Signal]) -> Double? {
        let datedSignals = signals.sorted { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
        if let latestIncreaseAmount = datedSignals.first(where: { $0.isPriceIncrease && $0.amount != nil })?.amount {
            return latestIncreaseAmount
        }
        if let explicitLatest = datedSignals.first(where: { $0.amount != nil })?.amount {
            return explicitLatest
        }
        return nil
    }

    private static func resolveCadence(from signals: [Signal]) -> String {
        let values = signals.compactMap(\.cadence)
        if values.contains("Yearly") || values.contains("Annual") {
            if values.filter({ $0 == "Monthly" }).count > values.filter({ $0 == "Yearly" || $0 == "Annual" }).count {
                return "Monthly"
            }
            return "Yearly"
        }
        return values.first ?? "Monthly"
    }

    private static func resolveNextDate(from signals: [Signal], cadence: String) -> Date? {
        let futureExplicit = signals.compactMap(\.nextDate)
            .filter { $0 >= Calendar.current.startOfDay(for: Date()) }
            .sorted()
        if let futureExplicit = futureExplicit.first {
            return futureExplicit
        }

        guard let latestChargeDate = signals.compactMap({ $0.message.date }).sorted(by: >).first else {
            return nil
        }

        let components: DateComponents
        if cadence == "Yearly" {
            components = DateComponents(year: 1)
        } else {
            components = DateComponents(month: 1)
        }

        return Calendar.current.date(byAdding: components, to: latestChargeDate)
    }

    private static func buildPriceHistory(from signals: [Signal]) -> [PricePoint] {
        let history = signals.compactMap { signal -> PricePoint? in
            guard let amount = signal.amount else { return nil }
            return PricePoint(amount: amount, date: signal.message.date, sourceSubject: signal.message.subject)
        }

        return history
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .reduce(into: []) { partialResult, point in
                if let existing = partialResult.first, existing.amount == point.amount {
                    if existing.date == point.date {
                        return
                    }
                }
                partialResult.append(point)
            }
    }

    private static func deduplicateEmails(_ emails: [EvidenceEmail]) -> [EvidenceEmail] {
        var seen: Set<String> = []
        var output: [EvidenceEmail] = []

        for email in emails {
            guard seen.insert(email.uid).inserted else { continue }
            output.append(email)
        }

        return output
    }

    private static func buildSummary(
        merchant: String,
        amount: Double?,
        cadence: String,
        status: SubscriptionStatus,
        nextDate: Date?,
        priceHistory: [PricePoint]
    ) -> String {
        switch status {
        case .trial:
            if let nextDate, let amount {
                return "\(merchant) trial ends on \(nextDate.formatted(date: .abbreviated, time: .omitted)) and is expected to convert at \(amount.currencyString) \(cadence.lowercased())."
            }
            return "\(merchant) appears to be in a trial period."
        case .increased:
            let sortedHistory = priceHistory.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            if let current = sortedHistory.first?.amount, let previous = sortedHistory.dropFirst().first?.amount, current != previous {
                return "\(merchant) appears to have increased from \(previous.currencyString) to \(current.currencyString)."
            }
            if let amount {
                return "\(merchant) shows a recent pricing change, with the current recurring amount detected at \(amount.currencyString)."
            }
            return "\(merchant) shows a recent subscription pricing change."
        case .active:
            if let nextDate, let amount {
                return "\(merchant) looks active with a recurring \(cadence.lowercased()) charge of \(amount.currencyString), next due \(nextDate.formatted(date: .abbreviated, time: .omitted))."
            }
            if let amount {
                return "\(merchant) looks active with a recurring \(cadence.lowercased()) charge of \(amount.currencyString)."
            }
            return "\(merchant) appears to be an active recurring subscription."
        }
    }

    private static func buildHighlights(subscriptions: [SubscriptionRecord], messages: [EmailMessage]) -> [String] {
        guard !subscriptions.isEmpty else {
            return ["No recurring subscriptions were confidently detected in the most recent inbox sync."]
        }

        var highlights: [String] = []

        if let increased = subscriptions.first(where: { $0.status == .increased }) {
            if let current = increased.currentAmount, let previous = increased.previousAmount, current != previous {
                highlights.append("I flagged a likely price increase from \(increased.merchant), moving from \(previous.currencyString) to \(current.currencyString).")
            } else if let amount = increased.amount {
                highlights.append("I flagged a likely price increase from \(increased.merchant), now showing \(amount.currencyString).")
            } else {
                highlights.append("I flagged a likely price increase from \(increased.merchant).")
            }
        }

        if let urgentTrial = subscriptions.first(where: { $0.status == .trial }) {
            if let countdownText = urgentTrial.countdownText {
                highlights.append("I found an active trial for \(urgentTrial.merchant) with \(countdownText.lowercased()) before the first charge.")
            } else {
                highlights.append("I found an active trial for \(urgentTrial.merchant).")
            }
        }

        let upcomingCount = subscriptions.filter { $0.badge == .upcoming }.count
        if upcomingCount > 0 {
            highlights.append("I found \(upcomingCount) subscription\(upcomingCount == 1 ? "" : "s") with a renewal coming up in the next 10 days.")
        }

        let senderCount = Set(messages.map { $0.senderDisplay }).count
        highlights.append("Latest scan reviewed \(messages.count) emails across \(senderCount) senders on-device.")

        return Array(highlights.prefix(3))
    }

    private static func extractSignal(from message: EmailMessage) -> Signal? {
        let originalText = [message.subject, message.snippet, message.bodyPreview, message.senderDisplay]
            .joined(separator: " ")
        let searchableText = originalText.lowercased()
        let merchant = merchantName(from: message)
        let amount = extractAmount(from: originalText)
        let cadence = extractCadence(from: searchableText)
        let nextDate = extractRelevantDate(from: originalText)
        let isTrial = containsAny(in: searchableText, terms: trialTerms)
        let isPriceIncrease = containsAny(in: searchableText, terms: increaseTerms)
        let hasRecurringCue = containsAny(in: searchableText, terms: recurringTerms)

        guard amount != nil || isTrial || isPriceIncrease || hasRecurringCue else {
            return nil
        }

        guard merchant.lowercased() != "unknown sender" else {
            return nil
        }

        return Signal(
            merchant: merchant,
            amount: amount,
            cadence: cadence,
            nextDate: nextDate,
            isTrial: isTrial,
            isPriceIncrease: isPriceIncrease,
            isRecurring: hasRecurringCue,
            message: message
        )
    }

    private static func normalizedText(for message: EmailMessage) -> String {
        [message.subject, message.snippet, message.bodyPreview, message.senderDisplay]
            .joined(separator: " ")
            .lowercased()
    }

    private static func merchantName(from message: EmailMessage) -> String {
        let sender = message.senderDisplay
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let generic = ["no reply", "noreply", "support", "billing", "member services"]
        let senderLower = sender.lowercased()

        if !sender.isEmpty, !generic.contains(where: senderLower.contains) {
            return sender
        }

        if let email = message.senderEmail {
            let host = email.split(separator: "@").last.map(String.init) ?? ""
            let parts = host.split(separator: ".").map(String.init)
            if let first = parts.first(where: { $0.count > 2 && $0 != "mail" && $0 != "email" && $0 != "support" }) {
                return first.capitalized
            }
        }

        return sender.isEmpty ? "Unknown Sender" : sender
    }

    private static func extractAmount(from text: String) -> Double? {
        let regex = try? NSRegularExpression(pattern: #"\$ ?([0-9]+(?:\.[0-9]{2})?)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        let amounts = matches.compactMap { match -> Double? in
            guard let amountRange = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[amountRange])
        }

        guard !amounts.isEmpty else {
            return nil
        }

        let lowered = text.lowercased()
        if lowered.contains("instead of") {
            return amounts.first
        }

        if lowered.contains("increase from") || lowered.contains(" from ") && lowered.contains(" to ") {
            return amounts.last
        }

        if lowered.contains("updated to") || lowered.contains("new price") || lowered.contains("renew at") {
            return amounts.first
        }

        return amounts.first
    }

    private static func extractCadence(from text: String) -> String? {
        if text.contains("yearly") || text.contains("annual") || text.contains("per year") {
            return "Yearly"
        }
        if text.contains("weekly") || text.contains("per week") {
            return "Weekly"
        }
        if text.contains("monthly") || text.contains("per month") {
            return "Monthly"
        }
        return nil
    }

    private static func extractRelevantDate(from text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: nsRange) ?? []
        let now = Date()

        let priorityTerms = ["trial ends", "renews", "renew", "next bill", "next billing", "charged on", "payment on", "starting"]
        var priorityDates: [Date] = []

        for match in matches {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let prefixStart = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
            let suffixEnd = text.index(range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
            let surrounding = String(text[prefixStart..<suffixEnd])

            if priorityTerms.contains(where: surrounding.contains) {
                priorityDates.append(date)
            }
        }

        if let bestPriorityDate = priorityDates
            .filter({ $0 >= now.addingTimeInterval(-86_400) })
            .sorted()
            .last {
            return bestPriorityDate
        }

        return matches.compactMap(\.date).filter { $0 > now.addingTimeInterval(-86_400 * 365) }.sorted().first
    }

    private static func containsAny(in text: String, terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }

    private static func subscriptionSort(lhs: SubscriptionRecord, rhs: SubscriptionRecord) -> Bool {
        func priority(for badge: SubscriptionBadge?) -> Int {
            switch badge {
            case .trial: return 0
            case .increase: return 1
            case .upcoming: return 2
            case nil: return 3
            }
        }

        let lhsPriority = priority(for: lhs.badge)
        let rhsPriority = priority(for: rhs.badge)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if let lhsDate = lhs.nextDate, let rhsDate = rhs.nextDate, lhsDate != rhsDate {
            return lhsDate < rhsDate
        }

        return lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant) == .orderedAscending
    }
}
