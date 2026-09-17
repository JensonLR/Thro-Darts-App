import SwiftUI
import ThroDesign
import ThroNet
import ThroTokens

// A tournament night's own page (PD-126).
//
// Discover listed tournaments as rows that did nothing, and the way into one was under You, behind a row called
// "Darts you can play". Two halves of one thing, with no path between them. This is the path: the row opens the
// night's page — when, where, how full, where it has got to, the draw once there is one — and the way in is on it,
// the same `EventActions` the list under You has always used, so entering here and entering there cannot differ.
//
// It is also where `https://thro.uk/event/<id>` lands (PD-127), so what an organiser posts in the pub's group chat
// opens the night itself, on the web for whoever has no app and here for whoever has.

/// The page's sentences, apart from the drawing so they are tested.
enum EventWords {
    static func kind(_ entrantKind: String) -> String {
        switch entrantKind { case "pair": return "Pairs"; case "team": return "Teams"; default: return "Singles" }
    }

    /// "5 entered · 11 places left". A night with no stated capacity says how many are in and stops there.
    static func places(_ page: EventPage) -> String {
        var parts = ["\(page.entries) entered"]
        if let spots = page.spotsRemaining { parts.append(spots == 0 ? "full" : "\(spots) \(spots == 1 ? "place" : "places") left") }
        return parts.joined(separator: " · ")
    }

    /// Where the night has got to, from the server's own state.
    static func standing(_ page: EventPage) -> String {
        switch page.state {
        case "open": return "Taking entries"
        case "entries_closed": return "Entries are closed. The draw is next."
        case "drawn", "in_progress":
            return page.draw.map(\.round).max().map { "Round \($0) is being played" } ?? "The draw is made"
        case "complete":
            guard let champion = page.winnerId, let tie = page.draw.first(where: { $0.winnerId == champion }) else { return "Over." }
            return "Over. \((tie.homeId == champion ? tie.home : tie.away) ?? "A guest") won it."
        case "cancelled": return "Called off"
        default: return page.state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// One tie in words. A name the server may not show (PD-124: a walk-up the organiser did not say may be named,
    /// a player who is not listed) is "a guest": never a blank, never a guess.
    static func tie(_ t: EventPage.Tie) -> String {
        let home = t.home ?? "A guest"
        if t.isBye { return "\(home) · a bye" }
        let away = t.away ?? "a guest"
        guard let winner = t.winnerId else { return "\(home) v \(away)" }
        return winner == t.homeId ? "\(home) beat \(away)" : "\(t.away ?? "A guest") beat \(t.home ?? "a guest")"
    }

    static func rounds(_ page: EventPage) -> [(round: Int, ties: [EventPage.Tie])] {
        Dictionary(grouping: page.draw, by: \.round).sorted { $0.key < $1.key }
            .map { (round: $0.key, ties: $0.value.sorted { $0.position < $1.position }) }
    }

    static func when(_ page: EventPage) -> String {
        page.startsAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
    }
}

public struct EventScreen: View {
    private let eventId: UUID
    private let api: ThroAPI?
    private let signedIn: Bool
    private let onBack: () -> Void
    @State private var page: EventPage?
    @State private var problem: String?

    public init(eventId: UUID, api: ThroAPI?, signedIn: Bool, onBack: @escaping () -> Void) {
        self.eventId = eventId; self.api = api; self.signedIn = signedIn; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            BoardHeader(title: page?.name ?? "Tournament", eyebrow: page.map { "\(EventWords.kind($0.entrantKind)) · \(EventWords.standing($0))" } ?? "On THRØ",
                        onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
                    if let problem {
                        ErrorState(title: "This tournament could not be read", what: problem, safe: "Nothing on this phone changed.",
                                   todo: "It may have been called off, or the link may be old.", actionLabel: "Try again") { Task { await load() } }
                    } else if let page {
                        facts(page)
                        way(in: page)
                        if !page.draw.isEmpty { draw(page) }
                    } else {
                        HStack { ProgressView(); Text("Reading the night").thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary) }
                    }
                }
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.vertical, ThroSpacing.spacing5)
                .throReadable()
            }
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea())
        .task { await load() }
    }

    private func facts(_ page: EventPage) -> some View {
        DeskCard(icon: .calendar, title: EventWords.when(page),
                 meta: [page.venue ?? page.venueLabel, page.locality].compactMap { $0 }.joined(separator: " · ").nonEmpty) {
            Text(EventWords.places(page)).thro(ThroTypography.bodyLarge.weight(.semibold)).foregroundStyle(ThroColor.colorTextPrimary)
            if let closes = page.entriesCloseAt, page.state == "open" {
                Text("Entries close \(closes.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).")
                    .thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
            }
            // The address is the page at thro.uk (PD-127): it opens here for whoever has THRØ and on the web for whoever has not.
            ShareLink(item: ThroRoute.event(eventId).shared, message: Text("\(page.name) on THRØ")) {
                Text("Share this night").thro(ThroTypography.labelStrong)
                    .foregroundStyle(ThroColor.colorTextBrand)
                    .frame(minHeight: ThroSpacing.touchTargetMinimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
        }
    }

    @ViewBuilder private func way(in page: EventPage) -> some View {
        DeskCard(icon: .trophy, title: page.you?.entered == true ? "You are in" : "The way in",
                 meta: page.access == "open" ? nil : "Entry is by invitation, from the organiser.") {
            if let api, signedIn {
                EventActions(api: api, card: DiscoveryCard(page: page)) { Task { await load() } }
            } else {
                Text("Sign in to enter. Your entry, your check-in on the night and your tie in the draw are kept with your account.")
                    .thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ThroButton("Sign in", variant: .primary, size: .medium) { ThroRouter.shared.go(.tab(.you)) }
            }
        }
    }

    private func draw(_ page: EventPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(EventWords.rounds(page), id: \.round) { round in
                SectionHeader("Round \(round.round)", meta: "\(round.ties.count)").padding(.top, ThroSpacing.spacing4)
                ThroDivider().padding(.top, ThroSpacing.spacing2)
                ForEach(round.ties) { t in
                    HStack(alignment: .firstTextBaseline) {
                        Text(EventWords.tie(t)).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: ThroSpacing.spacing2)
                        if let board = t.board, t.winnerId == nil {
                            Text(board).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextBrand)
                        } else if let outcome = t.outcome, outcome != "played", outcome != "bye" {
                            Text(outcome).thro(ThroTypography.metadata).foregroundStyle(ThroColor.colorTextSecondary)
                        }
                    }
                    .padding(.vertical, ThroSpacing.spacing3)
                    ThroDivider()
                }
            }
        }
    }

    private func load() async {
        guard let api else { problem = "This build names no server."; return }
        do { page = try await api.event(eventId); problem = nil }
        catch { problem = ThroAPI.refusal(error) ?? (error as? APIError)?.message ?? error.localizedDescription }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
