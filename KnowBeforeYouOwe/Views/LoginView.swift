import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: Field?
    @State private var stage: Stage = .mailboxPicker
    @State private var isPasswordVisible = false

    private enum Stage {
        case mailboxPicker
        case credentials
    }

    private enum Field {
        case email
        case password
        case host
    }

    private let providerOrder: [EmailProvider] = [.gmail, .outlook, .aol, .yahoo, .custom]

    var body: some View {
        ZStack {
            loginBackdrop

            if stage == .mailboxPicker {
                mailboxPicker
            } else {
                credentialsScreen
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: stage)
        .onTapGesture {
            focusedField = nil
        }
    }

    private var loginBackdrop: some View {
        KBYOPalette.background
            .ignoresSafeArea()
    }

    private var mailboxPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(KBYOPalette.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Add an email address")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(KBYOPalette.ink)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 28)

            VStack(spacing: 8) {
                Text(.init("By continuing, you agree to allow Yahoo to sync the email, calendar and contacts from your other account and treat them in accordance with the [Terms](https://legal.yahoo.com/us/en/yahoo/terms/otos/index.html) and [Privacy Policy](https://legal.yahoo.com/us/en/yahoo/privacy/index.html)."))
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KBYOPalette.secondary)
                    .tint(Color(hex: "0A66FF"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider().overlay(KBYOPalette.line)

            VStack(spacing: 0) {
                ForEach(providerOrder, id: \.self) { provider in
                    Button {
                        Haptics.softImpact()
                        appState.setProvider(provider)
                        stage = .credentials
                    } label: {
                        providerRow(provider)
                    }
                    .buttonStyle(.plain)

                    if provider != providerOrder.last {
                        Divider().overlay(KBYOPalette.line)
                    }
                }
            }

            Spacer(minLength: 20)

            Button("Use demo inbox") {
                focusedField = nil
                Haptics.softImpact()
                appState.useOfflineDemo()
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(KBYOPalette.accent)
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private func providerRow(_ provider: EmailProvider) -> some View {
        HStack(spacing: 18) {
            providerIcon(provider)

            Text(provider.title)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(KBYOPalette.ink)

            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 96)
    }

    @ViewBuilder
    private func providerIcon(_ provider: EmailProvider) -> some View {
        let stroke = KBYOPalette.line

        switch provider {
        case .gmail:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Text("G")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "4285F4"), Color(hex: "34A853"), Color(hex: "FBBC05"), Color(hex: "EA4335")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        case .outlook:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "0078D4"))
                            .frame(width: 28, height: 24)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        case .aol:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Text("AOL")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(KBYOPalette.ink)
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        case .yahoo:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Text("y!")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(KBYOPalette.accent)
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        case .custom:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "envelope")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(KBYOPalette.secondary)
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        case .icloud:
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(hex: "4B92FF"))
                )
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        }
    }

    private var credentialsScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                providerIntro

                if appState.credentials.provider == .gmail {
                    googleLoginCard
                }

                if appState.credentials.provider == .yahoo {
                    yahooLoginCard
                }

                imapCredentialsCard

                Button("Use demo inbox instead") {
                    focusedField = nil
                    Haptics.softImpact()
                    appState.useOfflineDemo()
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KBYOPalette.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.selection()
                stage = .mailboxPicker
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KBYOPalette.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(KBYOPalette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(appState.credentials.provider.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Spacer()

            providerIcon(appState.credentials.provider)
                .scaleEffect(0.92)
                .frame(width: 44, height: 44)
        }
    }

    private var providerIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heroTitle)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Text(heroSubtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(KBYOPalette.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var yahooLoginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Sign in with Yahoo")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)

                    Text("Use the Yahoo-style web sign-in first, then sync the same inbox into Know Before You Owe.")
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)
                }

                Spacer()

                Text("y!")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(KBYOPalette.accent)
            }

            if let session = appState.yahooOAuthSession {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Yahoo account verified", systemImage: "checkmark.circle.fill")
                        .font(AppFont.headline(16))
                        .foregroundStyle(KBYOPalette.success)
                    Text(session.email ?? appState.credentials.email)
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "EDF9F0"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button("Use a different Yahoo account") {
                    focusedField = nil
                    appState.clearYahooOAuthSession()
                    Task { await appState.signInWithYahooOAuth() }
                }
                .buttonStyle(SecondaryPillButtonStyle())
            } else if appState.isYahooOAuthConfigured {
                Button("Continue with Yahoo") {
                    focusedField = nil
                    Task { await appState.signInWithYahooOAuth() }
                }
                .buttonStyle(PrimaryPillButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yahoo OAuth needs a client ID and client secret in Settings before web sign-in can run.")
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)

                    Text("Until then, you can still connect Yahoo below with an app password.")
                        .font(AppFont.caption(14))
                        .foregroundStyle(KBYOPalette.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KBYOPalette.accentWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var googleLoginCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Sign in with Google")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KBYOPalette.ink)

                    Text("Connect your real Gmail inbox with a Google web sign-in, then let Know Before You Owe analyze recurring billing emails.")
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                providerIcon(.gmail)
                    .scaleEffect(0.92)
            }

            if let session = appState.googleOAuthSession {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Google account verified", systemImage: "checkmark.circle.fill")
                        .font(AppFont.headline(16))
                        .foregroundStyle(KBYOPalette.success)
                    Text(session.email ?? appState.credentials.email)
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "EDF9F0"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button("Use a different Google account") {
                    focusedField = nil
                    appState.clearGoogleOAuthSession()
                    Task { await appState.signInWithGoogleOAuth() }
                }
                .buttonStyle(SecondaryPillButtonStyle())
            } else if appState.isGoogleOAuthConfigured {
                Button("Continue with Google") {
                    focusedField = nil
                    Task { await appState.signInWithGoogleOAuth() }
                }
                .buttonStyle(PrimaryPillButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google web sign-in needs a Google OAuth client ID in Settings before it can run.")
                        .font(AppFont.body(15))
                        .foregroundStyle(KBYOPalette.secondary)

                    Link("Open Google app password setup", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                        .font(AppFont.headline(15))
                        .foregroundStyle(KBYOPalette.accent)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KBYOPalette.accentWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var imapCredentialsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(credentialsCardTitle)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Text(appState.credentials.provider.supportHint)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(KBYOPalette.secondary)

            labeledField(title: "Email") {
                TextField("you@example.com", text: $appState.credentials.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        focusedField = .password
                        appState.hydrateSavedPasswordIfPossible()
                    }
                    .onChange(of: appState.credentials.email) { _, _ in
                        appState.hydrateSavedPasswordIfPossible()
                    }
            }

            if shouldShowPasswordSection {
                if appState.canUseSavedPasswordForCurrentEmail {
                    Button {
                        focusedField = nil
                        Task { await appState.signInWithSavedPassword() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: appState.availableBiometricType == .faceID ? "faceid" : "touchid")
                                .font(.system(size: 19, weight: .semibold))
                            Text("Continue with \(appState.availableBiometricType.title)")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(KBYOPalette.accent)
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(KBYOPalette.accentWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                passwordField(
                    title: appState.credentials.provider == .gmail ? "Google App Password" : "Password / App Password",
                    placeholder: appState.credentials.provider == .yahoo ? "Yahoo app password" : "App password"
                )
            }

            if appState.credentials.provider == .custom {
                labeledField(title: "IMAP Host") {
                    TextField("mail.example.com", text: $appState.credentials.host)
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .host)
                }

                Stepper("Port \(appState.credentials.port)", value: $appState.credentials.port, in: 1...65535)
                    .font(AppFont.body(15))
                    .foregroundStyle(KBYOPalette.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Server \(appState.credentials.resolvedHost):\(appState.credentials.port)")
                        .font(AppFont.caption(14))
                }
                .foregroundStyle(KBYOPalette.secondary)
                .padding(.horizontal, 2)
            }

            if case .loading(let message) = appState.loadingState {
                Label(message, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(KBYOPalette.secondary)
            }

            if case .failed(let message) = appState.loadingState {
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(KBYOPalette.danger)
            }

            Button(syncButtonTitle) {
                focusedField = nil
                Task { await appState.signInAndSync() }
            }
            .buttonStyle(PrimaryPillButtonStyle())

            if appState.credentials.provider == .gmail {
                Text("Personal Gmail accounts connect here with IMAP using a Google app password after 2-step verification is enabled.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(KBYOPalette.secondary)
            } else {
                Text("Saved passwords stay in Keychain on this iPhone and can be unlocked with \(appState.availableBiometricType == .none ? "device security" : appState.availableBiometricType.title).")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(KBYOPalette.secondary)
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var heroTitle: String {
        switch appState.credentials.provider {
        case .yahoo:
            return "Connect your Yahoo inbox"
        case .gmail:
            return "Connect your Gmail inbox"
        default:
            return "Connect your inbox"
        }
    }

    private var heroSubtitle: String {
        switch appState.credentials.provider {
        case .yahoo:
            return "Use the connected inbox to surface recurring subscriptions, trials, and billing changes."
        case .gmail:
            return "Use Google web sign-in for the smooth path, or fall back to a Google app password if needed."
        default:
            return "Sync a real mailbox, then detect active subscriptions, trials, upcoming charges, and price increases."
        }
    }

    private var syncButtonTitle: String {
        if appState.credentials.provider == .yahoo, appState.hasYahooOAuthSession {
            return "Sync Yahoo Inbox"
        }
        if appState.credentials.provider == .gmail, appState.hasGoogleOAuthSession {
            return "Sync Gmail Inbox"
        }
        if appState.credentials.provider == .gmail {
            return "Connect Gmail Inbox"
        }
        return "Connect and Analyze"
    }

    private var credentialsCardTitle: String {
        switch appState.credentials.provider {
        case .yahoo:
            return appState.hasYahooOAuthSession ? "Mailbox details" : "Direct IMAP fallback"
        case .gmail:
            return appState.hasGoogleOAuthSession ? "Mailbox details" : "App password fallback"
        default:
            return "Sign in"
        }
    }

    private var shouldShowPasswordSection: Bool {
        switch appState.credentials.provider {
        case .yahoo:
            return !appState.hasYahooOAuthSession
        case .gmail:
            return !appState.hasGoogleOAuthSession
        default:
            return true
        }
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
            content()
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(KBYOPalette.line, lineWidth: 1)
                )
        }
    }

    private func passwordField(title: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)

            HStack(spacing: 10) {
                Group {
                    if isPasswordVisible {
                        TextField(placeholder, text: $appState.credentials.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder, text: $appState.credentials.password)
                    }
                }
                .focused($focusedField, equals: .password)

                Button {
                    isPasswordVisible.toggle()
                    Haptics.selection()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KBYOPalette.tertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KBYOPalette.line, lineWidth: 1)
            )
        }
    }
}
