import SwiftUI
import UIKit

enum KBYOPalette {
    static let accent = Color(hex: "6001D2")
    static let accentSoft = Color(hex: "EFE6FF")
    static let accentWash = Color(hex: "F7F2FF")
    static let background = Color(hex: "F3F4F7")
    static let backgroundTint = Color(hex: "ECEEF3")
    static let card = Color.white
    static let line = Color(hex: "E2E5EC")
    static let ink = Color(hex: "17191F")
    static let secondary = Color(hex: "666C78")
    static let tertiary = Color(hex: "949AA6")
    static let unreadDot = Color(hex: "7C3AED")
    static let success = Color(hex: "16A34A")
    static let warning = Color(hex: "F59E0B")
    static let danger = Color(hex: "D92D20")
    static let dock = Color.black.opacity(0.86)
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isShowingSplash = true
    @State private var hasBootstrappedDemo = false

    var body: some View {
        ZStack {
            MainTabView()
                .opacity(isShowingSplash ? 0 : 1)

            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .tint(KBYOPalette.accent)
        .preferredColorScheme(.light)
        .task {
            guard !hasBootstrappedDemo else { return }
            hasBootstrappedDemo = true
            appState.useOfflineDemo()

            try? await Task.sleep(for: .seconds(3.0))
            withAnimation(.easeInOut(duration: 0.28)) {
                isShowingSplash = false
            }
        }
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        selectedContent
            .safeAreaInset(edge: .bottom) {
                dockInset
            }
            .background(KBYOPalette.background.ignoresSafeArea())
    }

    private var dockInset: some View {
        YahooDock(selection: $appState.selectedTab)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch appState.selectedTab {
        case .inbox:
            NavigationStack {
                InboxView()
            }
        case .subscriptions:
            NavigationStack {
                LifeHubView()
            }
        case .settings:
            NavigationStack {
                AssistantView()
            }
        }
    }
}

private struct YahooDock: View {
    @Binding var selection: AppState.AppTab

    var body: some View {
        HStack(spacing: 8) {
            dockButton(tab: .inbox, icon: "tray.fill", label: "Home")
            dockButton(tab: .subscriptions, icon: "list.bullet.rectangle.portrait.fill", label: "Digest")
            dockButton(tab: .settings, icon: "sparkles", label: "Assistant")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(KBYOPalette.dock)
                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        )
    }

    private func dockButton(tab: AppState.AppTab, icon: String, label: String) -> some View {
        let isSelected = selection == tab

        return Button {
            Haptics.selection()
            selection = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                if isSelected {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSelected ? 14 : 10)
            .padding(.vertical, 11)
            .frame(width: isSelected ? selectedWidth(for: tab) : 50)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedWidth(for tab: AppState.AppTab) -> CGFloat {
        switch tab {
        case .settings:
            return 132
        case .subscriptions:
            return 102
        case .inbox:
            return 108
        }
    }
}

private struct SplashView: View {
    @State private var animateGlow = false
    @State private var animateOrbit = false
    @State private var animateCard = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "F6F1FF"), Color.white, Color(hex: "ECEBFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(KBYOPalette.accent.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 24)
                .offset(x: 120, y: -220)
                .scaleEffect(animateGlow ? 1.05 : 0.92)

            Circle()
                .stroke(KBYOPalette.accent.opacity(0.14), lineWidth: 26)
                .frame(width: 300, height: 300)
                .offset(x: -160, y: 250)
                .rotationEffect(.degrees(animateOrbit ? 18 : -12))

            VStack(spacing: 30) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [KBYOPalette.accent, Color(hex: "8727FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 170, height: 170)
                        .shadow(color: KBYOPalette.accent.opacity(0.28), radius: 28, x: 0, y: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                        )
                        .scaleEffect(animateCard ? 1.03 : 0.97)

                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 32, weight: .bold))
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundStyle(.white)

                        Text("y+")
                            .font(.system(size: 42, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "dollarsign")
                                .font(.system(size: 19, weight: .black))
                                .foregroundStyle(KBYOPalette.success)
                        )
                        .offset(x: 62, y: 62)
                }

                VStack(spacing: 14) {
                    Text("Know Before You Owe")
                        .font(.system(size: 42, weight: .black))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KBYOPalette.ink)

                    Text("Catch charges before they catch you.")
                        .font(.system(size: 29, weight: .black))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KBYOPalette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animateOrbit = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateCard = true
            }
        }
    }

}

private struct AssistantView: View {
    @EnvironmentObject private var appState: AppState
    @State private var animateCelebration = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader
                celebrationCard
                impactCard
                actionCard
                controlCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 44)
        }
        .background(screenBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                animateCelebration = true
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assistant")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(KBYOPalette.ink)

            Text("I organize billing risk, take the next best action, and keep the user ahead of unwanted charges.")
                .font(AppFont.body(16))
                .foregroundStyle(KBYOPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var celebrationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.celebrationTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text(appState.celebrationBody)
                        .font(AppFont.body(15))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(appState.totalAssistantActions > 0 ? KBYOPalette.success : Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)

                    Image(systemName: appState.totalAssistantActions > 0 ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(animateCelebration ? 1.08 : 0.94)
                        .rotationEffect(.degrees(animateCelebration ? 4 : -4))
                }
            }

            HStack(spacing: 10) {
                assistantStat(value: "\(appState.digest.recurringCount)", label: "tracked")
                assistantStat(value: "\(appState.demoCanceledTrialCount)", label: "trials canceled")
                assistantStat(value: "\(appState.demoSentEmailCount)", label: "emails sent")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [KBYOPalette.accent, Color(hex: "8E2DFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: KBYOPalette.accent.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var impactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("What I Found")

            HStack(spacing: 10) {
                colorfulInsightCard(
                    icon: "creditcard.fill",
                    title: "Recurring",
                    body: "\(appState.digest.recurringCount) active charges",
                    tint: KBYOPalette.accent
                )
                colorfulInsightCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Highest priority",
                    body: appState.recommendedSubscription?.merchant ?? "Ready",
                    tint: KBYOPalette.danger
                )
            }

            insightRow(title: "Recommended next move", body: appState.topRecommendation)
            if let lastSyncDate = appState.lastSyncDate {
                insightRow(title: "Latest refresh", body: lastSyncDate.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(20)
        .cardSurface()
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("What I Can Do")

            capabilityRow(icon: "bell.badge.fill", title: "Warn before renewals", body: "Call out upcoming charges and trial conversions before they hit.")
            capabilityRow(icon: "sparkles.rectangle.stack.fill", title: "Take action on your behalf", body: "Cancel trials, open the right billing path, and log completed actions back into the experience.")
            capabilityRow(icon: "doc.text.fill", title: "Prepare a polished dispute", body: "Draft a send-ready billing review email when a charge looks wrong or a price jumps.")
        }
        .padding(20)
        .cardSurface()
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Presentation Controls")

            Button("Reset Experience") {
                Haptics.success()
                appState.useOfflineDemo()
            }
            .buttonStyle(SecondaryPillButtonStyle())

            Button("Open Highest Priority Case") {
                Haptics.selection()
                if let recommended = appState.recommendedSubscription {
                    appState.requestSubscriptionDetail(for: recommended)
                } else {
                    appState.selectedTab = .subscriptions
                }
            }
            .buttonStyle(SecondaryPillButtonStyle())
        }
        .padding(20)
        .cardSurface()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AppFont.headline(22))
            .foregroundStyle(KBYOPalette.ink)
    }

    private func insightRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
            Text(body)
                .font(AppFont.body(15))
                .foregroundStyle(KBYOPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capabilityRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KBYOPalette.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.headline(16))
                    .foregroundStyle(KBYOPalette.ink)
                Text(body)
                    .font(AppFont.body(14))
                    .foregroundStyle(KBYOPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func assistantStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.caption(12))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func colorfulInsightCard(icon: String, title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(AppFont.caption(13))
                .foregroundStyle(KBYOPalette.secondary)
                .lineLimit(1)
            Text(body)
                .font(AppFont.headline(16))
                .foregroundStyle(KBYOPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F8F9FC"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var screenBackground: some View {
        KBYOPalette.background
    }
}

struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline(18))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(KBYOPalette.accent.opacity(configuration.isPressed ? 0.86 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline(18))
            .foregroundStyle(KBYOPalette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(KBYOPalette.line, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum Haptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func lightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func softImpact() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

struct PressableSpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

enum AppFont {
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func headline(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}

struct CardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KBYOPalette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }
}
