import Foundation

enum EmailProvider: String, CaseIterable, Identifiable, Codable {
    case yahoo
    case gmail
    case outlook
    case aol
    case icloud
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yahoo: return "Yahoo"
        case .gmail: return "Google"
        case .outlook: return "Outlook"
        case .aol: return "AOL"
        case .icloud: return "iCloud"
        case .custom: return "Others"
        }
    }

    var icon: String {
        switch self {
        case .yahoo: return "y.circle.fill"
        case .gmail: return "g.circle.fill"
        case .outlook: return "o.circle.fill"
        case .aol: return "a.circle.fill"
        case .icloud: return "cloud.circle.fill"
        case .custom: return "envelope.circle.fill"
        }
    }

    var brandColorHex: String {
        switch self {
        case .yahoo: return "6001D2"
        case .gmail: return "DB4437"
        case .outlook: return "0078D4"
        case .aol: return "111111"
        case .icloud: return "4B92FF"
        case .custom: return "6B7280"
        }
    }

    var defaultHost: String {
        switch self {
        case .yahoo: return "imap.mail.yahoo.com"
        case .gmail: return "imap.gmail.com"
        case .outlook: return "outlook.office365.com"
        case .aol: return "imap.aol.com"
        case .icloud: return "imap.mail.me.com"
        case .custom: return ""
        }
    }

    var defaultPort: Int { 993 }

    var defaultSMTPHost: String {
        switch self {
        case .yahoo: return "smtp.mail.yahoo.com"
        case .gmail: return "smtp.gmail.com"
        case .outlook: return "smtp-mail.outlook.com"
        case .aol: return "smtp.aol.com"
        case .icloud: return "smtp.mail.me.com"
        case .custom: return ""
        }
    }

    var defaultSMTPPort: Int {
        switch self {
        case .outlook:
            return 587
        default:
            return 465
        }
    }

    var supportsDirectSend: Bool {
        defaultSMTPPort == 465
    }

    var supportHint: String {
        switch self {
        case .yahoo:
            return "Use a Yahoo app password. Credentials stay on this device in Keychain."
        case .gmail:
            return "Use a Google app password with 2-step verification enabled."
        case .outlook:
            return "IMAP works with Outlook credentials, but direct send may require a provider-specific SMTP setup."
        case .aol:
            return "Use an AOL app password from Account Security."
        case .icloud:
            return "Use an Apple app-specific password from Apple ID settings."
        case .custom:
            return "Enter your IMAP host. Direct send is only available for implicit TLS SMTP servers."
        }
    }

    var defaultEmailDomain: String? {
        switch self {
        case .yahoo: return "yahoo.com"
        case .gmail: return "gmail.com"
        case .outlook: return "outlook.com"
        case .aol: return "aol.com"
        case .icloud: return "icloud.com"
        case .custom: return nil
        }
    }
}

struct EmailCredentials: Codable, Equatable {
    var provider: EmailProvider = .yahoo
    var email: String = ""
    var password: String = ""
    var host: String = ""
    var port: Int = 993
    var oauthAccessToken: String = ""

    var resolvedHost: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultHost : trimmed
    }

    var resolvedSMTPHost: String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .custom {
            return trimmed
        }
        return provider.defaultSMTPHost
    }

    var resolvedSMTPPort: Int {
        provider == .custom ? 465 : provider.defaultSMTPPort
    }
}

struct EmailMessage: Identifiable, Hashable {
    var id: String { uid }

    let uid: String
    let senderName: String
    let senderEmail: String?
    let replyToEmail: String?
    let subject: String
    let date: Date?
    let snippet: String
    let bodyPreview: String
    let isUnread: Bool

    var senderDisplay: String {
        let trimmed = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let senderEmail {
            return senderEmail
        }
        return "Unknown Sender"
    }

    var preferredReplyAddress: String? {
        if let replyToEmail, !replyToEmail.isEmpty {
            return replyToEmail
        }
        return senderEmail
    }
}

struct PricePoint: Identifiable, Hashable {
    let id = UUID()
    let amount: Double
    let date: Date?
    let sourceSubject: String
}

struct EvidenceEmail: Identifiable, Hashable {
    let uid: String
    let senderDisplay: String
    let senderEmail: String?
    let replyToEmail: String?
    let subject: String
    let date: Date?
    let snippet: String
    let bodyPreview: String

    var id: String { uid }

    var searchableText: String {
        [subject, snippet, bodyPreview, senderEmail ?? "", replyToEmail ?? ""]
            .joined(separator: "\n")
    }
}

enum SubscriptionStatus: String, Codable, Hashable {
    case active
    case trial
    case increased

    var title: String {
        switch self {
        case .active: return "Active"
        case .trial: return "Trial"
        case .increased: return "Price Increased"
        }
    }
}

enum SubscriptionBadge: String, Codable, Hashable {
    case trial = "TRIAL"
    case increase = "INCREASE"
    case upcoming = "UPCOMING"

    var tintHex: String {
        switch self {
        case .trial: return "0EA5E9"
        case .increase: return "D92D20"
        case .upcoming: return "6001D2"
        }
    }
}

struct SubscriptionRecord: Identifiable, Hashable {
    let merchant: String
    let amount: Double?
    let cadence: String
    let status: SubscriptionStatus
    let nextDate: Date?
    let startDate: Date?
    let emails: [EvidenceEmail]
    let priceHistory: [PricePoint]
    let summary: String
    let contactEmail: String?
    let badge: SubscriptionBadge?

    var id: String { merchant.lowercased() }

    var formattedAmount: String {
        guard let amount else { return "Unknown" }
        return amount.currencyString
    }

    var expectedChargeLine: String {
        if let amount {
            return "\(amount.currencyString) \(cadence.lowercased())"
        }
        return cadence
    }

    var countdownText: String? {
        guard let nextDate else { return nil }
        let now = Date()
        let day = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: nextDate)
        ).day ?? 0
        if day >= 1 {
            return "\(day) day" + (day == 1 ? " left" : "s left")
        }
        let components = Calendar.current.dateComponents([.hour], from: now, to: nextDate)
        if let hour = components.hour, hour >= 1 {
            return "\(hour) hour" + (hour == 1 ? " left" : "s left")
        }
        return "Due soon"
    }

    var countdownCompactValue: String? {
        guard let nextDate else { return nil }
        let now = Date()
        let day = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: nextDate)
        ).day ?? 0
        if day >= 1 {
            return "\(day)d"
        }
        let components = Calendar.current.dateComponents([.hour], from: now, to: nextDate)
        if let hour = components.hour, hour >= 1 {
            return "\(hour)h"
        }
        return nil
    }

    var previousAmount: Double? {
        guard priceHistory.count >= 2 else { return nil }
        return priceHistory
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .dropFirst()
            .first?
            .amount
    }

    var currentAmount: Double? {
        priceHistory
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .first?
            .amount ?? amount
    }

    var priceIncreaseDelta: Double {
        guard let currentAmount, let previousAmount else { return 0 }
        return currentAmount - previousAmount
    }

    var latestEvidence: EvidenceEmail? {
        emails.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.first
    }
}

struct FinancialDigest: Hashable {
    let recurringCount: Int
    let trialCount: Int
    let increaseCount: Int

    static let empty = FinancialDigest(recurringCount: 0, trialCount: 0, increaseCount: 0)
}

struct AnalyzerOutput {
    let subscriptions: [SubscriptionRecord]
    let digest: FinancialDigest
    let highlights: [String]
}

struct YahooOAuthConfiguration: Codable, Equatable {
    var clientID: String = ""
    var clientSecret: String = ""
    var redirectURI: String = "knowbeforeyouowe://oauth/yahoo"

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GoogleOAuthConfiguration: Codable, Equatable {
    var clientID: String = ""
    var redirectURI: String = "knowbeforeyouowe://oauth/google"

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct YahooOAuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String
    let expiresAt: Date
    let email: String?

    var isExpired: Bool {
        expiresAt <= Date()
    }

    var shouldRefreshSoon: Bool {
        expiresAt <= Date().addingTimeInterval(300)
    }
}

struct GoogleOAuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String
    let expiresAt: Date
    let email: String?

    var isExpired: Bool {
        expiresAt <= Date()
    }

    var shouldRefreshSoon: Bool {
        expiresAt <= Date().addingTimeInterval(300)
    }
}

struct CancellationDestination: Hashable {
    let url: URL
    let sourceSubject: String

    var hostDisplay: String {
        url.host ?? url.absoluteString
    }
}

enum LoadingState: Equatable {
    case idle
    case loading(String)
    case failed(String)
    case loaded
}

enum DraftIntent: String, Hashable {
    case refund
    case cancel

    var screenTitle: String {
        switch self {
        case .refund: return "Review Email"
        case .cancel: return "Review Email"
        }
    }

    var buttonTitle: String {
        switch self {
        case .refund: return "Send Email"
        case .cancel: return "Send Email"
        }
    }
}

struct DraftEmail: Identifiable, Hashable {
    let id = UUID()
    let to: String
    let subject: String
    let body: String
    let intent: DraftIntent
    let merchant: String
}

enum InboxBucket: String, CaseIterable, Identifiable {
    case all = "All"
    case primary = "Primary"
    case offers = "Offers"
    case other = "Other"

    var id: String { rawValue }
}

enum ScanMode: String, CaseIterable, Identifiable, Codable {
    case quick
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick:
            return "Quick Scan"
        case .deep:
            return "Deep Scan"
        }
    }

    var subtitle: String {
        switch self {
        case .quick:
            return "Fast recent inbox pass"
        case .deep:
            return "Recent pass plus 10,000-email background scan"
        }
    }
}

struct PersistedCredentials: Codable {
    let provider: EmailProvider
    let email: String
    let host: String
    let port: Int

    init(from credentials: EmailCredentials) {
        provider = credentials.provider
        email = credentials.email
        host = credentials.host
        port = credentials.port
    }
}

extension Double {
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "$%.2f", self)
    }
}

extension Array where Element == EmailMessage {
    static let mockMessages: [EmailMessage] = [
        EmailMessage(
            uid: "2001",
            senderName: "Netflix",
            senderEmail: "info@account.netflix.com",
            replyToEmail: "support@netflix.com",
            subject: "Your Netflix Premium plan will renew on March 28, 2026 for $22.99",
            date: Date().addingTimeInterval(-4_000),
            snippet: "Heads up: your Premium plan renews on March 28, 2026. Your next bill is $22.99.",
            bodyPreview: "Your Netflix Premium plan will renew on March 28, 2026 for $22.99. Manage or cancel anytime before your billing date at https://www.netflix.com/cancelplan.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2002",
            senderName: "Spotify",
            senderEmail: "no-reply@spotify.com",
            replyToEmail: "support@spotify.com",
            subject: "Your Spotify Premium trial ends March 18, 2026",
            date: Date().addingTimeInterval(-12_000),
            snippet: "Your free trial ends March 18, 2026. You will be charged $11.99 monthly unless you cancel.",
            bodyPreview: "Your Spotify Premium trial ends March 18, 2026. Unless canceled before then, your plan will continue at $11.99 per month. Cancel anytime at https://www.spotify.com/account/subscription/.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2003",
            senderName: "Dropbox",
            senderEmail: "no-reply@dropbox.com",
            replyToEmail: "support@dropbox.com",
            subject: "Upcoming Dropbox price increase",
            date: Date().addingTimeInterval(-40_000),
            snippet: "Starting April 2, 2026, Dropbox Plus will increase from $9.99 to $11.99 monthly.",
            bodyPreview: "Starting April 2, 2026, your Dropbox Plus subscription will increase from $9.99 to $11.99 monthly. Manage your plan at https://www.dropbox.com/account/plan.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2004",
            senderName: "Dropbox",
            senderEmail: "no-reply@dropbox.com",
            replyToEmail: "support@dropbox.com",
            subject: "Your Dropbox Plus receipt for $9.99",
            date: Date().addingTimeInterval(-2_500_000),
            snippet: "Thanks for your payment. Your monthly Dropbox Plus plan was charged $9.99.",
            bodyPreview: "Thanks for your payment. Your monthly Dropbox Plus subscription was charged $9.99 on February 2, 2026. Visit https://www.dropbox.com/account/plan to review billing settings.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2005",
            senderName: "The New York Times",
            senderEmail: "nytdirect@nytimes.com",
            replyToEmail: "help@nytimes.com",
            subject: "Your monthly payment of $4.00 was received",
            date: Date().addingTimeInterval(-86_400 * 10),
            snippet: "Thanks for subscribing. Your next monthly payment will be on March 31, 2026.",
            bodyPreview: "Thanks for subscribing to The New York Times. Your monthly payment of $4.00 was received, and your next monthly payment will be on March 31, 2026.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2006",
            senderName: "LinkedIn Job Alerts",
            senderEmail: "jobs-listings@linkedin.com",
            replyToEmail: nil,
            subject: "New product manager jobs",
            date: Date().addingTimeInterval(-5_400),
            snippet: "Here are the latest jobs that match your search.",
            bodyPreview: "Here are the latest jobs that match your search. Save jobs and apply faster.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2007",
            senderName: "Canva",
            senderEmail: "no-reply@canva.com",
            replyToEmail: "support@canva.com",
            subject: "Your Canva Pro yearly subscription renews April 30, 2026",
            date: Date().addingTimeInterval(-90_000),
            snippet: "We will charge $119.99 yearly on April 30, 2026.",
            bodyPreview: "Your Canva Pro yearly subscription renews April 30, 2026. We will charge $119.99 yearly to your saved payment method. Update or cancel at https://www.canva.com/settings/billing.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2008",
            senderName: "USPS",
            senderEmail: "auto-reply@usps.com",
            replyToEmail: nil,
            subject: "Package delivered",
            date: Date().addingTimeInterval(-3_600),
            snippet: "Your package was delivered in Sunnyvale, CA.",
            bodyPreview: "Your package was delivered in Sunnyvale, CA at 1:15 PM.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2009",
            senderName: "HBO Max",
            senderEmail: "no-reply@hbomax.com",
            replyToEmail: "support@hbomax.com",
            subject: "Your HBO Max monthly charge of $15.99",
            date: Date().addingTimeInterval(-86_400 * 33),
            snippet: "Your payment for HBO Max was successful. Next billing date: March 21, 2026.",
            bodyPreview: "Your payment for HBO Max was successful. Your monthly subscription remains active. Next billing date: March 21, 2026. Manage your subscription at https://play.max.com/settings/subscription.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2010",
            senderName: "HBO Max",
            senderEmail: "no-reply@hbomax.com",
            replyToEmail: "support@hbomax.com",
            subject: "Your HBO Max monthly charge of $15.99",
            date: Date().addingTimeInterval(-86_400 * 3),
            snippet: "Your payment for HBO Max was successful. Next billing date: April 21, 2026.",
            bodyPreview: "Your payment for HBO Max was successful. Your monthly subscription remains active. Next billing date: April 21, 2026. Manage your subscription at https://play.max.com/settings/subscription.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2011",
            senderName: "MasterClass",
            senderEmail: "billing@masterclass.com",
            replyToEmail: "support@masterclass.com",
            subject: "Your MasterClass annual membership renews March 20, 2026 for $180.00",
            date: Date().addingTimeInterval(-22_000),
            snippet: "Your annual membership renews in 8 days for $180.00 unless you cancel.",
            bodyPreview: "Your MasterClass annual membership renews on March 20, 2026 for $180.00. To prevent renewal, visit https://www.masterclass.com/settings/membership.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2012",
            senderName: "Spotify",
            senderEmail: "no-reply@spotify.com",
            replyToEmail: "support@spotify.com",
            subject: "Welcome to your Spotify Premium trial",
            date: Date().addingTimeInterval(-86_400 * 6),
            snippet: "Your trial started today and will renew for $11.99 monthly after March 18, 2026.",
            bodyPreview: "Your Spotify Premium trial started today. You can manage or cancel before March 18, 2026 at https://www.spotify.com/account/subscription/.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2013",
            senderName: "Notion",
            senderEmail: "team@updates.notion.so",
            replyToEmail: "team@make.notion.so",
            subject: "Your Notion Plus subscription renews on March 25, 2026 for $10.00",
            date: Date().addingTimeInterval(-14_000),
            snippet: "Your workspace will renew for $10.00 monthly on March 25, 2026.",
            bodyPreview: "Your Notion Plus subscription renews on March 25, 2026 for $10.00 monthly. Update billing settings at https://www.notion.so/settings/billing.",
            isUnread: false
        ),
        EmailMessage(
            uid: "2014",
            senderName: "Adobe",
            senderEmail: "billing@mail.adobe.com",
            replyToEmail: "support@adobe.com",
            subject: "Adobe Creative Cloud plan updated to $64.99 monthly",
            date: Date().addingTimeInterval(-48_000),
            snippet: "Your Creative Cloud All Apps plan will renew at the new price of $64.99 monthly.",
            bodyPreview: "Starting with your next billing cycle, Adobe Creative Cloud All Apps will renew at $64.99 monthly instead of $54.99. Review your plan at https://account.adobe.com/plans.",
            isUnread: true
        ),
        EmailMessage(
            uid: "2015",
            senderName: "Adobe",
            senderEmail: "billing@mail.adobe.com",
            replyToEmail: "support@adobe.com",
            subject: "Your Adobe Creative Cloud receipt for $54.99",
            date: Date().addingTimeInterval(-86_400 * 31),
            snippet: "Thanks for your payment. Your monthly plan was charged $54.99.",
            bodyPreview: "Thanks for your payment. Your Adobe Creative Cloud All Apps plan was charged $54.99 on February 9, 2026. Manage your plan at https://account.adobe.com/plans.",
            isUnread: false
        )
    ]
}
