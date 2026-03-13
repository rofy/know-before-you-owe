import Foundation
import Network

enum MailTransportError: LocalizedError {
    case invalidPort
    case connectionFailed
    case disconnected
    case authenticationFailed(String)
    case commandFailed(String)
    case unsupportedProvider(String)
    case recipientRequired

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid mail server port."
        case .connectionFailed:
            return "Unable to connect to the mail server."
        case .disconnected:
            return "The connection closed unexpectedly."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .commandFailed(let reason):
            return "Mail server rejected the request: \(reason)"
        case .unsupportedProvider(let reason):
            return reason
        case .recipientRequired:
            return "A recipient address is required before sending."
        }
    }
}

actor IMAPClient {
    private let queue = DispatchQueue(label: "com.knowbeforeyouowe.imap")
    private let fetchBatchSize = 24
    private var connection: NWConnection?
    private var textBuffer = ""
    private var tagCounter = 0

    func fetchInbox(
        credentials: EmailCredentials,
        accessToken: String? = nil,
        maxCount: Int = 150,
        since: Date? = nil
    ) async throws -> [EmailMessage] {
        try await connect(host: credentials.resolvedHost, port: credentials.port)
        defer {
            connection?.cancel()
            connection = nil
            textBuffer = ""
            tagCounter = 0
        }

        if let accessToken, !accessToken.isEmpty {
            do {
                try await authenticateXOAuth2(email: credentials.email, accessToken: accessToken)
            } catch {
                guard !credentials.password.isEmpty else {
                    throw error
                }
                try await authenticateWithPassword(credentials: credentials)
            }
        } else {
            try await authenticateWithPassword(credentials: credentials)
        }

        let targetUIDs = try await prioritizedTargetUIDs(since: since, maxCount: maxCount)

        return try await fetchMessages(for: targetUIDs)
    }

    func fetchInboxProgressively(
        credentials: EmailCredentials,
        accessToken: String? = nil,
        maxCount: Int = 150,
        since: Date? = nil,
        progressBatchSize: Int = 40,
        onBatch: @Sendable @escaping ([EmailMessage], Int, Int) async -> Void
    ) async throws -> [EmailMessage] {
        try await connect(host: credentials.resolvedHost, port: credentials.port)
        defer {
            connection?.cancel()
            connection = nil
            textBuffer = ""
            tagCounter = 0
        }

        if let accessToken, !accessToken.isEmpty {
            do {
                try await authenticateXOAuth2(email: credentials.email, accessToken: accessToken)
            } catch {
                guard !credentials.password.isEmpty else {
                    throw error
                }
                try await authenticateWithPassword(credentials: credentials)
            }
        } else {
            try await authenticateWithPassword(credentials: credentials)
        }

        let targetUIDs = try await prioritizedTargetUIDs(since: since, maxCount: maxCount)
        guard !targetUIDs.isEmpty else { return [] }

        var messages: [EmailMessage] = []
        var batch: [EmailMessage] = []
        var processed = 0

        for uidBatch in targetUIDs.chunked(into: fetchBatchSize) {
            try Task.checkCancellation()

            let fetchedBatch = try await fetchMessages(for: uidBatch)
            messages.append(contentsOf: fetchedBatch)
            batch.append(contentsOf: fetchedBatch)
            processed += fetchedBatch.count

            if batch.count >= progressBatchSize || processed >= targetUIDs.count {
                await onBatch(batch, processed, targetUIDs.count)
                batch.removeAll(keepingCapacity: true)
            }
        }

        return messages.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func prioritizedTargetUIDs(since: Date?, maxCount: Int) async throws -> [String] {
        _ = try await execute("SELECT INBOX")

        let searchSuffix = since.map { " SINCE \($0.imapSearchDate)" } ?? " ALL"
        let baselineResponse = try await execute("UID SEARCH\(searchSuffix)")
        let baselineUIDs = parseSearchUIDs(from: baselineResponse)
        guard !baselineUIDs.isEmpty else { return [] }

        var priorityUIDs: [String] = []
        for command in prioritySearchCommands(since: since) {
            if let response = try? await execute(command) {
                priorityUIDs.append(contentsOf: parseSearchUIDs(from: response))
            }
        }

        let prioritySet = Set(priorityUIDs)
        let prioritized = prioritySet
            .compactMap(Int.init)
            .sorted(by: >)
            .map(String.init)

        let fallback = baselineUIDs
            .filter { !prioritySet.contains($0) }
            .compactMap(Int.init)
            .sorted(by: >)
            .map(String.init)

        let combined = prioritized + fallback
        let effectiveCount = maxCount <= 0 ? combined.count : min(maxCount, combined.count)
        return Array(combined.prefix(effectiveCount))
    }

    private func prioritySearchCommands(since: Date?) -> [String] {
        let searchPrefix = since.map { "UID SEARCH SINCE \($0.imapSearchDate)" } ?? "UID SEARCH ALL"
        let subjectTerms = [
            "renew",
            "renewal",
            "subscription",
            "trial",
            "billing",
            "receipt",
            "invoice",
            "charge",
            "payment",
            "membership",
            "plan"
        ]
        let senderTerms = ["billing", "receipt", "support", "subscription", "no-reply"]

        let subjectCommands = subjectTerms.map { "\(searchPrefix) SUBJECT \($0.imapQuoted)" }
        let senderCommands = senderTerms.map { "\(searchPrefix) FROM \($0.imapQuoted)" }
        return subjectCommands + senderCommands
    }

    private func fetchMessages(for uids: [String]) async throws -> [EmailMessage] {
        guard !uids.isEmpty else { return [] }

        let response = try await execute(
            "UID FETCH \(uids.joined(separator: ",")) (FLAGS BODY.PEEK[HEADER.FIELDS (FROM REPLY-TO SUBJECT DATE)] BODY.PEEK[TEXT]<0.4000>)"
        )
        let messages = parseMessages(from: response)

        if messages.isEmpty {
            return []
        }

        return messages.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func authenticateWithPassword(credentials: EmailCredentials) async throws {
        let loginResult = try await execute(
            "LOGIN \(credentials.email.imapQuoted) \(credentials.password.imapQuoted)",
            failureAsAuth: true
        )

        guard loginResult.caseInsensitiveContains("OK") else {
            throw MailTransportError.authenticationFailed(loginResult.trimmedForError)
        }
    }

    private func authenticateXOAuth2(email: String, accessToken: String) async throws {
        tagCounter += 1
        let tag = String(format: "A%04d", tagCounter)
        try await send("\(tag) AUTHENTICATE XOAUTH2\r\n")

        let challenge = try await readLine()
        guard challenge.hasPrefix("+") else {
            throw MailTransportError.authenticationFailed(challenge.trimmedForError)
        }

        let payload = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let encoded = Data(payload.utf8).base64EncodedString()
        try await send(encoded + "\r\n")
        let response = try await readResponse(tag: tag)

        if response.caseInsensitiveContains("\(tag) NO") || response.caseInsensitiveContains("\(tag) BAD") {
            throw MailTransportError.authenticationFailed(response.trimmedForError)
        }
    }

    private func connect(host: String, port: Int) async throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw MailTransportError.invalidPort
        }

        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                guard !gate.resumed else { return }
                switch state {
                case .ready:
                    gate.resumed = true
                    continuation.resume(returning: ())
                case .failed:
                    gate.resumed = true
                    continuation.resume(throwing: MailTransportError.connectionFailed)
                case .cancelled:
                    gate.resumed = true
                    continuation.resume(throwing: MailTransportError.disconnected)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        _ = try await readLine()
    }

    private func execute(_ command: String, failureAsAuth: Bool = false) async throws -> String {
        tagCounter += 1
        let tag = String(format: "A%04d", tagCounter)
        let payload = "\(tag) \(command)\r\n"

        try await send(payload)
        let response = try await readResponse(tag: tag)

        if response.caseInsensitiveContains("\(tag) NO") || response.caseInsensitiveContains("\(tag) BAD") {
            if failureAsAuth {
                throw MailTransportError.authenticationFailed(response.trimmedForError)
            }
            throw MailTransportError.commandFailed(response.trimmedForError)
        }

        return response
    }

    private func send(_ command: String) async throws {
        guard let connection else { throw MailTransportError.disconnected }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func readResponse(tag: String) async throws -> String {
        var collected = ""
        while true {
            let line = try await readLine()
            collected += line + "\n"
            if line.uppercased().hasPrefix(tag.uppercased() + " ") {
                return collected
            }
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let range = textBuffer.range(of: "\r\n") {
                let line = String(textBuffer[..<range.lowerBound])
                textBuffer.removeSubrange(textBuffer.startIndex..<range.upperBound)
                return line
            }

            let chunk = try await receiveChunk()
            textBuffer += chunk
        }
    }

    private func receiveChunk() async throws -> String {
        guard let connection else { throw MailTransportError.disconnected }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if isComplete, (data?.isEmpty ?? true) {
                    continuation.resume(throwing: MailTransportError.disconnected)
                    return
                }

                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                continuation.resume(returning: text)
            }
        }
    }

    private func parseSearchUIDs(from response: String) -> [String] {
        let lines = response.components(separatedBy: .newlines)
        guard let searchLine = lines.first(where: { $0.uppercased().hasPrefix("* SEARCH") }) else {
            return []
        }

        return searchLine
            .replacingOccurrences(of: "* SEARCH", with: "", options: .caseInsensitive)
            .split(separator: " ")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted()
            .map(String.init)
    }

    private func parseMessages(from response: String) -> [EmailMessage] {
        splitFetchBlocks(from: response).map { parseMessage(from: $0, fallbackUID: UUID().uuidString) }
    }

    private func splitFetchBlocks(from response: String) -> [String] {
        let lines = response.components(separatedBy: .newlines)
        var blocks: [String] = []
        var current: [String] = []

        for line in lines {
            if isFetchStartLine(line) {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current.removeAll(keepingCapacity: true)
                }
                current.append(line)
            } else if line.uppercased().hasPrefix("A"), !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current.removeAll(keepingCapacity: true)
            } else if !current.isEmpty {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }

        return blocks
    }

    private func isFetchStartLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("* ") else { return false }
        return trimmed.uppercased().contains(" FETCH ")
    }

    private func parseMessage(from response: String, fallbackUID: String) -> EmailMessage {
        let lines = response.components(separatedBy: .newlines)
        let uid = lines.first(where: { $0.uppercased().contains(" UID ") }).flatMap { line -> String? in
            let parts = line.split(separator: " ")
            guard let index = parts.firstIndex(where: { $0.uppercased() == "UID" }), index + 1 < parts.count else {
                return nil
            }
            return String(parts[index + 1]).trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        } ?? fallbackUID

        let fromRaw = extractHeader("From", from: lines)
        let replyToRaw = extractHeader("Reply-To", from: lines)
        let subject = extractHeader("Subject", from: lines) ?? "(No subject)"
        let dateString = extractHeader("Date", from: lines)
        let date = MailDateParser.parse(dateString)
        let isUnread = !response.caseInsensitiveContains("\\Seen")

        let fromAddress = MailAddressParser.parse(fromRaw)
        let replyToAddress = MailAddressParser.parse(replyToRaw)
        let bodyLines = filterBodyLines(from: lines)
        let joinedBody = bodyLines.joined(separator: " ").cleanedPreview
        let snippet = String(joinedBody.prefix(180))
        let bodyPreview = String(joinedBody.prefix(1_200))

        return EmailMessage(
            uid: uid,
            senderName: fromAddress?.name ?? (fromRaw?.cleanHeaderValue ?? "Unknown Sender"),
            senderEmail: fromAddress?.email,
            replyToEmail: replyToAddress?.email,
            subject: subject.cleanHeaderValue,
            date: date,
            snippet: snippet.isEmpty ? "Open message to preview content." : snippet,
            bodyPreview: bodyPreview.isEmpty ? "Open message to preview content." : bodyPreview,
            isUnread: isUnread
        )
    }

    private func extractHeader(_ key: String, from lines: [String]) -> String? {
        let prefix = key.lowercased() + ":"
        return lines.first(where: { $0.lowercased().hasPrefix(prefix) })?
            .split(separator: ":", maxSplits: 1)
            .dropFirst()
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filterBodyLines(from lines: [String]) -> [String] {
        lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard !trimmed.hasPrefix("*") else { return false }
            guard !trimmed.uppercased().hasPrefix("A") else { return false }
            guard !trimmed.caseInsensitiveHasPrefix("from:") else { return false }
            guard !trimmed.caseInsensitiveHasPrefix("reply-to:") else { return false }
            guard !trimmed.caseInsensitiveHasPrefix("subject:") else { return false }
            guard !trimmed.caseInsensitiveHasPrefix("date:") else { return false }
            guard !trimmed.caseInsensitiveContains("BODY[") else { return false }
            guard trimmed != ")" else { return false }
            return true
        }
    }
}

private extension Date {
    var imapSearchDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter.string(from: self)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }

        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}

actor SMTPClient {
    private let queue = DispatchQueue(label: "com.knowbeforeyouowe.smtp")
    private var connection: NWConnection?
    private var textBuffer = ""

    func send(draft: DraftEmail, credentials: EmailCredentials, accessToken: String? = nil) async throws {
        guard !draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MailTransportError.recipientRequired
        }

        guard credentials.provider.supportsDirectSend || credentials.provider == .custom else {
            throw MailTransportError.unsupportedProvider("Direct one-tap send is currently available for Yahoo, Google app-password accounts, AOL, iCloud, and compatible custom SMTP servers using implicit TLS.")
        }

        let smtpHost = credentials.resolvedSMTPHost
        let smtpPort = credentials.resolvedSMTPPort
        guard !smtpHost.isEmpty else {
            throw MailTransportError.unsupportedProvider("No SMTP host is configured for this account.")
        }

        try await connect(host: smtpHost, port: smtpPort)
        defer {
            connection?.cancel()
            connection = nil
            textBuffer = ""
        }

        _ = try await readExpected(code: 220)
        _ = try await execute("EHLO knowbeforeyouowe.app", expecting: [250])

        if let accessToken, !accessToken.isEmpty {
            let xoauthPayload = "user=\(credentials.email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
            let encoded = Data(xoauthPayload.utf8).base64EncodedString()
            _ = try await execute("AUTH XOAUTH2 \(encoded)", expecting: [235])
        } else {
            let authPayload = Data("\u{0}\(credentials.email)\u{0}\(credentials.password)".utf8).base64EncodedString()
            _ = try await execute("AUTH PLAIN \(authPayload)", expecting: [235])
        }
        _ = try await execute("MAIL FROM:<\(credentials.email)>", expecting: [250])
        _ = try await execute("RCPT TO:<\(draft.to)>", expecting: [250, 251])
        _ = try await execute("DATA", expecting: [354])

        try await sendRaw(composeMessage(draft: draft, fromEmail: credentials.email))
        _ = try await readExpected(code: 250)
        _ = try? await execute("QUIT", expecting: [221])
    }

    private func connect(host: String, port: Int) async throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw MailTransportError.invalidPort
        }

        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                guard !gate.resumed else { return }
                switch state {
                case .ready:
                    gate.resumed = true
                    continuation.resume(returning: ())
                case .failed:
                    gate.resumed = true
                    continuation.resume(throwing: MailTransportError.connectionFailed)
                case .cancelled:
                    gate.resumed = true
                    continuation.resume(throwing: MailTransportError.disconnected)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func execute(_ command: String, expecting expectedCodes: [Int]) async throws -> [String] {
        try await sendRaw(command + "\r\n")
        let response = try await readResponse()
        guard let code = response.first.flatMap(parseResponseCode(_:)), expectedCodes.contains(code) else {
            throw MailTransportError.commandFailed(response.joined(separator: " | "))
        }
        return response
    }

    private func readExpected(code: Int) async throws -> [String] {
        let response = try await readResponse()
        guard let received = response.first.flatMap(parseResponseCode(_:)), received == code else {
            throw MailTransportError.commandFailed(response.joined(separator: " | "))
        }
        return response
    }

    private func readResponse() async throws -> [String] {
        var lines: [String] = []

        while true {
            let line = try await readLine()
            lines.append(line)

            guard line.count >= 4 else {
                return lines
            }

            let separatorIndex = line.index(line.startIndex, offsetBy: 3)
            if line[separatorIndex] == " " {
                return lines
            }
        }
    }

    private func parseResponseCode(_ line: String) -> Int? {
        Int(line.prefix(3))
    }

    private func sendRaw(_ command: String) async throws {
        guard let connection else { throw MailTransportError.disconnected }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let range = textBuffer.range(of: "\r\n") {
                let line = String(textBuffer[..<range.lowerBound])
                textBuffer.removeSubrange(textBuffer.startIndex..<range.upperBound)
                return line
            }

            let chunk = try await receiveChunk()
            textBuffer += chunk
        }
    }

    private func receiveChunk() async throws -> String {
        guard let connection else { throw MailTransportError.disconnected }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if isComplete, (data?.isEmpty ?? true) {
                    continuation.resume(throwing: MailTransportError.disconnected)
                    return
                }

                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                continuation.resume(returning: text)
            }
        }
    }

    private func composeMessage(draft: DraftEmail, fromEmail: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"

        let safeBody = draft.body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.hasPrefix(".") ? "." + line : String(line)
            }
            .joined(separator: "\r\n")

        let safeSubject = draft.subject
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        return [
            "From: <\(fromEmail)>",
            "To: <\(draft.to)>",
            "Subject: \(safeSubject)",
            "Date: \(formatter.string(from: Date()))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: 8bit",
            "",
            safeBody,
            ".",
            ""
        ].joined(separator: "\r\n")
    }
}

private final class ContinuationGate {
    var resumed = false
}

private enum MailDateParser {
    static let formatters: [DateFormatter] = {
        let patterns = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z"
        ]

        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return formatters.compactMap { $0.date(from: raw) }.first
    }
}

private struct ParsedAddress {
    let name: String
    let email: String
}

private enum MailAddressParser {
    static func parse(_ raw: String?) -> ParsedAddress? {
        guard let raw, !raw.isEmpty else { return nil }
        let cleaned = raw.replacingOccurrences(of: "\"", with: "")

        if let angleOpen = cleaned.firstIndex(of: "<"), let angleClose = cleaned.firstIndex(of: ">"), angleOpen < angleClose {
            let name = String(cleaned[..<angleOpen]).trimmingCharacters(in: .whitespacesAndNewlines)
            let email = String(cleaned[cleaned.index(after: angleOpen)..<angleClose]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedAddress(name: name.isEmpty ? email : name, email: email)
        }

        if cleaned.contains("@") {
            let parts = cleaned.split(separator: "@")
            if let localPart = parts.first {
                return ParsedAddress(name: String(localPart), email: cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return nil
    }
}

private extension String {
    var imapQuoted: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    var cleanHeaderValue: String {
        replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedPreview: String {
        replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func caseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }

    func caseInsensitiveHasPrefix(_ other: String) -> Bool {
        lowercased().hasPrefix(other.lowercased())
    }

    var trimmedForError: String {
        split(whereSeparator: { $0.isNewline })
            .suffix(4)
            .joined(separator: " | ")
    }
}
