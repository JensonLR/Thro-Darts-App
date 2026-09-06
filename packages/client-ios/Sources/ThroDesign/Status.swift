import SwiftUI
import ThroTokens

// State components: the design's own words for offline, sync, provenance and emptiness. Copy is
// the design's (`state/*.jsx`), not paraphrased — THRØ speaks as a competition official, and the
// wording was approved as part of the system.

// MARK: - Snackbar

/// `state/Snackbar`. Timing, position, stacking and dismissal are DESIGN_UNSPECIFIED (the
/// "smaller" list); this is the bar itself, and the screen decides when it appears.
public struct Snackbar: View {
    public enum Tone: Sendable { case neutral, success, error, offline }

    private let message: String
    private let tone: Tone
    private let actionLabel: String?
    private let onAction: (() -> Void)?

    public init(_ message: String, tone: Tone = .neutral, actionLabel: String? = nil, onAction: (() -> Void)? = nil) {
        self.message = message
        self.tone = tone
        self.actionLabel = actionLabel
        self.onAction = onAction
    }

    private var style: (background: Color, foreground: Color, icon: ThroIcon) {
        switch tone {
        case .neutral: return (ThroColor.throInk, ThroColor.throChalk, .info)
        case .success: return (ThroColor.throGreen, ThroColor.throChalk, .circleCheck)
        case .error: return (ThroColor.colorStatusError, ThroColor.throChalk, .triangleAlert)
        case .offline: return (ThroColor.throPewterDark, ThroColor.throChalk, .wifiOff)
        }
    }

    public var body: some View {
        let s = style
        HStack(spacing: ThroSpacing.spacing3) {
            Icon(s.icon, size: 18)
            Text(message)
                .thro(ThroTypography.label.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .thro(ThroTypography.labelStrong.weight(.bold).tracking(em: 0.04).uppercase(true))
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .padding(.horizontal, ThroSpacing.spacing4)
        .foregroundStyle(s.foreground)
        .background(s.background)
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium))
        .throElevation3()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Offline

/// `state/OfflineState`. Inline variant carries the title only.
public struct OfflineState: View {
    private let title: String
    private let message: String
    private let inline: Bool

    public init(
        title: String = "Offline",
        message: String = "Scoring continues on this device. Changes will sync when connection returns.",
        inline: Bool = false
    ) {
        self.title = title
        self.message = message
        self.inline = inline
    }

    public var body: some View {
        HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
            Icon(.wifiOff, size: 18)
                .foregroundStyle(ThroColor.colorStatusOffline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .thro(ThroTypography.label.weight(.bold).tracking(em: 0.04).uppercase(true))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                if !inline {
                    Text(message)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, inline ? ThroSpacing.spacing2 : ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spacing4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorStatusNeutralSurface)
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: ThroSpacing.borderWidthHairline))
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sync

/// `state/SyncState`. Four states, the design's wording.
public struct SyncState: View {
    public enum State: String, Sendable { case syncing, synced, queued, failed }

    private let state: State
    private let detail: String?
    private let onRetry: (() -> Void)?

    public init(_ state: State, detail: String? = nil, onRetry: (() -> Void)? = nil) {
        self.state = state
        self.detail = detail
        self.onRetry = onRetry
    }

    private var map: (icon: ThroIcon, color: Color, label: String, help: String) {
        switch state {
        case .syncing: return (.refreshCw, ThroColor.colorStatusInfo, "Syncing", "Sending this match to THRØ.")
        case .synced: return (.cloudCheck, ThroColor.colorStatusSuccess, "Synced", "This match is saved to THRØ.")
        case .queued: return (.clock, ThroColor.colorStatusPending, "Queued", "Will sync when connection returns.")
        case .failed: return (.cloudOff, ThroColor.colorStatusError, "Not synced", "Scoring is safe on this device. Retry when you have signal.")
        }
    }

    public var body: some View {
        let m = map
        HStack(spacing: ThroSpacing.spacing3) {
            Icon(m.icon, size: 18).foregroundStyle(m.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.label)
                    .thro(ThroTypography.label.weight(.semibold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                Text(detail ?? m.help)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state == .failed, let onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .thro(ThroTypography.labelStrong.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextBrand)
                        .frame(minHeight: ThroSpacing.touchTargetMinimum)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .padding(.horizontal, ThroSpacing.spacing4)
        .background(ThroColor.colorStatusNeutralSurface)
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Verification

/// The eight labels the approved design defines, with its own wording. Derived from provenance
/// by the trust module's rule, never stored beside it — see packages/trust `VerificationState.of`.
/// This is the rendering; the derivation stays where the evidence is.
public enum VerificationLabel: String, CaseIterable, Sendable {
    case selfReported = "self-reported"
    case participantConfirmed = "participant-confirmed"
    case throRecorded = "thro-recorded"
    case organiserConfirmed = "organiser-confirmed"
    case throVerified = "thro-verified"
    case pending
    case disputed
    case corrected

    var icon: ThroIcon {
        switch self {
        case .selfReported: return .filePen
        case .participantConfirmed: return .users
        case .throRecorded: return .smartphone
        case .organiserConfirmed: return .check
        case .throVerified: return .circleCheck
        case .pending: return .clock
        case .disputed: return .triangleAlert
        case .corrected: return .rotateCcw
        }
    }

    var tone: Color {
        switch self {
        case .selfReported: return ThroColor.colorTextSecondary
        case .participantConfirmed, .throRecorded, .corrected: return ThroColor.colorStatusInfo
        case .organiserConfirmed, .throVerified: return ThroColor.colorStatusVerified
        case .pending: return ThroColor.colorStatusPending
        case .disputed: return ThroColor.colorStatusDisputed
        }
    }

    public var label: String {
        switch self {
        case .selfReported: return "Self-reported"
        case .participantConfirmed: return "Participant-confirmed"
        case .throRecorded: return "THRØ recorded"
        case .organiserConfirmed: return "Organiser-confirmed"
        case .throVerified: return "THRØ verified"
        case .pending: return "Pending"
        case .disputed: return "Disputed"
        case .corrected: return "Corrected"
        }
    }

    public var help: String {
        switch self {
        case .selfReported: return "Entered by a player. Not independently confirmed."
        case .participantConfirmed: return "Both players confirmed this result."
        case .throRecorded: return "Scored live in the THRØ app."
        case .organiserConfirmed: return "Confirmed by the competition organiser."
        case .throVerified: return "Recorded in THRØ and confirmed by the organiser."
        case .pending: return "Awaiting confirmation."
        case .disputed: return "A participant has raised a dispute. Under review."
        case .corrected: return "This result was amended after submission."
        }
    }
}

/// `state/VerificationState`. Verification expresses evidence quality, never prestige.
public struct VerificationState: View {
    private let state: VerificationLabel
    private let explain: Bool
    private let compact: Bool

    public init(_ state: VerificationLabel, explain: Bool = false, compact: Bool = false) {
        self.state = state
        self.explain = explain
        self.compact = compact
    }

    public var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: ThroSpacing.spacing2) {
            Icon(state.icon, size: compact ? 14 : 18)
                .foregroundStyle(state.tone)
                .padding(.top, compact ? 0 : 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.label)
                    .thro((compact ? ThroTypography.metadata : ThroTypography.label).weight(.semibold))
                    .foregroundStyle(state.tone)
                if explain && !compact {
                    Text(state.help)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dialog

/// `state/Dialog`. The card only. Scrim, focus trap and dismissal are DESIGN_UNSPECIFIED #16, so
/// presentation is left to the platform's own sheet or alert rather than invented here.
public struct Dialog: View {
    private let title: String
    private let message: String?
    private let confirmLabel: String
    private let cancelLabel: String
    private let destructive: Bool
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(
        title: String, message: String? = nil,
        confirmLabel: String = "Confirm", cancelLabel: String = "Cancel",
        destructive: Bool = false,
        onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.destructive = destructive
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Text(title)
                .thro(ThroTypography.heading3)
                .foregroundStyle(ThroColor.colorTextPrimary)
            if let message {
                Text(message)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: ThroSpacing.spacing2) {
                ThroButton(cancelLabel, variant: .ghost, size: .small, fullWidth: true, action: onCancel)
                ThroButton(confirmLabel, variant: destructive ? .destructive : .primary, size: .small, fullWidth: true, action: onConfirm)
            }
            .padding(.top, ThroSpacing.spacing2)
        }
        .padding(ThroSpacing.spacing6)
        .frame(maxWidth: 340)
        .background(ThroColor.colorBackgroundRaised)
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard)
            .strokeBorder(ThroColor.colorBorderDefault, lineWidth: ThroSpacing.borderWidthHairline))
        .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard))
        .throElevation3()
    }
}

// MARK: - Empty

/// `state/EmptyState`. Leading-aligned, one action.
public struct EmptyState: View {
    private let title: String
    private let message: String?
    private let actionLabel: String?
    private let onAction: (() -> Void)?

    public init(title: String, message: String? = nil, actionLabel: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Text(title)
                .thro(ThroTypography.heading3.tracking(em: 0.02).uppercase(true))
                .foregroundStyle(ThroColor.colorTextPrimary)
            if let message {
                Text(message)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionLabel, let onAction {
                ThroButton(actionLabel, variant: .primary, action: onAction)
            }
        }
        .padding(.vertical, ThroSpacing.spacing8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
