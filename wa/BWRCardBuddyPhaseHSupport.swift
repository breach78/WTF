import SwiftUI
import Foundation

nonisolated struct BWRCardBuddyShellBackdropSnapshot: Equatable, Sendable {
    var topHex: String
    var bottomHex: String
    var spotlightHex: String
    var spotlightOpacity: Double
}

nonisolated struct BWRCardBuddyShellPanelStyleSnapshot: Equatable, Sendable {
    var cornerRadius: CGFloat
    var fillHex: String
    var fillOpacity: Double
    var strokeHex: String
    var strokeOpacity: Double
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat
}

nonisolated struct BWRCardBuddyShellButtonStyleSnapshot: Equatable, Sendable {
    var cornerRadius: CGFloat
    var fillHex: String
    var fillOpacity: Double
    var pressedFillOpacity: Double
    var strokeHex: String
    var strokeOpacity: Double
}

nonisolated enum BWRCardBuddyShellPanelRole: String, Sendable {
    case column
    case section
    case stage
    case band
}

nonisolated enum BWRCardBuddyShellButtonRole: String, Sendable {
    case toolbarPrimary
    case toolbarAccessory
}

nonisolated enum BWRCardBuddyShellChrome {
    static let backdrop = BWRCardBuddyShellBackdropSnapshot(
        topHex: "F3EEE6",
        bottomHex: "EAE2D8",
        spotlightHex: "FFFFFF",
        spotlightOpacity: 0.40
    )

    static func panelStyle(for role: BWRCardBuddyShellPanelRole) -> BWRCardBuddyShellPanelStyleSnapshot {
        switch role {
        case .column:
            return BWRCardBuddyShellPanelStyleSnapshot(
                cornerRadius: 28,
                fillHex: "FFFFFF",
                fillOpacity: 0.08,
                strokeHex: "4E4032",
                strokeOpacity: 0.05,
                shadowOpacity: 0.02,
                shadowRadius: 18,
                shadowYOffset: 4
            )
        case .section:
            return BWRCardBuddyShellPanelStyleSnapshot(
                cornerRadius: 22,
                fillHex: "FFFFFF",
                fillOpacity: 0.16,
                strokeHex: "4E4032",
                strokeOpacity: 0.06,
                shadowOpacity: 0.02,
                shadowRadius: 10,
                shadowYOffset: 2
            )
        case .stage:
            return BWRCardBuddyShellPanelStyleSnapshot(
                cornerRadius: 32,
                fillHex: "FFFFFF",
                fillOpacity: 0.20,
                strokeHex: "4E4032",
                strokeOpacity: 0.07,
                shadowOpacity: 0.035,
                shadowRadius: 28,
                shadowYOffset: 10
            )
        case .band:
            return BWRCardBuddyShellPanelStyleSnapshot(
                cornerRadius: 20,
                fillHex: "FFFFFF",
                fillOpacity: 0.14,
                strokeHex: "4E4032",
                strokeOpacity: 0.05,
                shadowOpacity: 0.015,
                shadowRadius: 8,
                shadowYOffset: 2
            )
        }
    }

    static func buttonStyle(for role: BWRCardBuddyShellButtonRole) -> BWRCardBuddyShellButtonStyleSnapshot {
        switch role {
        case .toolbarPrimary:
            return BWRCardBuddyShellButtonStyleSnapshot(
                cornerRadius: 15,
                fillHex: "FFFFFF",
                fillOpacity: 0.16,
                pressedFillOpacity: 0.24,
                strokeHex: "4E4032",
                strokeOpacity: 0.06
            )
        case .toolbarAccessory:
            return BWRCardBuddyShellButtonStyleSnapshot(
                cornerRadius: 14,
                fillHex: "FFFFFF",
                fillOpacity: 0.10,
                pressedFillOpacity: 0.18,
                strokeHex: "4E4032",
                strokeOpacity: 0.05
            )
        }
    }

    static func color(for hex: String) -> Color {
        guard let value = Int(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) else {
            return .white
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

struct BWRCardBuddyShellWorkspaceBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let backdrop = BWRCardBuddyShellChrome.backdrop
            let radius = max(geometry.size.width, geometry.size.height) * 0.62

            ZStack {
                LinearGradient(
                    colors: [
                        BWRCardBuddyShellChrome.color(for: backdrop.topHex),
                        BWRCardBuddyShellChrome.color(for: backdrop.bottomHex)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        BWRCardBuddyShellChrome.color(for: backdrop.spotlightHex).opacity(backdrop.spotlightOpacity),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 36,
                    endRadius: radius
                )
            }
            .ignoresSafeArea()
        }
    }
}

private struct BWRCardBuddyShellSurfaceModifier: ViewModifier {
    let style: BWRCardBuddyShellPanelStyleSnapshot

    func body(content: Content) -> some View {
        let fillColor = BWRCardBuddyShellChrome.color(for: style.fillHex)
        let strokeColor = BWRCardBuddyShellChrome.color(for: style.strokeHex)

        content
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(fillColor.opacity(style.fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(strokeColor.opacity(style.strokeOpacity), lineWidth: 1)
            )
            .shadow(
                color: strokeColor.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowYOffset
            )
    }
}

private struct BWRCardBuddyChromeButtonStyle: ButtonStyle {
    let snapshot: BWRCardBuddyShellButtonStyleSnapshot

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = BWRCardBuddyShellChrome.color(for: snapshot.fillHex)
        let strokeColor = BWRCardBuddyShellChrome.color(for: snapshot.strokeHex)
        let fillOpacity = configuration.isPressed ? snapshot.pressedFillOpacity : snapshot.fillOpacity

        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: snapshot.cornerRadius, style: .continuous)
                    .fill(fillColor.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: snapshot.cornerRadius, style: .continuous)
                    .stroke(strokeColor.opacity(snapshot.strokeOpacity), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: snapshot.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct BWRCardBuddySidebarListChromeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
        } else {
            content.listStyle(.plain)
        }
    }
}

extension View {
    func bwrCardBuddyShellSurface(_ style: BWRCardBuddyShellPanelStyleSnapshot) -> some View {
        modifier(BWRCardBuddyShellSurfaceModifier(style: style))
    }

    func bwrCardBuddyChromeButton(_ role: BWRCardBuddyShellButtonRole) -> some View {
        buttonStyle(BWRCardBuddyChromeButtonStyle(snapshot: BWRCardBuddyShellChrome.buttonStyle(for: role)))
    }

    func bwrCardBuddySidebarListChrome() -> some View {
        modifier(BWRCardBuddySidebarListChromeModifier())
    }
}
