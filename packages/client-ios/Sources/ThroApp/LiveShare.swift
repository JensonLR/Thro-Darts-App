import Foundation
import SwiftUI
import ThroDesign
import ThroJournal
import ThroNet
import ThroTokens

// Sharing a match live (PD-044).
//
// While a match is scored, a phone whose player has switched it on sends the match's journal as it
// grows, so the other player can follow it on their own phone. It is PD-040's upload and nothing
// new: the whole journal each time, idempotent on the server, so a send that fails is made good by
// the next, and nothing here remembers more than how many rows the server has already taken.

@MainActor
public final class LiveShare: ObservableObject {
    /// The matches being shared, by journal id — kept, so a match shared before the phone slept is
    /// still shared when it wakes.
    @Published public private(set) var sharing: Set<String>
    /// Why the last send of a match did not go, for the switch that shares it.
    @Published public private(set) var notes: [String: String] = [:]
    /// Rows the server has taken, per match, since this launch. A relaunch sends the lot once more,
    /// which the server takes as nothing new.
    private var taken: [String: Int] = [:]
    private let defaults: UserDefaults
    static let key = "thro.liveShare.matches"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sharing = Set(defaults.stringArray(forKey: LiveShare.key) ?? [])
    }

    public func isSharing(_ id: MatchId) -> Bool { sharing.contains(id.value) }

    public func set(_ id: MatchId, sharing on: Bool) {
        if on {
            sharing.insert(id.value)
        } else {
            sharing.remove(id.value)
            taken[id.value] = nil
            notes[id.value] = nil
        }
        defaults.set(Array(sharing).sorted(), forKey: LiveShare.key)
    }

    /// Whether a journal of [rows] rows holds anything the server has not taken.
    nonisolated static func due(rows: Int, taken: Int?) -> Bool { rows > (taken ?? 0) }

    /// One pass over the shared matches: each with rows THRØ has not taken is sent. Returns whether a
    /// match reached THRØ for the first time this launch, so the caller can read its list again once
    /// rather than after every visit.
    public func tick(store: AppStore, api: ThroAPI, profileName: String?) async -> Bool {
        guard !sharing.isEmpty, let journal = store.journal else { return false }
        var arrived = false
        for match in store.matches where sharing.contains(match.record.id.value) {
            let key = match.record.id.value
            let entries: [JournalEntry]
            do { entries = try journal.entries(for: match.record.id) } catch {
                notes[key] = "This phone could not read the match back: \(error.localizedDescription)"
                continue
            }
            guard LiveShare.due(rows: entries.count, taken: taken[key]) else {
                // All of it is on THRØ and the match is over: there is nothing left to share.
                if match.complete { set(match.record.id, sharing: false) }
                continue
            }
            // Nothing thrown yet is nothing to send; the match goes up with its first visit.
            guard case .ready(let rows) = MatchUpload.rows(from: entries) else { continue }
            guard let mine = profileName,
                  let seat = MatchUpload.seat(of: mine, home: match.record.homeName, away: match.record.awayName) else {
                notes[key] = "THRØ cannot tell which player you are in this match. Score under the name on your profile and it will know."
                continue
            }
            // Never an invented id: a match sent under a new one every pass would be a new match every pass.
            guard let matchId = UUID(uuidString: key), let deviceId = UUID(uuidString: AppStore.deviceId()) else {
                notes[key] = "This match's record cannot be named to THRØ, so it is not shared."
                continue
            }
            do {
                _ = try await api.sendMatch(matchId: matchId, deviceId: deviceId, seat: seat,
                                            format: MatchUpload.format(for: match.record), rows: rows)
                if taken[key] == nil { arrived = true }
                taken[key] = entries.count
                notes[key] = nil
            } catch {
                notes[key] = SignInProblem.words(error)
            }
        }
        return arrived
    }
}

/// The switch that shares a match live, under the match it shares (PD-044). Off unless switched on:
/// nothing leaves the phone as it is scored unless its player asked for exactly that.
struct LiveShareRow: View {
    @ObservedObject var share: LiveShare
    let match: AppStore.HomeMatch

    var body: some View {
        let on = share.isSharing(match.record.id)
        let note = share.notes[match.record.id.value]
        VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
            Toggle(isOn: Binding(get: { share.isSharing(match.record.id) },
                                 set: { share.set(match.record.id, sharing: $0) })) {
                Text("Share it live on THRØ")
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextPrimary)
            }
            .tint(ThroColor.colorSurfaceBrand)
            Text(note ?? (on
                ? "Each visit goes up as it is scored. Give the other player the code from On THRØ below, and they can follow it on their phone."
                : "Off, so it stays on this phone until you send it."))
                .thro(ThroTypography.metadata)
                .foregroundStyle(note == nil ? ThroColor.colorTextSecondary : ThroColor.colorStatusError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, ThroSpacing.spacing1)
    }
}
