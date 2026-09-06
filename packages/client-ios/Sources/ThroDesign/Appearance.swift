import SwiftUI

/// Whether the app is light, dark, or follows the phone. The founder decided this on 2026-09-06
/// (PD-003) after seeing the app both ways: the player chooses. It governs every screen the export
/// draws light; Match setup and Scoring stay dark as the export draws them.
///
/// The dark rendering of the light-drawn screens is the token layer's dark values applied to layouts
/// no designer has looked at in dark (DESIGN_UNSPECIFIED #20). That is recorded, not hidden.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    /// The UserDefaults key. Read with `@AppStorage(Appearance.storageKey)`.
    public static let storageKey = "thro.appearance"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` means follow the phone.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Never fails: an unknown stored value is treated as `.system`.
    public init(stored raw: String) {
        self = Appearance(rawValue: raw) ?? .system
    }
}

extension View {
    /// Applies an appearance to this screen: both the window's preferred scheme (so the status bar
    /// and asset colours follow) and, when a scheme is chosen, the subtree's environment.
    @ViewBuilder
    public func throAppearance(_ appearance: Appearance) -> some View {
        if let scheme = appearance.colorScheme {
            self.environment(\.colorScheme, scheme).preferredColorScheme(scheme)
        } else {
            self.preferredColorScheme(nil)
        }
    }
}
