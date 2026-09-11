import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// Reporting and blocking, on the phone (PD-050).
//
// Apple's guideline 1.2 and Google Play's user-generated-content policy ask for four things, and two of them
// are screens: a way to report what somebody wrote, from where it is read, and a way to be left alone by
// somebody. The other two are a queue with a person behind it and an address in the terms.
//
// Both screens are deliberately plain. A report is not a form to be enjoyed: it is a sentence about a thing,
// sent, with the app saying when it will be answered — a promise, printed, rather than a thank-you.

/// What the phone knows about reporting and blocking. One per signed-in account.
@MainActor
public final class SafetyModel: ObservableObject {
    @Published public private(set) var blocked: [UUID] = []
    @Published public private(set) var sending = false
    @Published public private(set) var note: String?
    /// What the last report was answered with, so the screen can say when it will be looked at.
    @Published public private(set) var raised: ThroAPI.ReportRaised?

    public init() {}

    public func loadBlocks(_ api: ThroAPI?) async {
        guard let api else { return }
        do { blocked = try await api.blocks() } catch { note = ThroAPI.refusal(error) ?? "The list could not be read just now." }
    }

    /// True when it was sent. The note carries the server's own sentence when it was not.
    @discardableResult
    public func report(_ kind: String, _ id: UUID, reason: String, _ api: ThroAPI?) async -> Bool {
        guard let api else { note = "This build names no server."; return false }
        sending = true
        defer { sending = false }
        do {
            raised = try await api.report(subjectKind: kind, subjectId: id, reason: reason)
            note = nil
            return true
        } catch { note = ThroAPI.refusal(error) ?? "That could not be sent just now."; return false }
    }

    public func block(_ accountId: UUID, _ api: ThroAPI?) async {
        guard let api else { note = "This build names no server."; return }
        do { blocked = try await api.block(accountId); note = nil }
        catch { note = ThroAPI.refusal(error) ?? "That could not be done just now." }
    }

    public func unblock(_ accountId: UUID, _ api: ThroAPI?) async {
        guard let api else { return }
        do { blocked = try await api.unblock(accountId); note = nil }
        catch { note = ThroAPI.refusal(error) ?? "That could not be lifted just now." }
    }
}

/// Reporting one thing: what it is, a sentence about it, and when it will be answered.
public struct ReportSheet: View {
    @ObservedObject private var safety: SafetyModel
    private let kind: String
    private let subjectId: UUID
    private let subjectName: String
    private let api: ThroAPI?
    private let onDone: () -> Void

    @State private var reason = ""
    @State private var sent = false

    public init(safety: SafetyModel, kind: String, subjectId: UUID, subjectName: String, api: ThroAPI?,
                onDone: @escaping () -> Void) {
        self.safety = safety
        self.kind = kind
        self.subjectId = subjectId
        self.subjectName = subjectName
        self.api = api
        self.onDone = onDone
    }

    /// What the thing is called in a sentence, so the screen never says "report this subject".
    private var noun: String {
        switch kind {
        case "team": return "team"
        case "venue": return "pub"
        case "league": return "league"
        case "match": return "match"
        default: return "player"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(sent ? "Sent" : "Report this \(noun)", eyebrow: subjectName, onBack: onDone)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    if sent, let raised = safety.raised {
                        Text("Thank you. Somebody reads this.")
                            .thro(ThroTypography.heading2).foregroundStyle(ThroColor.colorTextPrimary)
                        Text(ReportWords.answeredBy(raised))
                            .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Note("Nothing you reported has been deleted. It is looked at, and what was decided is recorded.")
                        ThroButton("Done", variant: .primary, size: .large, fullWidth: true, action: onDone)
                            .padding(.top, ThroSpacing.spacing4)
                    } else {
                        Text("What is wrong with it?")
                            .thro(ThroTypography.heading3).foregroundStyle(ThroColor.colorTextPrimary)
                        Text("One sentence is enough. A person reads every report, and answers it within a day.")
                            .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ThroTextField("Your reason", text: $reason, placeholder: "The name is a slur")
                        if let note = safety.note { Snackbar(note, tone: .error) }
                        ThroButton(safety.sending ? "Sending" : "Send the report", variant: .primary, size: .large, fullWidth: true) {
                            Task { sent = await safety.report(kind, subjectId, reason: reason, api) }
                        }
                        .disabled(safety.sending || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                        .padding(.top, ThroSpacing.spacing3)
                        Note("Reporting is not the same as blocking. If you would rather not hear from somebody at all, block them from their page.")
                            .padding(.top, ThroSpacing.spaceSectionGap)
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
    }
}

/// The accounts somebody has asked not to hear from, and the way back.
public struct BlockedAccountsScreen: View {
    @ObservedObject private var safety: SafetyModel
    private let api: ThroAPI?
    private let onBack: () -> Void

    public init(safety: SafetyModel, api: ThroAPI?, onBack: @escaping () -> Void) {
        self.safety = safety
        self.api = api
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar("Blocked", eyebrow: "Nobody hears from them", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                    if safety.blocked.isEmpty {
                        EmptyState(title: "Nobody is blocked",
                                   message: "Blocking somebody stops them inviting you, adding you as a friend, taking a seat against you or watching your match. You never need a reason.")
                    } else {
                        Text("Blocked while these stand, neither of you can reach the other on THRØ.")
                            .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ThroDivider()
                        ForEach(safety.blocked, id: \.self) { id in
                            HStack(spacing: ThroSpacing.spacing3) {
                                PersonMark(initials: "", size: 32)
                                Text(ReportWords.blockedLine(id))
                                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                                Spacer(minLength: ThroSpacing.spacing2)
                                ThroTextButton("Unblock", tone: .brand, alignment: .trailing) {
                                    Task { await safety.unblock(id, api) }
                                }
                            }
                            .padding(.vertical, ThroSpacing.spacing3)
                            ThroDivider()
                        }
                    }
                    if let note = safety.note { Snackbar(note, tone: .error).padding(.top, ThroSpacing.spacing3) }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task { await safety.loadBlocks(api) }
    }
}

/// The words these screens say, kept apart from the drawing so they are tested rather than looked at.
enum ReportWords {
    /// "It will be answered by 10pm tomorrow." A promise with an hour in it, or none at all.
    static func answeredBy(_ raised: ThroAPI.ReportRaised, now: Date = Date()) -> String {
        let when = raised.answerDueAt.formatted(.dateTime.weekday(.wide).hour().minute())
        return raised.urgent
            ? "This one is looked at first, and never left to sit: \(when) at the latest."
            : "It will be answered by \(when)."
    }

    /// A blocked account is named by nobody: THRØ holds no name to show, and the person who blocked them
    /// knows who they blocked. The id's first characters are enough to tell two apart.
    static func blockedLine(_ id: UUID) -> String {
        "Account " + id.uuidString.prefix(8).lowercased()
    }
}
